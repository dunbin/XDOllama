import Foundation

@MainActor
class ChatService: ObservableObject {
    static let shared = ChatService()
    
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var streamResponse: String = ""
    
    private let ollamaService = OllamaService.shared
    private let xinferenceService = XinferenceService.shared
    
    private weak var chatHistoryManager: ChatHistoryManager?
    
    private var isCancelled = false
    
    private init() {}
    
    func setHistoryManager(_ manager: ChatHistoryManager) {
        self.chatHistoryManager = manager
    }
    
    func clearMessages() {
        messages.removeAll()
    }
    
    func loadMessages(_ messages: [ChatMessage]) {
        self.messages = messages
    }
    
    func sendMessage(_ content: String) async {
        await chatHistoryManager?.sendMessage(content)
        
        let userMessage = ChatMessage(content: content, isUser: true)
        await MainActor.run {
            messages.append(userMessage)
            isLoading = true
            streamResponse = ""
            messages.append(ChatMessage(content: "", isUser: false))
        }
        
        do {
            try await generateStreamResponse(content)
            await MainActor.run {
                isLoading = false
                chatHistoryManager?.updateCurrentConversation(messages: messages)
            }
        } catch {
            print("Error generating response:", error)
            await MainActor.run {
                messages.removeLast()
                isLoading = false
            }
        }
    }
    
    func regenerateResponse() async {
        guard let lastUserMessage = messages.last(where: { $0.isUser }),
              messages.count >= 2 else { return }
        
        await MainActor.run {
            if !messages.last!.isUser {
                messages.removeLast()
            }
            isLoading = true
            streamResponse = ""
            messages.append(ChatMessage(content: "", isUser: false))
        }
        
        do {
            try await generateStreamResponse(lastUserMessage.content)
            await MainActor.run {
                isLoading = false
                chatHistoryManager?.updateCurrentConversation(messages: messages)
            }
        } catch {
            print("Error regenerating response:", error)
            await MainActor.run {
                messages.removeLast()
                isLoading = false
            }
        }
    }
    
    func sendXinferenceMessage(_ content: String) async {
        await chatHistoryManager?.sendMessage(content)
        
        let userMessage = ChatMessage(content: content, isUser: true)
        await MainActor.run {
            messages.append(userMessage)
            isLoading = true
            streamResponse = ""
            messages.append(ChatMessage(content: "", isUser: false))
        }
        
        do {
            try await generateXinferenceResponse(content)
            await MainActor.run {
                isLoading = false
                chatHistoryManager?.updateCurrentConversation(messages: messages)
            }
        } catch {
            print("Error generating response:", error)
            await MainActor.run {
                messages.removeLast()
                isLoading = false
            }
        }
    }
    
    func sendDifyMessage(_ content: String) async {
        await chatHistoryManager?.sendMessage(content)
        
        let userMessage = ChatMessage(content: content, isUser: true)
        await MainActor.run {
            messages.append(userMessage)
            isLoading = true
            streamResponse = ""
            messages.append(ChatMessage(content: "", isUser: false))
        }
        
        do {
            try await generateDifyResponse(content)
            await MainActor.run {
                isLoading = false
                chatHistoryManager?.updateCurrentConversation(messages: messages)
            }
        } catch {
            print("Error generating Dify response:", error)
            await MainActor.run {
                messages.removeLast()
                isLoading = false
            }
        }
    }
    
    func cancelGeneration() {
        isCancelled = true
    }
    
    private func generateStreamResponse(_ prompt: String) async throws {
        isCancelled = false
        var accumulatedResponse = ""
        
        guard let url = URL(string: "\(ollamaService.baseURL)/api/chat") else {
            throw URLError(.badURL)
        }
        
        let parameters: [String: Any] = [
            "model": ollamaService.selectedModel,
            "messages": ollamaService.buildConversationContext(messages + [ChatMessage(content: prompt, isUser: true)]),
            "stream": true
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        let (bytes, _) = try await URLSession.shared.bytes(for: request)
        
        struct StreamResponse: Codable {
            let message: Message
            let done: Bool
            
            struct Message: Codable {
                let role: String
                let content: String
            }
        }
        
        for try await line in bytes.lines {
            if isCancelled {
                await MainActor.run {
                    isLoading = false
                }
                break
            }
            
            guard !line.isEmpty else { continue }
            
            if let data = line.data(using: .utf8),
               let response = try? JSONDecoder().decode(StreamResponse.self, from: data) {
                accumulatedResponse += response.message.content
                
                await MainActor.run {
                    self.streamResponse = accumulatedResponse
                    if var lastMessage = messages.last, !lastMessage.isUser {
                        lastMessage.content = accumulatedResponse
                        messages[messages.count - 1] = lastMessage
                    }
                    objectWillChange.send()
                }
                
                if response.done {
                    break
                }
            }
        }
    }
    
    private func generateXinferenceResponse(_ prompt: String) async throws {
        isCancelled = false
        var accumulatedResponse = ""
        
        guard let url = URL(string: "\(xinferenceService.baseURL)/v1/chat/completions") else {
            throw URLError(.badURL)
        }
        
        let parameters: [String: Any] = [
            "model": xinferenceService.selectedModel,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "stream": true
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        let (bytes, _) = try await URLSession.shared.bytes(for: request)
        
        struct StreamResponse: Codable {
            let choices: [Choice]
            
            struct Choice: Codable {
                let delta: Delta
                
                struct Delta: Codable {
                    let content: String?
                }
            }
        }
        
        for try await line in bytes.lines {
            if isCancelled {
                await MainActor.run {
                    isLoading = false
                }
                break
            }
            
            guard !line.isEmpty, line != "data: [DONE]" else { continue }
            
            if let dataRange = line.range(of: "data: ") {
                let jsonString = String(line[dataRange.upperBound...])
                if let data = jsonString.data(using: .utf8),
                   let response = try? JSONDecoder().decode(StreamResponse.self, from: data) {
                    if let content = response.choices.first?.delta.content {
                        accumulatedResponse += content
                        
                        await MainActor.run {
                            self.streamResponse = accumulatedResponse
                            if var lastMessage = messages.last, !lastMessage.isUser {
                                lastMessage.content = accumulatedResponse
                                messages[messages.count - 1] = lastMessage
                                objectWillChange.send()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func generateDifyResponse(_ prompt: String) async throws {
        isCancelled = false
        var accumulatedResponse = ""
        
        let difyService = DifyService.shared
        
        guard !difyService.apiKey.isEmpty, 
              let url = URL(string: "\(difyService.baseURL)/chat-messages") else {
            throw URLError(.badURL)
        }
        
        let parameters: [String: Any] = [
            "inputs": [:],
            "query": prompt,
            "response_mode": "streaming",
            "conversation_id": "",
            "user": "xllama_user"
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(difyService.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        let (bytes, _) = try await URLSession.shared.bytes(for: request)
        
        struct DifyStreamResponse: Codable {
            let event: String?
            let message: Message?
            let answer: String?
            
            struct Message: Codable {
                let content: String?
            }
        }
        
        for try await line in bytes.lines {
            if isCancelled {
                await MainActor.run {
                    isLoading = false
                }
                break
            }
            
            guard !line.isEmpty, line.hasPrefix("data: ") else { continue }
            
            let jsonString = String(line.dropFirst(6))
            if let data = jsonString.data(using: .utf8),
               let response = try? JSONDecoder().decode(DifyStreamResponse.self, from: data) {
                
                let content = response.message?.content ?? response.answer ?? ""
                
                if !content.isEmpty {
                    accumulatedResponse += content
                    
                    await MainActor.run {
                        self.streamResponse = accumulatedResponse
                        if var lastMessage = messages.last, !lastMessage.isUser {
                            lastMessage.content = accumulatedResponse
                            messages[messages.count - 1] = lastMessage
                            objectWillChange.send()
                        }
                    }
                }
                
                if response.event == "message_end" || response.event == "[DONE]" {
                    break
                }
            }
        }
    }
    
    private func handleStreamResponse(_ response: String) {
        DispatchQueue.main.async {
            self.streamResponse = response
            // 更新最后一条消息的内容
            if let lastIndex = self.messages.lastIndex(where: { !$0.isUser }) {
                self.messages[lastIndex].content = response
            }
        }
    }
} 
import SwiftUI

// 添加 VisualEffectView
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .sidebar
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct ChatHistoryView: View {
    @StateObject private var chatHistoryManager = ChatHistoryManager.shared
    @State private var showDeleteConfirmation: Bool = false
    @State private var conversationToDelete: UUID?
    
    var body: some View {
        ZStack {
            // 背景模糊效果
            VisualEffectView()
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(chatHistoryManager.conversations) { conversation in
                        ConversationCard(
                            conversation: conversation,
                            isSelected: chatHistoryManager.currentConversationId == conversation.id,
                            onTap: {
                                chatHistoryManager.switchToConversation(conversation.id)
                            },
                            onDelete: {
                                conversationToDelete = conversation.id
                                showDeleteConfirmation = true
                            }
                        )
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
            }
        }
        .frame(minWidth: 250)
        .background(Color.clear)
        .confirmationDialog("确认删除对话?", 
            isPresented: $showDeleteConfirmation, 
            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let id = conversationToDelete {
                    chatHistoryManager.deleteConversation(id)
                }
            }
        }
    }
}

struct ConversationCard: View {
    let conversation: ChatHistoryManager.Conversation
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                // 对话图标
                Image(systemName: "message")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .white : .gray)
                
                // 对话标题
                Text(conversation.title)
                    .lineLimit(2)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white : .primary)
                
                Spacer()
                
                // 删除按钮 - 只在悬停时显示
                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(isSelected ? .white.opacity(0.7) : .gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // 消息数量指示
                if !conversation.messages.isEmpty {
                    Text("\(conversation.messages.count)")
                        .font(.system(size: 12))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.2) : Color.gray.opacity(0.2))
                        )
                        .foregroundColor(isSelected ? .white : .gray)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 19)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.black : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

@MainActor
class ChatHistoryManager: ObservableObject {
    static let shared = ChatHistoryManager()
    
    struct Conversation: Identifiable, Codable {
        let id: UUID
        var title: String
        var messages: [ChatMessage]
        var timestamp: Date
        var needsTitleUpdate: Bool
        
        init(title: String, messages: [ChatMessage], id: UUID = UUID()) {
            self.id = id
            self.title = title
            self.messages = messages
            self.timestamp = Date()
            self.needsTitleUpdate = false
        }
        
        enum CodingKeys: String, CodingKey {
            case id, title, messages, timestamp, needsTitleUpdate
        }
    }
    
    @Published var conversations: [Conversation] = []
    @Published var currentConversationId: UUID?
    @Published var currentMessages: [ChatMessage] = []
    
    private let ollamaService = OllamaService.shared
    private let conversationArchiveKey = "savedConversations"
    
    // 添加一个标志，表示是否允许自动创建对话
    @Published var canAutoCreateConversation = false
    
    init() {
        ChatService.shared.setHistoryManager(self)
        loadSavedConversations()
        
        // 如果没有对话，创建新对话
        if conversations.isEmpty {
            createNewConversation(autoCreated: true)
        }
    }
    
    // 保存对话到本地
    private func saveConversations() {
        do {
            let encodedData = try JSONEncoder().encode(conversations)
            UserDefaults.standard.set(encodedData, forKey: conversationArchiveKey)
        } catch {
            print("Error saving conversations: \(error)")
        }
    }
    
    // 加载本地保存的对话
    private func loadSavedConversations() {
        guard let savedData = UserDefaults.standard.data(forKey: conversationArchiveKey) else {
            return
        }
        
        do {
            conversations = try JSONDecoder().decode([Conversation].self, from: savedData)
        } catch {
            print("Error loading conversations: \(error)")
        }
    }
    
    // 删除对话
    func deleteConversation(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        
        // 如果删除的是当前对话，切换到第一个对话或创建新对话
        if currentConversationId == id {
            if let firstConversation = conversations.first {
                switchToConversation(firstConversation.id)
            } else {
                createNewConversation()
            }
        }
        
        saveConversations()
    }
    
    // 重写现有方法以支持持久化
    func createNewConversation(autoCreated: Bool = false) {
        let newConversation = Conversation(title: "新对话", messages: [])
        conversations.insert(newConversation, at: 0)
        currentConversationId = newConversation.id
        currentMessages = []
        ChatService.shared.clearMessages()
        
        // 只有手动创建或第一次初始化时才保存
        if !autoCreated {
            canAutoCreateConversation = true
        }
        
        saveConversations()
    }
    
    func updateCurrentConversation(messages: [ChatMessage]) {
        guard let currentId = currentConversationId,
              let index = conversations.firstIndex(where: { $0.id == currentId })
        else { return }
        
        conversations[index].messages = messages
        
        if conversations[index].title == "新对话" && messages.count >= 4 {
            conversations[index].needsTitleUpdate = true
            Task {
                await generateTitle(for: index)
            }
        }
        
        saveConversations()
    }
    
    func switchToConversation(_ id: UUID) {
        if id == currentConversationId {
            return
        }
        
        if let currentIndex = conversations.firstIndex(where: { $0.id == currentConversationId }),
           conversations[currentIndex].needsTitleUpdate {
            Task {
                await generateTitle(for: currentIndex)
            }
        }
        
        if let targetIndex = conversations.firstIndex(where: { $0.id == id }) {
            currentConversationId = id
            currentMessages = conversations[targetIndex].messages
            ChatService.shared.loadMessages(conversations[targetIndex].messages)
        }
    }
    
    private func generateTitle(for conversationIndex: Int) async {
        let messages = conversations[conversationIndex].messages
        guard messages.count >= 4 else { return }
        
        let prompt = """
        请根据以下对话生成一个简短的标题（不超过15个字）：
        
        用户：\(messages[0].content)
        AI：\(messages[1].content)
        用户：\(messages[2].content)
        AI：\(messages[3].content)
        
        只需要返回标题，不要其他任何内容。
        """
        
        do {
            guard let url = URL(string: "\(ollamaService.baseURL)/api/generate") else {
                return
            }
            
            let parameters: [String: Any] = [
                "model": ollamaService.selectedModel,
                "prompt": prompt,
                "stream": false
            ]
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
            
            struct GenerateResponse: Codable {
                let response: String
            }
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(GenerateResponse.self, from: data)
            
            let title = response.response.trimmingCharacters(in: .whitespacesAndNewlines)
            
            await MainActor.run {
                if !title.isEmpty {
                    conversations[conversationIndex].title = title
                    conversations[conversationIndex].needsTitleUpdate = false
                }
            }
            
        } catch {
            print("Error generating title:", error)
        }
    }
    
    func sendMessage(_ content: String) async {
        // 如果是第一条消息且未自动创建对话
        if !canAutoCreateConversation && currentMessages.isEmpty {
            createNewConversation()
        }
    }
} 
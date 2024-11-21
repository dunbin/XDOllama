import SwiftUI
import MarkdownUI

struct ChatView: View {
    @StateObject private var chatService = ChatService.shared
    @StateObject private var ollamaService = OllamaService.shared
    @StateObject private var xinferenceService = XinferenceService.shared
    @StateObject private var chatHistoryManager = ChatHistoryManager.shared
    @StateObject private var difyService = DifyService.shared
    @State private var messageText = ""
    @State private var ollamaModels: [OllamaModel] = []
    @State private var selectedModelType: ModelType = .ollama
    @FocusState private var isInputFocused: Bool
    
    enum ModelType: String {
        case ollama = "Ollama"
        case xinference = "Xinference"
        case dify = "Dify"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 模型选择器
            HStack {
                Picker("服务", selection: $selectedModelType) {
                    Text(ModelType.ollama.rawValue).tag(ModelType.ollama)
                    Text(ModelType.xinference.rawValue).tag(ModelType.xinference)
                    Text(ModelType.dify.rawValue).tag(ModelType.dify)
                }
                .frame(width: 120)
                
                Picker("模型", selection: Binding(
                    get: {
                        switch selectedModelType {
                        case .ollama: return ollamaService.selectedModel
                        case .xinference: return xinferenceService.selectedModel
                        case .dify: return difyService.selectedModel
                        }
                    },
                    set: { newValue in
                        Task { @MainActor in
                            switch selectedModelType {
                            case .ollama: ollamaService.selectedModel = newValue
                            case .xinference: xinferenceService.selectedModel = newValue
                            case .dify: difyService.selectedModel = newValue
                            }
                        }
                    }
                )) {
                    Text("选择模型").tag("")
                    if selectedModelType == .ollama {
                        ForEach(ollamaModels) { model in
                            Text(model.name).tag(model.name)
                        }
                    } else if selectedModelType == .xinference {
                        ForEach(xinferenceService.models.filter { $0.isAvailable }) { model in
                            Text(model.name).tag(model.name)
                        }
                    } else {
                        ForEach(DifyService.shared.models) { model in
                            Text(model.name).tag(model.name)
                        }
                    }
                }
                .frame(width: 200)
                .disabled(chatService.isLoading)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // 聊天消息列表
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(spacing: 20) {
                        ForEach(chatService.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        if chatService.isLoading {
                            LoadingDots()
                                .padding()
                                .id("loading_dots")
                        }
                    }
                    .padding()
                    .onChange(of: chatService.messages) { _, newMessages in
                        withAnimation {
                            if let lastMessageId = newMessages.last?.id {
                                proxy.scrollTo(lastMessageId, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            // 消息输入框
            HStack(spacing: 12) {
                TextEditor(text: $messageText)
                    .font(.body)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .frame(height: min(100, max(36, messageText.isEmpty ? 36 : messageText.height(withConstrainedWidth: 1000) + 16)))
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8)
                    .disabled(chatService.isLoading)
                    .focused($isInputFocused)
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear {
                                    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                                        if event.keyCode == 36 { // 回车键的键码
                                            if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chatService.isLoading {
                                                sendMessage()
                                                return nil
                                            }
                                        }
                                        return event
                                    }
                                }
                        }
                    )
                
                Button(action: sendMessage) {
                    Circle()
                        .fill(messageText.isEmpty || chatService.isLoading ? Color.gray.opacity(0.3) : Color.black)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        )
                }
                .disabled(messageText.isEmpty || chatService.isLoading)
                .buttonStyle(PlainButtonStyle())
            }
            .padding(12)
            .background(Color(.windowBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.gray.opacity(0.2)),
                alignment: .top
            )
        }
        .onAppear {
            isInputFocused = true
            Task {
                do {
                    // 获取 Ollama 模型列表
                    ollamaModels = try await ollamaService.fetchModels()
                    // 获取 Xinference 模型列表
                    try await xinferenceService.fetchModels()
                    // 获取 Dify 模型列表
                    try await DifyService.shared.fetchModels()
                } catch {
                    print("Error fetching models:", error)
                }
            }
        }
        .onChange(of: chatService.isLoading) { _, newValue in
            if !newValue {
                isInputFocused = true
            }
        }
        .onSubmit {
            if !messageText.isEmpty && !chatService.isLoading {
                sendMessage()
            }
        }
        .submitLabel(.send)
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        messageText = ""
        Task {
            switch selectedModelType {
            case .ollama:
                await chatService.sendMessage(content)
            case .xinference:
                await chatService.sendXinferenceMessage(content)
            case .dify:
                await chatService.sendDifyMessage(content)
            }
        }
    }
}

struct LoadingDots: View {
    @State private var dotOpacity1: Double = 0.3
    @State private var dotOpacity2: Double = 0.3
    @State private var dotOpacity3: Double = 0.3
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .frame(width: 6, height: 6)
                .opacity(dotOpacity1)
            Circle()
                .frame(width: 6, height: 6)
                .opacity(dotOpacity2)
            Circle()
                .frame(width: 6, height: 6)
                .opacity(dotOpacity3)
        }
        .foregroundColor(.gray)
        .onAppear {
            let animation = Animation.easeInOut(duration: 0.4).repeatForever()
            withAnimation(animation.delay(0.0)) {
                dotOpacity1 = 1
            }
            withAnimation(animation.delay(0.2)) {
                dotOpacity2 = 1
            }
            withAnimation(animation.delay(0.4)) {
                dotOpacity3 = 1
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    @State private var showCopyButton = false
    @State private var showCopiedFeedback = false
    @StateObject private var chatService = ChatService.shared
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading) {
                if message.isUser {
                    Text(message.content)
                        .font(.body)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                        .textSelection(.enabled)
                } else {
                    Markdown(message.content)
                        .markdownTheme(.gitHub.text {
                            ForegroundColor(.primary)
                            BackgroundColor(.clear)
                            FontSize(14)
                        })
                        .padding()
                        .cornerRadius(8)
                        .textSelection(.enabled)
                }
                
                if !message.isUser {
                    HStack(spacing: 12) {
                        // 重新生成按钮
                        Button(action: {
                            Task {
                                await chatService.regenerateResponse()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .opacity(showCopyButton ? 1 : 0)
                        .frame(width: 24, height: 24)
                        
                        // 复制按钮
                        Button(action: {
                            if !message.content.isEmpty {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.content, forType: .string)
                                
                                withAnimation {
                                    showCopiedFeedback = true
                                }
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation {
                                        showCopiedFeedback = false
                                    }
                                }
                            }
                        }) {
                            Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .opacity(showCopyButton ? 1 : 0)
                        .frame(width: 24, height: 24)
                    }
                    .padding(.top, -8)
                }
            }
            .onHover { isHovered in
                showCopyButton = isHovered
                if !isHovered {
                    showCopiedFeedback = false
                }
            }
            
            if !message.isUser {
                Spacer()
            }
        }
    }
}

// 添加 String 扩展来计算文本高度
extension String {
    func height(withConstrainedWidth width: CGFloat) -> CGFloat {
        let size = CGSize(width: width, height: .greatestFiniteMagnitude)
        let attributes = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        let boundingBox = self.boundingRect(with: size,
                                          options: [.usesFontLeading, .usesLineFragmentOrigin],
                                          attributes: attributes,
                                          context: nil)
        return ceil(boundingBox.height)
    }
}
 
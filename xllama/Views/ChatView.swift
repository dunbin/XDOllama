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
    @State private var shouldScrollToBottom = false
    
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
                    LazyVStack(spacing: 20) {
                        ForEach(chatService.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                                .transition(.opacity)
                        }
                        
                        if chatService.isLoading {
                            LoadingDots()
                                .padding()
                                .id("loading")
                        }
                        
                        // 底部锚点
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, 50)
                    .padding(.vertical, 20)
                    .onChange(of: chatService.messages) { _, _ in
                        shouldScrollToBottom = true
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: chatService.streamResponse) { _, _ in
                        shouldScrollToBottom = true
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: messageText) { _, _ in
                        shouldScrollToBottom = true
                        scrollToBottom(proxy: proxy)
                    }
                    .onAppear {
                        shouldScrollToBottom = true
                        scrollToBottom(proxy: proxy)
                    }
                }
            }
            .onChange(of: shouldScrollToBottom) { _, newValue in
                if newValue {
                    DispatchQueue.main.async {
                        withAnimation {
                            shouldScrollToBottom = false
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
                
                Button(action: {
                    if chatService.isLoading {
                        chatService.cancelGeneration()
                    } else {
                        sendMessage()
                    }
                }) {
                    Circle()
                        .fill(chatService.isLoading ? Color.black : (messageText.isEmpty ? Color.gray.opacity(0.3) : Color.black))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: chatService.isLoading ? "stop.fill" : "arrow.up")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        )
                }
                .disabled(messageText.isEmpty && !chatService.isLoading)
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
        
        Task { @MainActor in
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
    
    // 修改滚动辅助函数
    private func scrollToBottom(proxy: ScrollViewProxy) {
        // 使用 asyncAfter 确保在内容更新后滚动
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom", anchor: .bottom)
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

// 在 CodeBlockView 前添加代码高亮相关的结构体
struct CodeHighlighter {
    struct Token {
        let text: String
        let type: TokenType
    }
    
    enum TokenType {
        case keyword
        case string
        case number
        case comment
        case `operator`
        case identifier
        case type
        case plain
        
        var color: Color {
            switch self {
            case .keyword: return .blue
            case .string: return .green
            case .number: return .orange
            case .comment: return .gray
            case .operator: return .purple
            case .identifier: return .primary
            case .type: return Color(red: 0.8, green: 0.2, blue: 0.2)
            case .plain: return .primary
            }
        }
    }
    
    static func highlightCode(_ code: String, language: String) -> AttributedString {
        var attributedString = AttributedString(code)
        
        // 定义语法规则
        let patterns: [(pattern: String, type: TokenType)] = [
            // 关键字
            ("\\b(func|let|var|if|else|guard|return|while|for|in|switch|case|break|continue|struct|class|enum|import|try|catch|throws|async|await)\\b", .keyword),
            // 字符串
            ("\"[^\"\\\\]*(?:\\\\.[^\"\\\\]*)*\"", .string),
            // 数字
            ("\\b\\d+\\.?\\d*\\b", .number),
            // 注释
            ("//.*?$|/\\*.*?\\*/", .comment),
            // 运算符
            ("[=+\\-*/<>!&|^~?:%]", .operator),
            // 类型
            ("\\b(String|Int|Double|Bool|Array|Dictionary|Set|Any|Void)\\b", .type)
        ]
        
        for (pattern, type) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
            let nsRange = NSRange(code.startIndex..., in: code)
            let matches = regex.matches(in: code, range: nsRange)
            
            for match in matches.reversed() {
                guard let range = Range(match.range, in: code),
                      let attributedRange = Range(range, in: attributedString) else { continue }
                attributedString[attributedRange].foregroundColor = type.color
            }
        }
        
        return attributedString
    }
}

// 添加一个用于缓存代码块的类
class CodeBlockCache: ObservableObject {
    static let shared = CodeBlockCache()
    private var cache: [String: AttributedString] = [:]
    
    func getHighlightedCode(_ code: String, language: String) -> AttributedString {
        let key = "\(code)_\(language)"
        if let cached = cache[key] {
            return cached
        }
        let highlighted = CodeHighlighter.highlightCode(code, language: language)
        cache[key] = highlighted
        return highlighted
    }
}

// 修改 CodeBlockView
struct CodeBlockView: View {
    let content: String
    @State private var showCopyButton = false
    @State private var showCopiedFeedback = false
    @State private var isLoaded = false
    
    private func extractLanguageAndCode() -> (language: String, code: String) {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        if content.hasPrefix("```") {
            let firstLine = String(lines[0]).trimmingCharacters(in: .whitespaces)
            let language = firstLine.dropFirst(3).trimmingCharacters(in: .whitespaces)
            let codeLines = Array(lines.dropFirst().dropLast())
            let code = codeLines.joined(separator: "\n")
            return (language.isEmpty ? "plaintext" : language, code)
        }
        return ("plaintext", content)
    }
    
    var body: some View {
        let extracted = extractLanguageAndCode()
        
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text(extracted.language)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(extracted.code, forType: .string)
                    withAnimation {
                        showCopiedFeedback = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            showCopiedFeedback = false
                        }
                    }
                }) {
                    Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.controlBackgroundColor))
            
            // 代码内容
            Group {
                if isLoaded {
                    Text(CodeBlockCache.shared.getHighlightedCode(extracted.code, language: extracted.language))
                        .textSelection(.enabled)
                        .font(.system(.body, design: .monospaced))
                } else {
                    Text(extracted.code)
                        .textSelection(.enabled)
                        .font(.system(.body, design: .monospaced))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isLoaded = true
                            }
                        }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.textBackgroundColor))
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// 修改 MessageBubble 中 AI 回复部分的样式
struct MessageBubble: View {
    let message: ChatMessage
    @State private var showCopyButton = false
    @State private var showCopiedFeedback = false
    @StateObject private var chatService = ChatService.shared
    @State private var processedContent: (normalText: String, codeBlocks: [String])?
    
    // 添加对消息内容的监听
    private var messageContent: String {
        // 如果是最后一条 AI 消息且正在加载，使用实时内容
        if !message.isUser && message.id == chatService.messages.last?.id && chatService.isLoading {
            return chatService.streamResponse
        }
        return message.content
    }
    
    private var processedContentValue: (normalText: String, codeBlocks: [String]) {
        if let cached = processedContent, !chatService.isLoading {
            return cached
        }
        let result = processContent(messageContent)
        if !chatService.isLoading {
            DispatchQueue.main.async {
                processedContent = result
            }
        }
        return result
    }
    
    private func processContent(_ content: String) -> (normalText: String, codeBlocks: [String]) {
        var normalText = content
        var codeBlocks: [String] = []
        
        // 匹配代码块
        let pattern = "```[\\s\\S]*?```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (content, [])
        }
        
        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        
        // 确保匹配结果有效
        for match in matches.reversed() {
            if let range = Range(match.range, in: content) {
                let codeBlock = String(content[range])
                codeBlocks.insert(codeBlock, at: 0)
                
                // 从原文中移除代码块，替换为占位符
                if let textRange = Range(match.range, in: normalText) {
                    normalText.replaceSubrange(textRange, with: "{{CODE_BLOCK}}")
                }
            }
        }
        
        // 确保代码块数量和占位符数量匹配
        let placeholderCount = normalText.components(separatedBy: "{{CODE_BLOCK}}").count - 1
        if codeBlocks.count > placeholderCount {
            codeBlocks = Array(codeBlocks.prefix(placeholderCount))
        }
        
        return (normalText, codeBlocks)
    }
    
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
                        .background(Color(.controlBackgroundColor))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                        .textSelection(.enabled)
                } else {
                    let processed = processedContentValue
                    let textParts = processed.normalText.components(separatedBy: "{{CODE_BLOCK}}")
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(zip(textParts.indices, textParts)), id: \.0) { index, text in
                            // 显示文本部分
                            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Markdown(text)
                                    .markdownTheme(.gitHub.text {
                                        ForegroundColor(.primary)
                                        BackgroundColor(.clear)
                                        FontSize(14)
                                    })
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 8)
                            }
                            
                            // 安全地显示代码块
                            if index < processed.codeBlocks.count {
                                CodeBlockView(content: processed.codeBlocks[index])
                                    .id("\(message.id)-code-\(index)")
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        showCopyButton = hovering
                    }
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
                                .foregroundColor(.secondary)
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
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .opacity(showCopyButton ? 1 : 0)
                        .frame(width: 24, height: 24)
                    }
                    .padding(.top, -8)
                }
            }
            
            if !message.isUser {
                Spacer()
            }
        }
        .textSelection(.enabled)
        .id("\(message.id)-\(messageContent.hashValue)")  // 添加动态ID以触发重新渲染
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
 
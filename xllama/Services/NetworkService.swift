import Foundation
import Network

@MainActor
class NetworkService: ObservableObject {
    static let shared = NetworkService()
    
    @Published var isRunning = false {
        didSet {
            // 当状态改变时保存到 UserDefaults
            UserDefaults.standard.set(isRunning, forKey: "network_server_status")
        }
    }
    
    @Published var serverURL: String = ""
    @Published var serverPort: UInt16 {
        didSet {
            UserDefaults.standard.set(serverPort, forKey: "network_server_port")
            // 如果服务正在运行，重启服务以应用新端口
            if isRunning {
                stopServer()
                startServer()
            }
        }
    }
    
    private var httpServer: HttpServer?
    
    init() {
        // 从 UserDefaults 读取上次的运行状态
        self.isRunning = UserDefaults.standard.bool(forKey: "network_server_status")
        
        // 从 UserDefaults 读取保存的端口，如果没有则使用默认值 8383
        self.serverPort = UInt16(UserDefaults.standard.integer(forKey: "network_server_port"))
        if self.serverPort == 0 {
            self.serverPort = 8383
        }
        
        // 如果之前是运行状态或设置了自动启动，则启动服务器
        if self.isRunning || UserDefaults.standard.bool(forKey: "network_server_autostart") {
            startServer()
        }
    }
    
    func startServer() {
        guard !isRunning else { return }
        
        httpServer = HttpServer()
        
        // 配置路由
        configureRoutes()
        
        do {
            guard let server = httpServer else {
                print("Server initialization failed")
                return
            }
            try server.start(port: serverPort)
            isRunning = true
            
            // 获取本机IP地址
            if let ipAddress = getLocalIPAddress() {
                serverURL = "http://\(ipAddress):\(serverPort)"
            }
        } catch {
            print("Server start error: \(error)")
            isRunning = false
            serverURL = ""
        }
    }
    
    func stopServer() {
        httpServer?.stop()
        isRunning = false
        serverURL = ""
        // 清除自动启动状态
        UserDefaults.standard.set(false, forKey: "network_server_autostart")
    }
    
    private func configureRoutes() {
        // 添加根路径处理
        httpServer?.get("/") { _, responseHandler in
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <title>XDOLLama Chat</title>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
                <!-- 添加 marked.js -->
                <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
                <!-- 添加代码高亮支持 -->
                <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/highlight.js@11.8.0/styles/github.min.css">
                <script src="https://cdn.jsdelivr.net/npm/highlight.js@11.8.0/lib/highlight.min.js"></script>
                <style>
                    * {
                        margin: 0;
                        padding: 0;
                        box-sizing: border-box;
                    }
                    
                    body {
                        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                        line-height: 1.6;
                        color: #1a1a1a;
                        background-color: #ffffff;
                        height: 100vh;
                        display: flex;
                        flex-direction: column;
                    }
                    
                    .header {
                        background-color: #ffffff;
                        padding: 12px 16px;
                        border-bottom: 1px solid #e5e5e5;
                        display: flex;
                        justify-content: space-between;
                        align-items: center;
                        position: fixed;
                        top: 0;
                        left: 0;
                        right: 0;
                        z-index: 100;
                        height: 56px;
                        backdrop-filter: blur(10px);
                        -webkit-backdrop-filter: blur(10px);
                    }
                    
                    .header h1 {
                        font-size: 16px;
                        font-weight: 500;
                        color: #1a1a1a;
                    }
                    
                    select {
                        padding: 6px 10px;
                        border: 1px solid #e5e5e5;
                        border-radius: 6px;
                        font-size: 14px;
                        outline: none;
                        background-color: #fff;
                        color: #1a1a1a;
                        cursor: pointer;
                        min-width: 120px;
                    }
                    
                    select:hover {
                        border-color: #000000;
                    }
                    
                    #messages {
                        flex: 1;
                        overflow-y: auto;
                        padding: 0;
                        margin: 56px 0 80px 0;
                        display: flex;
                        flex-direction: column;
                        -webkit-overflow-scrolling: touch;
                    }
                    
                    .message-container {
                        width: 100%;
                        padding: 20px 0;
                        display: flex;
                        justify-content: center;
                        border-bottom: 1px solid rgba(0, 0, 0, 0.1);
                    }
                    
                    .message-container.user {
                        background-color: rgba(247, 247, 248);
                    }
                    
                    @media (prefers-color-scheme: dark) {
                        .message-container.user {
                            background-color: rgba(52, 53, 65);
                        }
                        
                        .message-container {
                            border-bottom-color: rgba(255, 255, 255, 0.1);
                        }
                    }
                    
                    .message-content {
                        max-width: 768px;
                        width: 100%;
                        padding: 0 16px;
                        margin: 0 auto;
                    }
                    
                    .message-wrapper {
                        display: flex;
                        gap: 16px;
                        align-items: flex-start;
                    }
                    
                    .avatar {
                        width: 30px;
                        height: 30px;
                        border-radius: 2px;
                        display: flex;
                        align-items: center;
                        justify-content: center;
                        font-weight: 500;
                        font-size: 14px;
                        flex-shrink: 0;
                    }
                    
                    .user-avatar {
                        background-color: rgb(171, 104, 255);
                        color: white;
                    }
                    
                    .ai-avatar {
                        background: rgb(16, 163, 127);
                        color: white;
                    }
                    
                    .message {
                        font-size: 15px;
                        line-height: 1.6;
                        padding-top: 4px;
                        overflow-wrap: break-word;
                    }
                    
                    .message h1, .message h2, .message h3, 
                    .message h4, .message h5, .message h6 {
                        margin: 1em 0 0.5em;
                        line-height: 1.2;
                    }
                    
                    .message h1 { font-size: 1.8em; }
                    .message h2 { font-size: 1.5em; }
                    .message h3 { font-size: 1.3em; }
                    
                    .message ul, .message ol {
                        margin: 0.5em 0;
                        padding-left: 2em;
                    }
                    
                    .message pre {
                        background-color: #f6f8fa;
                        border-radius: 6px;
                        padding: 16px;
                        margin: 16px 0;
                        overflow-x: auto;
                    }
                    
                    .message code {
                        font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, monospace;
                        font-size: 0.9em;
                        padding: 0.2em 0.4em;
                        background-color: rgba(175, 184, 193, 0.2);
                        border-radius: 6px;
                    }
                    
                    .message pre code {
                        padding: 0;
                        background-color: transparent;
                    }
                    
                    .message blockquote {
                        margin: 0.5em 0;
                        padding: 0.5em 1em;
                        border-left: 4px solid #ddd;
                        color: #666;
                    }
                    
                    .message table {
                        border-collapse: collapse;
                        margin: 1em 0;
                        width: 100%;
                    }
                    
                    .message th, .message td {
                        border: 1px solid #ddd;
                        padding: 6px 12px;
                    }
                    
                    .message th {
                        background-color: #f6f8fa;
                    }
                    
                    /* 暗黑模式下的 Markdown 样式 */
                    @media (prefers-color-scheme: dark) {
                        .message pre {
                            background-color: #161b22;
                        }
                        
                        .message code {
                            background-color: rgba(110, 118, 129, 0.4);
                        }
                        
                        .message blockquote {
                            border-left-color: #404040;
                            color: #999;
                        }
                        
                        .message th, .message td {
                            border-color: #404040;
                        }
                        
                        .message th {
                            background-color: #161b22;
                        }
                    }
                    
                    .input-container {
                        position: fixed;
                        bottom: 0;
                        left: 0;
                        right: 0;
                        padding: 12px;
                        background-color: #ffffff;
                        border-top: 1px solid #e5e5e5;
                        display: flex;
                        justify-content: center;
                        backdrop-filter: blur(10px);
                        -webkit-backdrop-filter: blur(10px);
                    }
                    
                    .input-wrapper {
                        position: relative;
                        width: 100%;
                        max-width: 768px;
                        margin: 0 auto;
                        background-color: #ffffff;
                        border: 1px solid #e5e5e5;
                        border-radius: 12px;
                        box-shadow: 0 2px 6px rgba(0, 0, 0, 0.05);
                    }
                    
                    #input {
                        width: 100%;
                        padding: 12px 76px 12px 16px;
                        border: none;
                        border-radius: 12px;
                        font-size: 16px;
                        resize: none;
                        outline: none;
                        min-height: 24px;
                        max-height: 120px;
                        line-height: 1.5;
                        background: transparent;
                        -webkit-appearance: none;
                    }
                    
                    button {
                        position: absolute;
                        right: 6px;
                        bottom: 6px;
                        top: 6px;
                        width: 64px;
                        background-color: #2196F3;
                        color: white;
                        border: none;
                        border-radius: 8px;
                        font-size: 15px;
                        font-weight: 500;
                        cursor: pointer;
                        transition: background-color 0.2s;
                        display: flex;
                        align-items: center;
                        justify-content: center;
                        -webkit-tap-highlight-color: transparent;
                    }
                    
                    @media (max-width: 768px) {
                        body {
                            font-size: 15px;
                        }
                        
                        .header h1 {
                            font-size: 16px;
                        }
                        
                        select {
                            font-size: 14px;
                            padding: 6px 8px;
                            min-width: 100px;
                        }
                        
                        .message-container {
                            padding: 12px 0;
                        }
                        
                        .user-icon, .ai-icon {
                            width: 28px;
                            height: 28px;
                            margin-right: 12px;
                            font-size: 12px;
                        }
                        
                        .input-container {
                            padding: 8px;
                        }
                        
                        .input-wrapper {
                            border-radius: 18px;
                        }
                        
                        #input {
                            font-size: 15px;
                            padding: 10px 70px 10px 14px;
                        }
                        
                        button {
                            right: 4px;
                            width: 60px;
                            font-size: 14px;
                            border-radius: 16px;
                        }
                    }
                    
                    /* 添加暗黑模式支持 */
                    @media (prefers-color-scheme: dark) {
                        body {
                            background-color: #1a1a1a;
                            color: #ffffff;
                        }
                        
                        .header {
                            background-color: rgba(26, 26, 26, 0.8);
                            border-bottom-color: #333;
                        }
                        
                        .input-container {
                            background-color: rgba(26, 26, 26, 0.8);
                            border-top-color: #333;
                        }
                        
                        .input-wrapper {
                            background-color: #2d2d2d;
                            border-color: #333;
                        }
                        
                        #input {
                            color: #ffffff;
                        }
                        
                        .message-container.user {
                            background-color: #2d2d2d;
                        }
                        
                        select {
                            background-color: #2d2d2d;
                            border-color: #333;
                            color: #ffffff;
                        }
                        
                        button:disabled {
                            background-color: #333;
                            color: #666;
                        }
                    }
                    
                    /* 添加安全区域支持 */
                    @supports(padding: max(0px)) {
                        .header {
                            padding-top: max(12px, env(safe-area-inset-top));
                            height: max(56px, env(safe-area-inset-top) + 44px);
                        }
                        
                        #messages {
                            margin-top: max(56px, env(safe-area-inset-top) + 44px);
                        }
                        
                        .input-container {
                            padding-bottom: max(12px, env(safe-area-inset-bottom));
                        }
                    }
                    
                    .model-selector {
                        display: flex;
                        gap: 8px;
                        align-items: center;
                    }
                    
                    .model-selector select {
                        min-width: 120px;
                    }
                    
                    @media (max-width: 768px) {
                        .model-selector {
                            flex-direction: column;
                            align-items: stretch;
                        }
                    }
                    
                    /* 添加模型选择弹窗样式 */
                    .modal {
                        display: none;
                        position: fixed;
                        top: 0;
                        left: 0;
                        right: 0;
                        bottom: 0;
                        background-color: rgba(0, 0, 0, 0.4);
                        z-index: 1000;
                        backdrop-filter: blur(8px);
                        -webkit-backdrop-filter: blur(8px);
                        animation: fadeIn 0.2s ease-out;
                    }
                    
                    .modal-content {
                        position: absolute;
                        top: 50%;
                        left: 50%;
                        transform: translate(-50%, -50%);
                        background-color: #ffffff;
                        border-radius: 12px;
                        width: 90%;
                        max-width: 360px;
                        display: flex;
                        flex-direction: column;
                        overflow: hidden;  /* 确保内容不会溢出圆角 */
                    }
                    
                    .modal-header {
                        padding: 16px;
                        border-bottom: 1px solid #f0f0f0;
                    }
                    
                    .modal-title {
                        font-size: 16px;
                        font-weight: 500;
                        margin: 0;
                    }
                    
                    .modal-body {
                        padding: 16px;
                    }
                    
                    .select-group {
                        margin-bottom: 16px;
                    }
                    
                    .select-label {
                        display: block;
                        font-size: 14px;
                        color: #666;
                        margin-bottom: 8px;
                    }
                    
                    .select-group select {
                        width: 100%;
                        padding: 8px 12px;
                        border: 1px solid #e5e5e5;
                        border-radius: 8px;
                        font-size: 14px;
                        background-color: #f5f5f5;
                    }
                    
                    /* 修改按钮容器样式 */
                    .modal-footer {
                        display: flex;
                        justify-content: space-between;  /* 左右分布 */
                        padding: 16px;
                        background-color: #fff;  /* 确保景是白色 */
                        border-top: 1px solid #f0f0f0;
                    }
                    
                    /* 修改按钮样式 */
                    .modal-button {
                        flex: 1;  /* 按钮占据相等空间 */
                        padding: 8px 0;
                        border: none;
                        border-radius: 8px;
                        font-size: 14px;
                        font-weight: 500;
                        cursor: pointer;
                        transition: background-color 0.2s;
                    }
                    
                    .modal-button.secondary {
                        background: none;  /* 移除背景色 */
                        color: #666;
                        margin-right: 8px;  /* 添加右边距 */
                    }
                    
                    .modal-button.primary {
                        background-color: #2196F3;
                        color: white;
                        margin-left: 8px;  /* 添加左边距 */
                    }
                    
                    /* 暗黑模式支持 */
                    @media (prefers-color-scheme: dark) {
                        .modal-content {
                            background-color: #2d2d2d;
                        }
                        
                        .modal-header {
                            border-bottom-color: #404040;
                        }
                        
                        .modal-footer {
                            background-color: #2d2d2d;
                            border-top-color: #404040;
                        }
                        
                        .select-group select {
                            background-color: #1a1a1a;
                            border-color: #404040;
                            color: #fff;
                        }
                        
                        .modal-button.secondary {
                            color: #999;
                        }
                    }
                    
                    /* 修改顶部按钮样式 */
                    .settings-button {
                        padding: 6px;
                        border-radius: 6px;
                        background: none;
                        border: none;
                        cursor: pointer;
                        color: #666;
                        transition: background-color 0.2s;
                    }
                    
                    .settings-button:hover {
                        background-color: rgba(0, 0, 0, 0.05);
                    }
                    
                    @media (prefers-color-scheme: dark) {
                        .modal-content {
                            background-color: #2d2d2d;
                            color: #ffffff;
                        }
                        
                        .modal-button.secondary {
                            background-color: #404040;
                            color: #ffffff;
                        }
                        
                        .settings-button {
                            color: #999;
                        }
                        
                        .settings-button:hover {
                            background-color: rgba(255, 255, 255, 0.1);
                        }
                    }
                    
                    /* 添加加载动画的 CSS 样式 */
                    .loading-dots {
                        display: inline-flex;
                        align-items: center;
                        gap: 4px;
                        height: 24px;
                    }
                    
                    .loading-dots span {
                        width: 4px;
                        height: 4px;
                        background-color: currentColor;
                        border-radius: 50%;
                        animation: dot-flashing 1s infinite linear alternate;
                        opacity: 0.3;
                    }
                    
                    .loading-dots span:nth-child(2) {
                        animation-delay: 0.2s;
                    }
                    
                    .loading-dots span:nth-child(3) {
                        animation-delay: 0.4s;
                    }
                    
                    @keyframes dot-flashing {
                        0% {
                            opacity: 0.3;
                        }
                        100% {
                            opacity: 1;
                        }
                    }
                    
                    .header-buttons {
                        display: flex;
                        gap: 8px;
                        align-items: center;
                    }
                    
                    .header-button {
                        padding: 6px;
                        border-radius: 6px;
                        background: none;
                        border: none;
                        cursor: pointer;
                        color: #666;
                        transition: background-color 0.2s;
                        display: flex;
                        align-items: center;
                        justify-content: center;
                    }
                    
                    .header-button:hover {
                        background-color: rgba(0, 0, 0, 0.05);
                    }
                    
                    @media (prefers-color-scheme: dark) {
                        .header-button {
                            color: #999;
                        }
                        
                        .header-button:hover {
                            background-color: rgba(255, 255, 255, 0.1);
                        }
                    }
                </style>
            </head>
            <body>
                <div class="header">
                    <h1>XDOLLama Chat</h1>
                    <div class="header-buttons">
                        <button class="header-button" onclick="newChat()" title="新建对话">
                            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <path d="M12 5v14M5 12h14"/>
                            </svg>
                        </button>
                        <button class="header-button" onclick="openSettings()" title="设置">
                            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <path d="M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z"/>
                                <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1Z"/>
                            </svg>
                        </button>
                    </div>
                </div>
                
                <div id="messages"></div>
                
                <div class="input-container">
                    <div class="input-wrapper">
                        <textarea id="input" placeholder="输入消息..." rows="1"></textarea>
                        <button onclick="sendMessage()" id="sendButton">发送</button>
                    </div>
                </div>
                
                <!-- 添加模型选择弹窗 -->
                <div id="settingsModal" class="modal">
                    <div class="modal-content">
                        <div class="modal-header">
                            <h3 class="modal-title">模型设置</h3>
                        </div>
                        <div class="modal-body">
                            <div class="select-group">
                                <label class="select-label">选择服务</label>
                                <select id="serviceType" onchange="updateModelList()">
                                    <option value="ollama">Ollama</option>
                                    <option value="xinference">Xinference</option>
                                    <option value="dify">Dify</option>
                                </select>
                            </div>
                            <div class="select-group">
                                <label class="select-label">选择模型</label>
                                <select id="modelType">
                                    <option value="">选择模型...</option>
                                </select>
                            </div>
                            <div class="modal-footer">
                                <button class="modal-button secondary" onclick="closeSettings()">取消</button>
                                <button class="modal-button primary" onclick="saveSettings()">确定</button>
                            </div>
                        </div>
                    </div>
                </div>
                
                <script>
                    const input = document.getElementById('input');
                    const messages = document.getElementById('messages');
                    const sendButton = document.getElementById('sendButton');
                    
                    function adjustInputHeight() {
                        input.style.height = '24px';  // 重置高度
                        const newHeight = Math.min(input.scrollHeight, 200);
                        input.style.height = newHeight + 'px';
                        
                        // 调整按钮位置
                        const button = document.getElementById('sendButton');
                        if (newHeight > 48) {
                            button.style.top = 'auto';
                            button.style.bottom = '8px';
                        } else {
                            button.style.top = '6px';
                            button.style.bottom = '6px';
                        }
                    }
                    
                    input.addEventListener('input', adjustInputHeight);
                    
                    // 配置 marked
                    marked.setOptions({
                        highlight: function(code, lang) {
                            if (lang && hljs.getLanguage(lang)) {
                                return hljs.highlight(code, { language: lang }).value;
                            }
                            return hljs.highlightAuto(code).value;
                        },
                        breaks: true,
                        gfm: true
                    });
                    
                    // 修改添加消息的函数
                    function addMessage(role, content) {
                        const messageHtml = `
                            <div class="message-container ${role === 'user' ? 'user' : ''}">
                                <div class="message-content">
                                    <div class="message-wrapper">
                                        <div class="avatar ${role === 'user' ? 'user-avatar' : 'ai-avatar'}">${role === 'user' ? 'U' : 'AI'}</div>
                                        <div class="message">${role === 'user' ? content : marked.parse(content)}</div>
                                    </div>
                                </div>
                            </div>
                        `;
                        messages.insertAdjacentHTML('beforeend', messageHtml);
                        
                        // 高亮新添加的代码块
                        const newMessage = messages.lastElementChild;
                        newMessage.querySelectorAll('pre code').forEach((block) => {
                            hljs.highlightBlock(block);
                        });
                    }
                    
                    // 修改发送消息的函数
                    async function sendMessage() {
                        const serviceType = document.getElementById('serviceType').value;
                        const modelType = document.getElementById('modelType').value;
                        const message = input.value.trim();
                        
                        if (!message || !modelType) {
                            if (!modelType) {
                                alert('请选择模型');
                            }
                            return;
                        }
                        
                        sendButton.disabled = true;
                        
                        // 添加用户消息
                        addMessage('user', message);
                        
                        // 添加 AI 加载动画
                        messages.innerHTML += `
                            <div class="message-container" id="ai-loading">
                                <div class="message-content">
                                    <div class="message-wrapper">
                                        <div class="avatar ai-avatar">AI</div>
                                        <div class="message">
                                            <div class="loading-dots">
                                                <span></span>
                                                <span></span>
                                                <span></span>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        `;
                        
                        input.value = '';
                        input.style.height = '48px';
                        messages.scrollTop = messages.scrollHeight;
                        
                        try {
                            const response = await fetch('/chat', {
                                method: 'POST',
                                headers: {
                                    'Content-Type': 'application/json',
                                },
                                body: JSON.stringify({
                                    modelType: serviceType,
                                    model: modelType,
                                    message: message
                                })
                            });
                            
                            const data = await response.json();
                            
                            // 移除加载动画
                            const loadingElement = document.getElementById('ai-loading');
                            if (loadingElement) {
                                loadingElement.remove();
                            }
                            
                            // 添加 AI 响应
                            addMessage('ai', data.response);
                            messages.scrollTop = messages.scrollHeight;
                        } catch (error) {
                            console.error('Error:', error);
                            
                            // 移除加载动画
                            const loadingElement = document.getElementById('ai-loading');
                            if (loadingElement) {
                                loadingElement.remove();
                            }
                            
                            // 显示错误消息
                            messages.innerHTML += `
                                <div class="message-container">
                                    <div class="message-content">
                                        <div class="message-wrapper">
                                            <div class="avatar ai-avatar">AI</div>
                                            <div class="message" style="color: #dc2626;">Error: ${error.message}</div>
                                        </div>
                                    </div>
                                </div>
                            `;
                        } finally {
                            sendButton.disabled = false;
                            input.focus();
                        }
                    }
                    
                    input.addEventListener('keypress', function(e) {
                        if (e.key === 'Enter' && !e.shiftKey) {
                            e.preventDefault();
                            sendMessage();
                        }
                    });
                    
                    input.focus();
                    
                    let currentServiceType = '';
                    let currentModelType = '';
                    
                    function openSettings() {
                        document.getElementById('settingsModal').style.display = 'block';
                        // 保存当前选择
                        currentServiceType = document.getElementById('serviceType').value;
                        currentModelType = document.getElementById('modelType').value;
                    }
                    
                    function closeSettings() {
                        document.getElementById('settingsModal').style.display = 'none';
                        // 恢复之前的选择
                        document.getElementById('serviceType').value = currentServiceType;
                        document.getElementById('modelType').value = currentModelType;
                    }
                    
                    function saveSettings() {
                        document.getElementById('settingsModal').style.display = 'none';
                        // 更新当前选择
                        currentServiceType = document.getElementById('serviceType').value;
                        currentModelType = document.getElementById('modelType').value;
                    }
                    
                    // 点击模态框外部关闭
                    window.onclick = function(event) {
                        const modal = document.getElementById('settingsModal');
                        if (event.target == modal) {
                            closeSettings();
                        }
                    }
                    
                    // 添加获取模型列表的函数
                    async function updateModelList() {
                        const serviceType = document.getElementById('serviceType').value;
                        const modelSelect = document.getElementById('modelType');
                        
                        try {
                            const response = await fetch('/models');
                            const data = await response.json();
                            
                            modelSelect.innerHTML = '<option value="">选择模型...</option>';
                            
                            let models = [];
                            switch(serviceType) {
                                case 'ollama':
                                    models = data.ollama;
                                    models.forEach(model => {
                                        modelSelect.innerHTML += `<option value="${model.name}">${model.name}</option>`;
                                    });
                                    break;
                                case 'xinference':
                                    models = data.xinference;
                                    models.forEach(model => {
                                        if (model.isAvailable) {
                                            modelSelect.innerHTML += `<option value="${model.name}">${model.name}</option>`;
                                        }
                                    });
                                    break;
                                case 'dify':
                                    models = data.dify;
                                    models.forEach(model => {
                                        modelSelect.innerHTML += `<option value="${model.name}">${model.name}</option>`;
                                    });
                                    break;
                            }
                        } catch (error) {
                            console.error('Error fetching models:', error);
                        }
                    }
                    
                    // 页面加载时获取模型列表
                    document.addEventListener('DOMContentLoaded', function() {
                        updateModelList();
                    });
                    
                    // 添加新建对话函数
                    function newChat() {
                        // 清空消息列表
                        messages.innerHTML = '';
                        
                        // 清空输入框
                        input.value = '';
                        input.style.height = '48px';
                        
                        // 重置滚动位置
                        messages.scrollTop = 0;
                        
                        // 聚焦输入框
                        input.focus();
                    }
                </script>
            </body>
            </html>
            """
            
            let responseData = html.data(using: .utf8)!
            responseHandler(.html(responseData))
        }
        
        // 添加 OPTIONS 请求支持
        httpServer?.routes["OPTIONS /chat"] = { _, responseHandler in
            var response = "HTTP/1.1 200 OK\r\n"
            response += "Access-Control-Allow-Origin: *\r\n"
            response += "Access-Control-Allow-Methods: POST, OPTIONS\r\n"
            response += "Access-Control-Allow-Headers: Content-Type\r\n"
            response += "Content-Length: 0\r\n"
            response += "\r\n"
            
            let responseData = response.data(using: .utf8)!
            responseHandler(.ok(responseData))
        }
        
        // 处理聊天请求
        httpServer?.post("/chat") { request, responseHandler in
            Task {
                do {
                    guard let data = request.body,
                          let chatRequest = try? JSONDecoder().decode(ChatRequest.self, from: data) else {
                        print("Failed to decode chat request")
                        responseHandler(.badRequest)
                        return
                    }
                    
                    print("Received chat request: \(chatRequest)")
                    
                    var response: String = ""
                    do {
                        switch chatRequest.modelType {
                        case .ollama:
                            response = try await self.forwardToOllama(chatRequest.message, model: chatRequest.model)
                        case .xinference:
                            response = try await self.forwardToXinference(chatRequest.message, model: chatRequest.model)
                        case .dify:
                            response = try await self.forwardToDify(chatRequest.message, model: chatRequest.model)
                        }
                        
                        print("Got response: \(response)")
                        
                        let responseData = ChatResponse(response: response)
                        let jsonData = try JSONEncoder().encode(responseData)
                        responseHandler(.ok(jsonData))
                    } catch {
                        print("Error forwarding request: \(error)")
                        // 返回具体的错误信息
                        let errorResponse = ChatResponse(response: "Error: \(error.localizedDescription)")
                        if let errorData = try? JSONEncoder().encode(errorResponse) {
                            responseHandler(.ok(errorData))
                        } else {
                            responseHandler(.internalServerError)
                        }
                    }
                } catch {
                    print("Error handling request: \(error)")
                    responseHandler(.internalServerError)
                }
            }
        }
        
        // 获取可用模型列表
        httpServer?.get("/models") { _, responseHandler in
            Task {
                do {
                    let models = NetworkModelsResponse(
                        ollama: try await OllamaService.shared.fetchModels(),
                        xinference: XinferenceService.shared.models,
                        dify: DifyService.shared.models
                    )
                    let jsonData = try JSONEncoder().encode(models)
                    responseHandler(.ok(jsonData))
                } catch {
                    responseHandler(.internalServerError)
                }
            }
        }
    }
    
    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            let interface = ptr?.pointee
            let addrFamily = interface?.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: (interface?.ifa_name)!)
                if name == "en0" || name == "en1" || name == "en2" || name == "en3" || name == "en4" || name == "en5" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface?.ifa_addr,
                              socklen_t((interface?.ifa_addr.pointee.sa_len)!),
                              &hostname,
                              socklen_t(hostname.count),
                              nil,
                              0,
                              NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }
    
    private func forwardToOllama(_ message: String, model: String) async throws -> String {
        guard let url = URL(string: "\(OllamaService.shared.baseURL)/api/chat") else {
            throw URLError(.badURL)
        }
        
        let parameters: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": message]
            ],
            "stream": false
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        print("Sending request to Ollama: \(parameters)")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let responseString = String(data: data, encoding: .utf8) {
            print("Ollama response: \(responseString)")
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        } else {
            throw URLError(.cannotParseResponse)
        }
    }
    
    private func forwardToXinference(_ message: String, model: String) async throws -> String {
        guard let url = URL(string: "\(XinferenceService.shared.baseURL)/v1/chat/completions") else {
            throw URLError(.badURL)
        }
        
        let parameters: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": message]
            ],
            "stream": false
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct XinferenceResponse: Codable {
            let choices: [Choice]
            
            struct Choice: Codable {
                let message: Message
                
                struct Message: Codable {
                    let content: String
                }
            }
        }
        
        let response = try JSONDecoder().decode(XinferenceResponse.self, from: data)
        return response.choices.first?.message.content ?? ""
    }
    
    private func forwardToDify(_ message: String, model: String) async throws -> String {
        guard let url = URL(string: "\(DifyService.shared.baseURL)/chat-messages"),
              !DifyService.shared.apiKey.isEmpty else {
            throw URLError(.badURL)
        }
        
        let parameters: [String: Any] = [
            "inputs": [:],
            "query": message,
            "response_mode": "blocking",
            "conversation_id": "",
            "user": "xllama_user",
            "model": model
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(DifyService.shared.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct DifyResponse: Codable {
            let answer: String
        }
        
        let response = try JSONDecoder().decode(DifyResponse.self, from: data)
        return response.answer
    }
}

// 请求和响应模型
struct ChatRequest: Codable {
    enum ModelType: String, Codable {
        case ollama
        case xinference
        case dify
    }
    
    let modelType: ModelType
    let model: String
    let message: String
}

struct ChatResponse: Codable {
    let response: String
}

// 修改 ModelsResponse 为 NetworkModelsResponse
struct NetworkModelsResponse: Codable {
    let ollama: [OllamaModel]
    let xinference: [XinferenceModel]
    let dify: [DifyModel]
}

// 简单的 HTTP 服务器实现
class HttpServer {
    private var listener: NWListener?
    var routes: [String: (HttpRequest, @escaping (HttpResponse) -> Void) -> Void] = [:]
    
    func start(port: UInt16) throws {
        let parameters = NWParameters.tcp
        let nwPort = NWEndpoint.Port(rawValue: port)!
        listener = try NWListener(using: parameters, on: nwPort)
        
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Server ready on port \(port)")
            case .failed(let error):
                print("Server failed with error: \(error)")
                self?.stop()
            default:
                break
            }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        
        listener?.start(queue: .main)
    }
    
    func stop() {
        listener?.cancel()
    }
    
    func post(_ path: String, handler: @escaping (HttpRequest, @escaping (HttpResponse) -> Void) -> Void) {
        routes["POST " + path] = handler
    }
    
    func get(_ path: String, handler: @escaping (HttpRequest, @escaping (HttpResponse) -> Void) -> Void) {
        routes["GET " + path] = handler
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Connection ready")
                self?.receiveRequest(connection)
            case .failed(let error):
                print("Connection failed: \(error)")
                connection.cancel()
            case .cancelled:
                print("Connection cancelled")
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func receiveRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            if let error = error {
                print("Receive error: \(error)")
                connection.cancel()
                return
            }
            
            guard let data = content, !data.isEmpty else {
                if isComplete {
                    connection.cancel()
                }
                return
            }
            
            // 解析 HTTP 请求
            if let requestString = String(data: data, encoding: .utf8) {
                let components = requestString.components(separatedBy: "\r\n\r\n")
                let headerPart = components[0]
                let bodyPart = components.count > 1 ? components[1] : nil
                
                let headerLines = headerPart.components(separatedBy: "\r\n")
                if let requestLine = headerLines.first {
                    let parts = requestLine.components(separatedBy: " ")
                    if parts.count >= 2 {
                        let method = parts[0]
                        let path = parts[1]
                        
                        // 解析请头
                        var headers: [String: String] = [:]
                        for line in headerLines.dropFirst() {
                            let headerParts = line.split(separator: ":", maxSplits: 1).map(String.init)
                            if headerParts.count == 2 {
                                headers[headerParts[0].trimmingCharacters(in: .whitespaces)] = 
                                    headerParts[1].trimmingCharacters(in: .whitespaces)
                            }
                        }
                        
                        // 构建请求对
                        let request = HttpRequest(
                            method: method,
                            path: path,
                            headers: headers,
                            body: bodyPart?.data(using: .utf8)
                        )
                        
                        // 查找并执行对应的由处理器
                        let routeKey = "\(method) \(path)"
                        if let handler = self?.routes[routeKey] {
                            handler(request) { response in
                                // 构建 HTTP 响应
                                var responseString = "HTTP/1.1 \(response.statusCode)\r\n"
                                responseString += "Content-Type: \(response.contentType)\r\n"
                                
                                switch response {
                                case .ok(let data), .html(let data):
                                    responseString += "Content-Length: \(data.count)\r\n\r\n"
                                    let responseData = responseString.data(using: .utf8)! + data
                                    
                                    connection.send(content: responseData, completion: .idempotent)
                                case .badRequest, .notFound, .internalServerError:
                                    responseString += "Content-Length: 0\r\n\r\n"
                                    let responseData = responseString.data(using: .utf8)!
                                    
                                    connection.send(content: responseData, completion: .idempotent)
                                }
                            }
                        } else {
                            // 处理 404 Not Found
                            let notFoundResponse = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
                            let responseData = notFoundResponse.data(using: .utf8)!
                            connection.send(content: responseData, completion: .idempotent)
                        }
                    }
                }
            }
            
            // 继续接收数据
            if !isComplete {
                self?.receiveRequest(connection)
            } else {
                connection.cancel()
            }
        }
    }
}

// HTTP 请求和响应型
struct HttpRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data?
}

enum HttpResponse {
    case ok(Data)
    case html(Data)
    case badRequest
    case notFound
    case internalServerError
    
    var statusCode: Int {
        switch self {
        case .ok, .html: return 200
        case .badRequest: return 400
        case .notFound: return 404
        case .internalServerError: return 500
        }
    }
    
    var contentType: String {
        switch self {
        case .html: return "text/html; charset=utf-8"
        default: return "application/json"
        }
    }
} 
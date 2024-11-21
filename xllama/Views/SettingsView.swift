import SwiftUI

// 在文件顶部添加 DifyService
@MainActor
class DifyService: ObservableObject {
    static let shared = DifyService()
    
    @Published var baseURL: String {
        didSet {
            UserDefaults.standard.set(baseURL, forKey: "dify_base_url")
        }
    }
    
    @Published var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: "dify_api_key")
        }
    }
    
    @Published var selectedModel: String {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: "dify_selected_model")
        }
    }
    
    @Published var models: [DifyModel] = [] {
        didSet {
            if let encoded = try? JSONEncoder().encode(models) {
                UserDefaults.standard.set(encoded, forKey: "dify_saved_models")
            }
        }
    }
    
    init() {
        self.baseURL = UserDefaults.standard.string(forKey: "dify_base_url") ?? "https://api.dify.ai/v1"
        self.apiKey = UserDefaults.standard.string(forKey: "dify_api_key") ?? ""
        self.selectedModel = UserDefaults.standard.string(forKey: "dify_selected_model") ?? ""
        
        if let savedModels = UserDefaults.standard.data(forKey: "dify_saved_models"),
           let decodedModels = try? JSONDecoder().decode([DifyModel].self, from: savedModels) {
            self.models = decodedModels
        }
    }
    
    func addModel(name: String) {
        let model = DifyModel(name: name)
        if !models.contains(where: { $0.name == name }) {
            models.append(model)
        }
    }
    
    func removeModel(_ model: DifyModel) {
        models.removeAll { $0.id == model.id }
    }
    
    func fetchModels() async throws {
        guard !apiKey.isEmpty, let url = URL(string: "\(baseURL)/model-providers") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(DifyModelsResponse.self, from: data)
        
        await MainActor.run {
            // 更新模型列表
            self.models = response.data.map { DifyModel(name: $0.name) }
        }
    }
}

struct DifyModel: Identifiable, Codable {
    var id: UUID
    let name: String
    var isAvailable: Bool
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.isAvailable = true
    }
}

struct DifyModelsResponse: Codable {
    let data: [DifyModelInfo]
}

struct DifyModelInfo: Codable {
    let name: String
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showOllamaSettings = false
    @State private var showXinferenceSettings = false
    @State private var showDifySettings = false
    
    var body: some View {
        VStack {
            HStack {
                Text("设置")
                    .font(.headline)
                Spacer()
                Button("完成") {
                    dismiss()
                }
            }
            .padding()
            
            Spacer()
            
            VStack(spacing: 16) {
                Button(action: { showOllamaSettings.toggle() }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black)
                            .frame(height: 44)
                        
                        Text("Ollama 设置")
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                
                Button(action: { showXinferenceSettings.toggle() }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black)
                            .frame(height: 44)
                        
                        Text("Xinference 设置")
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                
                Button(action: { showDifySettings.toggle() }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black)
                            .frame(height: 44)
                        
                        Text("Dify 设置")
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 40)
            
            Spacer()
            Spacer()
        }
        .frame(width: 400, height: 300)
        .background(Color(.windowBackgroundColor))
        .sheet(isPresented: $showOllamaSettings) {
            OllamaSettingsView()
        }
        .sheet(isPresented: $showXinferenceSettings) {
            XinferenceSettingsView()
        }
        .sheet(isPresented: $showDifySettings) {
            DifySettingsView()
        }
    }
}

struct OllamaSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ollamaService = OllamaService.shared
    @State private var models: [OllamaModel] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack {
            HStack {
                Text("Ollama 设置")
                    .font(.headline)
                Spacer()
                Button("完成") {
                    dismiss()
                }
            }
            .padding()
            
            Form {
                Section(header: Text("Ollama 配置").font(.headline)) {
                    TextField("Ollama 地址", text: $ollamaService.baseURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.vertical, 5)
                    
                    if !models.isEmpty {
                        Picker("默认模型", selection: $ollamaService.selectedModel) {
                            Text("未选择").tag("")
                            ForEach(models) { model in
                                Text(model.name).tag(model.name)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    
                    Stepper("历史对话轮次: \(ollamaService.maxConversationTurns)", 
                           value: $ollamaService.maxConversationTurns, 
                           in: 1...20)
                        .padding(.vertical, 5)
                    
                    Button(action: refreshModels) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("刷新模型列表")
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(.vertical, 5)
                    .disabled(isLoading)
                }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .padding()
            
            Spacer()
        }
        .frame(width: 400, height: 300)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            refreshModels()
        }
    }
    
    private func refreshModels() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                models = try await ollamaService.fetchModels()
            } catch {
                errorMessage = "获取模型列表失败: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}

struct XinferenceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var xinferenceService = XinferenceService.shared
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var newModelName = ""
    
    var body: some View {
        VStack {
            HStack {
                Text("Xinference 设置")
                    .font(.headline)
                Spacer()
                Button("完成") {
                    dismiss()
                }
            }
            .padding()
            
            Form {
                Section(header: Text("Xinference 配置").font(.headline)) {
                    TextField("服务地址", text: $xinferenceService.baseURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.vertical, 5)
                    
                    if !xinferenceService.models.isEmpty {
                        Picker("默认模型", selection: $xinferenceService.selectedModel) {
                            Text("未选择").tag("")
                            ForEach(xinferenceService.models) { model in
                                Text(model.name).tag(model.name)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    
                    HStack {
                        TextField("添加模型名称", text: $newModelName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button(action: {
                            if !newModelName.isEmpty {
                                xinferenceService.addModel(name: newModelName)
                                newModelName = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newModelName.isEmpty)
                    }
                    .padding(.vertical, 5)
                    
                    // 已保存的模型列表
                    ForEach(xinferenceService.models) { model in
                        HStack {
                            Text(model.name)
                            Spacer()
                            Button(action: {
                                xinferenceService.removeModel(model)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
                    Button(action: refreshModels) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("刷新模型列表")
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(.vertical, 5)
                    .disabled(isLoading)
                }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .padding()
            
            Spacer()
        }
        .frame(width: 400, height: 400)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            refreshModels()
        }
    }
    
    private func refreshModels() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await xinferenceService.fetchModels()
            } catch {
                errorMessage = "获取模型列表失败: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}

struct DifySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var difyService = DifyService.shared
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var newModelName = ""
    
    var body: some View {
        VStack {
            HStack {
                Text("Dify 设置")
                    .font(.headline)
                Spacer()
                Button("完成") {
                    dismiss()
                }
            }
            .padding()
            
            Form {
                Section(header: Text("Dify 配置").font(.headline)) {
                    TextField("服务地址", text: $difyService.baseURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.vertical, 5)
                    
                    SecureField("API Key", text: $difyService.apiKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.vertical, 5)
                    
                    if !difyService.models.isEmpty {
                        Picker("默认模型", selection: $difyService.selectedModel) {
                            Text("未选择").tag("")
                            ForEach(difyService.models) { model in
                                Text(model.name).tag(model.name)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    
                    HStack {
                        TextField("添加模型名称", text: $newModelName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button(action: {
                            if !newModelName.isEmpty {
                                difyService.addModel(name: newModelName)
                                newModelName = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newModelName.isEmpty)
                    }
                    .padding(.vertical, 5)
                    
                    // 已保存的模型列表
                    ForEach(difyService.models) { model in
                        HStack {
                            Text(model.name)
                            Spacer()
                            Button(action: {
                                difyService.removeModel(model)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
                    Button(action: refreshModels) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("刷新模型列表")
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(.vertical, 5)
                    .disabled(isLoading)
                }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .padding()
            
            Spacer()
        }
        .frame(width: 400, height: 400)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            refreshModels()
        }
    }
    
    private func refreshModels() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await difyService.fetchModels()
            } catch {
                errorMessage = "获取模型列表失败: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}

// 添加 XinferenceService
@MainActor
class XinferenceService: ObservableObject {
    static let shared = XinferenceService()
    
    @Published var baseURL: String {
        didSet {
            UserDefaults.standard.set(baseURL, forKey: "xinference_base_url")
        }
    }
    
    @Published var selectedModel: String {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: "xinference_selected_model")
        }
    }
    
    @Published var models: [XinferenceModel] = [] {
        didSet {
            if let encoded = try? JSONEncoder().encode(models) {
                UserDefaults.standard.set(encoded, forKey: "xinference_saved_models")
            }
        }
    }
    
    init() {
        self.baseURL = UserDefaults.standard.string(forKey: "xinference_base_url") ?? "http://127.0.0.1:9997"
        self.selectedModel = UserDefaults.standard.string(forKey: "xinference_selected_model") ?? ""
        
        if let savedModels = UserDefaults.standard.data(forKey: "xinference_saved_models"),
           let decodedModels = try? JSONDecoder().decode([XinferenceModel].self, from: savedModels) {
            self.models = decodedModels
        }
    }
    
    func addModel(name: String) {
        let model = XinferenceModel(name: name)
        if !models.contains(where: { $0.name == name }) {
            models.append(model)
        }
    }
    
    func removeModel(_ model: XinferenceModel) {
        models.removeAll { $0.id == model.id }
    }
    
    func fetchModels() async throws {
        // 这里实现从 Xinference 服务器获取模型列表的逻辑
        // 使用 /v1/models 接口
        guard let url = URL(string: "\(baseURL)/v1/models") else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(ModelsResponse.self, from: data)
        
        await MainActor.run {
            // 更新已保存的模型状态
            self.updateModelsStatus(with: response.data)
        }
    }
    
    private func updateModelsStatus(with availableModels: [ModelInfo]) {
        let availableModelNames = Set(availableModels.map { $0.id })
        for i in 0..<models.count {
            models[i].isAvailable = availableModelNames.contains(models[i].name)
        }
    }
}

struct XinferenceModel: Identifiable, Codable {
    var id: UUID
    let name: String
    var isAvailable: Bool
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.isAvailable = false
    }
}

struct ModelsResponse: Codable {
    let data: [ModelInfo]
}

struct ModelInfo: Codable {
    let id: String
    // 添加其他需要的字段
} 
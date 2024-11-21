import Foundation

// 修改数据模型以匹配 Ollama API 的实际返回格式
struct OllamaResponse: Codable {
    let models: [OllamaModel]
}

struct OllamaModel: Codable, Identifiable {
    let name: String
    
    // 这些字段在新版本可能不存在，设为可选
    let size: Int64?
    let digest: String?
    let modified_at: String?
    
    var id: String { name }
    
    // 添加自定义解码以处理不同的 JSON 格式
    enum CodingKeys: String, CodingKey {
        case name
        case size
        case digest
        case modified_at
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        size = try container.decodeIfPresent(Int64.self, forKey: .size)
        digest = try container.decodeIfPresent(String.self, forKey: .digest)
        modified_at = try container.decodeIfPresent(String.self, forKey: .modified_at)
    }
}

@MainActor
class OllamaService: ObservableObject {
    static let shared = OllamaService()
    
    @Published var baseURL: String {
        didSet {
            UserDefaults.standard.set(baseURL, forKey: "ollama_base_url")
        }
    }
    
    @Published var selectedModel: String {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: "ollama_selected_model")
        }
    }
    
    @Published var maxConversationTurns: Int {
        didSet {
            UserDefaults.standard.set(maxConversationTurns, forKey: "ollama_max_turns")
        }
    }
    
    init() {
        self.baseURL = UserDefaults.standard.string(forKey: "ollama_base_url") ?? "http://localhost:11434"
        self.selectedModel = UserDefaults.standard.string(forKey: "ollama_selected_model") ?? ""
        self.maxConversationTurns = UserDefaults.standard.integer(forKey: "ollama_max_turns") != 0 
            ? UserDefaults.standard.integer(forKey: "ollama_max_turns") 
            : 5  // 默认5轮对话
    }
    
    // 构建历史对话消息
    func buildConversationContext(_ messages: [ChatMessage]) -> [[String: String]] {
        let maxTurns = maxConversationTurns
        let recentMessages = messages.count > maxTurns * 2 
            ? Array(messages.suffix(maxTurns * 2)) 
            : messages
            
        return recentMessages.map { message in
            [
                "role": message.isUser ? "user" : "assistant",
                "content": message.content
            ]
        }
    }
    
    func fetchModels() async throws -> [OllamaModel] {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            if httpResponse.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            
            // 打印返回的 JSON 数据，用于调试
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Received JSON:", jsonString)
            }
            
            // 尝试解析返回的 JSON 数据
            let decoder = JSONDecoder()
            if let response = try? decoder.decode(OllamaResponse.self, from: data) {
                return response.models
            } else {
                // 如果上面的格式不匹配，尝试直接析为模型数组
                return try decoder.decode([OllamaModel].self, from: data)
            }
            
        } catch {
            print("Error fetching models:", error)
            throw error
        }
    }
} 
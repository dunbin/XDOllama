import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    var id: UUID
    var content: String
    let isUser: Bool
    let timestamp: Date
    
    init(content: String, isUser: Bool) {
        self.id = UUID()
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
    }
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        return lhs.id == rhs.id && 
               lhs.content == rhs.content && 
               lhs.isUser == rhs.isUser
    }
} 
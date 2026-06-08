import Foundation
import SwiftData

@Model class ChatMessage {
    @Attribute(.unique) var id: UUID = UUID()
    var role: MessageRole = MessageRole.user
    var content: String = ""
    var outputType: AIOutputType = AIOutputType.interpretation
    var relatedCommandId: UUID?
    var timestamp: Date = Date()
    var dataLayer: DataLayer = DataLayer.hot
    var isRead: Bool = false

    init(id: UUID = UUID(), role: MessageRole, content: String, outputType: AIOutputType = .interpretation, relatedCommandId: UUID? = nil, timestamp: Date = Date(), dataLayer: DataLayer = .hot, isRead: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.outputType = outputType
        self.relatedCommandId = relatedCommandId
        self.timestamp = timestamp
        self.dataLayer = dataLayer
        self.isRead = isRead
    }
}

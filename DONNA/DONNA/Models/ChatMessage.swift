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
    /// Marks this message as a morning briefing so it can be surfaced as a pinned card
    /// (and filtered out of the chronological chat feed).
    var isBriefing: Bool = false
    /// Set when the user collapses/dismisses the pinned briefing card. The message
    /// still persists in history; it just stops appearing as a pinned card.
    var isBriefingDismissed: Bool = false

    init(id: UUID = UUID(), role: MessageRole, content: String, outputType: AIOutputType = .interpretation, relatedCommandId: UUID? = nil, timestamp: Date = Date(), dataLayer: DataLayer = .hot, isRead: Bool = false, isBriefing: Bool = false, isBriefingDismissed: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.outputType = outputType
        self.relatedCommandId = relatedCommandId
        self.timestamp = timestamp
        self.dataLayer = dataLayer
        self.isRead = isRead
        self.isBriefing = isBriefing
        self.isBriefingDismissed = isBriefingDismissed
    }
}

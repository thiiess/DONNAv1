import Foundation
import SwiftData

@Model class CalendarEvent {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var startTime: Date = Date()
    var endTime: Date = Date()
    var isLocked: Bool = false
    var isAnnual: Bool = false
    var notes: String?
    var createdAt: Date = Date()
    var dataLayer: DataLayer = DataLayer.hot

    init(id: UUID = UUID(), title: String, startTime: Date, endTime: Date, isLocked: Bool = false, isAnnual: Bool = false, notes: String? = nil, createdAt: Date = Date(), dataLayer: DataLayer = .hot) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.isLocked = isLocked
        self.isAnnual = isAnnual
        self.notes = notes
        self.createdAt = createdAt
        self.dataLayer = dataLayer
    }
}

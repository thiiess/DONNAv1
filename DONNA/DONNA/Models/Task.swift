import Foundation
import SwiftData

@Model class DONNATask {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String?
    var status: TaskStatus
    var dueDate: Date?
    var dueTimeIncluded: Bool
    var priority: Priority
    var createdAt: Date
    var completedAt: Date?
    var dataLayer: DataLayer

    init(id: UUID = UUID(), title: String, notes: String? = nil, status: TaskStatus = .open, dueDate: Date? = nil, dueTimeIncluded: Bool = false, priority: Priority = .none, createdAt: Date = Date(), completedAt: Date? = nil, dataLayer: DataLayer = .hot) {
        self.id = id
        self.title = title
        self.notes = notes
        self.status = status
        self.dueDate = dueDate
        self.dueTimeIncluded = dueTimeIncluded
        self.priority = priority
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.dataLayer = dataLayer
    }
}

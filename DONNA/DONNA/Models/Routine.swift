import Foundation
import SwiftData

@Model class Routine {
    @Attribute(.unique) var id: UUID
    var title: String
    var frequency: RoutineFrequency
    var preferredTimeOfDay: Date?
    var durationMinutes: Int
    var priority: Priority
    var isActive: Bool
    var category: RoutineCategory
    var colorHex: String
    var maxSkipsBeforeWarning: Int
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \RoutineOccurrence.routine) var occurrences: [RoutineOccurrence] = []

    init(id: UUID = UUID(), title: String, frequency: RoutineFrequency, preferredTimeOfDay: Date? = nil, durationMinutes: Int, priority: Priority = .none, isActive: Bool = true, category: RoutineCategory = .custom, colorHex: String = "#FFFFFF", maxSkipsBeforeWarning: Int = 2, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.frequency = frequency
        self.preferredTimeOfDay = preferredTimeOfDay
        self.durationMinutes = durationMinutes
        self.priority = priority
        self.isActive = isActive
        self.category = category
        self.colorHex = colorHex
        self.maxSkipsBeforeWarning = maxSkipsBeforeWarning
        self.createdAt = createdAt
    }
}

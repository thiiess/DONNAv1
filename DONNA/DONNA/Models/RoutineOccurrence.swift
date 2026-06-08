import Foundation
import SwiftData

@Model class RoutineOccurrence {
    @Attribute(.unique) var id: UUID
    var routine: Routine?
    var scheduledDate: Date
    var status: OccurrenceStatus
    var completedAt: Date?
    var skippedReason: String?
    var dataLayer: DataLayer

    init(id: UUID = UUID(), routine: Routine? = nil, scheduledDate: Date, status: OccurrenceStatus = .scheduled, completedAt: Date? = nil, skippedReason: String? = nil, dataLayer: DataLayer = .hot) {
        self.id = id
        self.routine = routine
        self.scheduledDate = scheduledDate
        self.status = status
        self.completedAt = completedAt
        self.skippedReason = skippedReason
        self.dataLayer = dataLayer
    }
}

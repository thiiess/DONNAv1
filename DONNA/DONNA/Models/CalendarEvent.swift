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
    /// Shared by every instance of a recurring series (V2-S6); nil for one-off events.
    var seriesID: UUID?
    /// `EventRecurrence` raw value while the series is running. Cleared on the instances
    /// that remain when the rest of a series is deleted, which ends the series.
    var recurrenceRaw: String?
    /// Minutes kept free before the event (V2-S6 Vorbereitungszeit); nil/0 = none.
    var prepTimeMinutes: Int?

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

    var recurrence: EventRecurrence? { recurrenceRaw.flatMap(EventRecurrence.init(rawValue:)) }

    /// All-day entries carry no flag — they are persisted as 00:00–23:59.
    var spansWholeDay: Bool {
        CalendarEvent.spansWholeDay(start: startTime, end: endTime)
    }

    static func spansWholeDay(start: Date, end: Date) -> Bool {
        let cal = Calendar.current
        guard cal.startOfDay(for: start) == start else { return false }
        let comps = cal.dateComponents([.hour, .minute], from: end)
        return comps.hour == 23 && comps.minute == 59
    }
}

/// Simple recurrence for calendar events — deliberately only these two cases (spec V2-S6).
enum EventRecurrence: String, CaseIterable {
    case weekly, biweekly

    var intervalWeeks: Int { self == .weekly ? 1 : 2 }

    var label: String { self == .weekly ? "wöchentlich" : "alle 2 Wochen" }
}

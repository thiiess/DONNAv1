import Foundation

// MARK: - ConflictResult

struct ConflictResult {
    enum Conflict {
        case eventOverlap(CalendarEvent)
        case sleepWindowBlocked(SleepWindow)
    }

    let conflicts: [Conflict]

    static let none = ConflictResult(conflicts: [])

    var hasConflicts: Bool { !conflicts.isEmpty }

    /// Sleep-window violations are hard blocks; event overlaps are soft warnings.
    var isBlocked: Bool {
        conflicts.contains {
            if case .sleepWindowBlocked = $0 { return true }
            return false
        }
    }   

    var overlappingEvents: [CalendarEvent] {
        conflicts.compactMap {
            if case .eventOverlap(let e) = $0 { return e }
            return nil
        }
    }

    var blockedBySleepWindows: [SleepWindow] {
        conflicts.compactMap {
            if case .sleepWindowBlocked(let w) = $0 { return w }
            return nil
        }
    }

    // MARK: - User-facing messages

    /// Soft warning naming the overlapping event(s) — nil when nothing overlaps.
    var overlapWarning: String? {
        guard let first = overlappingEvents.first else { return nil }
        let range = ConflictResult.timeRange(first.startTime, first.endTime)
        let others = overlappingEvents.count - 1
        let suffix: String
        switch others {
        case 0:  suffix = ""
        case 1:  suffix = " und einem weiteren Termin"
        default: suffix = " und \(others) weiteren Terminen"
        }
        return "Überschneidet sich mit „\(first.title)“ (\(range))\(suffix)."
    }

    /// Hard block reason naming the protected sleep window — nil when nothing is blocked.
    var blockReason: String? {
        guard let window = blockedBySleepWindows.first else { return nil }
        let range = ConflictResult.timeRange(window.bedtime, window.wakeTime)
        return "Liegt im Schlafschutzfenster (\(range))."
    }

    private static func timeRange(_ start: Date, _ end: Date) -> String {
        "\(timeFormatter.string(from: start))–\(timeFormatter.string(from: end))"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - ConflictDetector

final class ConflictDetector {

    /// Checks whether a proposed [start, end) interval conflicts with existing
    /// calendar events or protected sleep windows.
    ///
    /// - Parameter excludingEventId: Skip the event with this ID (used when
    ///   updating an existing event so it doesn't conflict with itself).
    func check(
        start: Date,
        end: Date,
        against events: [CalendarEvent],
        sleepWindows: [SleepWindow],
        excludingEventId: UUID? = nil
    ) -> ConflictResult {
        var found: [ConflictResult.Conflict] = []

        for event in events where event.id != excludingEventId {
            if overlaps(start: start, end: end, otherStart: event.startTime, otherEnd: event.endTime) {
                found.append(.eventOverlap(event))
            }
        }

        // The sleep window is a daily rhythm: the most recently set protected window
        // applies to every night (it used to be compared with its absolute dates, so it
        // only ever protected the one night it was created on).
        if let window = sleepWindows.filter({ $0.isProtected }).max(by: { $0.date < $1.date }),
           intersectsDailySleepWindow(start: start, end: end, window: window) {
            found.append(.sleepWindowBlocked(window))
        }

        return ConflictResult(conflicts: found)
    }

    /// Check used at persistence time and by the event sheets. All-day and annual entries
    /// are stored as 00:00–23:59, so they would collide with every other event and every
    /// sleep window by construction — they are ignored on both sides of the comparison.
    func checkTimedEvent(
        start: Date,
        end: Date,
        against events: [CalendarEvent],
        sleepWindows: [SleepWindow],
        excludingEventId: UUID? = nil
    ) -> ConflictResult {
        guard !CalendarEvent.spansWholeDay(start: start, end: end) else { return .none }
        return check(
            start: start,
            end: end,
            against: events.filter { !$0.isAnnual && !$0.spansWholeDay },
            sleepWindows: sleepWindows,
            excludingEventId: excludingEventId
        )
    }

    // MARK: - Private helpers

    /// Half-open interval overlap: [a,b) overlaps [c,d) iff a < d && c < b.
    private func overlaps(start: Date, end: Date, otherStart: Date, otherEnd: Date) -> Bool {
        start < otherEnd && otherStart < end
    }

    /// Projects the window's clock times onto every night the interval could touch
    /// (the night before its start through the night of its end) and checks each.
    /// Windows may span midnight: then wake time is on the following day.
    func intersectsDailySleepWindow(start: Date, end: Date, window: SleepWindow, calendar: Calendar = .current) -> Bool {
        let bed = calendar.dateComponents([.hour, .minute], from: window.bedtime)
        let wake = calendar.dateComponents([.hour, .minute], from: window.wakeTime)
        let bedMin = (bed.hour ?? 0) * 60 + (bed.minute ?? 0)
        let wakeMin = (wake.hour ?? 0) * 60 + (wake.minute ?? 0)
        guard bedMin != wakeMin else { return false }
        let spansMidnight = wakeMin <= bedMin

        var day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: start)) ?? start
        let lastDay = calendar.startOfDay(for: end)
        while day <= lastDay {
            let nightStart = day.addingTimeInterval(TimeInterval(bedMin * 60))
            let nightEnd = day.addingTimeInterval(TimeInterval((spansMidnight ? wakeMin + 24 * 60 : wakeMin) * 60))
            if overlaps(start: start, end: end, otherStart: nightStart, otherEnd: nightEnd) { return true }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return false
    }
}

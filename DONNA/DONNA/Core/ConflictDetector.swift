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

        for window in sleepWindows where window.isProtected {
            if intersectsSleepWindow(start: start, end: end, window: window) {
                found.append(.sleepWindowBlocked(window))
            }
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

    /// Sleep windows can span midnight (bedtime later in the day than wakeTime).
    /// Handles this by advancing wakeTime by 24 h when it precedes bedtime.
    private func intersectsSleepWindow(start: Date, end: Date, window: SleepWindow) -> Bool {
        let bedtime = window.bedtime
        let wakeTime = window.wakeTime <= bedtime
            ? window.wakeTime.addingTimeInterval(86400)
            : window.wakeTime
        return overlaps(start: start, end: end, otherStart: bedtime, otherEnd: wakeTime)
    }
}

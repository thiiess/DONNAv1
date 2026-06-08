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

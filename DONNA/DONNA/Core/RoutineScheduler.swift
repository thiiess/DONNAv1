import Foundation

final class RoutineScheduler {

    /// Generates `RoutineOccurrence` objects for every applicable day in [start, end].
    ///
    /// The caller is responsible for inserting the returned objects into the
    /// ModelContext and for avoiding duplicates (pass `skipping:` if needed).
    ///
    /// - Parameter skipping: Set of `startOfDay` dates that already have an
    ///   occurrence, so they are not generated again.
    func generateOccurrences(
        for routine: Routine,
        from start: Date,
        to end: Date,
        skipping existingDates: Set<Date> = []
    ) -> [RoutineOccurrence] {
        guard routine.isActive, start <= end else { return [] }

        let calendar = Calendar.current
        // For .weekly: anchor to the weekday the routine was created on.
        let referenceWeekday = calendar.component(.weekday, from: routine.createdAt)

        var occurrences: [RoutineOccurrence] = []
        var cursor = calendar.startOfDay(for: start)
        let dayEnd = calendar.startOfDay(for: end)

        while cursor <= dayEnd {
            if !existingDates.contains(cursor),
               shouldOccur(on: cursor, routine: routine, referenceWeekday: referenceWeekday, calendar: calendar) {
                let scheduled = resolvedScheduledDate(on: cursor, routine: routine, calendar: calendar)
                occurrences.append(RoutineOccurrence(routine: routine, scheduledDate: scheduled))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return occurrences
    }

    /// Returns `true` if the routine should fire on the given date.
    func occursOn(date: Date, routine: Routine) -> Bool {
        let calendar = Calendar.current
        let referenceWeekday = calendar.component(.weekday, from: routine.createdAt)
        return shouldOccur(
            on: calendar.startOfDay(for: date),
            routine: routine,
            referenceWeekday: referenceWeekday,
            calendar: calendar
        )
    }

    // MARK: - Private

    private func shouldOccur(
        on day: Date,
        routine: Routine,
        referenceWeekday: Int,
        calendar: Calendar
    ) -> Bool {
        switch routine.frequency {
        case .daily:
            return true
        case .weekdays:
            // Calendar.weekday: 1 = Sunday, 2 = Monday … 6 = Friday, 7 = Saturday
            let weekday = calendar.component(.weekday, from: day)
            return (2...6).contains(weekday)
        case .weekly:
            return calendar.component(.weekday, from: day) == referenceWeekday
        case .custom:
            // Custom days require caller-supplied configuration; not scheduled here.
            return false
        }
    }

    /// Combines `day` (date-only) with the time from `routine.preferredTimeOfDay`.
    /// Falls back to midnight if no preferred time is set.
    private func resolvedScheduledDate(on day: Date, routine: Routine, calendar: Calendar) -> Date {
        guard let preferred = routine.preferredTimeOfDay else {
            return calendar.startOfDay(for: day)
        }
        let components = calendar.dateComponents([.hour, .minute], from: preferred)
        return calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: 0,
            of: day
        ) ?? calendar.startOfDay(for: day)
    }
}

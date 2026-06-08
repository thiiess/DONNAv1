import Foundation

// MARK: - SystemPhase

enum SystemPhase: String {
    case idle
    case interpreting
    case clarifying
    case proposing
    case awaitingConsent = "awaiting_consent"
    case blocked
}

// MARK: - Codable snapshot types (match Section 6 of the spec exactly)

private struct ContextPayload: Encodable {
    let user_text: String
    let system_phase: String
    let context_snapshot: ContextSnapshot
}

private struct ContextSnapshot: Encodable {
    let upcoming_events: [UpcomingEventEntry]
    let open_routines_today: [String]
    let sleep_window: SleepWindowEntry?
    let active_context_mode: String?
    let conflict_flags: [String]
}

private struct UpcomingEventEntry: Encodable {
    let type: String
    let start_offset_minutes: Int
    let duration_minutes: Int
    let is_locked: Bool
}

private struct SleepWindowEntry: Encodable {
    let bedtime_hour: Int
    let wake_hour: Int
    let is_protected: Bool
}

// MARK: - ContextBuilder

struct ContextBuilder {

    private let conflictDetector = ConflictDetector()
    private let windowHours: Double = 12

    /// Builds the anonymised JSON payload sent to the Internal Assistant.
    /// No names, no locations, no IDs — only types, offsets, durations, hours.
    func buildJSON(
        userText: String,
        systemPhase: SystemPhase,
        events: [CalendarEvent],
        occurrences: [RoutineOccurrence],
        sleepWindows: [SleepWindow],
        activeContextMode: ContextMode?,
        referenceDate: Date = Date()
    ) -> String? {

        let horizon = referenceDate.addingTimeInterval(windowHours * 3600)
        let calendar = Calendar.current

        // Upcoming CalendarEvents within the next 12 hours
        let upcomingEvents = events
            .filter { $0.startTime >= referenceDate && $0.startTime <= horizon }
            .sorted { $0.startTime < $1.startTime }

        let eventEntries = upcomingEvents.map { event in
            UpcomingEventEntry(
                type: "event",
                start_offset_minutes: minuteOffset(from: referenceDate, to: event.startTime),
                duration_minutes: max(0, Int(event.endTime.timeIntervalSince(event.startTime) / 60)),
                is_locked: event.isLocked
            )
        }

        // Open RoutineOccurrences today (scheduled, not completed)
        let todayOpen = occurrences.filter {
            calendar.isDateInToday($0.scheduledDate) && $0.status == .scheduled
        }
        let openRoutineTypes = todayOpen.compactMap { $0.routine?.category.rawValue }

        // Sleep window (tonight's or today's)
        let sleepEntry: SleepWindowEntry? = sleepWindows
            .first { calendar.isDateInToday($0.date) }
            .map { w in
                SleepWindowEntry(
                    bedtime_hour: calendar.component(.hour, from: w.bedtime),
                    wake_hour: calendar.component(.hour, from: w.wakeTime),
                    is_protected: w.isProtected
                )
            }

        // Conflict flags — check each upcoming event against all others and sleep windows
        var flags: [String] = []
        for event in upcomingEvents {
            let result = conflictDetector.check(
                start: event.startTime,
                end: event.endTime,
                against: upcomingEvents,
                sleepWindows: sleepWindows.filter { $0.isProtected },
                excludingEventId: event.id
            )
            if !result.overlappingEvents.isEmpty && !flags.contains("event_overlap") {
                flags.append("event_overlap")
            }
            if !result.blockedBySleepWindows.isEmpty && !flags.contains("sleep_window_conflict") {
                flags.append("sleep_window_conflict")
            }
        }

        let snapshot = ContextSnapshot(
            upcoming_events: eventEntries,
            open_routines_today: openRoutineTypes,
            sleep_window: sleepEntry,
            active_context_mode: activeContextMode?.name,
            conflict_flags: flags
        )

        let payload = ContextPayload(
            user_text: userText,
            system_phase: systemPhase.rawValue,
            context_snapshot: snapshot
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Private helpers

    private func minuteOffset(from reference: Date, to date: Date) -> Int {
        Int(date.timeIntervalSince(reference) / 60)
    }
}

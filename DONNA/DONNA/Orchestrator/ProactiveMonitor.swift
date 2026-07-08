import Foundation
import SwiftData
#if os(iOS)
import BackgroundTasks
#endif

// MARK: - ProactiveMonitor

/// Runs periodic scans to detect issues the user may have missed:
/// calendar conflicts, sleep deficit streaks, and forgotten routines.
/// Also triggers PatternExtractor + ProfileUpdater on each run.
///
/// Deduplication: issue keys are persisted in UserDefaults so the same
/// proposal is not inserted more than once per day.
@MainActor
final class ProactiveMonitor {

    static let bgRefreshIdentifier = "com.donna.proactive-refresh"

    private let conflictDetector = ConflictDetector()

    // MARK: - Background task scheduling

    static func scheduleNextBackgroundRefresh() {
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: bgRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 3600)
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }

    // MARK: - Main entry point

    /// Full scan: update learned profile + proactive issue detection.
    /// Safe to call on app foreground and from the background refresh handler.
    func run(modelContext: ModelContext) {
        let patterns = runLearningCycle(modelContext: modelContext)
        detectCalendarConflicts(modelContext: modelContext)
        detectSleepDeficitStreak(sleep: patterns.sleep, modelContext: modelContext)
        detectForgottenRoutines(modelContext: modelContext)
    }

    // MARK: - Learning cycle

    @discardableResult
    private func runLearningCycle(modelContext: ModelContext) -> PatternResult {
        let extractor = PatternExtractor()
        let updater = ProfileUpdater(context: modelContext)
        let patterns = extractor.extract(from: modelContext)
        updater.update(with: patterns)
        return patterns
    }

    // MARK: - Calendar conflict detection

    private func detectCalendarConflicts(modelContext: ModelContext) {
        let events = (try? modelContext.fetch(
            FetchDescriptor<CalendarEvent>(sortBy: [SortDescriptor(\.startTime)])
        )) ?? []
        let sleepWindows = (try? modelContext.fetch(FetchDescriptor<SleepWindow>())) ?? []

        let now = Date()
        let futureEvents = events.filter { $0.startTime > now }

        // Avoid O(n²) duplicate pairs by only checking each pair once
        for i in 0..<futureEvents.count {
            for j in (i + 1)..<futureEvents.count {
                let a = futureEvents[i]
                let b = futureEvents[j]
                let result = conflictDetector.check(
                    start: a.startTime,
                    end: a.endTime,
                    against: [b],
                    sleepWindows: [],
                    excludingEventId: nil
                )
                if result.hasConflicts {
                    let ids = [a.id.uuidString, b.id.uuidString].sorted()
                    let key = "conflict_overlap_\(ids[0])_\(ids[1])"
                    createProposalIfNew(
                        key: key,
                        content: "Ich habe einen Terminkonflikt bemerkt: Zwei geplante Ereignisse überschneiden sich zeitlich. Möchtest du einen der Termine verschieben?",
                        modelContext: modelContext
                    )
                }
            }

            // Check each event against sleep windows separately
            let a = futureEvents[i]
            let sleepResult = conflictDetector.check(
                start: a.startTime,
                end: a.endTime,
                against: [],
                sleepWindows: sleepWindows,
                excludingEventId: nil
            )
            for window in sleepResult.blockedBySleepWindows {
                let key = "conflict_sleep_\(a.id.uuidString)_\(window.id.uuidString)"
                createProposalIfNew(
                    key: key,
                    content: "Ein geplanter Termin liegt in deinem Schlafschutzfenster. Soll ich einen anderen Zeitslot vorschlagen?",
                    modelContext: modelContext
                )
            }
        }
    }

    // MARK: - Sleep deficit streak detection

    private func detectSleepDeficitStreak(sleep: SleepPatternData?, modelContext: ModelContext) {
        guard let sleep, sleep.recentDeficitStreak >= 3 else { return }

        let dayKey = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date())).prefix(10)
        let key = "sleep_deficit_streak_\(dayKey)"
        createProposalIfNew(
            key: key,
            content: "Du schläfst seit \(sleep.recentDeficitStreak) Tagen in Folge weniger als 6 Stunden. Möchtest du dein Schlaffenster anpassen oder eine Erinnerung einrichten?",
            modelContext: modelContext
        )
    }

    // MARK: - Forgotten routine detection

    private func detectForgottenRoutines(modelContext: ModelContext) {
        let now = Date()
        let occurrences = (try? modelContext.fetch(FetchDescriptor<RoutineOccurrence>())) ?? []

        let forgotten = occurrences.filter {
            $0.status == .scheduled && $0.scheduledDate < now
        }

        for occ in forgotten {
            let key = "forgotten_routine_\(occ.id.uuidString)"
            let title = occ.routine?.title ?? "Routine"
            createProposalIfNew(
                key: key,
                content: "Die Routine \"\(title)\" wurde zum geplanten Zeitpunkt nicht erledigt. Möchtest du sie nachholen, überspringen oder neu planen?",
                modelContext: modelContext
            )
        }
    }

    // MARK: - Morning briefing (V2-S2)

    // These keys mirror the @AppStorage keys used in SettingsView — keep in sync.
    private static let briefingEnabledKey = "donna_briefing_enabled"
    private static let briefingTimeKey    = "donna_briefing_time"

    /// Generates today's morning briefing if it is enabled and the configured time has passed,
    /// and it has not already been generated today. Safe to call on every foreground / refresh.
    func generateMorningBriefingIfDue(modelContext: ModelContext, now: Date = Date()) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.briefingEnabledKey) else { return }

        // Fall back to the SettingsView default (07:30) if the time was never persisted.
        let interval: Double
        if defaults.object(forKey: Self.briefingTimeKey) != nil {
            interval = defaults.double(forKey: Self.briefingTimeKey)
        } else {
            var c = DateComponents(); c.hour = 7; c.minute = 30
            interval = Calendar.current.date(from: c)?.timeIntervalSinceReferenceDate ?? 0
        }

        let cal = Calendar.current
        let briefingTime = Date(timeIntervalSinceReferenceDate: interval)
        guard let fireToday = cal.date(
            bySettingHour: cal.component(.hour, from: briefingTime),
            minute: cal.component(.minute, from: briefingTime),
            second: 0,
            of: now
        ), now >= fireToday else { return }

        generateMorningBriefing(modelContext: modelContext, now: now)
    }

    /// Builds the briefing text and posts it as an assistant ChatMessage via CommandHandler.
    /// Deduplicated so at most one briefing is created per calendar day.
    func generateMorningBriefing(modelContext: ModelContext, now: Date = Date()) {
        let dayKey = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: now)).prefix(10)
        let storeKey = "briefing_generated_\(dayKey)"
        guard !UserDefaults.standard.bool(forKey: storeKey) else { return }

        let text = buildMorningBriefingText(modelContext: modelContext, referenceDate: now)
        let result = CommandHandler(modelContext: modelContext)
            .execute(.postAssistantMessage(content: text, outputType: .interpretation, isBriefing: true))
        guard case .success = result else { return }
        UserDefaults.standard.set(true, forKey: storeKey)
    }

    /// Composes the German briefing string. Pure and read-only — no persistence.
    func buildMorningBriefingText(modelContext: ModelContext, referenceDate: Date = Date()) -> String {
        let cal = Calendar.current

        let events = ((try? modelContext.fetch(
            FetchDescriptor<CalendarEvent>(sortBy: [SortDescriptor(\.startTime)])
        )) ?? []).filter { cal.isDate($0.startTime, inSameDayAs: referenceDate) }

        let openRoutines = ((try? modelContext.fetch(FetchDescriptor<RoutineOccurrence>())) ?? [])
            .filter { cal.isDate($0.scheduledDate, inSameDayAs: referenceDate) && $0.status == .scheduled }

        let dueTasks = ((try? modelContext.fetch(FetchDescriptor<DONNATask>())) ?? [])
            .filter { $0.status == .open }
            .filter { task in
                guard let due = task.dueDate else { return false }
                return cal.isDate(due, inSameDayAs: referenceDate)
            }

        let sleepWindows = (try? modelContext.fetch(FetchDescriptor<SleepWindow>())) ?? []
        let todaysWindow = sleepWindows.first { cal.isDate($0.date, inSameDayAs: referenceDate) }

        // The event named in the day-overview part below; used to avoid repeating its
        // name in the conflict sentence.
        let highlightedEventID = events.first?.id
        let conflictSentence = briefingConflictSentence(
            events: events,
            sleepWindows: sleepWindows,
            highlightedEventID: highlightedEventID
        )

        var parts: [String] = ["Guten Morgen."]

        // Termine
        if events.isEmpty {
            parts.append("Heute stehen keine Termine an.")
        } else {
            let first = events[0]
            let descriptor = first.isAnnual
                ? "\(first.title) (ganztägig)"
                : "\(first.title) um \(Self.briefingTimeFormatter.string(from: first.startTime)) Uhr"
            if events.count == 1 {
                parts.append("Heute: ein Termin – \(descriptor).")
            } else {
                parts.append("Heute: \(events.count) Termine, zuerst \(descriptor).")
            }
        }

        // Offene Routinen
        if !openRoutines.isEmpty {
            let titles = openRoutines.compactMap { $0.routine?.title }
            if titles.isEmpty {
                parts.append("\(openRoutines.count) Routinen sind noch offen.")
            } else {
                parts.append("Offene Routinen: \(titles.joined(separator: ", ")).")
            }
        }

        // Fällige Aufgaben
        if !dueTasks.isEmpty {
            parts.append(dueTasks.count == 1
                ? "Eine Aufgabe ist heute fällig."
                : "\(dueTasks.count) Aufgaben sind heute fällig.")
        }

        // Geplantes Schlaffenster (nie „gemessen" — DONNA misst keinen Schlaf bis V2-S10)
        if let window = todaysWindow {
            let hours = Double(window.durationMinutes) / 60.0
            let hoursStr = String(format: "%.1f", hours).replacingOccurrences(of: ".", with: ",")
            parts.append("Dein geplantes Schlaffenster: \(hoursStr) h.")
        }

        // Genau eine Frage oder ein Vorschlag zum Schluss
        if let conflictSentence {
            parts.append(conflictSentence)
        } else if !openRoutines.isEmpty {
            parts.append("Soll ich dir helfen, mit einer Sache anzufangen?")
        } else if !dueTasks.isEmpty {
            parts.append("Womit möchtest du beginnen?")
        } else {
            parts.append("Was möchtest du heute planen?")
        }

        return parts.joined(separator: " ")
    }

    /// Builds a specific German conflict sentence naming the overlapping events and their
    /// time ranges, or nil if there is no conflict. Returns exactly one sentence so the
    /// briefing keeps its "one question at the end" shape.
    ///
    /// Summarization: a single overlapping pair is named; with two or more distinct pairs it
    /// says "Mehrere Termine überschneiden sich, z. B. …" and names the first pair as an
    /// example. All-day / annual events are excluded — they are day markers, not real time
    /// conflicts, and would otherwise appear to overlap every timed event.
    ///
    /// If the first named event was already mentioned in the day overview
    /// (`highlightedEventID`), it is back-referenced ("Dabei …") instead of repeated.
    private func briefingConflictSentence(
        events: [CalendarEvent],
        sleepWindows: [SleepWindow],
        highlightedEventID: UUID?
    ) -> String? {
        let timed = events.filter { !$0.isAnnual }

        var pairs: [(CalendarEvent, CalendarEvent)] = []
        for i in 0..<timed.count {
            for j in (i + 1)..<timed.count {
                let a = timed[i], b = timed[j]
                if a.startTime < b.endTime && b.startTime < a.endTime {
                    pairs.append((a, b))
                }
            }
        }

        if let (a, b) = pairs.first {
            if pairs.count == 1 {
                // Single pair: back-reference the first event if it was just named.
                if a.id == highlightedEventID {
                    return "Dabei überschneidet sich das mit \(b.title) (\(timeRange(b))). Soll ich einen verschieben?"
                }
                return "\(a.title) (\(timeRange(a))) überschneidet sich mit \(b.title) (\(timeRange(b))). Soll ich einen verschieben?"
            }
            // Multiple pairs: name the first pair in full as an example.
            return "Mehrere Termine überschneiden sich, z. B. \(a.title) (\(timeRange(a))) und \(b.title) (\(timeRange(b))). Soll ich etwas verschieben?"
        }

        // No event-event overlap — surface a protected sleep-window violation if present.
        let protectedWindows = sleepWindows.filter { $0.isProtected }
        for event in timed {
            let result = conflictDetector.check(
                start: event.startTime,
                end: event.endTime,
                against: [],
                sleepWindows: protectedWindows,
                excludingEventId: event.id
            )
            if !result.blockedBySleepWindows.isEmpty {
                if event.id == highlightedEventID {
                    return "Dabei liegt das in deinem Schlaffenster. Soll ich einen anderen Zeitslot vorschlagen?"
                }
                return "\(event.title) (\(timeRange(event))) liegt in deinem Schlaffenster. Soll ich einen anderen Zeitslot vorschlagen?"
            }
        }

        return nil
    }

    private func timeRange(_ event: CalendarEvent) -> String {
        let start = Self.briefingTimeFormatter.string(from: event.startTime)
        let end = Self.briefingTimeFormatter.string(from: event.endTime)
        return "\(start)–\(end)"
    }

    private static let briefingTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: - Deduplication

    /// Seen keys are stored in UserDefaults as a flat array of strings.
    /// Each entry is retained for 7 days to allow re-surfacing recurring issues.
    private var seenKeys: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "proactive_seen_keys") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "proactive_seen_keys") }
    }

    private func createProposalIfNew(key: String, content: String, modelContext: ModelContext) {
        var keys = seenKeys
        guard !keys.contains(key) else { return }

        let result = CommandHandler(modelContext: modelContext)
            .execute(.postAssistantMessage(content: content, outputType: .proposal))
        guard case .success = result else { return }

        keys.insert(key)
        seenKeys = keys
    }
}

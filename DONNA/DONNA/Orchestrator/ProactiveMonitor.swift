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
        keys.insert(key)
        seenKeys = keys

        let message = ChatMessage(
            role: .assistant,
            content: content,
            outputType: .proposal,
            isRead: false
        )
        modelContext.insert(message)
        try? modelContext.save()
    }
}

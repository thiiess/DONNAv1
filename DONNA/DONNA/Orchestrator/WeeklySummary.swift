import Foundation
import SwiftData

// MARK: - Weekly summary (V2-S2)

/// Sunday-evening look back at the week and one look ahead. Like the morning briefing it
/// is a plain assistant ChatMessage posted through CommandHandler; the text is built here
/// without any persistence so it can be previewed and tested in isolation.
///
/// Tone (V2-S11 / Fundament): neutral numbers, no judgement, no streaks, no guilt —
/// and exactly one question at the end.
extension ProactiveMonitor {

    // These keys mirror the @AppStorage keys used in SettingsView — keep in sync.
    static let weeklySummaryEnabledKey = "donna_weekly_summary_enabled"
    static let weeklySummaryTimeKey    = "donna_weekly_summary_time"

    /// Default: Sunday 19:00.
    static var defaultWeeklySummaryTime: Double {
        var c = DateComponents(); c.hour = 19; c.minute = 0
        return Calendar.current.date(from: c)?.timeIntervalSinceReferenceDate ?? 0
    }

    /// Posts the weekly summary if enabled, it is Sunday, the configured time has passed,
    /// and this week's summary has not been posted yet. Safe to call on every foreground.
    func generateWeeklySummaryIfDue(modelContext: ModelContext, now: Date = Date()) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.weeklySummaryEnabledKey) else { return }

        let cal = Calendar.current
        guard cal.component(.weekday, from: now) == 1 else { return } // 1 = Sunday

        let interval = defaults.object(forKey: Self.weeklySummaryTimeKey) != nil
            ? defaults.double(forKey: Self.weeklySummaryTimeKey)
            : Self.defaultWeeklySummaryTime
        let time = Date(timeIntervalSinceReferenceDate: interval)
        guard let fireToday = cal.date(
            bySettingHour: cal.component(.hour, from: time),
            minute: cal.component(.minute, from: time),
            second: 0,
            of: now
        ), now >= fireToday else { return }

        generateWeeklySummary(modelContext: modelContext, now: now)
    }

    /// Posts the summary for the week containing `now`. Deduplicated per ISO week.
    func generateWeeklySummary(modelContext: ModelContext, now: Date = Date()) {
        let storeKey = Self.weeklySummaryStoreKey(for: now)
        guard !UserDefaults.standard.bool(forKey: storeKey) else { return }

        let text = buildWeeklySummaryText(modelContext: modelContext, referenceDate: now)
        let result = CommandHandler(modelContext: modelContext)
            .execute(.postAssistantMessage(content: text, outputType: .interpretation))
        guard case .success = result else { return }
        UserDefaults.standard.set(true, forKey: storeKey)
    }

    static func weeklySummaryStoreKey(for date: Date) -> String {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = .current
        let comps = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "weekly_summary_\(comps.yearForWeekOfYear ?? 0)_W\(comps.weekOfYear ?? 0)"
    }

    /// Composes the German summary. Read-only.
    func buildWeeklySummaryText(modelContext: ModelContext, referenceDate: Date = Date()) -> String {
        // ISO weeks run Monday–Sunday regardless of the device's first-weekday setting,
        // so a Sunday-evening summary always covers the week that is just ending.
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        guard let week = cal.dateInterval(of: .weekOfYear, for: referenceDate),
              let nextWeek = cal.dateInterval(of: .weekOfYear, for: week.end) else {
            return "Diese Woche ist geschafft. Was ist dir für nächste Woche wichtig?"
        }

        // Routines: done vs. planned, only occurrences that were already due.
        let occurrences = ((try? modelContext.fetch(FetchDescriptor<RoutineOccurrence>())) ?? [])
            .filter { $0.routine != nil && week.contains($0.scheduledDate) && $0.scheduledDate <= referenceDate }
        var byRoutine: [UUID: (title: String, done: Int, total: Int)] = [:]
        for occ in occurrences {
            guard let routine = occ.routine else { continue }
            var entry = byRoutine[routine.id] ?? (routine.title, 0, 0)
            entry.total += 1
            if occ.status == .completed { entry.done += 1 }
            byRoutine[routine.id] = entry
        }
        let routineStats = byRoutine.values.sorted { $0.total > $1.total || ($0.total == $1.total && $0.title < $1.title) }

        let completedTasks = ((try? modelContext.fetch(FetchDescriptor<DONNATask>())) ?? [])
            .filter { task in
                guard task.status == .completed, let done = task.completedAt else { return false }
                return week.contains(done)
            }

        let sleepWindows = ((try? modelContext.fetch(FetchDescriptor<SleepWindow>())) ?? [])
            .filter { week.contains($0.date) }

        let nextEvents = ((try? modelContext.fetch(FetchDescriptor<CalendarEvent>())) ?? [])
            .filter { nextWeek.contains($0.startTime) }
        let nextTimed = nextEvents.filter { !$0.isAnnual && !$0.spansWholeDay }

        var parts: [String] = ["Deine Woche im Überblick."]

        // Rückblick
        if routineStats.isEmpty && completedTasks.isEmpty {
            parts.append("Diese Woche gab es keine erledigten Routinen oder Aufgaben, die ich zählen konnte.")
        } else {
            if !routineStats.isEmpty {
                let list = routineStats.prefix(4).map { "\($0.title) \($0.done) von \($0.total)" }
                parts.append("Routinen: \(list.joined(separator: ", ")).")
            }
            if !completedTasks.isEmpty {
                parts.append(completedTasks.count == 1
                    ? "Eine Aufgabe erledigt."
                    : "\(completedTasks.count) Aufgaben erledigt.")
            }
        }

        // Geplanter Schlaf (DONNA misst keinen Schlaf bis V2-S10 — daher immer „geplant")
        if !sleepWindows.isEmpty {
            let avgHours = Double(sleepWindows.map(\.durationMinutes).reduce(0, +)) / Double(sleepWindows.count) / 60.0
            parts.append("Geplanter Schlaf: Ø \(Self.decimal(avgHours)) h.")
        }

        // Ausblick
        let busiestDay = Self.busiestDay(in: nextTimed, calendar: cal)
        let annual = nextEvents.filter(\.isAnnual)
        if nextEvents.isEmpty {
            parts.append("Nächste Woche ist noch frei.")
        } else {
            var outlook = nextTimed.count == 1
                ? "Nächste Woche: ein Termin"
                : "Nächste Woche: \(nextTimed.count) Termine"
            if let busiestDay, busiestDay.count >= 3 {
                outlook += ", die meisten am \(Self.weekdayFormatter.string(from: busiestDay.day))"
            }
            parts.append(outlook + ".")
            if let first = annual.first {
                parts.append("Außerdem: \(first.title) am \(Self.weekdayFormatter.string(from: first.startTime)).")
            }
        }

        // Genau eine Frage zum Schluss
        let struggling = routineStats.first { $0.total >= 3 && Double($0.done) / Double($0.total) < 0.5 }
        if let struggling {
            parts.append("Soll ich \(struggling.title) nächste Woche anders einplanen, damit es leichter passt?")
        } else if let busiestDay, busiestDay.count >= 3 {
            parts.append("Soll ich am \(Self.weekdayFormatter.string(from: busiestDay.day)) etwas Puffer einplanen?")
        } else {
            parts.append("Was ist dir für nächste Woche wichtig?")
        }

        return parts.joined(separator: " ")
    }

    // MARK: Helpers

    private static func busiestDay(in events: [CalendarEvent], calendar: Calendar) -> (day: Date, count: Int)? {
        let grouped = Dictionary(grouping: events) { calendar.startOfDay(for: $0.startTime) }
        return grouped
            .map { (day: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count || ($0.count == $1.count && $0.day < $1.day) }
            .first
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE"
        return f
    }()
}

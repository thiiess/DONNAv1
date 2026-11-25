import Foundation
import SwiftData

/// Answers "what's coming up" questions locally instead of via Gemini.
///
/// The Gemini context is deliberately anonymised and limited to the next 12 hours, so it
/// cannot describe the user's week — and it should not see titles anyway. These overviews
/// are read-only, built on-device, and never leave the app.
enum OverviewAnswers {

    enum Kind { case today, week }

    /// Detects an overview question. Deliberately narrow: anything that could be a
    /// request to *change* something still goes to Gemini.
    static func detect(_ text: String) -> Kind? {
        let t = text.lowercased()
        let changeWords = ["verschieb", "lösch", "trag", "erstell", "leg ", "anlegen", "ändere", "streich", "absag"]
        guard !changeWords.contains(where: { t.contains($0) }) else { return nil }

        let weekPhrases = ["meine woche", "diese woche", "die woche", "nächste woche", "nächsten tage",
                           "wochenübersicht", "überblick über die woche", "was steht die woche", "woche an"]
        if weekPhrases.contains(where: { t.contains($0) }) { return .week }

        let todayPhrases = ["was steht heute", "was hab ich heute", "was habe ich heute", "mein tag",
                            "heute an?", "tagesübersicht", "was ist heute los"]
        if todayPhrases.contains(where: { t.contains($0) }) { return .today }
        return nil
    }

    @MainActor
    static func answer(_ kind: Kind, modelContext: ModelContext, now: Date = Date()) -> String {
        switch kind {
        case .today:
            // Same wording as the morning briefing, minus the greeting.
            let text = ProactiveMonitor().buildMorningBriefingText(modelContext: modelContext, referenceDate: now)
            return text.replacingOccurrences(of: "Guten Morgen. ", with: "")
        case .week:
            return weekText(modelContext: modelContext, now: now)
        }
    }

    @MainActor
    private static func weekText(modelContext: ModelContext, now: Date) -> String {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 7, to: start) else { return "" }

        let events = ((try? modelContext.fetch(FetchDescriptor<CalendarEvent>(sortBy: [SortDescriptor(\.startTime)]))) ?? [])
            .filter { $0.startTime >= start && $0.startTime < end }
        let occurrences = ((try? modelContext.fetch(FetchDescriptor<RoutineOccurrence>())) ?? [])
            .filter { $0.routine != nil && $0.status == .scheduled && $0.scheduledDate >= now && $0.scheduledDate < end }
        let tasks = ((try? modelContext.fetch(FetchDescriptor<DONNATask>())) ?? [])
            .filter { task in
                guard task.status == .open, let due = task.dueDate else { return false }
                return due >= start && due < end
            }

        guard !events.isEmpty || !occurrences.isEmpty || !tasks.isEmpty else {
            return "Die nächsten sieben Tage sind noch frei. Möchtest du etwas planen?"
        }

        var lines: [String] = ["Deine nächsten sieben Tage:"]
        let byDay = Dictionary(grouping: events) { cal.startOfDay(for: $0.startTime) }
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: start),
                  let dayEvents = byDay[day], !dayEvents.isEmpty else { continue }
            let label = offset == 0 ? "Heute" : offset == 1 ? "Morgen" : dayFormatter.string(from: day)
            let items = dayEvents.map { event -> String in
                event.isAnnual || event.spansWholeDay
                    ? "\(event.title) (ganztägig)"
                    : "\(event.title) \(timeFormatter.string(from: event.startTime))"
            }
            lines.append("• \(label): \(items.joined(separator: ", "))")
        }
        if !occurrences.isEmpty {
            let titles = Set(occurrences.compactMap { $0.routine?.title }).sorted()
            lines.append("Routinen: \(occurrences.count)× geplant (\(titles.joined(separator: ", "))).")
        }
        if !tasks.isEmpty {
            lines.append(tasks.count == 1
                ? "Fällig: \(tasks[0].title)."
                : "\(tasks.count) Aufgaben werden fällig.")
        }
        return lines.joined(separator: "\n")
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEE d.M."
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()
}

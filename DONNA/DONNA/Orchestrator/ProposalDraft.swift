import Foundation

/// Editable view of a pending `[PROPOSAL_DATA]` JSON (V2-S4 „Vorschlag bearbeiten").
///
/// The card's „Ändern" editor works on this value; `json()` writes the edits back into
/// the original dictionary so every field Gemini sent but the editor does not show
/// (notes, isLocked, category, …) survives untouched. Nothing is executed here — the
/// edited JSON still goes through the normal confirm → CommandHandler path.
struct ProposalDraft {

    enum Kind {
        case event, task, routine, routineUpdate, sleep
    }

    let kind: Kind
    var title: String
    /// Event day, or task due date.
    var date: Date
    /// Tasks only: whether a due date is set at all.
    var hasDate: Bool
    /// Event start / routine preferred time / bedtime.
    var start: Date
    /// Event end / wake time.
    var end: Date
    /// Events stored as whole-day markers (all-day or annual) only edit the day.
    private(set) var isWholeDay: Bool
    /// Routines: length in minutes.
    var durationMinutes: Int
    /// Timed events: preparation time before the event (0 = none).
    var prepMinutes: Int = 0

    private let raw: [String: Any]

    // MARK: - Parsing

    init?(json: String) {
        guard let dict = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let type = dict["type"] as? String else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func time(_ h: String, _ m: String, default dh: Int, on day: Date = today) -> Date {
            cal.date(bySettingHour: dict[h] as? Int ?? dh, minute: dict[m] as? Int ?? 0, second: 0, of: day) ?? day
        }

        raw = dict
        title = dict["title"] as? String ?? ""
        durationMinutes = dict["durationMinutes"] as? Int ?? 30
        hasDate = true
        isWholeDay = false

        switch type {
        case "createEvent":
            guard let day = (dict["date"] as? String).flatMap({ DateFormatter.isoDate.date(from: $0) }) else { return nil }
            kind = .event
            date = day
            start = time("startHour", "startMinute", default: 9, on: day)
            end = time("endHour", "endMinute", default: 10, on: day)
            isWholeDay = (dict["isAllDay"] as? Bool ?? false) || (dict["isAnnual"] as? Bool ?? false)
            prepMinutes = dict["prepMinutes"] as? Int ?? 0

        case "createTask":
            kind = .task
            let due = (dict["dueDate"] as? String).flatMap { DateFormatter.isoDate.date(from: $0) }
            hasDate = due != nil
            date = due ?? today
            start = today
            end = today

        case "createRoutine":
            kind = .routine
            date = today
            start = time("preferredTimeHour", "preferredTimeMinute", default: 9)
            end = start

        case "updateRoutine":
            kind = .routineUpdate
            title = dict["routineTitle"] as? String ?? title
            date = today
            start = time("preferredTimeHour", "preferredTimeMinute", default: 9)
            end = start

        case "setSleepWindow":
            kind = .sleep
            date = today
            start = time("bedtimeHour", "bedtimeMinute", default: 23)
            end = time("wakeHour", "wakeMinute", default: 7)

        default:
            // skipRoutine and anything unknown: nothing meaningful to edit.
            return nil
        }
    }

    // MARK: - Writing back

    /// The original JSON with the edited fields replaced. Returns nil if serialisation fails.
    func json() -> String? {
        var out = raw
        let cal = Calendar.current
        func put(_ date: Date, hour h: String, minute m: String) {
            out[h] = cal.component(.hour, from: date)
            out[m] = cal.component(.minute, from: date)
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
        case .event:
            if !trimmed.isEmpty { out["title"] = trimmed }
            out["date"] = DateFormatter.isoDate.string(from: date)
            if !isWholeDay {
                let (s, e) = normalizedEventTimes
                put(s, hour: "startHour", minute: "startMinute")
                put(e, hour: "endHour", minute: "endMinute")
                out["prepMinutes"] = prepMinutes > 0 ? prepMinutes : NSNull()
            }
        case .task:
            if !trimmed.isEmpty { out["title"] = trimmed }
            if hasDate {
                out["dueDate"] = DateFormatter.isoDate.string(from: date)
            } else {
                out.removeValue(forKey: "dueDate")
            }
        case .routine:
            if !trimmed.isEmpty { out["title"] = trimmed }
            put(start, hour: "preferredTimeHour", minute: "preferredTimeMinute")
            out["durationMinutes"] = durationMinutes
        case .routineUpdate:
            put(start, hour: "preferredTimeHour", minute: "preferredTimeMinute")
            out["durationMinutes"] = durationMinutes
        case .sleep:
            put(start, hour: "bedtimeHour", minute: "bedtimeMinute")
            put(end, hour: "wakeHour", minute: "wakeMinute")
        }

        guard let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Start/end on the same clock as the pickers; an end at or before the start keeps
    /// the originally proposed length instead of producing a negative event.
    var normalizedEventTimes: (start: Date, end: Date) {
        let cal = Calendar.current
        let s = cal.dateComponents([.hour, .minute], from: start)
        let e = cal.dateComponents([.hour, .minute], from: end)
        let startMin = (s.hour ?? 0) * 60 + (s.minute ?? 0)
        var endMin = (e.hour ?? 0) * 60 + (e.minute ?? 0)
        if endMin <= startMin {
            let original = Self.originalLength(raw) ?? 60
            endMin = min(startMin + original, 23 * 60 + 59)
        }
        let day = cal.startOfDay(for: date)
        return (day.addingTimeInterval(TimeInterval(startMin * 60)),
                day.addingTimeInterval(TimeInterval(endMin * 60)))
    }

    private static func originalLength(_ raw: [String: Any]) -> Int? {
        guard let sh = raw["startHour"] as? Int, let eh = raw["endHour"] as? Int else { return nil }
        let len = (eh * 60 + (raw["endMinute"] as? Int ?? 0)) - (sh * 60 + (raw["startMinute"] as? Int ?? 0))
        return len > 0 ? len : nil
    }

    // MARK: - Summary

    /// One German sentence describing the edited proposal, shown on the card and logged
    /// in the chat so the history reflects what was actually confirmed.
    var summary: String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .event:
            let day = Self.dayFormatter.string(from: date)
            if isWholeDay { return "Termin „\(name)“ am \(day), ganztägig." }
            let (s, e) = normalizedEventTimes
            if let rec = (raw["recurrence"] as? String).flatMap(EventRecurrence.init(rawValue:)) {
                return "Serientermin „\(name)“ \(rec.label) ab \(day), \(Self.clock(s))–\(Self.clock(e)) Uhr."
            }
            let prep = prepMinutes > 0 ? " Davor \(prepMinutes) Minuten Vorbereitung." : ""
            return "Termin „\(name)“ am \(day) von \(Self.clock(s)) bis \(Self.clock(e)) Uhr.\(prep)"
        case .task:
            return hasDate
                ? "Aufgabe „\(name)“, fällig am \(Self.dayFormatter.string(from: date))."
                : "Aufgabe „\(name)“ ohne Fälligkeitsdatum."
        case .routine:
            return "Routine „\(name)“ um \(Self.clock(start)) Uhr, \(durationMinutes) Minuten."
        case .routineUpdate:
            return "Routine „\(name)“ künftig um \(Self.clock(start)) Uhr, \(durationMinutes) Minuten."
        case .sleep:
            return "Schlaffenster von \(Self.clock(start)) bis \(Self.clock(end)) Uhr."
        }
    }

    private static func clock(_ date: Date) -> String { clockFormatter.string(from: date) }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEE, d. MMMM"
        return f
    }()
}

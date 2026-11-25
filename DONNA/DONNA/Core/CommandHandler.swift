import Foundation
import SwiftData

// MARK: - Change Descriptors

/// Describes a single field update: unchanged, set to a value, or cleared (nil).
enum FieldChange<T> {
    case unchanged
    case set(T)
    case clear // only valid for optional fields
}

struct TaskChanges {
    var title: FieldChange<String> = .unchanged
    var notes: FieldChange<String> = .unchanged
    var status: FieldChange<TaskStatus> = .unchanged
    var dueDate: FieldChange<Date> = .unchanged
    var dueTimeIncluded: FieldChange<Bool> = .unchanged
    var priority: FieldChange<Priority> = .unchanged
}

struct EventChanges {
    var title: FieldChange<String> = .unchanged
    var startTime: FieldChange<Date> = .unchanged
    var endTime: FieldChange<Date> = .unchanged
    var isLocked: FieldChange<Bool> = .unchanged
    var isAnnual: FieldChange<Bool> = .unchanged
    var notes: FieldChange<String> = .unchanged
    var prepTimeMinutes: FieldChange<Int> = .unchanged
}

struct RoutineDefinition {
    var title: String
    var frequency: RoutineFrequency
    var preferredTimeOfDay: Date?
    var durationMinutes: Int
    var priority: Priority
    var category: RoutineCategory
    var colorHex: String
    var maxSkipsBeforeWarning: Int

    init(
        title: String,
        frequency: RoutineFrequency,
        preferredTimeOfDay: Date? = nil,
        durationMinutes: Int,
        priority: Priority = .none,
        category: RoutineCategory = .custom,
        colorHex: String = "#FFFFFF",
        maxSkipsBeforeWarning: Int = 2
    ) {
        self.title = title
        self.frequency = frequency
        self.preferredTimeOfDay = preferredTimeOfDay
        self.durationMinutes = durationMinutes
        self.priority = priority
        self.category = category
        self.colorHex = colorHex
        self.maxSkipsBeforeWarning = maxSkipsBeforeWarning
    }
}

// MARK: - Command Enum

enum DONNACommand {
    // Tasks
    case createTask(title: String, dueDate: Date?, priority: Priority, notes: String? = nil)
    case updateTask(id: UUID, changes: TaskChanges)
    case completeTask(id: UUID)
    case deleteTask(id: UUID)

    // Calendar
    case createEvent(title: String, start: Date, end: Date, locked: Bool, notes: String?, isAnnual: Bool = false, prepMinutes: Int? = nil)
    case updateEvent(id: UUID, changes: EventChanges)
    case deleteEvent(id: UUID)
    /// Creates a recurring series: one CalendarEvent per occurrence, `eventSeriesHorizonWeeks` ahead.
    case createEventSeries(title: String, start: Date, end: Date, locked: Bool, notes: String?, recurrence: EventRecurrence)
    /// Deletes the series instances starting on or after `from` and ends the series there.
    case deleteEventSeries(seriesID: UUID, from: Date)
    /// Housekeeping on app start: tops running series up to the horizon. Not undoable.
    case extendEventSeries

    // Routines
    case createRoutine(definition: RoutineDefinition)
    case updateRoutine(id: UUID, title: String, frequency: RoutineFrequency, preferredTimeOfDay: Date?, durationMinutes: Int? = nil)
    case deleteRoutine(id: UUID)
    case completeOccurrence(id: UUID)
    case skipOccurrence(id: UUID, reason: String?)
    case rescheduleOccurrence(id: UUID, newDate: Date)
    /// Deletes occurrences whose routine no longer exists (leftovers from before the
    /// `.cascade` delete rule). Housekeeping, run on app start.
    case purgeOrphanedOccurrences

    // Recovery (V2-S3 Erschöpfungs-Modus)
    /// Marks `date` as a recovery day: records `exhaustion_day_<date>` and makes the day's
    /// still-open, non-high-priority routine occurrences optional (skipped, can still be done).
    case startRecoveryDay(date: Date)

    // Sleep
    case setSleepWindow(bedtime: Date, wakeTime: Date)

    // Preferences & Profile
    case confirmPreference(key: String, value: String)
    case setExplicitPreference(key: String, value: String)
    case deleteLearnedItem(key: String)

    // Context
    case activateContextMode(name: String, until: Date?)
    case deactivateContextMode

    // Chat
    /// Inserts a user-authored ChatMessage from the input field.
    case postUserMessage(content: String)
    /// Inserts an assistant-authored ChatMessage (e.g. the morning briefing).
    /// Routed through CommandHandler so all persistent writes stay in one place.
    case postAssistantMessage(content: String, outputType: AIOutputType, isBriefing: Bool = false)
    /// Marks every unread assistant ChatMessage as read (used when the chat view appears).
    case markAssistantMessagesRead
    /// Deletes every ChatMessage (Settings → „Chat-Verlauf löschen" and the one-shot
    /// test-message purge in DONNAApp both route through this).
    case clearChatHistory
    /// Collapses/dismisses a pinned briefing card without deleting the message.
    case dismissBriefing(id: UUID)

    // Undo
    case undo
}

// MARK: - Result Types

enum CommandError: Error, LocalizedError {
    case conflictDetected(description: String)
    case sleepWindowViolation
    case validationFailed(reason: String)
    case notFound(id: UUID)
    case undoUnavailable

    var errorDescription: String? {
        switch self {
        case .conflictDetected(let desc):   return desc
        case .sleepWindowViolation:         return "Diese Zeit liegt im Schlafschutzfenster."
        case .validationFailed(let reason): return reason
        case .notFound(let id):             return "Objekt nicht gefunden: \(id)"
        case .undoUnavailable:              return "Kein Undo verfügbar."
        }
    }
}

enum CommandResult {
    /// The mutation happened. `warning` carries a soft, non-blocking advisory the caller may
    /// surface (e.g. an event overlap); `case .success` without a binding still matches.
    case success(warning: String? = nil)
    case blocked(reason: String)
    case failure(CommandError)
}

// MARK: - CommandHandler

@MainActor
final class CommandHandler {
    private let modelContext: ModelContext
    /// Shared across all CommandHandler instances: views and services create a fresh
    /// handler per call, so a per-instance manager would lose the undo stack immediately.
    let undoManager: DONNAUndoManager
    private let conflictDetector: ConflictDetector
    private let scienceEngine: ScienceEngine
    private let routineScheduler: RoutineScheduler
    /// Set by create handlers so execute() can register a "delete it again" undo.
    private var createdObject: (UndoableModel, UUID)?
    /// Set by handleCreateEventSeries — undo deletes the whole new series.
    private var createdSeries: UUID?

    /// How far ahead recurring series are materialised.
    static let eventSeriesHorizonWeeks = 12

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.undoManager = DONNAUndoManager.shared
        self.conflictDetector = ConflictDetector()
        self.scienceEngine = ScienceEngine()
        self.routineScheduler = RoutineScheduler()
    }

    func execute(_ command: DONNACommand) -> CommandResult {
        if case .undo = command { return handleUndo() }

        // Undo: capture the pre-execution state, run, and register the snapshot only if
        // the command actually changed something. Chat and housekeeping commands are not
        // undoable and leave the pending undo untouched — otherwise the "Erledigt." message
        // posted right after a confirmed proposal would wipe that proposal's undo.
        let label = undoLabel(for: command)
        let before = label == nil ? nil : captureSnapshot(for: command)
        createdObject = nil
        createdSeries = nil

        let result = dispatch(command)

        if case .success = result, let label {
            if let seriesID = createdSeries {
                undoManager.register(.createdSeries(seriesID), label: label)
            } else if let (kind, id) = createdObject {
                undoManager.register(.created(kind, id: id), label: label)
            } else if let before {
                undoManager.register(before, label: label)
            }
        }
        return result
    }

    // MARK: - Undo capture

    /// German label for the undo toast; nil means the command is not undoable.
    private func undoLabel(for command: DONNACommand) -> String? {
        switch command {
        case .createTask:               return "Aufgabe erstellt"
        case .updateTask:               return "Aufgabe geändert"
        case .completeTask:             return "Aufgabe erledigt"
        case .deleteTask:               return "Aufgabe gelöscht"
        case .createEvent:              return "Termin erstellt"
        case .updateEvent:              return "Termin geändert"
        case .deleteEvent:              return "Termin gelöscht"
        case .createEventSeries:        return "Terminserie erstellt"
        case .deleteEventSeries:        return "Terminserie gelöscht"
        case .createRoutine:            return "Routine erstellt"
        case .updateRoutine:            return "Routine geändert"
        case .deleteRoutine:            return "Routine gelöscht"
        case .completeOccurrence:       return "Routine erledigt"
        case .skipOccurrence:           return "Routine übersprungen"
        case .rescheduleOccurrence:     return "Routine verschoben"
        case .setSleepWindow:           return "Schlaffenster gesetzt"
        case .startRecoveryDay:         return "Erholungstag"
        case .confirmPreference,
             .setExplicitPreference:    return "Präferenz gespeichert"
        case .deleteLearnedItem:        return "Präferenz gelöscht"
        case .activateContextMode:      return "Kontextmodus aktiviert"
        case .deactivateContextMode:    return "Kontextmodus beendet"
        case .purgeOrphanedOccurrences, .extendEventSeries,
             .postUserMessage, .postAssistantMessage, .markAssistantMessagesRead,
             .clearChatHistory, .dismissBriefing, .undo:
            return nil
        }
    }

    /// State the command is about to change. Creates return nil here — their undo is
    /// "delete the new object", registered from `createdObject` after dispatch.
    private func captureSnapshot(for command: DONNACommand) -> DONNASnapshot? {
        switch command {
        case let .updateTask(id, _), let .completeTask(id), let .deleteTask(id):
            return fetchAll(DONNATask.self).first { $0.id == id }.map { .task($0.snapshot()) }

        case let .updateEvent(id, _), let .deleteEvent(id):
            return fetchAll(CalendarEvent.self).first { $0.id == id }.map { .calendarEvent($0.snapshot()) }

        case let .deleteEventSeries(seriesID, _):
            // Whole series: deleted instances come back and the survivors get their recurrence back.
            return .calendarEvents(fetchAll(CalendarEvent.self).filter { $0.seriesID == seriesID }.map { $0.snapshot() })

        case let .updateRoutine(id, _, _, _, _), let .deleteRoutine(id):
            guard let routine = fetchAll(Routine.self).first(where: { $0.id == id }) else { return nil }
            return .routine(routine.snapshot(), occurrences: routine.occurrences.map { $0.snapshot() })

        case let .completeOccurrence(id):
            // Completing also retires stale siblings — snapshot the whole routine's set.
            let all = fetchAll(RoutineOccurrence.self)
            guard let occ = all.first(where: { $0.id == id }) else { return nil }
            let siblings = occ.routine.map { r in all.filter { $0.routine?.id == r.id } } ?? [occ]
            return .occurrences(siblings.map { $0.snapshot() })

        case let .skipOccurrence(id, _), let .rescheduleOccurrence(id, _):
            return fetchAll(RoutineOccurrence.self).first { $0.id == id }.map { .occurrences([$0.snapshot()]) }

        case let .confirmPreference(key, _), let .setExplicitPreference(key, _), let .deleteLearnedItem(key):
            let previous = fetchAll(Preference.self).first { $0.key == key }
            return .preference(key: key, previous: previous?.snapshot())

        case .activateContextMode, .deactivateContextMode:
            return .contextModes(fetchAll(ContextMode.self).map { $0.snapshot() })

        case let .startRecoveryDay(date):
            let key = Self.recoveryKey(for: date)
            let previous = fetchAll(Preference.self).first { $0.key == key }
            let day = fetchAll(RoutineOccurrence.self).filter { Calendar.current.isDate($0.scheduledDate, inSameDayAs: date) }
            return .multiple([
                .preference(key: key, previous: previous?.snapshot()),
                .occurrences(day.map { $0.snapshot() })
            ])

        default:
            return nil
        }
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
    }

    // MARK: - Dispatch

    private func dispatch(_ command: DONNACommand) -> CommandResult {
        switch command {
        case let .createTask(title, dueDate, priority, notes):
            return handleCreateTask(title: title, dueDate: dueDate, priority: priority, notes: notes)
        case let .updateTask(id, changes):
            return handleUpdateTask(id: id, changes: changes)
        case let .completeTask(id):
            return handleCompleteTask(id: id)
        case let .deleteTask(id):
            return handleDeleteTask(id: id)

        case let .createEvent(title, start, end, locked, notes, isAnnual, prepMinutes):
            return handleCreateEvent(title: title, start: start, end: end, locked: locked, notes: notes, isAnnual: isAnnual, prepMinutes: prepMinutes)
        case let .updateEvent(id, changes):
            return handleUpdateEvent(id: id, changes: changes)
        case let .deleteEvent(id):
            return handleDeleteEvent(id: id)
        case let .createEventSeries(title, start, end, locked, notes, recurrence):
            return handleCreateEventSeries(title: title, start: start, end: end, locked: locked, notes: notes, recurrence: recurrence)
        case let .deleteEventSeries(seriesID, from):
            return handleDeleteEventSeries(seriesID: seriesID, from: from)
        case .extendEventSeries:
            return handleExtendEventSeries()

        case let .createRoutine(definition):
            return handleCreateRoutine(definition: definition)
        case let .updateRoutine(id, title, frequency, preferredTimeOfDay, durationMinutes):
            return handleUpdateRoutine(id: id, title: title, frequency: frequency, preferredTimeOfDay: preferredTimeOfDay, durationMinutes: durationMinutes)
        case let .deleteRoutine(id):
            return handleDeleteRoutine(id: id)
        case let .completeOccurrence(id):
            return handleCompleteOccurrence(id: id)
        case let .skipOccurrence(id, reason):
            return handleSkipOccurrence(id: id, reason: reason)
        case let .rescheduleOccurrence(id, newDate):
            return handleRescheduleOccurrence(id: id, newDate: newDate)
        case .purgeOrphanedOccurrences:
            return handlePurgeOrphanedOccurrences()

        case let .setSleepWindow(bedtime, wakeTime):
            return handleSetSleepWindow(bedtime: bedtime, wakeTime: wakeTime)
        case let .startRecoveryDay(date):
            return handleStartRecoveryDay(date: date)

        case let .confirmPreference(key, value):
            return handleConfirmPreference(key: key, value: value)
        case let .setExplicitPreference(key, value):
            return handleSetExplicitPreference(key: key, value: value)
        case let .deleteLearnedItem(key):
            return handleDeleteLearnedItem(key: key)

        case let .activateContextMode(name, until):
            return handleActivateContextMode(name: name, until: until)
        case .deactivateContextMode:
            return handleDeactivateContextMode()

        case let .postUserMessage(content):
            return handlePostUserMessage(content: content)
        case let .postAssistantMessage(content, outputType, isBriefing):
            return handlePostAssistantMessage(content: content, outputType: outputType, isBriefing: isBriefing)
        case .markAssistantMessagesRead:
            return handleMarkAssistantMessagesRead()
        case .clearChatHistory:
            return handleClearChatHistory()
        case let .dismissBriefing(id):
            return handleDismissBriefing(id: id)

        case .undo:
            return handleUndo()
        }
    }

    // MARK: - Persistence

    /// Saves pending changes and reports the outcome honestly. On failure the context is
    /// rolled back so a half-applied mutation cannot be picked up by a later save.
    private func persist(warning: String? = nil) -> CommandResult {
        do {
            try modelContext.save()
            return .success(warning: warning)
        } catch {
            modelContext.rollback()
            #if DEBUG
            print("[DEBUG] CommandHandler: save failed — \(error)")
            #endif
            return .failure(.validationFailed(reason: "Änderung konnte nicht gespeichert werden."))
        }
    }

    // MARK: - Task Handlers

    private func handleCreateTask(title: String, dueDate: Date?, priority: Priority, notes: String?) -> CommandResult {
        let task = DONNATask(title: title, notes: notes, dueDate: dueDate, priority: priority)
        modelContext.insert(task)
        createdObject = (.task, task.id)
        return persist()
    }

    private func handleUpdateTask(id: UUID, changes: TaskChanges) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<DONNATask>()),
              let task = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        if case .set(let v) = changes.title { task.title = v }
        switch changes.notes {
        case .set(let v): task.notes = v
        case .clear:      task.notes = nil
        case .unchanged:  break
        }
        if case .set(let v) = changes.status { task.status = v }
        switch changes.dueDate {
        case .set(let v): task.dueDate = v
        case .clear:      task.dueDate = nil
        case .unchanged:  break
        }
        if case .set(let v) = changes.dueTimeIncluded { task.dueTimeIncluded = v }
        if case .set(let v) = changes.priority { task.priority = v }
        return persist()
    }

    private func handleCompleteTask(id: UUID) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<DONNATask>()),
              let task = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        task.status = .completed
        task.completedAt = Date()
        return persist()
    }

    private func handleDeleteTask(id: UUID) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<DONNATask>()),
              let task = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        modelContext.delete(task)
        return persist()
    }

    // MARK: - Calendar Handlers

    private func fetchEvents() -> [CalendarEvent] {
        (try? modelContext.fetch(FetchDescriptor<CalendarEvent>())) ?? []
    }

    private func fetchSleepWindows() -> [SleepWindow] {
        (try? modelContext.fetch(FetchDescriptor<SleepWindow>())) ?? []
    }

    private func handleCreateEvent(title: String, start: Date, end: Date, locked: Bool, notes: String?, isAnnual: Bool = false, prepMinutes: Int? = nil) -> CommandResult {
        let cal = Calendar.current
        let actualLocked = locked || isAnnual
        let actualStart: Date
        let actualEnd: Date
        if isAnnual {
            actualStart = cal.startOfDay(for: start)
            actualEnd   = cal.date(bySettingHour: 23, minute: 59, second: 0, of: start) ?? start
        } else {
            actualStart = start
            actualEnd   = end
        }
        let conflicts = conflictDetector.checkTimedEvent(
            start: actualStart,
            end: actualEnd,
            against: fetchEvents(),
            sleepWindows: fetchSleepWindows()
        )
        if let reason = conflicts.blockReason { return .blocked(reason: reason) }

        let event = CalendarEvent(title: title, startTime: actualStart, endTime: actualEnd, isLocked: actualLocked, isAnnual: isAnnual, notes: notes)
        if let prepMinutes, prepMinutes > 0, !isAnnual { event.prepTimeMinutes = prepMinutes }
        modelContext.insert(event)
        createdObject = (.calendarEvent, event.id)
        return persist(warning: conflicts.overlapWarning)
    }

    private func handleUpdateEvent(id: UUID, changes: EventChanges) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<CalendarEvent>()),
              let event = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }

        // Re-check only when the event is being moved — an edit that leaves the time window
        // alone must not be blocked by a conflict that was already accepted.
        var newStart = event.startTime
        var newEnd = event.endTime
        var timesChanged = false
        if case .set(let v) = changes.startTime { newStart = v; timesChanged = true }
        if case .set(let v) = changes.endTime   { newEnd   = v; timesChanged = true }

        var conflicts = ConflictResult.none
        if timesChanged, newStart != event.startTime || newEnd != event.endTime {
            conflicts = conflictDetector.checkTimedEvent(
                start: newStart,
                end: newEnd,
                against: all,
                sleepWindows: fetchSleepWindows(),
                excludingEventId: event.id
            )
            if let reason = conflicts.blockReason { return .blocked(reason: reason) }
        }

        if case .set(let v) = changes.title { event.title = v }
        if case .set(let v) = changes.startTime { event.startTime = v }
        if case .set(let v) = changes.endTime { event.endTime = v }
        if case .set(let v) = changes.isLocked { event.isLocked = v }
        if case .set(let v) = changes.isAnnual { event.isAnnual = v }
        switch changes.prepTimeMinutes {
        case .set(let v): event.prepTimeMinutes = v > 0 ? v : nil
        case .clear:      event.prepTimeMinutes = nil
        case .unchanged:  break
        }
        switch changes.notes {
        case .set(let v): event.notes = v
        case .clear:      event.notes = nil
        case .unchanged:  break
        }
        return persist(warning: conflicts.overlapWarning)
    }

    private func handleDeleteEvent(id: UUID) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<CalendarEvent>()),
              let event = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        modelContext.delete(event)
        return persist()
    }

    // MARK: - Event Series Handlers

    private static func seriesGeneratedUntilKey(_ id: UUID) -> String { "event_series_until_\(id.uuidString)" }

    /// Inserts instances of a series from `first` (inclusive) every `recurrence.intervalWeeks`
    /// up to the horizon. Instances that would land in a protected sleep window are skipped.
    /// Returns (created, skipped, overlapping).
    private func materializeSeries(
        seriesID: UUID, title: String, first: Date, duration: TimeInterval, locked: Bool,
        notes: String?, recurrence: EventRecurrence, horizon: Date
    ) -> (created: Int, skipped: Int, overlaps: Int) {
        let cal = Calendar.current
        var created = 0, skipped = 0, overlaps = 0
        var start = first
        var lastGenerated: Date?
        let sleep = fetchSleepWindows()
        while start <= horizon {
            let end = start.addingTimeInterval(duration)
            let check = conflictDetector.checkTimedEvent(start: start, end: end, against: fetchEvents(), sleepWindows: sleep)
            if check.blockReason != nil {
                skipped += 1
            } else {
                if check.overlapWarning != nil { overlaps += 1 }
                let event = CalendarEvent(title: title, startTime: start, endTime: end, isLocked: locked, notes: notes)
                event.seriesID = seriesID
                event.recurrenceRaw = recurrence.rawValue
                modelContext.insert(event)
                created += 1
            }
            lastGenerated = start
            guard let next = cal.date(byAdding: .weekOfYear, value: recurrence.intervalWeeks, to: start) else { break }
            start = next
        }
        if let lastGenerated {
            UserDefaults.standard.set(lastGenerated.timeIntervalSince1970, forKey: Self.seriesGeneratedUntilKey(seriesID))
        }
        return (created, skipped, overlaps)
    }

    private func seriesHorizon(from date: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .weekOfYear, value: Self.eventSeriesHorizonWeeks, to: date) ?? date
    }

    private func handleCreateEventSeries(title: String, start: Date, end: Date, locked: Bool, notes: String?, recurrence: EventRecurrence) -> CommandResult {
        guard end > start else { return .failure(.validationFailed(reason: "Ende liegt vor dem Beginn.")) }
        let seriesID = UUID()
        let result = materializeSeries(
            seriesID: seriesID, title: title, first: start, duration: end.timeIntervalSince(start),
            locked: locked, notes: notes, recurrence: recurrence,
            horizon: max(seriesHorizon(), start)
        )
        guard result.created > 0 else {
            modelContext.rollback()
            return .blocked(reason: "Alle Termine dieser Serie lägen in deinem Schlaffenster.")
        }
        createdSeries = seriesID

        var hints: [String] = []
        if result.overlaps > 0 {
            hints.append(result.overlaps == 1
                ? "Ein Termin der Serie überschneidet sich mit einem anderen Termin."
                : "\(result.overlaps) Termine der Serie überschneiden sich mit anderen Terminen.")
        }
        if result.skipped > 0 {
            hints.append(result.skipped == 1
                ? "Ein Termin lag im Schlaffenster und wurde ausgelassen."
                : "\(result.skipped) Termine lagen im Schlaffenster und wurden ausgelassen.")
        }
        return persist(warning: hints.isEmpty ? nil : hints.joined(separator: " "))
    }

    private func handleDeleteEventSeries(seriesID: UUID, from: Date) -> CommandResult {
        let cutoff = Calendar.current.startOfDay(for: from)
        let series = fetchEvents().filter { $0.seriesID == seriesID }
        guard !series.isEmpty else { return .failure(.notFound(id: seriesID)) }
        for event in series {
            if event.startTime >= cutoff {
                modelContext.delete(event)
            } else {
                event.recurrenceRaw = nil   // series ends here, nothing gets re-generated
            }
        }
        return persist()
    }

    private func handleExtendEventSeries() -> CommandResult {
        let running = fetchEvents().filter { $0.seriesID != nil && $0.recurrence != nil }
        let groups = Dictionary(grouping: running) { $0.seriesID! }
        let horizon = seriesHorizon()
        let cal = Calendar.current
        var changed = false
        for (seriesID, events) in groups {
            guard let latest = events.max(by: { $0.startTime < $1.startTime }),
                  let recurrence = latest.recurrence else { continue }
            // Continue from the last *generated* date, not the last existing instance, so a
            // deleted single occurrence at the end of the series is not re-created.
            let stored = UserDefaults.standard.object(forKey: Self.seriesGeneratedUntilKey(seriesID)) as? Double
            let anchor = max(latest.startTime, stored.map { Date(timeIntervalSince1970: $0) } ?? latest.startTime)
            guard let next = cal.date(byAdding: .weekOfYear, value: recurrence.intervalWeeks, to: anchor),
                  next <= horizon else { continue }
            let result = materializeSeries(
                seriesID: seriesID, title: latest.title,
                first: cal.date(bySettingHour: cal.component(.hour, from: latest.startTime),
                                minute: cal.component(.minute, from: latest.startTime), second: 0, of: next) ?? next,
                duration: latest.endTime.timeIntervalSince(latest.startTime),
                locked: latest.isLocked, notes: latest.notes, recurrence: recurrence, horizon: horizon
            )
            changed = changed || result.created > 0
        }
        return changed ? persist() : .success()
    }

    // MARK: - Routine Handlers

    private func handleCreateRoutine(definition: RoutineDefinition) -> CommandResult {
        let routine = Routine(
            title: definition.title,
            frequency: definition.frequency,
            preferredTimeOfDay: definition.preferredTimeOfDay,
            durationMinutes: definition.durationMinutes,
            priority: definition.priority,
            category: definition.category,
            colorHex: definition.colorHex,
            maxSkipsBeforeWarning: definition.maxSkipsBeforeWarning
        )
        modelContext.insert(routine)
        createdObject = (.routine, routine.id)
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        for occ in routineScheduler.generateOccurrences(for: routine, from: now, to: end) {
            modelContext.insert(occ)
        }
        return persist()
    }

    private func handleUpdateRoutine(id: UUID, title: String, frequency: RoutineFrequency, preferredTimeOfDay: Date?, durationMinutes: Int? = nil) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<Routine>()),
              let routine = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        routine.title = title
        routine.frequency = frequency
        routine.preferredTimeOfDay = preferredTimeOfDay
        if let durationMinutes {
            routine.durationMinutes = durationMinutes
        }
        // Move still-pending occurrences to the new preferred time so the change
        // is visible in the calendar, not only on future generations.
        if let preferred = preferredTimeOfDay {
            let cal = Calendar.current
            let comps = cal.dateComponents([.hour, .minute], from: preferred)
            for occ in routine.occurrences where occ.status == .scheduled {
                if let moved = cal.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0,
                                        second: 0, of: occ.scheduledDate) {
                    occ.scheduledDate = moved
                }
            }
        }
        return persist()
    }

    private func handleDeleteRoutine(id: UUID) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<Routine>()),
              let routine = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        modelContext.delete(routine)
        return persist()
    }

    private func handleCompleteOccurrence(id: UUID) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<RoutineOccurrence>()),
              let occ = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        occ.status = .completed
        occ.completedAt = Date()

        // Completing one occurrence means the routine has been caught up, so the other
        // past-due occurrences of the same routine are moot. Retiring them here keeps
        // them from piling up and re-firing ProactiveMonitor's consolidated proposal.
        // The filter mirrors detectForgottenRoutines' definition of "forgotten".
        if let routineID = occ.routine?.id {
            let now = Date()
            let staleSiblings = all.filter {
                $0.id != occ.id
                    && $0.routine?.id == routineID
                    && $0.status == .scheduled
                    && $0.scheduledDate < now
            }
            for sibling in staleSiblings {
                sibling.status = .skipped
                sibling.skippedReason = "automatisch übersprungen – Routine nachgeholt"
            }
        }

        return persist()
    }

    private func handleSkipOccurrence(id: UUID, reason: String?) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<RoutineOccurrence>()),
              let occ = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        occ.status = .skipped
        occ.skippedReason = reason
        return persist()
    }

    private func handleRescheduleOccurrence(id: UUID, newDate: Date) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<RoutineOccurrence>()),
              let occ = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        occ.scheduledDate = newDate
        occ.status = .rescheduled
        return persist()
    }

    private func handlePurgeOrphanedOccurrences() -> CommandResult {
        let all = (try? modelContext.fetch(FetchDescriptor<RoutineOccurrence>())) ?? []
        let orphans = all.filter { $0.routine == nil }
        guard !orphans.isEmpty else { return .success() }
        for occ in orphans { modelContext.delete(occ) }
        return persist()
    }

    // MARK: - Recovery Handler

    static let recoveryKeyPrefix = "exhaustion_day_"
    static let recoverySkipReason = "Erholungstag – optional"

    static func recoveryKey(for date: Date) -> String {
        recoveryKeyPrefix + DateFormatter.isoDate.string(from: date)
    }

    private func handleStartRecoveryDay(date: Date) -> CommandResult {
        let key = Self.recoveryKey(for: date)
        if !fetchAll(Preference.self).contains(where: { $0.key == key }) {
            modelContext.insert(Preference(
                key: key,
                value: DateFormatter.isoDate.string(from: date),
                scope: .global,
                isActive: true,
                source: .explicit,
                confirmedAt: Date()
            ))
        }
        // "Nicht-fixe" Routinen: everything except high priority becomes optional for the day.
        let cal = Calendar.current
        for occ in fetchAll(RoutineOccurrence.self)
        where occ.status == .scheduled
            && cal.isDate(occ.scheduledDate, inSameDayAs: date)
            && occ.routine?.priority != .high {
            occ.status = .skipped
            occ.skippedReason = Self.recoverySkipReason
        }
        return persist()
    }

    // MARK: - Sleep Handler

    private func handleSetSleepWindow(bedtime: Date, wakeTime: Date) -> CommandResult {
        let today = Calendar.current.startOfDay(for: Date())
        let window = SleepWindow(date: today, bedtime: bedtime, wakeTime: wakeTime)
        modelContext.insert(window)
        createdObject = (.sleepWindow, window.id)
        return persist()
    }

    // MARK: - Preference & Profile Handlers

    private func handleConfirmPreference(key: String, value: String) -> CommandResult {
        let updater = ProfileUpdater(context: modelContext)
        updater.confirmPreference(key: key, value: value)
        return .success()
    }

    /// Upserts a user-provided preference (source: .explicit) — e.g. from onboarding
    /// or Settings. Unlike confirmPreference (source: .observed), these are treated as
    /// manual entries and are not removed by the "beobachtete Präferenzen löschen" reset.
    private func handleSetExplicitPreference(key: String, value: String) -> CommandResult {
        let all = (try? modelContext.fetch(FetchDescriptor<Preference>())) ?? []
        if let existing = all.first(where: { $0.key == key }) {
            existing.value = value
            existing.scope = .global
            existing.source = .explicit
            existing.isActive = true
            existing.confirmedAt = Date()
        } else {
            modelContext.insert(Preference(
                key: key,
                value: value,
                scope: .global,
                isActive: true,
                source: .explicit,
                confirmedAt: Date()
            ))
        }
        return persist()
    }

    private func handleDeleteLearnedItem(key: String) -> CommandResult {
        let descriptor = FetchDescriptor<Preference>()
        guard let all = try? modelContext.fetch(descriptor),
              let pref = all.first(where: { $0.key == key }) else {
            return .failure(.validationFailed(reason: "Präferenz nicht gefunden: \(key)"))
        }
        modelContext.delete(pref)
        return persist()
    }

    // MARK: - Context Mode Handlers

    private func handleActivateContextMode(name: String, until: Date?) -> CommandResult {
        let allModes = (try? modelContext.fetch(FetchDescriptor<ContextMode>())) ?? []
        for mode in allModes { mode.isActive = false }
        if let match = allModes.first(where: { $0.name.lowercased() == name.lowercased() }) {
            match.isActive = true
            match.startDate = Date()
            match.endDate = until
        } else {
            modelContext.insert(ContextMode(name: name, isActive: true, startDate: Date(), endDate: until))
        }
        return persist()
    }

    private func handleDeactivateContextMode() -> CommandResult {
        let allModes = (try? modelContext.fetch(FetchDescriptor<ContextMode>())) ?? []
        for mode in allModes { mode.isActive = false }
        return persist()
    }

    // MARK: - Chat Handler

    private func handlePostUserMessage(content: String) -> CommandResult {
        let message = ChatMessage(role: .user, content: content)
        modelContext.insert(message)
        return persist()
    }

    private func handlePostAssistantMessage(content: String, outputType: AIOutputType, isBriefing: Bool) -> CommandResult {
        let message = ChatMessage(role: .assistant, content: content, outputType: outputType, isRead: false, isBriefing: isBriefing)
        modelContext.insert(message)
        return persist()
    }

    private func handleMarkAssistantMessagesRead() -> CommandResult {
        let all = (try? modelContext.fetch(FetchDescriptor<ChatMessage>())) ?? []
        let unread = all.filter { $0.role == .assistant && !$0.isRead }
        guard !unread.isEmpty else { return .success() }
        for msg in unread { msg.isRead = true }
        return persist()
    }

    private func handleClearChatHistory() -> CommandResult {
        let all = (try? modelContext.fetch(FetchDescriptor<ChatMessage>())) ?? []
        for message in all { modelContext.delete(message) }
        return persist()
    }

    private func handleDismissBriefing(id: UUID) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<ChatMessage>()),
              let message = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        message.isBriefingDismissed = true
        return persist()
    }

    // MARK: - Undo

    private func handleUndo() -> CommandResult {
        guard undoManager.canUndo else {
            return .failure(.undoUnavailable)
        }
        do {
            try undoManager.undo(context: modelContext)
            return persist()
        } catch {
            return .failure(.validationFailed(reason: error.localizedDescription))
        }
    }
}

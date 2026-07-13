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
    case createEvent(title: String, start: Date, end: Date, locked: Bool, notes: String?, isAnnual: Bool = false)
    case updateEvent(id: UUID, changes: EventChanges)
    case deleteEvent(id: UUID)

    // Routines
    case createRoutine(definition: RoutineDefinition)
    case updateRoutine(id: UUID, title: String, frequency: RoutineFrequency, preferredTimeOfDay: Date?)
    case deleteRoutine(id: UUID)
    case completeOccurrence(id: UUID)
    case skipOccurrence(id: UUID, reason: String?)
    case rescheduleOccurrence(id: UUID, newDate: Date)

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
    case success
    case blocked(reason: String)
    case failure(CommandError)
}

// MARK: - CommandHandler

@MainActor
final class CommandHandler {
    private let modelContext: ModelContext
    // TODO(V2-S3): capture a snapshot before each mutation and call undoManager.save(_:)
    let undoManager: DONNAUndoManager
    private let conflictDetector: ConflictDetector
    private let scienceEngine: ScienceEngine
    private let routineScheduler: RoutineScheduler

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.undoManager = DONNAUndoManager()
        self.conflictDetector = ConflictDetector()
        self.scienceEngine = ScienceEngine()
        self.routineScheduler = RoutineScheduler()
    }

    func execute(_ command: DONNACommand) -> CommandResult {
        if case .undo = command { return handleUndo() }
        return dispatch(command)
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

        case let .createEvent(title, start, end, locked, notes, isAnnual):
            return handleCreateEvent(title: title, start: start, end: end, locked: locked, notes: notes, isAnnual: isAnnual)
        case let .updateEvent(id, changes):
            return handleUpdateEvent(id: id, changes: changes)
        case let .deleteEvent(id):
            return handleDeleteEvent(id: id)

        case let .createRoutine(definition):
            return handleCreateRoutine(definition: definition)
        case let .updateRoutine(id, title, frequency, preferredTimeOfDay):
            return handleUpdateRoutine(id: id, title: title, frequency: frequency, preferredTimeOfDay: preferredTimeOfDay)
        case let .deleteRoutine(id):
            return handleDeleteRoutine(id: id)
        case let .completeOccurrence(id):
            return handleCompleteOccurrence(id: id)
        case let .skipOccurrence(id, reason):
            return handleSkipOccurrence(id: id, reason: reason)
        case let .rescheduleOccurrence(id, newDate):
            return handleRescheduleOccurrence(id: id, newDate: newDate)

        case let .setSleepWindow(bedtime, wakeTime):
            return handleSetSleepWindow(bedtime: bedtime, wakeTime: wakeTime)

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

    // MARK: - Task Handlers

    private func handleCreateTask(title: String, dueDate: Date?, priority: Priority, notes: String?) -> CommandResult {
        let task = DONNATask(title: title, notes: notes, dueDate: dueDate, priority: priority)
        modelContext.insert(task)
        try? modelContext.save()
        return .success
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
        try? modelContext.save()
        return .success
    }

    private func handleCompleteTask(id: UUID) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<DONNATask>()),
              let task = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        task.status = .completed
        task.completedAt = Date()
        try? modelContext.save()
        return .success
    }

    private func handleDeleteTask(id: UUID) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<DONNATask>()),
              let task = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        modelContext.delete(task)
        try? modelContext.save()
        return .success
    }

    // MARK: - Calendar Handlers

    private func handleCreateEvent(title: String, start: Date, end: Date, locked: Bool, notes: String?, isAnnual: Bool = false) -> CommandResult {
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
        let event = CalendarEvent(title: title, startTime: actualStart, endTime: actualEnd, isLocked: actualLocked, isAnnual: isAnnual, notes: notes)
        modelContext.insert(event)
        try? modelContext.save()
        return .success
    }

    private func handleUpdateEvent(id: UUID, changes: EventChanges) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<CalendarEvent>()),
              let event = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        if case .set(let v) = changes.title { event.title = v }
        if case .set(let v) = changes.startTime { event.startTime = v }
        if case .set(let v) = changes.endTime { event.endTime = v }
        if case .set(let v) = changes.isLocked { event.isLocked = v }
        if case .set(let v) = changes.isAnnual { event.isAnnual = v }
        switch changes.notes {
        case .set(let v): event.notes = v
        case .clear:      event.notes = nil
        case .unchanged:  break
        }
        try? modelContext.save()
        return .success
    }

    private func handleDeleteEvent(id: UUID) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<CalendarEvent>()),
              let event = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        modelContext.delete(event)
        try? modelContext.save()
        return .success
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
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        for occ in routineScheduler.generateOccurrences(for: routine, from: now, to: end) {
            modelContext.insert(occ)
        }
        try? modelContext.save()
        return .success
    }

    private func handleUpdateRoutine(id: UUID, title: String, frequency: RoutineFrequency, preferredTimeOfDay: Date?) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<Routine>()),
              let routine = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        routine.title = title
        routine.frequency = frequency
        routine.preferredTimeOfDay = preferredTimeOfDay
        try? modelContext.save()
        return .success
    }

    private func handleDeleteRoutine(id: UUID) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<Routine>()),
              let routine = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        modelContext.delete(routine)
        try? modelContext.save()
        return .success
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

        try? modelContext.save()
        return .success
    }

    private func handleSkipOccurrence(id: UUID, reason: String?) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<RoutineOccurrence>()),
              let occ = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        occ.status = .skipped
        occ.skippedReason = reason
        try? modelContext.save()
        return .success
    }

    private func handleRescheduleOccurrence(id: UUID, newDate: Date) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<RoutineOccurrence>()),
              let occ = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        occ.scheduledDate = newDate
        occ.status = .rescheduled
        try? modelContext.save()
        return .success
    }

    // MARK: - Sleep Handler

    private func handleSetSleepWindow(bedtime: Date, wakeTime: Date) -> CommandResult {
        let today = Calendar.current.startOfDay(for: Date())
        let window = SleepWindow(date: today, bedtime: bedtime, wakeTime: wakeTime)
        modelContext.insert(window)
        try? modelContext.save()
        return .success
    }

    // MARK: - Preference & Profile Handlers

    private func handleConfirmPreference(key: String, value: String) -> CommandResult {
        let updater = ProfileUpdater(context: modelContext)
        updater.confirmPreference(key: key, value: value)
        return .success
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
        try? modelContext.save()
        return .success
    }

    private func handleDeleteLearnedItem(key: String) -> CommandResult {
        let descriptor = FetchDescriptor<Preference>()
        guard let all = try? modelContext.fetch(descriptor),
              let pref = all.first(where: { $0.key == key }) else {
            return .failure(.validationFailed(reason: "Präferenz nicht gefunden: \(key)"))
        }
        modelContext.delete(pref)
        try? modelContext.save()
        return .success
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
        try? modelContext.save()
        return .success
    }

    private func handleDeactivateContextMode() -> CommandResult {
        let allModes = (try? modelContext.fetch(FetchDescriptor<ContextMode>())) ?? []
        for mode in allModes { mode.isActive = false }
        try? modelContext.save()
        return .success
    }

    // MARK: - Chat Handler

    private func handlePostUserMessage(content: String) -> CommandResult {
        let message = ChatMessage(role: .user, content: content)
        modelContext.insert(message)
        try? modelContext.save()
        return .success
    }

    private func handlePostAssistantMessage(content: String, outputType: AIOutputType, isBriefing: Bool) -> CommandResult {
        let message = ChatMessage(role: .assistant, content: content, outputType: outputType, isRead: false, isBriefing: isBriefing)
        modelContext.insert(message)
        try? modelContext.save()
        return .success
    }

    private func handleMarkAssistantMessagesRead() -> CommandResult {
        let all = (try? modelContext.fetch(FetchDescriptor<ChatMessage>())) ?? []
        let unread = all.filter { $0.role == .assistant && !$0.isRead }
        guard !unread.isEmpty else { return .success }
        for msg in unread { msg.isRead = true }
        try? modelContext.save()
        return .success
    }

    private func handleClearChatHistory() -> CommandResult {
        let all = (try? modelContext.fetch(FetchDescriptor<ChatMessage>())) ?? []
        for message in all { modelContext.delete(message) }
        try? modelContext.save()
        return .success
    }

    private func handleDismissBriefing(id: UUID) -> CommandResult {
        guard let all = try? modelContext.fetch(FetchDescriptor<ChatMessage>()),
              let message = all.first(where: { $0.id == id }) else {
            return .failure(.notFound(id: id))
        }
        message.isBriefingDismissed = true
        try? modelContext.save()
        return .success
    }

    // MARK: - Undo

    private func handleUndo() -> CommandResult {
        guard undoManager.canUndo else {
            return .failure(.undoUnavailable)
        }
        do {
            try undoManager.undo(context: modelContext)
            return .success
        } catch {
            return .failure(.validationFailed(reason: error.localizedDescription))
        }
    }
}

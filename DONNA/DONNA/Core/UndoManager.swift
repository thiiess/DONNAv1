import Foundation
import SwiftData
import Observation

// MARK: - Snapshot Value Types
// Each struct mirrors the stored properties of its @Model counterpart.
// Values are captured before execution so they can be restored on undo — including
// re-inserting an object that the command deleted (same id, same values).

struct TaskSnapshot {
    let id: UUID
    let title: String
    let notes: String?
    let status: TaskStatus
    let dueDate: Date?
    let dueTimeIncluded: Bool
    let priority: Priority
    let createdAt: Date
    let completedAt: Date?
    let dataLayer: DataLayer
}

struct CalendarEventSnapshot {
    let id: UUID
    let title: String
    let startTime: Date
    let endTime: Date
    let isLocked: Bool
    let isAnnual: Bool
    let notes: String?
    let createdAt: Date
    let dataLayer: DataLayer
    let seriesID: UUID?
    let recurrenceRaw: String?
}

struct RoutineSnapshot {
    let id: UUID
    let title: String
    let frequency: RoutineFrequency
    let preferredTimeOfDay: Date?
    let durationMinutes: Int
    let priority: Priority
    let isActive: Bool
    let category: RoutineCategory
    let colorHex: String
    let maxSkipsBeforeWarning: Int
    let createdAt: Date
}

struct OccurrenceSnapshot {
    let id: UUID
    let routineID: UUID?
    let scheduledDate: Date
    let status: OccurrenceStatus
    let completedAt: Date?
    let skippedReason: String?
    let dataLayer: DataLayer
}

struct PreferenceSnapshot {
    let id: UUID
    let key: String
    let value: String
    let scope: PreferenceScope
    let isActive: Bool
    let source: PreferenceSource
    let confirmedAt: Date?
    let createdAt: Date
}

struct ContextModeSnapshot {
    let id: UUID
    let name: String
    let isActive: Bool
    let startDate: Date?
    let endDate: Date?
    let overrides: Data
}

// MARK: - Snapshot Enum

enum UndoableModel {
    case task, calendarEvent, routine, sleepWindow
}

enum DONNASnapshot {
    /// Undo of a create: delete the object with this id (routines cascade to their occurrences).
    case created(UndoableModel, id: UUID)
    case task(TaskSnapshot)
    case calendarEvent(CalendarEventSnapshot)
    /// Several events at once (a recurring series).
    case calendarEvents([CalendarEventSnapshot])
    /// Undo of a series create: delete every event of the series.
    case createdSeries(UUID)
    /// A routine together with every occurrence it had — covers edits that move
    /// occurrences and deletes that cascade.
    case routine(RoutineSnapshot, occurrences: [OccurrenceSnapshot])
    /// One or more occurrences (completing one also retires its stale siblings).
    case occurrences([OccurrenceSnapshot])
    /// The preference stored under `key` before the command; nil = there was none.
    case preference(key: String, previous: PreferenceSnapshot?)
    /// Every context mode before the command (activation deactivates all others).
    case contextModes([ContextModeSnapshot])
}

// MARK: - Undo Errors

enum UndoError: Error, LocalizedError {
    case noSnapshotAvailable
    case restorationFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .noSnapshotAvailable:      return "Kein Undo-Snapshot vorhanden."
        case .restorationFailed(let r): return "Wiederherstellung fehlgeschlagen: \(r)"
        }
    }
}

// MARK: - DONNAUndoManager

/// Holds exactly one pre-execution snapshot (one level of undo — spec requirement) and
/// restores it. Observable so the undo toast can follow the latest undoable action.
/// All writes still go through CommandHandler: the toast calls `.undo`, and only
/// CommandHandler calls `register`/`undo` here.
@MainActor
@Observable
final class DONNAUndoManager {
    /// Single app-wide undo stack (see CommandHandler.init).
    static let shared = DONNAUndoManager()

    private(set) var pendingSnapshot: DONNASnapshot?
    /// Short German description of the action that can be undone, e.g. "Termin gelöscht".
    private(set) var actionLabel: String?
    /// Changes on every registered action / undo so the toast can restart its timer.
    private(set) var revision = 0
    /// Set after a successful undo so the toast can confirm it.
    private(set) var lastUndoneLabel: String?

    var canUndo: Bool { pendingSnapshot != nil }

    func register(_ snapshot: DONNASnapshot, label: String) {
        pendingSnapshot = snapshot
        actionLabel = label
        lastUndoneLabel = nil
        revision += 1
    }

    /// Clears the snapshot without restoring.
    func clear() {
        pendingSnapshot = nil
        actionLabel = nil
    }

    /// Restores the pre-execution state into `context`. The caller saves.
    func undo(context: ModelContext) throws {
        guard let snapshot = pendingSnapshot else { throw UndoError.noSnapshotAvailable }
        try restore(snapshot, context: context)
        lastUndoneLabel = actionLabel
        pendingSnapshot = nil
        actionLabel = nil
        revision += 1
    }

    // MARK: - Restore

    private func restore(_ snapshot: DONNASnapshot, context: ModelContext) throws {
        switch snapshot {
        case let .created(kind, id):
            deleteCreated(kind, id: id, context: context)
        case let .task(snap):
            restoreTask(snap, context: context)
        case let .calendarEvent(snap):
            restoreCalendarEvent(snap, context: context)
        case let .calendarEvents(snaps):
            for snap in snaps { restoreCalendarEvent(snap, context: context) }
        case let .createdSeries(seriesID):
            for event in fetch(CalendarEvent.self, context) where event.seriesID == seriesID {
                context.delete(event)
            }
        case let .routine(snap, occurrences):
            let routine = restoreRoutine(snap, context: context)
            for occ in occurrences { restoreOccurrence(occ, routine: routine, context: context) }
        case let .occurrences(snaps):
            let routines = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
            for occ in snaps {
                let routine = routines.first { $0.id == occ.routineID }
                restoreOccurrence(occ, routine: routine, context: context)
            }
        case let .preference(key, previous):
            restorePreference(key: key, previous: previous, context: context)
        case let .contextModes(snaps):
            restoreContextModes(snaps, context: context)
        }
    }

    private func deleteCreated(_ kind: UndoableModel, id: UUID, context: ModelContext) {
        switch kind {
        case .task:
            if let obj = fetch(DONNATask.self, context).first(where: { $0.id == id }) { context.delete(obj) }
        case .calendarEvent:
            if let obj = fetch(CalendarEvent.self, context).first(where: { $0.id == id }) { context.delete(obj) }
        case .routine:
            if let obj = fetch(Routine.self, context).first(where: { $0.id == id }) { context.delete(obj) }
        case .sleepWindow:
            if let obj = fetch(SleepWindow.self, context).first(where: { $0.id == id }) { context.delete(obj) }
        }
    }

    private func restoreTask(_ s: TaskSnapshot, context: ModelContext) {
        let task = fetch(DONNATask.self, context).first { $0.id == s.id } ?? {
            let t = DONNATask(id: s.id, title: s.title)
            context.insert(t)
            return t
        }()
        task.title = s.title
        task.notes = s.notes
        task.status = s.status
        task.dueDate = s.dueDate
        task.dueTimeIncluded = s.dueTimeIncluded
        task.priority = s.priority
        task.createdAt = s.createdAt
        task.completedAt = s.completedAt
        task.dataLayer = s.dataLayer
    }

    private func restoreCalendarEvent(_ s: CalendarEventSnapshot, context: ModelContext) {
        let event = fetch(CalendarEvent.self, context).first { $0.id == s.id } ?? {
            let e = CalendarEvent(id: s.id, title: s.title, startTime: s.startTime, endTime: s.endTime)
            context.insert(e)
            return e
        }()
        event.title = s.title
        event.startTime = s.startTime
        event.endTime = s.endTime
        event.isLocked = s.isLocked
        event.isAnnual = s.isAnnual
        event.notes = s.notes
        event.createdAt = s.createdAt
        event.dataLayer = s.dataLayer
        event.seriesID = s.seriesID
        event.recurrenceRaw = s.recurrenceRaw
    }

    private func restoreRoutine(_ s: RoutineSnapshot, context: ModelContext) -> Routine {
        let routine = fetch(Routine.self, context).first { $0.id == s.id } ?? {
            let r = Routine(id: s.id, title: s.title, frequency: s.frequency, durationMinutes: s.durationMinutes)
            context.insert(r)
            return r
        }()
        routine.title = s.title
        routine.frequency = s.frequency
        routine.preferredTimeOfDay = s.preferredTimeOfDay
        routine.durationMinutes = s.durationMinutes
        routine.priority = s.priority
        routine.isActive = s.isActive
        routine.category = s.category
        routine.colorHex = s.colorHex
        routine.maxSkipsBeforeWarning = s.maxSkipsBeforeWarning
        routine.createdAt = s.createdAt
        return routine
    }

    private func restoreOccurrence(_ s: OccurrenceSnapshot, routine: Routine?, context: ModelContext) {
        let occ = fetch(RoutineOccurrence.self, context).first { $0.id == s.id } ?? {
            let o = RoutineOccurrence(id: s.id, scheduledDate: s.scheduledDate)
            context.insert(o)
            return o
        }()
        if let routine { occ.routine = routine }
        occ.scheduledDate = s.scheduledDate
        occ.status = s.status
        occ.completedAt = s.completedAt
        occ.skippedReason = s.skippedReason
        occ.dataLayer = s.dataLayer
    }

    private func restorePreference(key: String, previous: PreferenceSnapshot?, context: ModelContext) {
        let current = fetch(Preference.self, context).filter { $0.key == key }
        guard let s = previous else {
            for pref in current { context.delete(pref) }
            return
        }
        let pref = current.first { $0.id == s.id } ?? current.first ?? {
            let p = Preference(id: s.id, key: s.key, value: s.value, scope: s.scope, source: s.source)
            context.insert(p)
            return p
        }()
        pref.value = s.value
        pref.scope = s.scope
        pref.isActive = s.isActive
        pref.source = s.source
        pref.confirmedAt = s.confirmedAt
        pref.createdAt = s.createdAt
    }

    private func restoreContextModes(_ snaps: [ContextModeSnapshot], context: ModelContext) {
        let current = fetch(ContextMode.self, context)
        // Modes created by the command did not exist before — remove them.
        for mode in current where !snaps.contains(where: { $0.id == mode.id }) {
            context.delete(mode)
        }
        for s in snaps {
            let mode = current.first { $0.id == s.id } ?? {
                let m = ContextMode(id: s.id, name: s.name)
                context.insert(m)
                return m
            }()
            mode.name = s.name
            mode.isActive = s.isActive
            mode.startDate = s.startDate
            mode.endDate = s.endDate
            mode.overrides = s.overrides
        }
    }

    private func fetch<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }
}

// MARK: - Model → Snapshot Helpers

extension DONNATask {
    func snapshot() -> TaskSnapshot {
        TaskSnapshot(
            id: id, title: title, notes: notes, status: status,
            dueDate: dueDate, dueTimeIncluded: dueTimeIncluded,
            priority: priority, createdAt: createdAt,
            completedAt: completedAt, dataLayer: dataLayer
        )
    }
}

extension CalendarEvent {
    func snapshot() -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id, title: title, startTime: startTime, endTime: endTime,
            isLocked: isLocked, isAnnual: isAnnual, notes: notes,
            createdAt: createdAt, dataLayer: dataLayer,
            seriesID: seriesID, recurrenceRaw: recurrenceRaw
        )
    }
}

extension Routine {
    func snapshot() -> RoutineSnapshot {
        RoutineSnapshot(
            id: id, title: title, frequency: frequency,
            preferredTimeOfDay: preferredTimeOfDay, durationMinutes: durationMinutes,
            priority: priority, isActive: isActive, category: category,
            colorHex: colorHex, maxSkipsBeforeWarning: maxSkipsBeforeWarning, createdAt: createdAt
        )
    }
}

extension RoutineOccurrence {
    func snapshot() -> OccurrenceSnapshot {
        OccurrenceSnapshot(
            id: id, routineID: routine?.id, scheduledDate: scheduledDate,
            status: status, completedAt: completedAt,
            skippedReason: skippedReason, dataLayer: dataLayer
        )
    }
}

extension Preference {
    func snapshot() -> PreferenceSnapshot {
        PreferenceSnapshot(
            id: id, key: key, value: value, scope: scope,
            isActive: isActive, source: source,
            confirmedAt: confirmedAt, createdAt: createdAt
        )
    }
}

extension ContextMode {
    func snapshot() -> ContextModeSnapshot {
        ContextModeSnapshot(
            id: id, name: name, isActive: isActive,
            startDate: startDate, endDate: endDate, overrides: overrides
        )
    }
}

import Foundation
import SwiftData

// MARK: - Snapshot Value Types
// Each struct mirrors the stored properties of its @Model counterpart.
// Values are captured before execution so they can be restored on undo.

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
    let notes: String?
    let createdAt: Date
    let dataLayer: DataLayer
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

struct SleepWindowSnapshot {
    let id: UUID
    let date: Date
    let bedtime: Date
    let wakeTime: Date
    let isProtected: Bool
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
}

// MARK: - Snapshot Enum

enum DONNASnapshot {
    /// Undo of a create: delete the object with this ID.
    case createdObject(id: UUID, type: String)

    case task(TaskSnapshot)
    case calendarEvent(CalendarEventSnapshot)
    case routine(RoutineSnapshot)
    case occurrence(OccurrenceSnapshot)
    case sleepWindow(SleepWindowSnapshot)
    case preference(PreferenceSnapshot)
    case learnedItem(key: String, previousValue: String)
    case contextMode(ContextModeSnapshot?)

    /// Groups multiple snapshots for commands that touch more than one object.
    case compound([DONNASnapshot])
}

// MARK: - Undo Errors

enum UndoError: Error, LocalizedError {
    case noSnapshotAvailable
    case objectNotFound(id: UUID)
    case restorationFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .noSnapshotAvailable:          return "Kein Undo-Snapshot vorhanden."
        case .objectNotFound(let id):       return "Objekt nicht gefunden: \(id)"
        case .restorationFailed(let r):     return "Wiederherstellung fehlgeschlagen: \(r)"
        }
    }
}

// MARK: - DONNAUndoManager

/// Stores exactly one pre-execution snapshot and can restore it.
/// Only one level of undo is supported (spec requirement).
final class DONNAUndoManager {
    private(set) var pendingSnapshot: DONNASnapshot?

    var canUndo: Bool { pendingSnapshot != nil }

    /// Called by CommandHandler before each execution to capture current state.
    func save(_ snapshot: DONNASnapshot) {
        pendingSnapshot = snapshot
    }

    /// Clears the snapshot without restoring (e.g. after the user declines undo).
    func clear() {
        pendingSnapshot = nil
    }

    /// Restores the pre-execution state. Implemented per handler in Session 3–4.
    func undo(context: ModelContext) throws {
        guard let snapshot = pendingSnapshot else {
            throw UndoError.noSnapshotAvailable
        }
        try restore(snapshot, context: context)
        pendingSnapshot = nil
    }

    // MARK: - Restore (Session 3–4)

    private func restore(_ snapshot: DONNASnapshot, context: ModelContext) throws {
        switch snapshot {
        case let .createdObject(id, type):
            try deleteCreatedObject(id: id, type: type, context: context)
        case let .task(snap):
            try restoreTask(snap, context: context)
        case let .calendarEvent(snap):
            try restoreCalendarEvent(snap, context: context)
        case let .routine(snap):
            try restoreRoutine(snap, context: context)
        case let .occurrence(snap):
            try restoreOccurrence(snap, context: context)
        case let .sleepWindow(snap):
            try restoreSleepWindow(snap, context: context)
        case let .preference(snap):
            try restorePreference(snap, context: context)
        case let .learnedItem(key, previousValue):
            try restoreLearnedItem(key: key, previousValue: previousValue, context: context)
        case let .contextMode(snap):
            try restoreContextMode(snap, context: context)
        case let .compound(snapshots):
            for s in snapshots { try restore(s, context: context) }
        }
    }

    // MARK: - Per-Type Restores (implemented in Session 3)

    private func deleteCreatedObject(id: UUID, type: String, context: ModelContext) throws {
        // TODO(V2-S3): fetch object by ID and type, delete from context
    }

    private func restoreTask(_ snap: TaskSnapshot, context: ModelContext) throws {
        // TODO(V2-S3): fetch Task by snap.id, write all properties back
    }

    private func restoreCalendarEvent(_ snap: CalendarEventSnapshot, context: ModelContext) throws {
        // TODO(V2-S3): fetch CalendarEvent by snap.id, write all properties back
    }

    private func restoreRoutine(_ snap: RoutineSnapshot, context: ModelContext) throws {
        // TODO(V2-S3): fetch Routine by snap.id, write all properties back
    }

    private func restoreOccurrence(_ snap: OccurrenceSnapshot, context: ModelContext) throws {
        // TODO(V2-S3): fetch RoutineOccurrence by snap.id, write all properties back
    }

    private func restoreSleepWindow(_ snap: SleepWindowSnapshot, context: ModelContext) throws {
        // TODO(V2-S3): fetch SleepWindow by snap.id, write all properties back
    }

    private func restorePreference(_ snap: PreferenceSnapshot, context: ModelContext) throws {
        // TODO(V2-S3): fetch Preference by snap.id, write all properties back
    }

    private func restoreLearnedItem(key: String, previousValue: String, context: ModelContext) throws {
        // TODO(V2-S3): restore Preference with source=observed for this key
    }

    private func restoreContextMode(_ snap: ContextModeSnapshot?, context: ModelContext) throws {
        // TODO(V2-S3): deactivate current mode, restore previous if snap != nil
    }
}

// MARK: - Model → Snapshot Helpers

extension Task {
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
            isLocked: isLocked, notes: notes, createdAt: createdAt, dataLayer: dataLayer
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

extension SleepWindow {
    func snapshot() -> SleepWindowSnapshot {
        SleepWindowSnapshot(
            id: id, date: date, bedtime: bedtime, wakeTime: wakeTime,
            isProtected: isProtected, dataLayer: dataLayer
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
            startDate: startDate, endDate: endDate
        )
    }
}

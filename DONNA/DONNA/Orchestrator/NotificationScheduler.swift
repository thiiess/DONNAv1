import Foundation
import UserNotifications
import SwiftData

// MARK: - NotificationScheduler

/// Manages all UNUserNotification scheduling for tasks, routines, and sleep warnings.
/// Also keeps the app badge count in sync with unread assistant ChatMessages.
final class NotificationScheduler: @unchecked Sendable {

    static let shared = NotificationScheduler()
    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Permission

    /// Requests notification authorization on first launch (idempotent).
    func requestPermissionIfNeeded() {
        let key = "notification_permission_requested"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - Task reminders (30 min before dueDate when dueTimeIncluded)

    func scheduleTaskReminder(for task: Task) {
        guard let due = task.dueDate, task.dueTimeIncluded, task.status == .open else { return }
        let fireDate = due.addingTimeInterval(-30 * 60)
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Aufgabe fällig")
        content.body = task.title
        content.sound = .default

        schedule(
            identifier: taskReminderID(task),
            content: content,
            at: fireDate
        )
    }

    func cancelTaskReminder(for task: Task) {
        center.removePendingNotificationRequests(withIdentifiers: [taskReminderID(task)])
    }

    // MARK: - Routine reminders (15 min before scheduledDate)

    func scheduleRoutineReminder(for occurrence: RoutineOccurrence) {
        guard occurrence.status == .scheduled else { return }
        let fireDate = occurrence.scheduledDate.addingTimeInterval(-15 * 60)
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Routine-Erinnerung")
        content.body = occurrence.routine?.title ?? String(localized: "Deine Routine startet bald")
        content.sound = .default

        schedule(
            identifier: routineReminderID(occurrence),
            content: content,
            at: fireDate
        )
    }

    func cancelRoutineReminder(for occurrence: RoutineOccurrence) {
        center.removePendingNotificationRequests(withIdentifiers: [routineReminderID(occurrence)])
    }

    // MARK: - Sleep warning (immediate, when an event lands inside the sleep window)

    func scheduleSleepWarning(for event: CalendarEvent, sleepWindow: SleepWindow) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Schlafwarnung")
        content.body = String(localized: "Ein geplanter Termin liegt in deinem Schlafschutzfenster.")
        content.sound = .default

        // Deliver immediately (5 s offset so the system can coalesce)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let id = "sleep_warning_\(event.id.uuidString)_\(sleepWindow.id.uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }

    // MARK: - Badge count

    /// Counts unread assistant ChatMessages and updates the app badge.
    /// Call this whenever messages are inserted or marked as read.
    func updateBadgeCount(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<ChatMessage>()
        let messages = (try? modelContext.fetch(descriptor)) ?? []
        let unreadCount = messages.filter { $0.role == .assistant && !$0.isRead }.count
        center.setBadgeCount(unreadCount, withCompletionHandler: nil)
    }

    // MARK: - Private helpers

    private func taskReminderID(_ task: Task) -> String {
        "task_reminder_\(task.id.uuidString)"
    }

    private func routineReminderID(_ occurrence: RoutineOccurrence) -> String {
        "routine_reminder_\(occurrence.id.uuidString)"
    }

    private func schedule(identifier: String, content: UNMutableNotificationContent, at date: Date) {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        // Replace any existing notification with the same ID
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.add(request, withCompletionHandler: nil)
    }
}

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

    /// Requests authorization and returns whether notifications are granted.
    /// The system only shows the prompt once; subsequent calls resolve immediately.
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: - Morning briefing (repeating daily nudge)

    private static let morningBriefingID = "morning_briefing"

    /// Schedules (or replaces) a repeating daily notification at the given time.
    /// The notification is only a generic nudge — the actual briefing is generated
    /// in-app as a ChatMessage when the app is opened.
    func scheduleMorningBriefing(at time: Date) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Guten Morgen")
        content.body = String(localized: "Dein Tagesüberblick wartet in DONNA.")
        content.sound = .default

        let cal = Calendar.current
        var components = DateComponents()
        components.hour = cal.component(.hour, from: time)
        components.minute = cal.component(.minute, from: time)

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.morningBriefingID,
            content: content,
            trigger: trigger
        )
        center.removePendingNotificationRequests(withIdentifiers: [Self.morningBriefingID])
        center.add(request, withCompletionHandler: nil)
    }

    func cancelMorningBriefing() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.morningBriefingID])
    }

    // MARK: - Weekly summary (repeating Sunday nudge)

    private static let weeklySummaryID = "weekly_summary"

    /// Schedules (or replaces) a repeating Sunday notification at the given time of day.
    /// Like the morning briefing it is only a nudge; the summary itself is built in-app.
    func scheduleWeeklySummary(at time: Date) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Wochenrückblick")
        content.body = String(localized: "Deine Woche im Überblick wartet in DONNA.")
        content.sound = .default

        let cal = Calendar.current
        var components = DateComponents()
        components.weekday = 1 // Sunday
        components.hour = cal.component(.hour, from: time)
        components.minute = cal.component(.minute, from: time)

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: Self.weeklySummaryID, content: content, trigger: trigger)
        center.removePendingNotificationRequests(withIdentifiers: [Self.weeklySummaryID])
        center.add(request, withCompletionHandler: nil)
    }

    func cancelWeeklySummary() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.weeklySummaryID])
    }

    // MARK: - Central reminder sync

    private static let reminderIDsKey = "donna_reminder_ids"
    /// iOS keeps at most 64 pending local notifications per app; leave room for the
    /// briefing/summary nudges.
    private static let maxReminders = 50

    /// Replaces every DONNA reminder with a fresh set built from the current data:
    /// open tasks with a due time, scheduled routine occurrences, and timed events
    /// (at the start of their preparation time if they have one) in the next 7 days.
    /// Called on app start and after every data command, so reminders can never drift
    /// from what is in the calendar. Wording invites, never alarms (Fundament).
    @MainActor
    func rescheduleAll(modelContext: ModelContext, now: Date = Date()) {
        let defaults = UserDefaults.standard
        let old = defaults.stringArray(forKey: Self.reminderIDsKey) ?? []
        center.removePendingNotificationRequests(withIdentifiers: old)

        guard let horizon = Calendar.current.date(byAdding: .day, value: 7, to: now) else { return }
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "de_DE")
        clock.dateFormat = "HH:mm"

        var planned: [(id: String, date: Date, title: String, body: String)] = []

        for task in (try? modelContext.fetch(FetchDescriptor<DONNATask>())) ?? []
        where task.status == .open && task.dueTimeIncluded {
            guard let due = task.dueDate else { continue }
            let fire = due.addingTimeInterval(-30 * 60)
            if fire > now && fire < horizon {
                planned.append(("task_reminder_\(task.id.uuidString)", fire, "In 30 Minuten fällig", task.title))
            }
        }

        for occ in (try? modelContext.fetch(FetchDescriptor<RoutineOccurrence>())) ?? []
        where occ.status == .scheduled {
            guard let routine = occ.routine, routine.isActive else { continue }
            let fire = occ.scheduledDate.addingTimeInterval(-15 * 60)
            if fire > now && fire < horizon {
                planned.append(("routine_reminder_\(occ.id.uuidString)", fire, routine.title,
                                "Um \(clock.string(from: occ.scheduledDate)) – wenn es heute passt."))
            }
        }

        for event in (try? modelContext.fetch(FetchDescriptor<CalendarEvent>())) ?? []
        where !event.isAnnual && !event.spansWholeDay {
            let prep = event.prepTimeMinutes ?? 0
            let fire = event.startTime.addingTimeInterval(TimeInterval(-(prep > 0 ? prep : 15) * 60))
            guard fire > now && fire < horizon else { continue }
            let body = prep > 0
                ? "Zeit zur Vorbereitung – los geht's um \(clock.string(from: event.startTime))."
                : "Beginnt um \(clock.string(from: event.startTime))."
            planned.append(("event_reminder_\(event.id.uuidString)", fire, event.title, body))
        }

        let chosen = planned.sorted { $0.date < $1.date }.prefix(Self.maxReminders)
        for item in chosen {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            schedule(identifier: item.id, content: content, at: item.date)
        }
        defaults.set(chosen.map(\.id), forKey: Self.reminderIDsKey)
    }

    // MARK: - Task reminders (30 min before dueDate when dueTimeIncluded)

    func scheduleTaskReminder(for task: DONNATask) {
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

    func cancelTaskReminder(for task: DONNATask) {
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

    private func taskReminderID(_ task: DONNATask) -> String {
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

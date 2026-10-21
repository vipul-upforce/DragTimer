import Foundation
import EventKit
import AppKit

final class ReminderSync {
    static let shared = ReminderSync()
    private let store = EKEventStore()
    private init() {}

    var authorizationStatus: EKAuthorizationStatus {
        if #available(macOS 14.0, *) {
            return EKEventStore.authorizationStatus(for: .reminder)
        }
        return EKEventStore.authorizationStatus(for: .reminder)
    }

    func requestAccess(_ completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToReminders { granted, error in
                if let error {
                    NSLog("DragTimer: Reminders access error: \(error.localizedDescription)")
                }
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            store.requestAccess(to: .reminder) { granted, error in
                if let error {
                    NSLog("DragTimer: Reminders access error: \(error.localizedDescription)")
                }
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    func addReminder(for timer: TimerItem, completion: @escaping (String?) -> Void) {
        requestAccess { [weak self] granted in
            guard granted, let self else {
                NSLog("DragTimer: Reminders permission not granted")
                completion(nil)
                return
            }

            guard let calendar = self.store.defaultCalendarForNewReminders() else {
                NSLog("DragTimer: no default Reminders calendar")
                completion(nil)
                return
            }

            let reminder = EKReminder(eventStore: self.store)
            reminder.title = timer.displayTitle
            reminder.calendar = calendar
            reminder.notes = "Created by DragTimer"
            // Include seconds so short timers aren't rounded to the current minute.
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: timer.dueAt
            )
            // Due date alone does not alert — an alarm is required for notification.
            reminder.addAlarm(EKAlarm(absoluteDate: timer.dueAt))

            do {
                try self.store.save(reminder, commit: true)
                NSLog("DragTimer: saved Reminder \(reminder.calendarItemIdentifier) due \(timer.dueAt)")
                completion(reminder.calendarItemIdentifier)
            } catch {
                NSLog("DragTimer: failed to save Reminder: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }
}

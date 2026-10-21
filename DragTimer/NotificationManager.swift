import Foundation
import UserNotifications
import AppKit
import Combine

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {
        refreshAuthorizationStatus()
    }

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.authorizationStatus = settings.authorizationStatus
                switch settings.authorizationStatus {
                case .notDetermined:
                    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                        if let error {
                            NSLog("DragTimer: notification auth error: \(error.localizedDescription)")
                        }
                        Task { @MainActor in
                            self?.refreshAuthorizationStatus()
                            if !granted {
                                NSLog("DragTimer: notification permission not granted")
                            }
                        }
                    }
                case .denied:
                    NSLog("DragTimer: notifications denied — enable in System Settings › Notifications › DragTimer")
                default:
                    break
                }
            }
        }
    }

    func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    func schedule(_ timer: TimerItem) {
        guard timer.dueAt > Date() else { return }
        guard AlertPreferences.shared.systemNotifications else { return }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.authorizationStatus = settings.authorizationStatus
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    self?.enqueue(timer)
                case .notDetermined:
                    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                        Task { @MainActor in
                            self?.refreshAuthorizationStatus()
                            if granted { self?.enqueue(timer) }
                        }
                    }
                case .denied:
                    NSLog("DragTimer: cannot schedule notification — permission denied")
                @unknown default:
                    self?.enqueue(timer)
                }
            }
        }
    }

    /// System notification banner when a timer completes (often suppressed by Focus/DND).
    func deliverCompletion(_ timer: TimerItem, playSound: Bool = true) {
        guard AlertPreferences.shared.systemNotifications else { return }

        let center = UNUserNotificationCenter.current()
        let id = timer.id.uuidString

        center.getDeliveredNotifications { delivered in
            let alreadyShown = delivered.contains { $0.request.identifier == id }
            center.removePendingNotificationRequests(withIdentifiers: [id])

            Task { @MainActor in
                if playSound {
                    if let sound = NSSound(named: NSSound.Name("Glass")) {
                        sound.play()
                    } else {
                        NSSound.beep()
                    }
                }

                guard !alreadyShown else { return }

                let content = UNMutableNotificationContent()
                content.title = timer.displayTitle
                content.body = "Timer finished"
                content.sound = playSound ? .default : nil
                if #available(macOS 12.0, *) {
                    content.interruptionLevel = .timeSensitive
                }

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
                let request = UNNotificationRequest(identifier: "done-\(id)", content: content, trigger: trigger)
                center.add(request) { error in
                    if let error {
                        NSLog("DragTimer: deliverCompletion failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func cancel(_ timer: TimerItem) {
        let center = UNUserNotificationCenter.current()
        let ids = [timer.id.uuidString, "done-\(timer.id.uuidString)"]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func enqueue(_ timer: TimerItem) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [timer.id.uuidString])

        let content = UNMutableNotificationContent()
        content.title = timer.displayTitle
        content.body = "Timer finished"
        content.sound = .default
        if #available(macOS 12.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let interval = max(1, timer.dueAt.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: timer.id.uuidString,
            content: content,
            trigger: trigger
        )
        center.add(request) { error in
            if let error {
                NSLog("DragTimer: schedule failed: \(error.localizedDescription)")
            } else {
                NSLog("DragTimer: scheduled notification in \(Int(interval))s for \(timer.id)")
            }
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}

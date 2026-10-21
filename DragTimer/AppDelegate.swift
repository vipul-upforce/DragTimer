import AppKit
import UserNotifications

// NOTE: @main removed — see main.swift. Using @main on a @MainActor class in
// Swift 5.9 generates an async entry point that never fires applicationDidFinishLaunching.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        NotificationManager.shared.requestAuthorization()

        // Create the status item after the run loop is spinning. Synchronous
        // @MainActor hops from the delegate callback can deadlock on newer macOS.
        DispatchQueue.main.async { [weak self] in
            self?.menuBarController = MenuBarController(store: .shared)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

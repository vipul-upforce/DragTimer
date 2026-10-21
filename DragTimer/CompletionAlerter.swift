import AppKit

/// Routes timer-finished alerts according to user preferences.
@MainActor
final class CompletionAlerter {
    static let shared = CompletionAlerter()

    private let popup = CompletionPopupController()
    private let prefs = AlertPreferences.shared

    /// Provides the menu-bar button used to anchor the in-app popup.
    var statusButtonProvider: (() -> NSStatusBarButton?)?

    private init() {
        popup.onSnooze = { [weak self] id in
            TimerStore.shared.snooze(id: id, minutes: 5)
            _ = self
        }
    }

    func timerDidComplete(_ timer: TimerItem) {
        if prefs.playSound {
            if let sound = NSSound(named: NSSound.Name("Glass")) {
                sound.play()
            } else {
                NSSound.beep()
            }
        }

        if prefs.showMenuPopup, let button = statusButtonProvider?() {
            popup.present(timer, relativeTo: button)
        }

        if prefs.systemNotifications {
            NotificationManager.shared.deliverCompletion(timer, playSound: false)
        }
    }
}

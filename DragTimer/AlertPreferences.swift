import Foundation
import Combine

/// What DragTimer does when a timer finishes. Menu popup is the reliable path
/// under Focus / Do Not Disturb; system notifications are optional extras.
@MainActor
final class AlertPreferences: ObservableObject {
    static let shared = AlertPreferences()

    @Published var showMenuPopup: Bool {
        didSet { defaults.set(showMenuPopup, forKey: Keys.showMenuPopup) }
    }
    @Published var playSound: Bool {
        didSet { defaults.set(playSound, forKey: Keys.playSound) }
    }
    @Published var systemNotifications: Bool {
        didSet { defaults.set(systemNotifications, forKey: Keys.systemNotifications) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let showMenuPopup = "dragTimer.alert.menuPopup"
        static let playSound = "dragTimer.alert.sound"
        static let systemNotifications = "dragTimer.alert.systemNotifications"
    }

    private init() {
        // Defaults: popup + sound on (DND-proof); system banners on if the user allows them.
        if defaults.object(forKey: Keys.showMenuPopup) == nil { defaults.set(true, forKey: Keys.showMenuPopup) }
        if defaults.object(forKey: Keys.playSound) == nil { defaults.set(true, forKey: Keys.playSound) }
        if defaults.object(forKey: Keys.systemNotifications) == nil { defaults.set(true, forKey: Keys.systemNotifications) }

        showMenuPopup = defaults.bool(forKey: Keys.showMenuPopup)
        playSound = defaults.bool(forKey: Keys.playSound)
        systemNotifications = defaults.bool(forKey: Keys.systemNotifications)
    }
}

import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()
    @Published private(set) var isEnabled: Bool = false

    private init() {
        // Defer SMAppService check off the main thread — it makes a blocking
        // XPC call that can hang on ad-hoc or unsigned builds.
        Task.detached(priority: .utility) { [weak self] in
            guard #available(macOS 13.0, *) else { return }
            let enabled = SMAppService.mainApp.status == .enabled
            await MainActor.run { self?.isEnabled = enabled }
        }
    }

    func refresh() {
        Task.detached(priority: .utility) { [weak self] in
            guard #available(macOS 13.0, *) else { return }
            let enabled = SMAppService.mainApp.status == .enabled
            await MainActor.run { self?.isEnabled = enabled }
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        Task.detached(priority: .utility) { [weak self] in
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try await SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Launch-at-login change failed: \(error)")
            }
            let newStatus = SMAppService.mainApp.status == .enabled
            await MainActor.run { self?.isEnabled = newStatus }
        }
    }
}

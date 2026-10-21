import Foundation
import Combine

@MainActor
final class TimerStore: ObservableObject {
    static let shared = TimerStore()

    @Published private(set) var timers: [TimerItem] = []
    @Published var syncToReminders: Bool {
        didSet { defaults.set(syncToReminders, forKey: Keys.syncToReminders) }
    }

    private let defaults = UserDefaults.standard
    private var heartbeat: Timer?

    private enum Keys {
        static let timers = "dragTimer.timers.v1"
        static let syncToReminders = "dragTimer.syncToReminders"
    }

    private init() {
        syncToReminders = defaults.bool(forKey: Keys.syncToReminders)
        load()
        startHeartbeat()
        rescheduleNotifications()
    }

    var activeTimers: [TimerItem] {
        timers.filter { $0.completedAt == nil && $0.dueAt > Date() }.sorted { $0.dueAt < $1.dueAt }
    }

    var recentTimers: [TimerItem] {
        timers.filter { $0.completedAt != nil || $0.dueAt <= Date() }.sorted { $0.dueAt > $1.dueAt }
    }

    @discardableResult
    func addTimer(seconds: TimeInterval, title: String = "") -> UUID? {
        guard seconds >= 60 else { return nil }
        var item = TimerItem(title: title, dueAt: Date().addingTimeInterval(seconds))
        timers.append(item)
        save()
        NotificationManager.shared.schedule(item)

        if syncToReminders {
            ReminderSync.shared.addReminder(for: item) { [weak self] identifier in
                guard let identifier else { return }
                Task { @MainActor in
                    guard let self, let index = self.timers.firstIndex(where: { $0.id == item.id }) else { return }
                    self.timers[index].reminderIdentifier = identifier
                    item.reminderIdentifier = identifier
                    self.save()
                }
            }
        }
        return item.id
    }

    func updateTitle(id: UUID, title: String) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        timers[index].title = title
        NotificationManager.shared.schedule(timers[index])
        save()
    }

    func cancel(id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        NotificationManager.shared.cancel(timers[index])
        timers.remove(at: index)
        save()
    }

    func snooze(id: UUID, minutes: Int = 5) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        timers[index].completedAt = nil
        timers[index].dueAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        NotificationManager.shared.schedule(timers[index])
        save()
    }

    func clearCompleted() {
        timers.removeAll { $0.completedAt != nil || $0.dueAt <= Date() }
        save()
    }

    private func startHeartbeat() {
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(heartbeat!, forMode: .common)
    }

    private func tick() {
        var changed = false
        let now = Date()
        var completed: [TimerItem] = []
        for index in timers.indices where timers[index].completedAt == nil && timers[index].dueAt <= now {
            timers[index].completedAt = now
            completed.append(timers[index])
            changed = true
        }
        if changed { save() }
        for item in completed {
            CompletionAlerter.shared.timerDidComplete(item)
        }
        objectWillChange.send()
    }

    private func load() {
        guard let data = defaults.data(forKey: Keys.timers),
              let decoded = try? JSONDecoder().decode([TimerItem].self, from: data) else { return }
        timers = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(timers) { defaults.set(data, forKey: Keys.timers) }
    }

    private func rescheduleNotifications() {
        for timer in activeTimers { NotificationManager.shared.schedule(timer) }
    }
}

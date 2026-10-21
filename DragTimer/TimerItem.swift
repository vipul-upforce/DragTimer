import Foundation

struct TimerItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    var dueAt: Date
    var completedAt: Date?
    var reminderIdentifier: String?

    init(id: UUID = UUID(), title: String = "", createdAt: Date = Date(), dueAt: Date, completedAt: Date? = nil, reminderIdentifier: String? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.dueAt = dueAt
        self.completedAt = completedAt
        self.reminderIdentifier = reminderIdentifier
    }

    var isComplete: Bool { completedAt != nil || dueAt <= Date() }
    var displayTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Timer" : title }
}

import Foundation

/// A single task the user can track time against.
struct TaskItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    /// Total time (in seconds) recorded against this task across all sessions.
    var totalSeconds: Int
    let createdAt: Date

    init(id: UUID = UUID(), name: String, totalSeconds: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.totalSeconds = totalSeconds
        self.createdAt = createdAt
    }
}

extension Int {
    /// Formats a number of seconds as `H:MM:SS` (or `M:SS` when under an hour).
    var asClock: String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

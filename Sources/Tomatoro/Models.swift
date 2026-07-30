import Foundation

/// One recorded chunk of work against a task: when it started and how long it lasted.
struct WorkRecord: Identifiable, Codable, Equatable {
    let id: UUID
    /// Wall-clock time the work session began.
    let startedAt: Date
    /// Time actually worked during the session, in seconds.
    var durationSeconds: Int
    /// Free-form note about what was done during this session.
    var description: String

    init(id: UUID = UUID(), startedAt: Date, durationSeconds: Int, description: String = "") {
        self.id = id
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.description = description
    }

    // MARK: - Codable (with migration for records saved before `description` existed)

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, durationSeconds, description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(description, forKey: .description)
    }
}

/// A single task the user can track time against.
///
/// The total time is intentionally *not* stored: it is derived from `records`
/// so there is a single source of truth and no risk of the two drifting apart.
struct TaskItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    /// Free-form notes about the task, e.g. what it involves or its scope.
    var description: String
    /// The individual work sessions logged against this task.
    var records: [WorkRecord]
    let createdAt: Date
    /// Archived tasks are hidden by default and cannot be edited or logged
    /// against until they are unarchived.
    var isArchived: Bool

    init(id: UUID = UUID(), name: String, description: String = "", records: [WorkRecord] = [], createdAt: Date = Date(), isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.description = description
        self.records = records
        self.createdAt = createdAt
        self.isArchived = isArchived
    }

    /// Total time (in seconds) across all recorded sessions, computed on demand.
    var totalSeconds: Int {
        records.reduce(0) { $0 + $1.durationSeconds }
    }

    // MARK: - Codable (with migration from the pre-records format)

    private enum CodingKeys: String, CodingKey {
        case id, name, description, records, createdAt, isArchived
        // Legacy key from the first version, used only for migration on read.
        case totalSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false

        if let decodedRecords = try container.decodeIfPresent([WorkRecord].self, forKey: .records) {
            records = decodedRecords
        } else if let legacyTotal = try container.decodeIfPresent(Int.self, forKey: .totalSeconds),
                  legacyTotal > 0 {
            // Migrate old data: fold the previous total into a single record.
            records = [WorkRecord(startedAt: createdAt, durationSeconds: legacyTotal)]
        } else {
            records = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(records, forKey: .records)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(createdAt, forKey: .createdAt)
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

    /// Formats a number of seconds as `Hh MMm`, rounding to the nearest minute.
    ///
    /// Hours are never capped at 24 and are never expressed in days, so long
    /// totals read e.g. `25h 00m` rather than `1d 1h`.
    var asHoursMinutes: String {
        let totalMinutes = (self + 30) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%dh %02dm", hours, minutes)
    }
}

import Foundation

/// Loads and persists the task list as a JSON file in Application Support.
///
/// File location: `~/Library/Application Support/Tomatoro/tasks.json`
@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []

    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Tomatoro", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("tasks.json")
        load()
    }

    // MARK: - Mutations

    /// Creates a task, optionally filed under a project from the start
    /// (e.g. the caller's current default project) — pass `projectName`
    /// as whatever `projectID` currently resolves to, since `TaskStore`
    /// doesn't hold a live reference to `ProjectStore`.
    @discardableResult
    func addTask(named name: String, projectID: UUID? = nil, projectName: String = "") -> TaskItem {
        let task = TaskItem(name: name, projectID: projectID, projectName: projectName)
        tasks.append(task)
        save()
        return task
    }

    func deleteTask(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        save()
    }

    /// Updates a task's description and persists the change.
    func updateDescription(_ description: String, for task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].description = description
        save()
    }

    /// Renames a task and persists the change.
    func rename(_ task: TaskItem, to name: String) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].name = name
        save()
    }

    /// Archives or unarchives a task and persists the change.
    func setArchived(_ isArchived: Bool, for task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isArchived = isArchived
        save()
    }

    /// Assigns (or clears, if `projectID` is nil) a task's project, and
    /// rewrites the denormalized project text on all of its existing
    /// records to match — see `WorkRecord.project`. `name` is whatever
    /// `projectID` currently resolves to in `ProjectStore` (empty for nil).
    func setProject(_ projectID: UUID?, name: String, for task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].projectID = projectID
        tasks[index].projectName = name
        for recordIndex in tasks[index].records.indices {
            tasks[index].records[recordIndex].project = name
        }
        save()
    }

    /// Cascades a project rename onto every task currently filed under it,
    /// and onto all of those tasks' existing records.
    func refreshProjectName(for projectID: UUID, newName: String) {
        for index in tasks.indices where tasks[index].projectID == projectID {
            tasks[index].projectName = newName
            for recordIndex in tasks[index].records.indices {
                tasks[index].records[recordIndex].project = newName
            }
        }
        save()
    }

    /// Unassigns a deleted project from every task that referenced it, and
    /// clears the denormalized text on all of those tasks' existing records.
    func clearProject(_ projectID: UUID) {
        for index in tasks.indices where tasks[index].projectID == projectID {
            tasks[index].projectID = nil
            tasks[index].projectName = ""
            for recordIndex in tasks[index].records.indices {
                tasks[index].records[recordIndex].project = ""
            }
        }
        save()
    }

    /// Logs a completed work session against a task and persists the change.
    /// The record is stamped with the task's *current* project (looked up
    /// fresh, not from the possibly-stale `task` snapshot passed in).
    func addRecord(startedAt: Date, durationSeconds: Int, description: String = "", to task: TaskItem) {
        guard durationSeconds > 0, let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let record = WorkRecord(startedAt: startedAt, durationSeconds: durationSeconds, description: description, project: tasks[index].projectName)
        tasks[index].records.append(record)
        save()
    }

    /// Updates a single work record's description and persists the change.
    func updateRecordDescription(_ description: String, recordID: WorkRecord.ID, in task: TaskItem) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == task.id }),
              let recordIndex = tasks[taskIndex].records.firstIndex(where: { $0.id == recordID }) else { return }
        tasks[taskIndex].records[recordIndex].description = description
        save()
    }

    /// Updates a work record's start time, duration, and description, and persists the change.
    func updateRecord(recordID: WorkRecord.ID, in task: TaskItem, startedAt: Date, durationSeconds: Int, description: String) {
        guard durationSeconds > 0,
              let taskIndex = tasks.firstIndex(where: { $0.id == task.id }),
              let recordIndex = tasks[taskIndex].records.firstIndex(where: { $0.id == recordID }) else { return }
        tasks[taskIndex].records[recordIndex].startedAt = startedAt
        tasks[taskIndex].records[recordIndex].durationSeconds = durationSeconds
        tasks[taskIndex].records[recordIndex].description = description
        save()
    }

    /// Removes a single work record entirely and persists the change.
    func deleteRecord(recordID: WorkRecord.ID, in task: TaskItem) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[taskIndex].records.removeAll { $0.id == recordID }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([TaskItem].self, from: data) {
            tasks = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(tasks) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

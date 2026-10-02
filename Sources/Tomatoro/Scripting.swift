import AppKit

/// `MainActor.assumeIsolated` requires its result to be `Sendable`, but a
/// scripting command's result is a plain `Any?` (a string, dictionary, date,
/// ...). The crossing is same-thread by construction — Apple Event delivery
/// and the `assumeIsolated` call both run on the main thread — so boxing it
/// unchecked is safe here, unlike a genuine cross-thread handoff.
private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}

/// A plain string error, so scripting commands can use `Result` to report a
/// human-readable failure back to `performDefaultImplementation()`.
private struct ScriptingError: Error {
    let message: String

    /// Validation failures all carry "invalid data", so a caller can tell a
    /// bad request from an internal failure by the message text alone.
    static func invalidData(_ detail: String) -> ScriptingError {
        ScriptingError(message: "invalid data: \(detail)")
    }
}

/// Backing object for Tomatoro's AppleScript dictionary (see `Tomatoro.sdef`
/// at the repo root, bundled into `Contents/Resources` by `build_app.sh`).
///
/// `NSApplication` forwards a scripting key it doesn't itself recognize to
/// its delegate when `application(_:delegateHandlesKey:)` returns true for
/// that key — the standard Cocoa Scripting technique for exposing custom
/// top-level properties (here, `tasks`) without subclassing `NSApplication`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set once from `TomatoroApp.init()`. Static because the scripting
    /// runtime instantiates `CreateTaskCommand`/`AddRecordCommand` itself,
    /// so there's no call site to inject a store reference through.
    static var store: TaskStore?
    static var projectStore: ProjectStore?

    func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
        key == "tasks"
    }

    @objc var tasks: [[String: Any]] {
        (AppDelegate.store?.tasks ?? [])
            .filter { !$0.isArchived }
            .map { $0.scriptingRecord(projectName: AppDelegate.projectStore?.project(withID: $0.projectID)?.name) }
    }
}

private extension TaskItem {
    /// `taskProject` is empty for a task without a project.
    func scriptingRecord(projectName: String?) -> [String: Any] {
        ["taskId": id.uuidString, "taskName": name, "taskDescription": description, "taskProject": projectName ?? ""]
    }
}

/// Validates the (task name, project name) pair every command identifies a
/// task by. A project is never created through scripting.
@MainActor
private func resolveProject(named projectName: String?) -> Result<Project, ScriptingError> {
    guard let projectName, !projectName.isEmpty else {
        return .failure(.invalidData("missing project (use \"in project\")."))
    }
    guard let project = AppDelegate.projectStore?.project(named: projectName) else {
        return .failure(.invalidData("project \"\(projectName)\" doesn't exist."))
    }
    return .success(project)
}

@objc(CreateTaskCommand)
final class CreateTaskCommand: NSScriptCommand {
    // `performDefaultImplementation()` overrides a non-isolated NSObject
    // method, so it can't itself be @MainActor. Read the (Sendable) inputs
    // here, do the actual work in a @MainActor static function via
    // `assumeIsolated` — safe because Apple Event delivery to a GUI app
    // always happens on the main thread — then apply the (Sendable) result
    // back to `self` out here.
    override func performDefaultImplementation() -> Any? {
        let name = (directParameter as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let projectName = (evaluatedArguments?["inProject"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = (evaluatedArguments?["withDescription"] as? String) ?? ""

        let outcome = MainActor.assumeIsolated {
            UncheckedSendable(value: CreateTaskCommand.createTask(name: name, projectName: projectName, description: description))
        }.value

        switch outcome {
        case .success(let record):
            return record
        case .failure(let error):
            scriptErrorNumber = NSArgumentsWrongScriptError
            scriptErrorString = error.message
            return nil
        }
    }

    /// A task is identified by (project, name). If an unarchived one exists
    /// it's returned unchanged (description included); an archived one is
    /// unarchived and returned; otherwise a new task is created in the
    /// project. The same name in another project is a different task.
    @MainActor
    private static func createTask(name: String, projectName: String?, description: String) -> Result<[String: Any], ScriptingError> {
        guard !name.isEmpty else { return .failure(.invalidData("missing task name.")) }
        guard let store = AppDelegate.store else { return .failure(ScriptingError(message: "Tomatoro isn't ready yet.")) }
        let project: Project
        switch resolveProject(named: projectName) {
        case .success(let found): project = found
        case .failure(let error): return .failure(error)
        }

        if let existing = store.task(named: name, inProject: project.id) {
            if existing.isArchived {
                store.setArchived(false, for: existing)
            }
            return .success(existing.scriptingRecord(projectName: project.name))
        }

        let task = store.addTask(named: name, projectID: project.id)
        if !description.isEmpty {
            store.updateDescription(description, for: task)
        }
        return .success(task.scriptingRecord(projectName: project.name).merging(["taskDescription": description]) { _, new in new })
    }
}

@objc(AddRecordCommand)
final class AddRecordCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let identifier = (directParameter as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let projectName = (evaluatedArguments?["inProject"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let durationMinutes = evaluatedArguments?["duration"] as? Int
        let startedAtOverride = evaluatedArguments?["startedAt"] as? Date
        let notes = (evaluatedArguments?["notes"] as? String) ?? ""

        let outcome = MainActor.assumeIsolated {
            AddRecordCommand.addRecord(identifier: identifier, projectName: projectName, durationMinutes: durationMinutes, startedAtOverride: startedAtOverride, notes: notes)
        }

        if case .failure(let error) = outcome {
            scriptErrorNumber = NSArgumentsWrongScriptError
            scriptErrorString = error.message
        }
        return nil
    }

    /// `identifier` is either the id of an existing task (the project is then
    /// ignored) or a task name, which needs `projectName` too. A name that
    /// matches no task in that project creates one; an archived match is
    /// unarchived first.
    @MainActor
    private static func addRecord(identifier: String, projectName: String?, durationMinutes: Int?, startedAtOverride: Date?, notes: String) -> Result<Void, ScriptingError> {
        guard !identifier.isEmpty else {
            return .failure(.invalidData("missing task (a task id, or a task name with \"in project\")."))
        }
        guard let store = AppDelegate.store else {
            return .failure(ScriptingError(message: "Tomatoro isn't ready yet."))
        }
        guard let durationMinutes, durationMinutes > 0 else {
            return .failure(.invalidData("\"duration\" must be a positive number of minutes."))
        }

        let task: TaskItem
        if let byID = store.tasks.first(where: { $0.id.uuidString.caseInsensitiveCompare(identifier) == .orderedSame }) {
            task = byID
        } else {
            let project: Project
            switch resolveProject(named: projectName) {
            case .success(let found): project = found
            case .failure(let error): return .failure(error)
            }
            task = store.task(named: identifier, inProject: project.id)
                ?? store.addTask(named: identifier, projectID: project.id)
        }
        if task.isArchived {
            store.setArchived(false, for: task)
        }

        let durationSeconds = durationMinutes * 60
        let startedAt = startedAtOverride ?? Date().addingTimeInterval(-Double(durationSeconds))
        store.addRecord(startedAt: startedAt, durationSeconds: durationSeconds, description: notes, to: task)
        return .success(())
    }
}

// MARK: - export worklog

private struct WorklogExport: Encodable {
    let schemaVersion: Int
    let from: String
    let to: String
    let tasks: [WorklogTask]
}

private struct WorklogTask: Encodable {
    let id: String
    let name: String
    let projectName: String?
    let estimatedHours: Double?
    let totalRecordedSeconds: Int
    let records: [WorklogRecordEntry]

    // Swift's synthesized Encodable uses `encodeIfPresent` for Optional
    // properties, which *omits* the key entirely when nil — the schema
    // requires an explicit `null` instead, so `projectName`/`estimatedHours`
    // need a hand-written `encode(to:)` using plain `encode`.
    private enum CodingKeys: String, CodingKey {
        case id, name, projectName, estimatedHours, totalRecordedSeconds, records
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(projectName, forKey: .projectName)
        try container.encode(estimatedHours, forKey: .estimatedHours)
        try container.encode(totalRecordedSeconds, forKey: .totalRecordedSeconds)
        try container.encode(records, forKey: .records)
    }
}

private struct WorklogRecordEntry: Encodable {
    let id: String
    let startedAt: String
    let durationSeconds: Int
    let description: String
}

@objc(ExportWorklogCommand)
final class ExportWorklogCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let fromText = (evaluatedArguments?["from"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let toText = (evaluatedArguments?["to"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let outcome = MainActor.assumeIsolated {
            ExportWorklogCommand.exportWorklog(fromText: fromText, toText: toText)
        }

        switch outcome {
        case .success(let json):
            return json
        case .failure(let error):
            scriptErrorNumber = NSArgumentsWrongScriptError
            scriptErrorString = error.message
            return nil
        }
    }

    /// Every task with at least one record whose `startedAt` falls (in
    /// local time) within `[fromText, toText]` inclusive — archived tasks
    /// included. `totalRecordedSeconds` is each task's all-time total, not
    /// limited to the range; `records` is just the in-range ones.
    @MainActor
    private static func exportWorklog(fromText: String, toText: String?) -> Result<String, ScriptingError> {
        guard AppDelegate.store != nil else {
            return .failure(ScriptingError(message: "Tomatoro isn't ready yet."))
        }
        guard !fromText.isEmpty else {
            return .failure(ScriptingError(message: "Specify a start date (\"from\"), in yyyy-MM-dd format."))
        }

        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = .current
        dayFormatter.calendar = calendar

        guard let fromDate = dayFormatter.date(from: fromText) else {
            return .failure(ScriptingError(message: "\"from\" must be a valid date in yyyy-MM-dd format."))
        }
        let fromDay = calendar.startOfDay(for: fromDate)

        let toDay: Date
        let toOutputText: String
        if let toText, !toText.isEmpty {
            guard let toDate = dayFormatter.date(from: toText) else {
                return .failure(ScriptingError(message: "\"to\" must be a valid date in yyyy-MM-dd format."))
            }
            toDay = calendar.startOfDay(for: toDate)
            toOutputText = toText
        } else {
            toDay = fromDay
            toOutputText = fromText
        }

        guard toDay >= fromDay else {
            return .failure(ScriptingError(message: "\"to\" can't be before \"from\"."))
        }

        let store = AppDelegate.store!
        let projectStore = AppDelegate.projectStore

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = .current
        isoFormatter.formatOptions = [.withInternetDateTime]

        var entries: [(sortKey: Date, task: WorklogTask)] = []
        for task in store.tasks {
            let recordsInRange = task.records
                .filter { record in
                    let day = calendar.startOfDay(for: record.startedAt)
                    return day >= fromDay && day <= toDay
                }
                .sorted { $0.startedAt < $1.startedAt }
            guard let firstStart = recordsInRange.first?.startedAt else { continue }

            let entry = WorklogTask(
                id: task.id.uuidString,
                name: task.name,
                projectName: projectStore?.project(withID: task.projectID)?.name,
                estimatedHours: task.estimatedHours,
                totalRecordedSeconds: task.totalSeconds,
                records: recordsInRange.map { record in
                    WorklogRecordEntry(
                        id: record.id.uuidString,
                        startedAt: isoFormatter.string(from: record.startedAt),
                        durationSeconds: record.durationSeconds,
                        description: record.description
                    )
                }
            )
            entries.append((sortKey: firstStart, task: entry))
        }
        entries.sort { $0.sortKey < $1.sortKey }

        let export = WorklogExport(schemaVersion: 1, from: fromText, to: toOutputText, tasks: entries.map(\.task))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(export), let json = String(data: data, encoding: .utf8) else {
            return .failure(ScriptingError(message: "Failed to encode the worklog as JSON."))
        }
        return .success(json)
    }
}

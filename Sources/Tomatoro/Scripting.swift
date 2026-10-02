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
            .map(\.scriptingRecord)
    }
}

private extension TaskItem {
    var scriptingRecord: [String: Any] {
        ["taskId": id.uuidString, "taskName": name, "taskDescription": description]
    }
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
        let description = (evaluatedArguments?["withDescription"] as? String) ?? ""

        let outcome = MainActor.assumeIsolated {
            UncheckedSendable(value: CreateTaskCommand.createTask(name: name, description: description))
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

    /// If an unarchived task of this name already exists, that task is
    /// returned unchanged (no duplicate is created). If it exists but is
    /// archived, it's unarchived and returned as-is. Otherwise a new task
    /// is created with the given description.
    @MainActor
    private static func createTask(name: String, description: String) -> Result<[String: Any], ScriptingError> {
        guard !name.isEmpty else { return .failure(ScriptingError(message: "A task needs a name.")) }
        guard let store = AppDelegate.store else { return .failure(ScriptingError(message: "Tomatoro isn't ready yet.")) }

        if let existing = store.tasks.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            if existing.isArchived {
                store.setArchived(false, for: existing)
            }
            return .success(["taskId": existing.id.uuidString, "taskName": existing.name, "taskDescription": existing.description])
        }

        let task = store.addTask(named: name, projectID: AppDelegate.projectStore?.defaultProject?.id)
        if !description.isEmpty {
            store.updateDescription(description, for: task)
        }
        return .success(["taskId": task.id.uuidString, "taskName": task.name, "taskDescription": description])
    }
}

@objc(AddRecordCommand)
final class AddRecordCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let identifier = (directParameter as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let durationMinutes = evaluatedArguments?["duration"] as? Int
        let startedAtOverride = evaluatedArguments?["startedAt"] as? Date
        let notes = (evaluatedArguments?["notes"] as? String) ?? ""

        let outcome = MainActor.assumeIsolated {
            AddRecordCommand.addRecord(identifier: identifier, durationMinutes: durationMinutes, startedAtOverride: startedAtOverride, notes: notes)
        }

        if case .failure(let error) = outcome {
            scriptErrorNumber = NSArgumentsWrongScriptError
            scriptErrorString = error.message
        }
        return nil
    }

    /// Resolves the task by name or id if it already exists (unarchiving it
    /// first if needed), or — if `identifier` doesn't match any existing
    /// task — creates a new task named `identifier` to log against.
    @MainActor
    private static func addRecord(identifier: String, durationMinutes: Int?, startedAtOverride: Date?, notes: String) -> Result<Void, ScriptingError> {
        guard !identifier.isEmpty else {
            return .failure(ScriptingError(message: "Specify which task to log time against, by name or id."))
        }
        guard let store = AppDelegate.store else {
            return .failure(ScriptingError(message: "Tomatoro isn't ready yet."))
        }
        guard let durationMinutes, durationMinutes > 0 else {
            return .failure(ScriptingError(message: "\"duration\" must be a positive number of minutes."))
        }

        let task: TaskItem
        if let existing = store.tasks.first(where: {
            $0.name.caseInsensitiveCompare(identifier) == .orderedSame || $0.id.uuidString.caseInsensitiveCompare(identifier) == .orderedSame
        }) {
            if existing.isArchived {
                store.setArchived(false, for: existing)
            }
            task = existing
        } else {
            task = store.addTask(named: identifier, projectID: AppDelegate.projectStore?.defaultProject?.id)
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

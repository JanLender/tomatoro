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

        let task = store.addTask(named: name)
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
            task = store.addTask(named: identifier)
        }

        let durationSeconds = durationMinutes * 60
        let startedAt = startedAtOverride ?? Date().addingTimeInterval(-Double(durationSeconds))
        store.addRecord(startedAt: startedAt, durationSeconds: durationSeconds, description: notes, to: task)
        return .success(())
    }
}

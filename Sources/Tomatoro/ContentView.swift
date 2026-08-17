import SwiftUI

/// A single, non-combinable field to sort the task list by.
enum TaskSortField: String, CaseIterable, Identifiable {
    case created = "Date Created"
    case lastRecordTime = "Last Record"
    case name = "Name"
    case totalTime = "Total Time"

    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow

    @State private var selectedTaskID: TaskItem.ID?
    @State private var newTaskName: String = ""
    @State private var minutes: Int = 25
    @State private var sessionMode: SessionMode = .countdown
    @State private var showingManualEntry = false
    @State private var showingEditDescription = false
    @State private var showArchived = false
    @State private var pendingDescription: String = ""
    @State private var renamingTask: TaskItem?
    @State private var sortField: TaskSortField = .created
    @State private var sortAscending = true

    private var selectedTask: TaskItem? {
        store.tasks.first { $0.id == selectedTaskID }
    }

    private var activeTasks: [TaskItem] {
        sortedTasks(store.tasks.filter { !$0.isArchived })
    }

    private var archivedTasks: [TaskItem] {
        sortedTasks(store.tasks.filter { $0.isArchived })
    }

    private func sortedTasks(_ tasks: [TaskItem]) -> [TaskItem] {
        let ascending = tasks.sorted { a, b in
            switch sortField {
            case .created:
                return a.createdAt < b.createdAt
            case .lastRecordTime:
                let aLast = a.records.map(\.startedAt).max() ?? .distantPast
                let bLast = b.records.map(\.startedAt).max() ?? .distantPast
                return aLast < bLast
            case .name:
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .totalTime:
                return a.totalSeconds < b.totalSeconds
            }
        }
        return sortAscending ? ascending : ascending.reversed()
    }

    var body: some View {
        NavigationSplitView {
            taskListPane
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            sessionPane
                .frame(minWidth: 320)
        }
        .navigationTitle("Tomatoro")
        .toolbar {
            ToolbarItem {
                Button {
                    openWindow(id: "dailySummary")
                } label: {
                    Label("Daily Summary", systemImage: "calendar")
                }
            }
        }
        .onAppear {
            minutes = settings.defaultCountdownMinutes
        }
        .onChange(of: settings.defaultCountdownMinutes) { _, newValue in
            minutes = newValue
        }
    }

    // MARK: - Task list

    private var taskListPane: some View {
        VStack(spacing: 0) {
            Toggle("Show archived", isOn: $showArchived)
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            HStack(spacing: 6) {
                Picker("Sort by", selection: $sortField) {
                    ForEach(TaskSortField.allCases) { field in
                        Text(field.rawValue).tag(field)
                    }
                }
                .labelsHidden()
                .controlSize(.small)

                Button {
                    sortAscending.toggle()
                } label: {
                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(sortAscending ? "Ascending" : "Descending")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List(selection: $selectedTaskID) {
                Section("Tasks") {
                    ForEach(activeTasks) { task in
                        TaskRow(task: task, isActive: session.activeTask?.id == task.id)
                            .tag(task.id)
                            .contextMenu {
                                Button("View Records") {
                                    openWindow(id: "taskRecords", value: task.id)
                                }
                                Divider()
                                Button("Rename") {
                                    renamingTask = task
                                }
                                Button("Archive") {
                                    store.setArchived(true, for: task)
                                }
                                .disabled(session.activeTask?.id == task.id)
                                Button("Delete", role: .destructive) {
                                    store.deleteTask(task)
                                }
                            }
                    }
                }

                if showArchived && !archivedTasks.isEmpty {
                    Section("Archived") {
                        ForEach(archivedTasks) { task in
                            TaskRow(task: task, isActive: false)
                                .tag(task.id)
                                .foregroundStyle(.secondary)
                                .contextMenu {
                                    Button("View Records") {
                                        openWindow(id: "taskRecords", value: task.id)
                                    }
                                    Divider()
                                    Button("Rename") {
                                        renamingTask = task
                                    }
                                    Button("Unarchive") {
                                        store.setArchived(false, for: task)
                                    }
                                    Button("Delete", role: .destructive) {
                                        store.deleteTask(task)
                                    }
                                }
                        }
                    }
                }
            }

            Divider()

            HStack {
                TextField("New task…", text: $newTaskName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)
                Button(action: addTask) {
                    Image(systemName: "plus")
                }
                .disabled(newTaskName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(8)
        }
        .sheet(item: $renamingTask) { task in
            RenameTaskSheet(name: task.name) { newName in
                store.rename(task, to: newName)
            }
        }
    }

    private func addTask() {
        let name = newTaskName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let task = store.addTask(named: name)
        newTaskName = ""
        selectedTaskID = task.id
    }

    // MARK: - Session pane

    @ViewBuilder
    private var sessionPane: some View {
        if session.isActive {
            activeSessionView
        } else {
            setupView
        }
    }

    private var setupView: some View {
        VStack(spacing: 20) {
            if let task = selectedTask {
                Text(task.name)
                    .font(.title2).bold()

                if task.isArchived {
                    Label("Archived", systemImage: "archivebox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if task.description.isEmpty {
                    if !task.isArchived {
                        Button {
                            showingEditDescription = true
                        } label: {
                            Label("Add description", systemImage: "pencil")
                        }
                        .buttonStyle(.link)
                    }
                } else {
                    VStack(spacing: 4) {
                        Text(task.description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if !task.isArchived {
                            Button {
                                showingEditDescription = true
                            } label: {
                                Label("Edit description", systemImage: "pencil")
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                    .frame(maxWidth: 320)
                }

                Text("Recorded so far: \(task.totalSeconds.asHoursMinutes)")
                    .foregroundStyle(.secondary)

                if task.isArchived {
                    Text("Unarchive this task to start a session or log work against it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)

                    Button {
                        store.setArchived(false, for: task)
                    } label: {
                        Label("Unarchive", systemImage: "tray.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Picker("Mode", selection: $sessionMode) {
                        Text("Countdown").tag(SessionMode.countdown)
                        Text("Stopwatch").tag(SessionMode.stopwatch)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)

                    if sessionMode == .countdown {
                        Stepper(value: $minutes, in: 1...180, step: 5) {
                            Text("Duration: \(minutes) min")
                        }
                        .frame(maxWidth: 220)
                    } else {
                        Text("Counts up until you stop it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField("What are you working on? (optional)", text: $pendingDescription)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)

                    Button {
                        session.start(task: task, mode: sessionMode, minutes: minutes, description: pendingDescription)
                        pendingDescription = ""
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .frame(maxWidth: 160)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    HStack(spacing: 16) {
                        Button {
                            openWindow(id: "taskRecords", value: task.id)
                        } label: {
                            Label("View records", systemImage: "list.bullet")
                        }
                        .buttonStyle(.link)

                        Button {
                            showingManualEntry = true
                        } label: {
                            Label("Add record manually", systemImage: "plus.circle")
                        }
                        .buttonStyle(.link)
                    }

                    Button {
                        store.setArchived(true, for: task)
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }

                if task.isArchived {
                    Button {
                        openWindow(id: "taskRecords", value: task.id)
                    } label: {
                        Label("View records", systemImage: "list.bullet")
                    }
                    .buttonStyle(.link)
                }
            } else {
                ContentUnavailableView(
                    "Pick a task",
                    systemImage: "checklist",
                    description: Text("Select a task on the left, or create a new one, then start a timer.")
                )
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingManualEntry) {
            if let task = selectedTask {
                ManualRecordSheet(taskName: task.name, defaultMinutes: settings.defaultManualRecordMinutes) { startedAt, durationSeconds, description in
                    store.addRecord(startedAt: startedAt, durationSeconds: durationSeconds, description: description, to: task)
                }
            }
        }
        .sheet(isPresented: $showingEditDescription) {
            if let task = selectedTask {
                EditDescriptionSheet(taskName: task.name, description: task.description) { newDescription in
                    store.updateDescription(newDescription, for: task)
                }
            }
        }
    }

    private var activeSessionView: some View {
        VStack(spacing: 24) {
            Text(session.activeTask?.name ?? "")
                .font(.title2).bold()
                .multilineTextAlignment(.center)

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 12)
                if session.mode == .countdown {
                    Circle()
                        .trim(from: 0, to: session.progress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: session.progress)
                }
                VStack(spacing: 4) {
                    Text(session.mode == .countdown
                         ? session.remainingSeconds.asClock
                         : session.elapsedSeconds.asClock)
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(session.mode == .countdown ? "remaining" : "elapsed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 200, height: 200)

            TextField("What are you working on? (optional)", text: $session.description)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)

            HStack(spacing: 16) {
                Button {
                    session.togglePause()
                } label: {
                    Label(session.isPaused ? "Resume" : "Pause",
                          systemImage: session.isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 110)
                }
                .controlSize(.large)

                Button(role: .destructive) {
                    session.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(width: 110)
                }
                .controlSize(.large)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let isActive: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.name)
                Text(task.totalSeconds.asHoursMinutes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "timer")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A small sheet for renaming a task.
private struct RenameTaskSheet: View {
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(name: String, onSave: @escaping (String) -> Void) {
        self.onSave = onSave
        self._name = State(initialValue: name)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename task")
                .font(.headline)

            TextField("Task name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName)
        dismiss()
    }
}

/// A small sheet for editing a task's free-form description.
private struct EditDescriptionSheet: View {
    let taskName: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var description: String

    init(taskName: String, description: String, onSave: @escaping (String) -> Void) {
        self.taskName = taskName
        self.onSave = onSave
        self._description = State(initialValue: description)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit description")
                .font(.headline)
            Text(taskName)
                .foregroundStyle(.secondary)

            TextEditor(text: $description)
                .font(.body)
                .frame(height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    onSave(description.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

/// A small sheet for logging a work record by hand: when it started and how long it lasted.
struct ManualRecordSheet: View {
    let taskName: String
    let onSave: (Date, Int, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var startedAt = Date()
    @State private var hours: Int
    @State private var minutes: Int
    @State private var hoursValid = true
    @State private var minutesValid = true
    @State private var description = ""

    init(taskName: String, defaultMinutes: Int, onSave: @escaping (Date, Int, String) -> Void) {
        self.taskName = taskName
        self.onSave = onSave
        self._hours = State(initialValue: defaultMinutes / 60)
        self._minutes = State(initialValue: defaultMinutes % 60)
    }

    private var durationSeconds: Int { hours * 3600 + minutes * 60 }
    private var inputsValid: Bool { hoursValid && minutesValid }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add record")
                .font(.headline)
            Text(taskName)
                .foregroundStyle(.secondary)

            DatePicker("Started", selection: $startedAt)

            HStack(spacing: 16) {
                NumberStepperField(label: "Hours", value: $hours, range: 0...99, isValid: $hoursValid)
                NumberStepperField(label: "Minutes", value: $minutes, range: 0...59, isValid: $minutesValid)
            }

            if inputsValid {
                Text("Duration: \(durationSeconds.asHoursMinutes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Enter whole numbers (hours 0–99, minutes 0–59).")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            TextField("Description (optional)", text: $description)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") {
                    onSave(startedAt, durationSeconds, description.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!inputsValid || durationSeconds == 0)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

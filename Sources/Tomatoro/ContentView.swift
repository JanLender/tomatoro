import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var session: SessionController

    @State private var selectedTaskID: TaskItem.ID?
    @State private var newTaskName: String = ""
    @State private var minutes: Int = 25
    @State private var sessionMode: SessionMode = .countdown
    @State private var showingManualEntry = false
    @State private var showingDailySummary = false
    @State private var showingTaskRecords = false
    @State private var showingEditDescription = false

    private var selectedTask: TaskItem? {
        store.tasks.first { $0.id == selectedTaskID }
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
                    showingDailySummary = true
                } label: {
                    Label("Daily Summary", systemImage: "calendar")
                }
            }
        }
        .sheet(isPresented: $showingDailySummary) {
            DailySummaryView()
        }
        .alert("Time's up!", isPresented: $session.showCompletionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your focus session has finished. Nice work!")
        }
    }

    // MARK: - Task list

    private var taskListPane: some View {
        VStack(spacing: 0) {
            List(selection: $selectedTaskID) {
                Section("Tasks") {
                    ForEach(store.tasks) { task in
                        TaskRow(task: task, isActive: session.activeTask?.id == task.id)
                            .tag(task.id)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    store.deleteTask(task)
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

                if task.description.isEmpty {
                    Button {
                        showingEditDescription = true
                    } label: {
                        Label("Add description", systemImage: "pencil")
                    }
                    .buttonStyle(.link)
                } else {
                    VStack(spacing: 4) {
                        Text(task.description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            showingEditDescription = true
                        } label: {
                            Label("Edit description", systemImage: "pencil")
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    .frame(maxWidth: 320)
                }

                Text("Recorded so far: \(task.totalSeconds.asHoursMinutes)")
                    .foregroundStyle(.secondary)

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

                Button {
                    session.start(task: task, mode: sessionMode, minutes: minutes)
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                HStack(spacing: 16) {
                    Button {
                        showingTaskRecords = true
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
                ManualRecordSheet(taskName: task.name) { startedAt, durationSeconds in
                    store.addRecord(startedAt: startedAt, durationSeconds: durationSeconds, to: task)
                }
            }
        }
        .sheet(isPresented: $showingTaskRecords) {
            if let task = selectedTask {
                TaskRecordsView(taskID: task.id)
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
private struct ManualRecordSheet: View {
    let taskName: String
    let onSave: (Date, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var startedAt = Date()
    @State private var hours = 0
    @State private var minutes = 25
    @State private var hoursValid = true
    @State private var minutesValid = true

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

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") {
                    onSave(startedAt, durationSeconds)
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

/// An integer input that can be typed directly or nudged with a stepper.
///
/// Non-numeric or out-of-range text is *not* silently discarded: the field
/// turns red and reports `isValid = false` so callers can block saving.
/// Reused wherever a duration component is edited.
private struct NumberStepperField: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    @Binding var isValid: Bool

    @State private var text: String

    init(label: String, value: Binding<Int>, range: ClosedRange<Int>, isValid: Binding<Bool>) {
        self.label = label
        self._value = value
        self.range = range
        self._isValid = isValid
        self._text = State(initialValue: String(value.wrappedValue))
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("\(label):")
            TextField(label, text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .labelsHidden()
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isValid ? Color.clear : Color.red, lineWidth: 1)
                )
                .onChange(of: text) { _, newText in
                    validate(newText)
                }
            Stepper(label, value: $value, in: range)
                .labelsHidden()
                .onChange(of: value) { _, newValue in
                    let synced = String(newValue)
                    if synced != text { text = synced }
                }
        }
    }

    private func validate(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if let parsed = Int(trimmed), range.contains(parsed) {
            value = parsed
            isValid = true
        } else {
            isValid = false
        }
    }
}

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var session: SessionController

    @State private var selectedTaskID: TaskItem.ID?
    @State private var newTaskName: String = ""
    @State private var minutes: Int = 25

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
                Text("Recorded so far: \(task.totalSeconds.asHoursMinutes)")
                    .foregroundStyle(.secondary)

                Stepper(value: $minutes, in: 1...180, step: 5) {
                    Text("Duration: \(minutes) min")
                }
                .frame(maxWidth: 220)

                Button {
                    session.start(task: task, minutes: minutes)
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
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
    }

    private var activeSessionView: some View {
        VStack(spacing: 24) {
            Text(session.activeTask?.name ?? "")
                .font(.title2).bold()
                .multilineTextAlignment(.center)

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: session.progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: session.progress)
                Text(session.remainingSeconds.asClock)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
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

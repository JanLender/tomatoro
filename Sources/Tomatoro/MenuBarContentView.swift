import SwiftUI
import AppKit

/// The menu bar (status item) icon, showing at a glance whether a session
/// is idle, counting, or paused, plus the live remaining/elapsed time.
struct MenuBarLabel: View {
    @EnvironmentObject private var session: SessionController

    private var iconName: String {
        guard session.isActive else { return "timer" }
        return session.isPaused ? "pause.circle" : "timer"
    }

    private var timeText: String? {
        guard session.isActive else { return nil }
        return session.mode == .countdown ? session.remainingSeconds.asClock : session.elapsedSeconds.asClock
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
            if let timeText {
                Text(timeText)
                    .monospacedDigit()
            }
        }
    }
}

/// The fast-access dropdown shown when the menu bar icon is clicked: the
/// active session's controls (if any), and quick-start controls for every
/// non-archived task.
struct MenuBarContentView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var session: SessionController
    @Environment(\.openWindow) private var openWindow

    @State private var manualEntryTask: TaskItem?

    private var activeTasks: [TaskItem] {
        store.tasks.filter { !$0.isArchived }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let activeTask = session.activeTask {
                activeSessionSection(activeTask)
                Divider()
            }

            if activeTasks.isEmpty {
                Text("No tasks yet")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(activeTasks) { task in
                            taskRow(task)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 280)
            }

            Divider()

            HStack {
                Button("Open Tomatoro") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
        }
        .frame(width: 280)
        .sheet(item: $manualEntryTask) { task in
            ManualRecordSheet(taskName: task.name) { startedAt, durationSeconds, description in
                store.addRecord(startedAt: startedAt, durationSeconds: durationSeconds, description: description, to: task)
            }
        }
    }

    private func activeSessionSection(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.name)
                .font(.headline)
                .lineLimit(1)

            HStack {
                Text(session.mode == .countdown
                     ? session.remainingSeconds.asClock
                     : session.elapsedSeconds.asClock)
                    .font(.system(.title2, design: .rounded))
                    .monospacedDigit()
                Text(session.mode == .countdown ? "remaining" : "elapsed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    session.togglePause()
                } label: {
                    Label(session.isPaused ? "Resume" : "Pause",
                          systemImage: session.isPaused ? "play.fill" : "pause.fill")
                }

                Button(role: .destructive) {
                    session.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
            }
        }
        .padding(12)
    }

    private func taskRow(_ task: TaskItem) -> some View {
        HStack {
            Text(task.name)
                .lineLimit(1)

            Spacer()

            Button {
                session.start(task: task, mode: .countdown, minutes: SessionController.defaultCountdownMinutes)
            } label: {
                Image(systemName: "timer")
            }
            .help("Start a \(SessionController.defaultCountdownMinutes)-minute countdown")
            .disabled(session.isActive)

            Button {
                session.start(task: task, mode: .stopwatch, minutes: 0)
            } label: {
                Image(systemName: "stopwatch")
            }
            .help("Start stopwatch")
            .disabled(session.isActive)

            Button {
                manualEntryTask = task
            } label: {
                Image(systemName: "plus.circle")
            }
            .help("Add manual record")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 2)
    }
}

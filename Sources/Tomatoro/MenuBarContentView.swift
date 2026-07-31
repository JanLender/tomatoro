import SwiftUI
import AppKit

/// The menu bar (status item) icon: the "timer" glyph, colored green while
/// anything is being tracked, red when idle past the configured threshold
/// (if the idle-reminder icon setting is on), and white otherwise, plus the
/// live remaining/elapsed time while a session is running.
///
/// The glyph is a real bitmap `NSImage`, not a SwiftUI `Shape` or a plain
/// `.foregroundStyle`-tinted `Image(systemName:)` — both were tried and
/// neither showed up in the actual menu bar: `MenuBarExtra`'s label has
/// documented limitations rendering arbitrary custom `View` content, and
/// macOS automatically renders SF Symbol status-item icons as monochrome
/// "template" images, discarding any applied color (per Apple's own
/// `NSImage.isTemplate` documentation: a template image is filled with the
/// system's own color, and any original color is removed).
///
/// Instead, the symbol is rendered into a real bitmap via
/// `withSymbolConfiguration`, then recolored with the standard AppKit
/// template-tinting recipe — fill its bounds with the target color using
/// the `.sourceIn` blend mode, which replaces color only where the
/// symbol's own pixels are already opaque, preserving its shape — and
/// finally marked `isTemplate = false` so the color survives instead of
/// being stripped back out by the status item.
struct MenuBarLabel: View {
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var idleReminder: IdleReminderController

    private var indicatorColor: NSColor {
        if session.isActive {
            return .systemGreen
        }
        if idleReminder.isIdle && settings.idleReminderHighlightIcon {
            return .systemRed
        }
        return .white
    }

    private var timeText: String? {
        guard session.isActive else { return nil }
        return session.mode == .countdown ? session.remainingSeconds.asClock : session.elapsedSeconds.asClock
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: Self.timerIcon(color: indicatorColor))
            if let timeText {
                Text(timeText)
                    .monospacedDigit()
            }
        }
    }

    private static func timerIcon(color: NSColor, pointSize: CGFloat = 14) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "timer", accessibilityDescription: "Tomatoro")?
            .withSymbolConfiguration(config),
            let tinted = symbol.copy() as? NSImage
        else {
            return dotFallback(color: color)
        }

        tinted.lockFocus()
        color.set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceIn)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }

    /// Used only if the SF Symbol lookup above ever fails.
    private static func dotFallback(color: NSColor, diameter: CGFloat = 12) -> NSImage {
        let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// The fast-access dropdown shown when the menu bar icon is clicked: the
/// active session's controls (if any), and quick-start controls for every
/// non-archived task.
struct MenuBarContentView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var settings: SettingsStore
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
            ManualRecordSheet(taskName: task.name, defaultMinutes: settings.defaultManualRecordMinutes) { startedAt, durationSeconds, description in
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
                session.start(task: task, mode: .countdown, minutes: settings.defaultCountdownMinutes)
            } label: {
                Image(systemName: "timer")
            }
            .help("Start a \(settings.defaultCountdownMinutes)-minute countdown")
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

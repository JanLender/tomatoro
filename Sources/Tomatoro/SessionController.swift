import Foundation
import AppKit

/// How the active session measures time.
enum SessionMode: Equatable {
    /// Counts down from a preset duration and alerts when it reaches zero.
    case countdown
    /// Counts up indefinitely until the user stops it (e.g. an ad-hoc meeting).
    case stopwatch
}

/// Drives a single focus session for a task, recording the time actually
/// worked (even if the user stops early). Supports both a countdown and a
/// count-up stopwatch.
@MainActor
final class SessionController: ObservableObject {
    /// Seconds left on the countdown (unused in stopwatch mode).
    @Published private(set) var remainingSeconds: Int = 0
    /// Seconds worked so far this session; the stopwatch display counts this up.
    @Published private(set) var elapsedSeconds: Int = 0
    /// The task currently being worked on, if a session is active.
    @Published private(set) var activeTask: TaskItem?
    @Published private(set) var mode: SessionMode = .countdown
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isPaused: Bool = false
    /// Set to true when the countdown reaches zero; the UI observes this to alert.
    @Published var showCompletionAlert: Bool = false
    /// Work log note for the session in progress. Editable before starting
    /// and while running; saved onto the record when the session ends.
    @Published var description: String = ""

    private var plannedSeconds: Int = 0
    /// Wall-clock time the current session started, used when logging the record.
    private var sessionStartedAt: Date?
    private var timer: Timer?

    private let store: TaskStore

    init(store: TaskStore) {
        self.store = store
    }

    var isActive: Bool { activeTask != nil }

    /// Countdown progress from 0 (just started) to 1 (finished).
    /// Always 0 in stopwatch mode (there is no fixed end).
    var progress: Double {
        guard mode == .countdown, plannedSeconds > 0 else { return 0 }
        return Double(plannedSeconds - remainingSeconds) / Double(plannedSeconds)
    }

    // MARK: - Controls

    func start(task: TaskItem, mode: SessionMode, minutes: Int, description: String = "") {
        stopTimer()
        activeTask = task
        self.mode = mode
        self.description = description
        if mode == .countdown {
            plannedSeconds = max(1, minutes * 60)
            remainingSeconds = plannedSeconds
        } else {
            plannedSeconds = 0
            remainingSeconds = 0
        }
        elapsedSeconds = 0
        sessionStartedAt = Date()
        isPaused = false
        isRunning = true
        scheduleTimer()
    }

    func togglePause() {
        guard isActive else { return }
        if isPaused {
            isPaused = false
            isRunning = true
            scheduleTimer()
        } else {
            isPaused = true
            isRunning = false
            stopTimer()
        }
    }

    /// Stops the session early and records the time worked so far.
    func stop() {
        recordElapsed()
        reset()
    }

    // MARK: - Timer

    private func scheduleTimer() {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isRunning else { return }
        elapsedSeconds += 1
        guard mode == .countdown else { return }
        remainingSeconds -= 1
        if remainingSeconds <= 0 {
            finish()
        }
    }

    private func finish() {
        stopTimer()
        recordElapsed()
        isRunning = false
        isPaused = false
        remainingSeconds = 0
        notifyUser()
        showCompletionAlert = true
    }

    private func recordElapsed() {
        if let task = activeTask, let startedAt = sessionStartedAt, elapsedSeconds > 0 {
            store.addRecord(startedAt: startedAt, durationSeconds: elapsedSeconds, description: description, to: task)
        }
        elapsedSeconds = 0
    }

    private func reset() {
        stopTimer()
        activeTask = nil
        isRunning = false
        isPaused = false
        remainingSeconds = 0
        plannedSeconds = 0
        elapsedSeconds = 0
        sessionStartedAt = nil
        description = ""
    }

    private func notifyUser() {
        NSSound.beep()
        NSApp.activate(ignoringOtherApps: true)
    }
}

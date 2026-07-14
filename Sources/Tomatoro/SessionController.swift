import Foundation
import AppKit

/// Drives a single focus session: a countdown for one task, recording the
/// time actually worked (even if the user stops early).
@MainActor
final class SessionController: ObservableObject {
    /// Seconds left on the countdown.
    @Published private(set) var remainingSeconds: Int = 0
    /// The task currently being worked on, if a session is active.
    @Published private(set) var activeTask: TaskItem?
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isPaused: Bool = false
    /// Set to true when the countdown reaches zero; the UI observes this to alert.
    @Published var showCompletionAlert: Bool = false

    private var plannedSeconds: Int = 0
    /// Seconds actually spent working this session (ticks while running).
    private var elapsedSeconds: Int = 0
    /// Wall-clock time the current session started, used when logging the record.
    private var sessionStartedAt: Date?
    private var timer: Timer?

    private let store: TaskStore

    init(store: TaskStore) {
        self.store = store
    }

    var isActive: Bool { activeTask != nil }

    /// Progress from 0 (just started) to 1 (finished).
    var progress: Double {
        guard plannedSeconds > 0 else { return 0 }
        return Double(plannedSeconds - remainingSeconds) / Double(plannedSeconds)
    }

    // MARK: - Controls

    func start(task: TaskItem, minutes: Int) {
        stopTimer()
        activeTask = task
        plannedSeconds = max(1, minutes * 60)
        remainingSeconds = plannedSeconds
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
            store.addRecord(startedAt: startedAt, durationSeconds: elapsedSeconds, to: task)
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
    }

    private func notifyUser() {
        NSSound.beep()
        NSApp.activate(ignoringOtherApps: true)
    }
}

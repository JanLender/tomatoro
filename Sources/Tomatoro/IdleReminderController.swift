import Foundation
import Combine

/// Watches session activity and, once nothing has been tracked for the
/// configured idle threshold, reminds the user — via a repeating system
/// notification and/or a red menu bar icon, both configurable in Settings.
@MainActor
final class IdleReminderController: ObservableObject {
    /// True once the configured idle threshold has elapsed with no active session.
    /// Drives the menu bar icon's red tint; stays false whenever the feature is disabled.
    @Published private(set) var isIdle = false

    private var idleTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let settings: SettingsStore

    init(session: SessionController, settings: SettingsStore) {
        self.settings = settings

        session.$activeTask
            .sink { [weak self] task in
                self?.reschedule(isSessionActive: task != nil)
            }
            .store(in: &cancellables)

        settings.$idleReminderEnabled
            .sink { [weak self] _ in
                self?.reschedule(isSessionActive: session.isActive)
            }
            .store(in: &cancellables)
    }

    private func reschedule(isSessionActive: Bool) {
        isIdle = false
        idleTimer?.invalidate()
        idleTimer = nil

        guard !isSessionActive, settings.idleReminderEnabled else { return }

        let interval = TimeInterval(max(1, settings.idleReminderMinutes) * 60)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fire() }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func fire() {
        isIdle = true
        if settings.idleReminderNotify {
            NotificationManager.shared.notifyIdle()
        }
    }
}

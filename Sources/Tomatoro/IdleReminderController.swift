import Foundation
import Combine

/// Watches session activity and, once nothing has been tracked for the
/// configured idle threshold, sends a repeating system notification
/// (configurable in Settings). Note: the menu bar icon's red state is
/// handled separately in `MenuBarLabel` and is intentionally *not* gated by
/// this threshold — it reflects "nothing being tracked right now" immediately.
///
/// The countdown toward the threshold restarts from zero whenever a session
/// starts or stops, whenever "Send a notification" is turned on, whenever
/// the idle-reminder master switch is turned on, or whenever the threshold
/// itself is changed while otherwise active — enabling notifications (or
/// changing the threshold) does not produce an immediate notification, it
/// starts a fresh countdown.
@MainActor
final class IdleReminderController: ObservableObject {
    /// True once the configured idle threshold has elapsed with no active session.
    @Published private(set) var isIdle = false

    private var idleTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let settings: SettingsStore

    init(session: SessionController, settings: SettingsStore) {
        self.settings = settings

        // Each subscription below passes the value Combine hands it
        // directly for the property that triggered it, and reads the
        // others straight from `settings`. That's the important bit for
        // correctness: `@Published`'s projected-value publisher sends its
        // notification *before* updating the property's own backing
        // storage, so re-reading that SAME property synchronously inside
        // the handler would always observe the previous value (confirmed
        // by instrumented testing — this bit a previous version of this
        // exact code). Reading a *different* property that isn't
        // simultaneously being mutated is safe.
        session.$activeTask
            .sink { [weak self] task in
                self?.reschedule(
                    isSessionActive: task != nil,
                    isEnabled: settings.idleReminderEnabled,
                    isNotify: settings.idleReminderNotify,
                    minutes: settings.idleReminderMinutes
                )
            }
            .store(in: &cancellables)

        settings.$idleReminderEnabled
            .sink { [weak self] isEnabled in
                self?.reschedule(
                    isSessionActive: session.isActive,
                    isEnabled: isEnabled,
                    isNotify: settings.idleReminderNotify,
                    minutes: settings.idleReminderMinutes
                )
            }
            .store(in: &cancellables)

        settings.$idleReminderNotify
            .sink { [weak self] isNotify in
                self?.reschedule(
                    isSessionActive: session.isActive,
                    isEnabled: settings.idleReminderEnabled,
                    isNotify: isNotify,
                    minutes: settings.idleReminderMinutes
                )
            }
            .store(in: &cancellables)

        settings.$idleReminderMinutes
            .sink { [weak self] minutes in
                self?.reschedule(
                    isSessionActive: session.isActive,
                    isEnabled: settings.idleReminderEnabled,
                    isNotify: settings.idleReminderNotify,
                    minutes: minutes
                )
            }
            .store(in: &cancellables)
    }

    /// Cancels any in-flight countdown and, if everything required is true
    /// (nothing being tracked, the master switch on, and notifications on),
    /// starts a brand new one from zero at the current threshold.
    private func reschedule(isSessionActive: Bool, isEnabled: Bool, isNotify: Bool, minutes: Int) {
        isIdle = false
        idleTimer?.invalidate()
        idleTimer = nil

        guard !isSessionActive, isEnabled, isNotify else { return }

        let interval = TimeInterval(max(1, minutes) * 60)
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

import Foundation

/// User-configurable defaults, persisted in `UserDefaults`.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var defaultCountdownMinutes: Int {
        didSet { UserDefaults.standard.set(defaultCountdownMinutes, forKey: Keys.defaultCountdownMinutes) }
    }
    @Published var defaultManualRecordMinutes: Int {
        didSet { UserDefaults.standard.set(defaultManualRecordMinutes, forKey: Keys.defaultManualRecordMinutes) }
    }
    @Published var showMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
    }
    /// Master switch: remind the user when no session has been active for a while.
    @Published var idleReminderEnabled: Bool {
        didSet { UserDefaults.standard.set(idleReminderEnabled, forKey: Keys.idleReminderEnabled) }
    }
    /// How long nothing must be tracked before a reminder fires, and then repeats.
    @Published var idleReminderMinutes: Int {
        didSet { UserDefaults.standard.set(idleReminderMinutes, forKey: Keys.idleReminderMinutes) }
    }
    @Published var idleReminderNotify: Bool {
        didSet { UserDefaults.standard.set(idleReminderNotify, forKey: Keys.idleReminderNotify) }
    }
    @Published var idleReminderHighlightIcon: Bool {
        didSet { UserDefaults.standard.set(idleReminderHighlightIcon, forKey: Keys.idleReminderHighlightIcon) }
    }

    private enum Keys {
        static let defaultCountdownMinutes = "defaultCountdownMinutes"
        static let defaultManualRecordMinutes = "defaultManualRecordMinutes"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let idleReminderEnabled = "idleReminderEnabled"
        static let idleReminderMinutes = "idleReminderMinutes"
        static let idleReminderNotify = "idleReminderNotify"
        static let idleReminderHighlightIcon = "idleReminderHighlightIcon"
    }

    init() {
        let defaults = UserDefaults.standard
        defaultCountdownMinutes = defaults.object(forKey: Keys.defaultCountdownMinutes) as? Int ?? 25
        defaultManualRecordMinutes = defaults.object(forKey: Keys.defaultManualRecordMinutes) as? Int ?? 25
        showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
        idleReminderEnabled = defaults.object(forKey: Keys.idleReminderEnabled) as? Bool ?? false
        idleReminderMinutes = defaults.object(forKey: Keys.idleReminderMinutes) as? Int ?? 15
        idleReminderNotify = defaults.object(forKey: Keys.idleReminderNotify) as? Bool ?? true
        idleReminderHighlightIcon = defaults.object(forKey: Keys.idleReminderHighlightIcon) as? Bool ?? true
    }
}

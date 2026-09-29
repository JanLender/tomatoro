import Foundation

/// User-configurable defaults, persisted in `UserDefaults`.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var defaultCountdownMinutes: Int {
        didSet { UserDefaults.standard.set(defaultCountdownMinutes, forKey: Keys.defaultCountdownMinutes) }
    }
    @Published var defaultManualRecordHours: Int {
        didSet { UserDefaults.standard.set(defaultManualRecordHours, forKey: Keys.defaultManualRecordHours) }
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
        static let defaultManualRecordHours = "defaultManualRecordHours"
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

        if let hours = defaults.object(forKey: Keys.defaultManualRecordHours) as? Int {
            defaultManualRecordHours = hours
            defaultManualRecordMinutes = defaults.object(forKey: Keys.defaultManualRecordMinutes) as? Int ?? 25
        } else {
            // Migrate from the pre-split format, where this key held a single
            // total (1...180) rather than just the minutes part (0...59).
            let legacyTotal = defaults.object(forKey: Keys.defaultManualRecordMinutes) as? Int ?? 25
            defaultManualRecordHours = legacyTotal / 60
            defaultManualRecordMinutes = legacyTotal % 60
        }
        showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
        idleReminderEnabled = defaults.object(forKey: Keys.idleReminderEnabled) as? Bool ?? false
        idleReminderMinutes = defaults.object(forKey: Keys.idleReminderMinutes) as? Int ?? 15
        idleReminderNotify = defaults.object(forKey: Keys.idleReminderNotify) as? Bool ?? true
        idleReminderHighlightIcon = defaults.object(forKey: Keys.idleReminderHighlightIcon) as? Bool ?? true
    }
}

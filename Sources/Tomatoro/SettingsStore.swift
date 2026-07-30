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

    private enum Keys {
        static let defaultCountdownMinutes = "defaultCountdownMinutes"
        static let defaultManualRecordMinutes = "defaultManualRecordMinutes"
        static let showMenuBarIcon = "showMenuBarIcon"
    }

    init() {
        let defaults = UserDefaults.standard
        defaultCountdownMinutes = defaults.object(forKey: Keys.defaultCountdownMinutes) as? Int ?? 25
        defaultManualRecordMinutes = defaults.object(forKey: Keys.defaultManualRecordMinutes) as? Int ?? 25
        showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
    }
}

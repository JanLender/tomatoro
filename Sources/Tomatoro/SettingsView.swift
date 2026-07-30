import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    /// The menu bar status item's actual insertion state. This is the single
    /// source of truth (owned by `TomatoroApp`) rather than `settings.showMenuBarIcon`
    /// directly — see the comment on `TomatoroApp.menuBarInserted` for why.
    @Binding var showMenuBarIcon: Bool

    var body: some View {
        Form {
            Stepper(value: $settings.defaultCountdownMinutes, in: 1...180, step: 5) {
                Text("Default countdown: \(settings.defaultCountdownMinutes) min")
            }

            Stepper(value: $settings.defaultManualRecordMinutes, in: 1...180, step: 5) {
                Text("Default manual record: \(settings.defaultManualRecordMinutes) min")
            }

            Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
        }
        .padding(20)
        .frame(width: 360)
    }
}

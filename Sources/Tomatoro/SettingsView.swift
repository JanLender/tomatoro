import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    /// The menu bar status item's actual insertion state. This is the single
    /// source of truth (owned by `TomatoroApp`) rather than `settings.showMenuBarIcon`
    /// directly — see the comment on `TomatoroApp.menuBarInserted` for why.
    @Binding var showMenuBarIcon: Bool

    @State private var defaultCountdownValid = true
    @State private var defaultManualRecordValid = true
    @State private var idleThresholdValid = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Default countdown") {
                NumberStepperField(suffix: "min", value: $settings.defaultCountdownMinutes, range: 1...180, isValid: $defaultCountdownValid)
            }

            row("Default manual record") {
                NumberStepperField(suffix: "min", value: $settings.defaultManualRecordMinutes, range: 1...180, isValid: $defaultManualRecordValid)
            }

            row("Show menu bar icon") {
                Toggle("", isOn: $showMenuBarIcon)
                    .labelsHidden()
            }

            Divider()

            Text("Idle Reminders")
                .font(.headline)

            row("Remind me when nothing is being tracked") {
                Toggle("", isOn: $settings.idleReminderEnabled)
                    .labelsHidden()
            }

            if settings.idleReminderEnabled {
                row("Idle threshold") {
                    NumberStepperField(suffix: "min", value: $settings.idleReminderMinutes, range: 1...120, isValid: $idleThresholdValid)
                }

                row("Send a notification") {
                    Toggle("", isOn: $settings.idleReminderNotify)
                        .labelsHidden()
                }

                row("Turn the menu bar icon red") {
                    Toggle("", isOn: $settings.idleReminderHighlightIcon)
                        .labelsHidden()
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    /// A settings row: label flush left, control flush right — kept
    /// consistent regardless of whether the control is a Stepper or a
    /// Toggle, unlike `Form`'s automatic (and inconsistent) alignment.
    @ViewBuilder
    private func row<Content: View>(_ label: String, @ViewBuilder control: () -> Content) -> some View {
        HStack {
            Text(label)
            Spacer()
            control()
        }
    }
}

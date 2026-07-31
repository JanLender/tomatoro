import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    /// The menu bar status item's actual insertion state. This is the single
    /// source of truth (owned by `TomatoroApp`) rather than `settings.showMenuBarIcon`
    /// directly — see the comment on `TomatoroApp.menuBarInserted` for why.
    @Binding var showMenuBarIcon: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Default countdown") {
                Stepper("\(settings.defaultCountdownMinutes) min", value: $settings.defaultCountdownMinutes, in: 1...180, step: 5)
                    .fixedSize()
            }

            row("Default manual record") {
                Stepper("\(settings.defaultManualRecordMinutes) min", value: $settings.defaultManualRecordMinutes, in: 1...180, step: 5)
                    .fixedSize()
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
                    Stepper("\(settings.idleReminderMinutes) min", value: $settings.idleReminderMinutes, in: 1...120, step: 5)
                        .fixedSize()
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

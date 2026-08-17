import SwiftUI

@main
struct TomatoroApp: App {
    @StateObject private var store: TaskStore
    @StateObject private var session: SessionController
    @StateObject private var settings: SettingsStore
    @StateObject private var idleReminder: IdleReminderController
    // MenuBarExtra's `isInserted` binding must not be rooted directly in an
    // ObservableObject's @Published property: SwiftUI writes back to it when
    // inserting/removing the status item, and that write re-triggers the
    // whole App's Scene body (since it observes `settings`), which creates
    // a runaway reconciliation loop (100% CPU). A plain local @State is the
    // single source of truth for actual insertion instead — both the menu
    // bar and the Settings toggle read/write it directly — and it's mirrored
    // into `settings` (for persistence) as a one-way side effect in onChange.
    @State private var menuBarInserted: Bool

    init() {
        let store = TaskStore()
        _store = StateObject(wrappedValue: store)
        let session = SessionController(store: store)
        _session = StateObject(wrappedValue: session)
        let settings = SettingsStore()
        _settings = StateObject(wrappedValue: settings)
        _idleReminder = StateObject(wrappedValue: IdleReminderController(session: session, settings: settings))
        _menuBarInserted = State(initialValue: settings.showMenuBarIcon)
        NotificationManager.shared.requestAuthorization()
        AppActivity.preventAppNap()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(session)
                .environmentObject(settings)
                .frame(minWidth: 640, minHeight: 420)
        }
        .windowResizability(.contentSize)

        Window("Daily Summary", id: "dailySummary") {
            DailySummaryView()
                .environmentObject(store)
        }
        .windowResizability(.contentMinSize)

        MenuBarScene(
            store: store,
            session: session,
            settings: settings,
            isInserted: $menuBarInserted
        )
        .onChange(of: menuBarInserted) { _, newValue in
            settings.showMenuBarIcon = newValue
        }

        Settings {
            SettingsView(showMenuBarIcon: $menuBarInserted)
                .environmentObject(settings)
        }
    }
}

/// The menu bar status item, split into its own `Scene` conformance taking
/// its `ObservableObject`s as explicit `@ObservedObject` parameters rather
/// than via `.environmentObject()` on an inline `MenuBarExtra` — the
/// verified fix for `MenuBarExtra`'s label/content not reliably re-rendering
/// when state changes from a background timer (see the comment on
/// `MenuBarLabel`).
private struct MenuBarScene: Scene {
    @ObservedObject var store: TaskStore
    @ObservedObject var session: SessionController
    @ObservedObject var settings: SettingsStore
    @Binding var isInserted: Bool

    var body: some Scene {
        MenuBarExtra(isInserted: $isInserted) {
            MenuBarContentView(store: store, session: session, settings: settings)
        } label: {
            MenuBarLabel(session: session, settings: settings)
        }
        .menuBarExtraStyle(.window)
    }
}

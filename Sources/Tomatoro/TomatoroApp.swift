import SwiftUI

@main
struct TomatoroApp: App {
    @StateObject private var store: TaskStore
    @StateObject private var session: SessionController
    @StateObject private var settings: SettingsStore
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
        _session = StateObject(wrappedValue: SessionController(store: store))
        let settings = SettingsStore()
        _settings = StateObject(wrappedValue: settings)
        _menuBarInserted = State(initialValue: settings.showMenuBarIcon)
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

        MenuBarExtra(isInserted: $menuBarInserted) {
            MenuBarContentView()
                .environmentObject(store)
                .environmentObject(session)
                .environmentObject(settings)
        } label: {
            MenuBarLabel()
                .environmentObject(session)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: menuBarInserted) { _, newValue in
            settings.showMenuBarIcon = newValue
        }

        Settings {
            SettingsView(showMenuBarIcon: $menuBarInserted)
                .environmentObject(settings)
        }
    }
}

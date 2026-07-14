import SwiftUI

@main
struct TomatoroApp: App {
    @StateObject private var store: TaskStore
    @StateObject private var session: SessionController

    init() {
        let store = TaskStore()
        _store = StateObject(wrappedValue: store)
        _session = StateObject(wrappedValue: SessionController(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(session)
                .frame(minWidth: 640, minHeight: 420)
        }
        .windowResizability(.contentSize)
    }
}

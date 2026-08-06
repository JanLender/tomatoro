import Foundation

/// Keeps Tomatoro out of App Nap for its entire lifetime.
///
/// Without this, macOS still fires the idle-reminder `Timer` on schedule
/// (confirmed: notifications arrive exactly on time even after hours
/// backgrounded), but can defer the actual redraw of a backgrounded app's
/// status item — compositing something no one is looking at is exactly the
/// kind of energy-saving deferral App Nap performs — so the menu bar icon
/// silently stays stale even though the underlying state changed correctly.
///
/// `.userInitiatedAllowingIdleSystemSleep` opts only *this app* out of
/// napping/throttling; it does not prevent the Mac itself from sleeping
/// per the user's Energy Saver settings. This mirrors the standard fix
/// documented in Apple's App Nap guide and used by real-world menu bar
/// utilities (e.g. alt-tab-macos) for exactly this "stay responsive while
/// backgrounded" scenario.
@MainActor
enum AppActivity {
    /// Must be retained for the whole process lifetime: App Nap resumes
    /// the instant this token is deallocated.
    private static let token: NSObjectProtocol = ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep,
        reason: "Keep idle-reminder timers and menu bar icon updates responsive in the background"
    )

    /// Call once at launch to force the lazy `token` above into existence.
    static func preventAppNap() {
        _ = token
    }
}

import SwiftUI

/// Snapping a start time or duration to the nearest 5-minute mark — the
/// common case when tidying up a recorded time (started at 9:06, really
/// meant 9:00; worked 57 minutes, call it an even hour).
///
/// Rounding always *moves* by at least one 5-minute step, even from a value
/// that's already on the grid — so clicking "round down" on 9:00 gives
/// 8:55, not a no-op. That matches how a stepper behaves, which is the
/// mental model these buttons sit right next to.
enum TimeRounding {
    /// Snaps `date`'s minute down to the previous multiple of 5, carrying
    /// over the hour/day as needed, and zeroes the seconds.
    static func roundedDown(_ date: Date, calendar: Calendar = .current) -> Date {
        let minute = calendar.component(.minute, from: date)
        let remainder = minute % 5
        let delta = remainder == 0 ? -5 : -remainder
        return zeroingSeconds(shifted(date, byMinutes: delta, calendar: calendar), calendar: calendar)
    }

    /// Snaps `date`'s minute up to the next multiple of 5, carrying over
    /// the hour/day as needed, and zeroes the seconds.
    static func roundedUp(_ date: Date, calendar: Calendar = .current) -> Date {
        let minute = calendar.component(.minute, from: date)
        let remainder = minute % 5
        let delta = remainder == 0 ? 5 : (5 - remainder)
        return zeroingSeconds(shifted(date, byMinutes: delta, calendar: calendar), calendar: calendar)
    }

    /// Snaps a total-minutes duration down to the previous multiple of 5
    /// (never below 0).
    static func roundedDown(minutes total: Int) -> Int {
        guard total > 0 else { return 0 }
        let floor5 = (total / 5) * 5
        return floor5 == total ? max(0, floor5 - 5) : floor5
    }

    /// Snaps a total-minutes duration up to the next multiple of 5, capped
    /// at `maxMinutes` so it can't overflow whatever hours/minutes range
    /// the caller is bound by.
    static func roundedUp(minutes total: Int, maxMinutes: Int) -> Int {
        let ceil5 = ((total / 5) + 1) * 5
        return min(ceil5, maxMinutes)
    }

    private static func shifted(_ date: Date, byMinutes delta: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .minute, value: delta, to: date) ?? date
    }

    /// Zeroes the seconds (and sub-second) component of `date`.
    ///
    /// Deliberately *not* `calendar.date(bySetting: .second, value: 0, of:)`:
    /// that method performs a forward date *search* for the next moment
    /// matching the requested component, not a simple field overwrite — for
    /// `.second` specifically it jumped to the *next* top-of-minute instead
    /// of truncating the current one (confirmed empirically: 9:05:23 in,
    /// 9:06:00 out). Rebuilding the date from explicit components is the
    /// unambiguous way to just set a field.
    private static func zeroingSeconds(_ date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components) ?? date
    }
}

/// A pair of small "round down" / "round up" buttons, sized to sit right
/// next to a `DatePicker` or a duration's hours/minutes fields.
struct RoundToFiveButtons: View {
    let onRoundDown: () -> Void
    let onRoundUp: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onRoundDown) {
                Image(systemName: "arrow.down.to.line")
            }
            .help("Round down to the nearest 5 minutes")

            Button(action: onRoundUp) {
                Image(systemName: "arrow.up.to.line")
            }
            .help("Round up to the nearest 5 minutes")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }
}

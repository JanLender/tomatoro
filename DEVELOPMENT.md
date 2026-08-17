# Development

This document is for anyone changing Tomatoro's code. It covers the
architecture, a handful of non-obvious platform gotchas that cost real
debugging time to work out, and the day-to-day workflow for testing changes.
For what the app does and how to build/run it, see [README.md](README.md).

## Architecture overview

Tomatoro is a single SwiftUI `App` (`TomatoroApp`) with five scenes:

- `WindowGroup(id: "main")` — the main window (`ContentView`).
- `Window(id: "dailySummary")` — the Daily Summary window (`DailySummaryView`),
  a singleton scene: `openWindow(id: "dailySummary")` just refocuses it if it's
  already open rather than creating a second one.
- `WindowGroup(id: "taskRecords", for: TaskItem.ID.self)` — the Task Records
  window (`TaskRecordsView`), one per task. Opened via
  `openWindow(id: "taskRecords", value: task.id)`; opening the same task's ID
  again refocuses its existing window instead of duplicating it. Use this
  `WindowGroup(for:)` form (not a plain `Window`) for any future window whose
  content depends on which piece of data it was opened for.
- `MenuBarExtra` — the status item, wrapped in its own `MenuBarScene: Scene`
  (see [Gotcha 2](#2-menubarextra-doesnt-reliably-see-environmentobject-changes) for why it's split out like that).
- `Settings` — the Settings window (`SettingsView`), reachable via ⌘, or the app menu.

Both `DailySummaryView` and `TaskRecordsView` used to be `.sheet`s; they were
converted to real window scenes so they could be moved and resized (sheets
are pinned to their parent window and can't be either). One consequence: they
lost their in-content title/Done-button row in favor of the window's native
title bar and close button — don't re-add that row if you touch these views.

`DailySummaryView`'s data (`entriesForDay`) is deliberately a `@State`
snapshot, not a computed property reading live from `store`. It's rebuilt via
`refreshEntries()` only on `.onAppear`, on `.onChange(of: selectedDate)`, and
right after an edit made from within that same view — never merely because
`store.tasks` changed elsewhere. Two real bugs motivated this: (1) a
`Dictionary(grouping:by:)`-based grouping's iteration order isn't guaranteed
stable across separate constructions of the same content, so tied rows in the
"By task" section would visibly swap places every time the view re-rendered
(which happens once a second while any timer is ticking anywhere in the app,
since re-rendering a computed property re-runs the grouping from scratch);
and (2) today's data would silently shift under the user while the window
stayed open, if today happened to be the selected date and a background timer
logged a new record. If you add a new field to `Entry` or a new derived view
(`totalsByTask`, `totalSeconds`, etc.), it's safe to leave those as computed
properties *of* `entriesForDay` — just don't make `entriesForDay` itself live
again.

State lives in a small number of `@MainActor` `ObservableObject`s, all
constructed once in `TomatoroApp.init()` and threaded down from there:

| Object | Owns | Persists to |
|---|---|---|
| `TaskStore` | tasks and their work records | `~/Library/Application Support/Tomatoro/tasks.json` |
| `SessionController` | the currently running countdown/stopwatch | — (in-memory only) |
| `SettingsStore` | user-configurable defaults | `UserDefaults` |
| `IdleReminderController` | the idle-reminder countdown/notification timer | — (in-memory only) |

`NotificationManager` and `AppActivity` are singletons (`.shared`) rather than
constructor-injected — neither holds state that needs to be swapped out or
mocked, so the extra plumbing wasn't worth it.

Data model: `TaskItem` holds an array of `WorkRecord`s (one per logged
session); a task's total time is always derived from its records rather than
stored separately, so there's no way for the two to drift apart. Both types
have hand-written `Codable` conformances that fall back to sensible defaults
for fields that didn't exist in older versions of `tasks.json` — check those
before adding a new stored property to either type, and add the same kind of
fallback rather than a hard `decode`.

## Non-obvious gotchas

These cost real time to track down. If you're touching the menu bar item,
notifications, or Settings, read this first.

### 1. `MenuBarExtra`'s status-item icon strips out color

Setting `.foregroundStyle(_:)` on an `Image(systemName:)` used as a
`MenuBarExtra` label has no effect — macOS renders SF Symbol status-item
icons as monochrome "template" images and discards any color, regardless of
how the modifier is applied. A plain SwiftUI `Shape` doesn't work either —
`MenuBarExtra`'s label has documented limitations rendering arbitrary custom
`View` content, and it may simply not appear at all.

**Fix** (`MenuBarContentView.swift`, `MenuBarLabel.timerIcon`): render the
symbol into a real bitmap via `withSymbolConfiguration`, recolor it with the
standard AppKit template-tinting recipe (fill with `.sourceIn`, which only
replaces color where the symbol's own pixels are already opaque), then set
`isTemplate = false` so the color survives instead of being stripped back out.

### 2. `MenuBarExtra` doesn't reliably see `@EnvironmentObject` changes

State injected into a `MenuBarExtra` label/content via `.environmentObject()`
can fail to trigger a re-render when that state changes from a background
timer, even though the state itself is correct (confirmed by instrumenting
both sides — the underlying `@Published` value was flipping right on
schedule; the view just never redrew). This matches a documented class of
`MenuBarExtra` bugs (Apple Developer Forums thread 720625).

**Fix**: pass the observable objects as explicit `@ObservedObject`
initializer parameters instead of injecting them via the environment, and
give `MenuBarExtra` its own `Scene` conformance (`MenuBarScene` in
`TomatoroApp.swift`) rather than declaring it inline in the app's `body`.

### 3. `MenuBarExtra(isInserted:)` bound to a `@Published` property → 100% CPU

Binding `isInserted` directly to `$someObservableObject.someProperty` sends
the app into a runaway reconciliation loop pegging a full CPU core: SwiftUI
writes back to the binding when it inserts/removes the status item, and
because the binding's root is an `ObservableObject`, that write re-triggers
the whole `App.body` (which observes that object), which reconstructs
`MenuBarExtra`, which writes back again.

**Fix** (`TomatoroApp.swift`, `menuBarInserted`): use a plain local `@State`
as the single source of truth for `isInserted` instead. Mirror it into the
persisted setting as a one-way side effect in `.onChange`, never the other
way around — a *second* `.onChange` bridging the other direction reintroduces
the same class of loop.

If you're ever debugging something that looks like this (CPU pegged, app
otherwise seems fine), check `ps -p <pid> -o pcpu` over a few seconds — a
genuine loop stays pegged near 100%; normal transient work spikes once and
settles back to ~0%.

### 4. `@Published`'s publisher fires *before* the property's storage updates

`@Published`'s projected-value publisher (`$property`) sends its
notification via `subject.send(newValue)` **before** the actual backing
storage is updated. A `.sink` closure that ignores the emitted value and
instead re-reads that *same* property directly from the object will always
observe the *previous* value — every change processed one step behind
itself. This isn't specific to Combine subtlety trivia — it produced a real,
user-visible bug: toggling idle reminders off then back on silently stopped
scheduling anything, because the "on" handler read `enabled` as still `false`.

**Fix** (`IdleReminderController.swift`): use the value the `sink` closure
receives as its parameter, not a fresh read of `settings.idleReminderEnabled`
(etc.) from inside the closure. Reading a *different* property that isn't
simultaneously being mutated is fine — the risk is only for the property
whose own publisher you're currently inside.

Note this doesn't affect ordinary SwiftUI view updates (e.g. `MenuBarLabel`
picking up a settings change): SwiftUI defers the actual `body` re-evaluation
to the next run loop turn, by which point the mutation has fully completed.
It's specifically hand-written synchronous `Combine.sink` code that's at risk.

### 5. App Nap can silently stop the menu bar icon from redrawing

The idle-reminder `Timer` kept firing exactly on schedule even after hours
backgrounded (confirmed via the system log), but the menu bar icon still
didn't visually update. macOS keeps a backgrounded app's timers running but
can defer the actual *redraw* of things nobody's looking at — exactly what
idle reminders trigger, since the whole point is firing after long stretches
with no window focus or interaction.

**Fix** (`AppActivity.swift`): hold a
`ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason:)`
token for the app's entire lifetime — App Nap resumes the instant it's
deallocated. This opts only Tomatoro out of napping/throttling; it does not
keep the Mac itself awake, since that option still allows system sleep per
the user's Energy Saver settings. (The older `NSAppSleepDisabled` Info.plist
key is a no-op on modern macOS — ignored since Sierra — don't bother with it.)

### 6. `Form` gives `Stepper` and `Toggle` inconsistent alignment on macOS

Mixing `Stepper(label) { Text(...) }` and `Toggle(label, isOn:)` inside a
macOS `Form` produces a visually broken layout: `Stepper`'s label sits flush
left like normal, but `Toggle`'s checkbox+label unit gets right-aligned into
the "control column" instead, with a large empty gap where its label should
be — and long `Toggle` labels get clipped in that narrow leftover space.

**Fix** (`SettingsView.swift`): don't use `Form` for settings UI here. Use a
plain `VStack` of `HStack` rows (label, `Spacer()`, control) via the small
`row(_:control:)` helper — every row aligns identically regardless of
control type.

## Validated, editable numeric input

`NumberStepperField.swift` is the shared pattern for "a number the user can
type or step, that never ends up invalid": commit an in-range value to the
bound `Int` the moment it parses; otherwise leave the bound value alone and
show a red outline. Critically, it also **reverts to the last valid value the
moment the field loses focus** (`@FocusState`, tracked via `.onChange(of:
isFocused)`), covering both blur (click away, tab out) and the containing
window closing — macOS doesn't necessarily tear down and recreate a
`Settings`-scene view's `@State` when its window closes and reopens, so
relying on a fresh `@State` to reset stale invalid text isn't safe; reverting
eagerly on focus loss is.

Reuse this component for any new "type a whole number in a range" field
rather than reaching for a bare `Stepper` or `TextField`.

## Manual testing workflow

There's no automated test suite yet — everything below is manual.

**Packaged app vs. `swift run`**: `swift build` / `swift run` only update
`.build/`, not `dist/Tomatoro.app`. Menu bar behavior, notifications, and the
app icon all depend on running the actual bundle:

```bash
./scripts/build_app.sh
open dist/Tomatoro.app
```

**`open` does not relaunch an already-running app** — it just brings the
existing process to the front, so if you're testing a rebuild, fully quit
first (menu bar dropdown → Quit, ⌘Q, or `killall Tomatoro`) or you'll be
looking at stale code. To be certain nothing is left running before a test:

```bash
killall Tomatoro 2>/dev/null; sleep 1; pgrep -x Tomatoro   # should print nothing
```

**Seeding settings without clicking through the UI**: `SettingsStore` reads
`UserDefaults` once at launch, so you can pre-set values before starting the
app — handy for testing a short idle-reminder threshold instead of waiting
the default 15 minutes:

```bash
defaults write com.tomatoro.app idleReminderEnabled -bool true
defaults write com.tomatoro.app idleReminderMinutes -int 1
open dist/Tomatoro.app
```

This only works *before* launch — the running app doesn't observe external
`UserDefaults` changes, so writing keys while it's already running has no
effect until the next launch.

**Reading the system log** is the most reliable way to verify background
behavior (timers, notifications) without needing to watch the screen:

```bash
# after-the-fact query
log show --predicate 'process == "Tomatoro"' --style compact --last 5m

# live tail — needed for anything logged at .debug level, which log show
# doesn't surface unless it happens to still be in the in-memory buffer
log stream --predicate 'process == "Tomatoro"' --style compact --level debug
```

Look for `Adding notification request` (a notification was actually
scheduled with the OS) and `Publishing changes from within view updates`
(a SwiftUI state-mutation-during-render bug, per Gotcha 3).

**Crash reports** land in `~/Library/Logs/DiagnosticReports/Tomatoro-*.ips`.

**Direct-launch with environment variables**, when you need to pass one
(`open` doesn't forward the shell's environment):

```bash
SOME_VAR=1 dist/Tomatoro.app/Contents/MacOS/Tomatoro
```

## Adding a new setting

1. `SettingsStore.swift`: add a `@Published var` with a `didSet` that writes
   to `UserDefaults`, a matching key in the private `Keys` enum, and a
   default in `init()`.
2. `SettingsView.swift`: add a `row(...)` for it — `NumberStepperField` for
   numbers, `Toggle` for booleans.
3. Wire up whatever reads it. If it needs to react live to the setting
   changing (not just read it lazily), watch out for Gotcha 4 above.

# Tomatoro

A simple native macOS task & time tracker. Pick (or create) a task, run a
countdown or stopwatch, and Tomatoro records how long you actually spent —
down to individual work log entries with their own notes. A menu bar icon
mirrors what's happening at a glance, even when the main window is closed.

This is a learning project built with **Swift + SwiftUI** using the
**Swift Package Manager** — no full Xcode installation required, just the
Command Line Tools.

## Features

- Create tasks, each with an optional free-form description; rename or archive
  them any time from the sidebar
- Sort the task list by date created, last record time, name, or total time
  recorded — ascending or descending
- Two session modes: countdown (with a chosen duration) or an open-ended stopwatch
- Pause / resume / stop a running session; a system notification lets you know when a countdown finishes
- Every session is logged as an individual work record with its own optional note —
  written before starting, live while the timer runs, or added/edited/deleted afterwards
- Add work records manually (for time not tracked live)
- **Task Records** — its own movable, resizable window (one per task, reachable
  from the sidebar or the task detail view) listing every record grouped by day,
  with per-day and running totals. Edit a record's start time, duration, and
  description, or delete just its description; right-click any name or
  description to copy it
- **Daily Summary** — also its own movable, resizable window. Pick any day
  (with prev/next-day arrows) and see every record logged that day, broken
  down by task with a grand total. Each task's unique record descriptions are
  listed right there (case-insensitive duplicates like "Code Review" /
  "code review" collapse to one line) and copyable — individually, or as
  "name + descriptions" ready to paste into an external work-log entry. The
  view is a snapshot taken when it opens or the date changes, so it won't
  shuffle or update itself while a timer keeps running elsewhere
- Archive tasks you're done with — hidden by default, can't be started or edited
  while archived, toggle visibility on demand, unarchive to resume; delete works on
  archived or active tasks
- A menu bar status item that mirrors tracking state at a glance: the icon turns
  green while a session is running and shows the live remaining/elapsed time, red
  when nothing has been tracked for a while (if idle reminders are on), white
  otherwise. Its dropdown lets you start a task's default countdown, start a
  stopwatch, add a manual record, or pause/resume/stop the active session — all
  without opening the main window
- Idle reminders: get a repeating system notification, a red menu bar icon, or
  both, after a configurable period with nothing being tracked
- A Settings window (⌘,) for defaults and idle-reminder behavior — default
  countdown/manual-record duration, whether the menu bar icon is shown, and the
  idle-reminder threshold/notification/icon options. Numeric fields can be typed
  directly (validated, with invalid input rejected) or stepped one at a time
- A custom app icon, and a script to package everything into a standalone `.app`
- Tasks persist between launches as JSON, with backward-compatible migration as the format evolves
- Scriptable via AppleScript (`osascript`, Script Editor, Shortcuts) — list unarchived tasks, create a task, or log a
  work record, creating or unarchiving the task automatically as needed; see [AUTOMATION.md](AUTOMATION.md)

## Requirements

- macOS 14 or later
- Swift toolchain (comes with Xcode **or** the Command Line Tools):

```bash
swift --version
```

## Build & run

Build the app bundle and open it:

```bash
./scripts/build_app.sh
open dist/Tomatoro.app
```

For quick iteration during development you can also run it straight from
the terminal (a window will appear, though menu/focus behaviour is best in
the bundled `.app`):

```bash
swift run
```

Note: `swift build` / `swift run` only update `.build/`, not `dist/Tomatoro.app` —
rerun `./scripts/build_app.sh` whenever you want to try the packaged app.

## How it works

- `Sources/Tomatoro/Models.swift` — the `TaskItem` and `WorkRecord` data models.
- `Sources/Tomatoro/TaskStore.swift` — loads/saves tasks as JSON.
- `Sources/Tomatoro/SessionController.swift` — drives the countdown/stopwatch and records elapsed time.
- `Sources/Tomatoro/SettingsStore.swift` — user-configurable defaults, persisted via `UserDefaults`.
- `Sources/Tomatoro/IdleReminderController.swift` — tracks idle time and drives idle reminders.
- `Sources/Tomatoro/NotificationManager.swift` — posts system notifications (countdown finished, idle reminder).
- `Sources/Tomatoro/AppActivity.swift` — keeps the app responsive in the background so idle
  reminders and the menu bar icon stay accurate while it's not the active app.
- `Sources/Tomatoro/NumberStepperField.swift` — shared validated numeric input, typed or stepped.
- `Sources/Tomatoro/Clipboard.swift` — the shared "Copy" helper used throughout the record/summary views.
- `Sources/Tomatoro/ContentView.swift` — the main SwiftUI window: task list (sortable), session controls, manual entry.
- `Sources/Tomatoro/TaskRecordsView.swift` — its own window (one per task) with the day-grouped record list, editing, and totals.
- `Sources/Tomatoro/DailySummaryView.swift` — its own window: a snapshot summary for a chosen day, by task and by record.
- `Sources/Tomatoro/MenuBarContentView.swift` — the menu bar status item icon and its quick-access dropdown.
- `Sources/Tomatoro/SettingsView.swift` — the Settings window.
- `Sources/Tomatoro/TomatoroApp.swift` — the app entry point, wiring up all of the app's windows and the menu bar scene.
- `Sources/Tomatoro/Scripting.swift` — the AppleScript command implementations (`create task`, `add record`) and the `AppDelegate` that exposes `tasks`.
- `Tomatoro.sdef` — the AppleScript dictionary; see [AUTOMATION.md](AUTOMATION.md) for usage examples.
- `scripts/build_app.sh` — compiles and wraps the binary into a `Tomatoro.app` bundle, generating `AppIcon.icns` from `tomatoro-icon.png`.

Changing the code? See [DEVELOPMENT.md](DEVELOPMENT.md) for the architecture,
a manual testing workflow, and a handful of platform gotchas worth knowing
before touching the menu bar item, notifications, or Settings.

## Data location

Tasks are stored at:

```
~/Library/Application Support/Tomatoro/tasks.json
```

## Roadmap ideas

- Pomodoro presets (25/5) and automatic break timers
- Weekly/monthly summaries, and exporting records (CSV, etc.)
- Launch at login

# Tomatoro

A simple native macOS task & time tracker. Pick (or create) a task, run a
countdown or stopwatch, and Tomatoro records how long you actually spent —
down to individual work log entries with their own notes.

This is a learning project built with **Swift + SwiftUI** using the
**Swift Package Manager** — no full Xcode installation required, just the
Command Line Tools.

## Features

- Create tasks, each with an optional free-form description
- Two session modes: countdown (with a chosen duration) or an open-ended stopwatch
- Pause / resume / stop a running session; alert (with sound) when a countdown finishes
- Every session is logged as an individual work record with its own optional note —
  written before starting, live while the timer runs, or added/edited/deleted afterwards
- Add work records manually (for time not tracked live)
- Per-task record list, grouped by day, with per-day and running totals
- Daily summary view: pick any day and see every record logged that day across all
  tasks, broken down by task with a grand total
- Archive tasks you're done with — hidden by default, can't be started or edited
  while archived, toggle visibility on demand, unarchive to resume; delete works on
  archived or active tasks
- A menu bar status item mirrors the app: idle/counting/paused at a glance, with a
  dropdown to start a task's default countdown, start a stopwatch, add a manual
  record, or pause/resume/stop the active session — all without opening the main window
- A custom app icon, and a script to package everything into a standalone `.app`
- Tasks persist between launches as JSON, with backward-compatible migration as the format evolves

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
- `Sources/Tomatoro/ContentView.swift` — the main SwiftUI window: task list, session controls, manual entry.
- `Sources/Tomatoro/TaskRecordsView.swift` — per-task record list with day grouping and totals.
- `Sources/Tomatoro/DailySummaryView.swift` — cross-task summary for a chosen day.
- `Sources/Tomatoro/MenuBarContentView.swift` — the menu bar status item and its quick-access dropdown.
- `Sources/Tomatoro/TomatoroApp.swift` — the app entry point, wiring up the main window and the menu bar scene.
- `scripts/build_app.sh` — compiles and wraps the binary into a `Tomatoro.app` bundle, generating `AppIcon.icns` from `tomatoro-icon.png`.

## Data location

Tasks are stored at:

```
~/Library/Application Support/Tomatoro/tasks.json
```

## Roadmap ideas

- Pomodoro presets (25/5) and automatic break timers
- Native notifications instead of an in-app alert
- Rename a task after creation
- Weekly/monthly summaries, and exporting records (CSV, etc.)
- Launch at login

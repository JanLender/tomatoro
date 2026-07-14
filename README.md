# Tomatoro

A simple native macOS task & time tracker. Pick (or create) a task, set a
countdown, work until it rings, and Tomatoro records how long you actually spent.

This is a learning project built with **Swift + SwiftUI** using the
**Swift Package Manager** — no full Xcode installation required, just the
Command Line Tools.

## Features (MVP)

- Create and select tasks
- Set a countdown timer (in minutes) for the selected task
- Pause / resume / stop a running session
- Alert (with sound) when the timer finishes
- Records total time spent per task, even if you stop early
- Tasks persist between launches as JSON

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

## How it works

- `Sources/Tomatoro/Models.swift` — the `TaskItem` data model.
- `Sources/Tomatoro/TaskStore.swift` — loads/saves tasks as JSON.
- `Sources/Tomatoro/SessionController.swift` — drives the countdown and records elapsed time.
- `Sources/Tomatoro/ContentView.swift` — the SwiftUI user interface.
- `Sources/Tomatoro/TomatoroApp.swift` — the app entry point.
- `scripts/build_app.sh` — compiles and wraps the binary into a `Tomatoro.app` bundle.

## Data location

Tasks are stored at:

```
~/Library/Application Support/Tomatoro/tasks.json
```

## Roadmap ideas

- Pomodoro presets (25/5) and automatic break timers
- Native notifications instead of an in-app alert
- A menu bar item to start/stop without the main window
- Per-session history and daily/weekly summaries
- App icon and packaging for distribution

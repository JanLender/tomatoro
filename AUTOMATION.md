# Automation

Tomatoro has a small AppleScript dictionary (`Tomatoro.sdef`, bundled into
`Contents/Resources` by `scripts/build_app.sh`) so it can be driven from
Script Editor, `osascript`, or Shortcuts' "Run AppleScript" action. This
covers what's scriptable and how to use it. For the implementation itself —
the `NSScriptCommand` subclasses, the sdef gotchas that cost real debugging
time — see [DEVELOPMENT.md](DEVELOPMENT.md).

Tomatoro must be running (or `open`-able) for any of this to work; these are
Apple Events sent to a live app, not a headless CLI.

## Browsing the dictionary

Script Editor → File → Open Dictionary… → Tomatoro shows the full dictionary
with descriptions, the same way you'd browse Mail's or Finder's.

## Task identity: project + name

A task is identified by the pair **(project, task name)**, both compared
ignoring case. The same name in two projects is two different tasks. The
scripting API never relies on the default project — that's a GUI convenience
— so every command that addresses a task by name must also name its project.

- A project is given by name (`in project "ORCA"`) and must already exist;
  the API never creates one. Manage projects in the Projects window.
- Missing or empty task name or project, or an unknown project, is an
  ordinary AppleScript error whose message contains `invalid data`.
- Tasks created before projects existed have no project; they can't be
  addressed by name any more, only by id (`add record "<task id>" …`).

## `get tasks`

Returns every **unarchived** task as a list of `task info` records, each with
`task id`, `task name`, `task description` and `task project` (the project's
name, empty for a task without one).

```applescript
tell application "Tomatoro"
    get tasks
end tell
```

```applescript
tell application "Tomatoro"
    set allTasks to get tasks
    repeat with t in allTasks
        log (task project of t) & " / " & (task name of t) & " — " & (task id of t)
    end repeat
end tell
```

## `create task`

```applescript
tell application "Tomatoro"
    create task "Q3 Planning" in project "ORCA"
    create task "Q3 Planning" in project "ORCA" with description "Roadmap review and staffing"
end tell
```

Idempotent per (project, name): if an **unarchived** task with that identity
exists it's returned unchanged — description included, so `with description`
only matters for a brand-new task. If it exists but is **archived**, it's
unarchived and returned. Otherwise it's created in that project. A task with
the same name in another project is unaffected. The result is a `task info`
record, so it's safe to always capture it:

```applescript
tell application "Tomatoro"
    set t to create task "Q3 Planning" in project "ORCA"
    return task id of t
end tell
```

## `add record`

Logs a completed work session. The task is given either by **id**, or by
**name together with `in project`**.

```applescript
tell application "Tomatoro"
    add record "Q3 Planning" duration 30 in project "ORCA"
    add record "Q3 Planning" duration 45 notes "Reviewed staffing plan" in project "ORCA"
    add record "9D0E1C3A-…-task-id" duration 15 -- by id: no project needed
end tell
```

- `duration` is in **minutes** and required.
- `in project` is required when the task is given by name; it is ignored
  when the first argument is a task id (an id is already unambiguous).
- `started at` is optional and defaults to `(now − duration)`, i.e. a session
  that just ended. Pass an explicit date to backfill a different time:

  ```applescript
  tell application "Tomatoro"
      set d to current date
      set year of d to 2026
      set month of d to 8
      set day of d to 20
      set hours of d to 9
      set minutes of d to 30
      set seconds of d to 0
      add record "Q3 Planning" duration 25 started at d notes "Backfilled" in project "ORCA"
  end tell
  ```

- `notes` is optional free-form text.

If no task has that (project, name), one is created in the project; if a
matching task is archived, it's unarchived first, then the record is added —
so `add record` alone is enough to log time without ever having to
`create task` or unarchive anything by hand first.

## `export worklog`

Read-only: exports tasks and their work records for a date range as a single
JSON string, for tools that report or bill time logged in Tomatoro (see
[JanLender/tajman](https://github.com/JanLender/tajman) — the doc that
originally specified this command lives at
`docs/tomatoro-interface.md` in that repo).

```applescript
tell application "Tomatoro"
    export worklog from "2026-09-30" to "2026-09-30"
end tell
```

- `from` is required, `to` is optional and defaults to `from` — both
  `yyyy-MM-dd`, in the Mac's local time zone, inclusive. A record belongs to
  the local day its `started at` falls on.
- Includes **archived and unarchived** tasks alike, unlike `get tasks` — any
  task with at least one record in range is included.
- Tasks are ordered by the start of their first record *in the range*;
  records within a task are ordered by `started at`.
- `totalRecordedSeconds` is each task's all-time total, not limited to the
  requested range — only `records` itself is filtered to the range.
- `projectName` and `estimatedHours` are `null` when the task has no project
  or no estimate set.

```applescript
tell application "Tomatoro"
    set json to export worklog from "2026-09-01" to "2026-09-30"
    -- hand `json` to whatever actually parses it (Shortcuts, a shell
    -- pipeline via osascript, etc.) — AppleScript itself has no JSON parser
end tell
```

```bash
osascript -e 'tell application "Tomatoro" to export worklog from "2026-09-30"' | python3 -m json.tool
```

## Error handling

Bad input (empty name, missing or unknown project, non-positive duration)
raises a normal AppleScript error whose human-readable message contains
`invalid data` — wrap calls
in a `try` block if a script needs to continue past a failure:

```applescript
tell application "Tomatoro"
    try
        add record "Some Task" duration 0 in project "ORCA"
    on error errText
        log "Failed: " & errText
    end try
end tell
```

## From the shell

Any of the above also works via `osascript`, which is handy for quick checks
or non-AppleScript automation (cron, Shortcuts' "Run Shell Script", etc.):

```bash
osascript -e 'tell application "Tomatoro" to get tasks'
osascript -e 'tell application "Tomatoro" to add record "Q3 Planning" duration 15 notes "Quick sync" in project "ORCA"'
```

## A worked example

Log a block of time against a task, creating it in its project on the fly if
it doesn't exist yet — the common case for a script fed by an external time source
(a calendar event, a ticket you just closed, etc.):

```applescript
tell application "Tomatoro"
    add record "Daily SU" duration 15 notes "Standup" in project "ORCA"
end tell
```

That's the whole script — no need to check whether "Daily SU" exists in ORCA,
create it, or unarchive it first; `add record` handles all three cases.

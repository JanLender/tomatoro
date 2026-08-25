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

## `get tasks`

Returns every **unarchived** task as a list of `task info` records, each with
`task id`, `task name`, and `task description`.

```applescript
tell application "Tomatoro"
    get tasks
end tell
```

```applescript
tell application "Tomatoro"
    repeat with t in tasks
        log (task name of t) & " — " & (task id of t)
    end repeat
end tell
```

## `create task`

```applescript
tell application "Tomatoro"
    create task "Q3 Planning"
    create task "Q3 Planning" with description "Roadmap review and staffing"
end tell
```

Idempotent by name (case-insensitive): calling it again with a name that
already matches an **unarchived** task just returns that task unchanged — no
duplicate is created. If the matching task is **archived**, it's unarchived
and returned instead of creating a new one. Either way the result is a
`task info` record, so it's safe to always capture it:

```applescript
tell application "Tomatoro"
    set t to create task "Q3 Planning"
    return task id of t
end tell
```

## `add record`

Logs a completed work session against a task, identified by name or id.

```applescript
tell application "Tomatoro"
    add record "Q3 Planning" duration 30
    add record "Q3 Planning" duration 45 notes "Reviewed staffing plan"
end tell
```

- `duration` is in **minutes** and required.
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
      add record "Q3 Planning" duration 25 started at d notes "Backfilled"
  end tell
  ```

- `notes` is optional free-form text.

If no task matches the given name (or id), one is created automatically and
the record is logged against it. If a matching task exists but is archived,
it's unarchived first, then the record is added — so `add record` alone is
enough to log time without ever having to `create task` or unarchive
anything by hand first.

## Error handling

Bad input (empty name, non-positive duration, an id that matches nothing)
raises a normal AppleScript error with a human-readable message — wrap calls
in a `try` block if a script needs to continue past a failure:

```applescript
tell application "Tomatoro"
    try
        add record "Some Task" duration 0
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
osascript -e 'tell application "Tomatoro" to add record "Q3 Planning" duration 15 notes "Quick sync"'
```

## A worked example

Log a block of time against a task, creating it on the fly if it doesn't
exist yet — the common case for a script fed by an external time source
(a calendar event, a ticket you just closed, etc.):

```applescript
tell application "Tomatoro"
    add record "ORCA Daily SU" duration 15 notes "Standup"
end tell
```

That's the whole script — no need to check whether "ORCA Daily SU" exists,
create it, or unarchive it first; `add record` handles all three cases.

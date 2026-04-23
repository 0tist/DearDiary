---
theme: default
paging: "%d / %d"
---

# Background Auto-Updating TODO

Design spec — 2026-04-23
Owner: jayesh@aiatella.com
Status: pending user review

---

## 1 · Purpose

Keep a single, always-fresh TODO at `~/Housekeeping/TODO.md` that is
updated automatically by every Claude Code session the user runs —
across any project, any working directory.

Survives: long sessions, parallel sessions, short sessions, crashes.

---

## 2 · Non-goals

- Full task management (priorities, due dates, dependency graphs)
- Sync to external systems (Linear, Jira, Todoist)
- Per-project TODOs — **one global list** is the explicit choice
- Replacing in-session `TaskCreate` — this operates across sessions, not inside one

---

## 3 · Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Any Claude Code session (slides, AortaAIM, anywhere)    │
└──────────────────────────────────────────────────────────┘
         │ SessionStart          │ Stop / SessionEnd
         ▼                       ▼
  inject current TODO     run update script
  into session context    (throttled + locked)
                                 │
                                 ▼
                  ┌──────────────────────────────┐
                  │  ~/Housekeeping/             │
                  │    TODO.md          ← truth  │
                  │    .todo-update.lock         │
                  │    .todo-last-update         │
                  │    .todo-events.log          │
                  └──────────────────────────────┘
```

Three pieces, orchestrated by hooks in **global** `~/.claude/settings.json`.

---

## 4.1 · `TODO.md` schema

Human-readable markdown. Stable section headers so the updater can diff cleanly.

```markdown
# TODO

_Last updated: 2026-04-23 14:32 UTC by session <id> (cwd: ~/slides)_

## Active
- [ ] [slides] wire up CLI flag `--theme` (in progress)
- [ ] [AortaAIM] regenerate landmark JSON after dataset refresh

## Blocked / Waiting
- [ ] [slides] confirm whether export format is PDF or HTML

## Done (last 7 days)
- [x] 2026-04-22 [slides] initial CLI scaffold
```

Items tagged `[project]`. User may edit manually; updater preserves unknown content.

---

## 4.2 · `todo-update.sh` — Phase A (front end)

Runs **synchronously in the hook**. Must return in milliseconds.

1. Read hook JSON from stdin → capture `transcript_path`, `session_id`,
   `cwd`, trigger (`stop` / `end`).
2. Fork a **detached background child** that runs Phase B.
3. Redirect child's stdout/stderr to `~/Housekeeping/.todo-events.log`.
4. Parent exits 0 immediately → Claude Code hook unblocked.

---

## 4.2 · `todo-update.sh` — Phase B (worker)

Runs in background. Not on the hook's critical path.

1. `flock -n` on `.todo-update.lock` → exit 0 if held by another session.
2. Throttle: if trigger=`stop` and last update <5 min ago → exit.
   `end` skips this check.
3. Extract last ~50 turns of transcript, capped at ~30 KB.
4. `timeout 60 claude -p --model claude-haiku-4-5-20251001 "<prompt>"`
   with: current TODO + recent activity → updated TODO.
5. Validate output has `# TODO` + the 3 standard headers. If not → skip write.
6. Atomic: `TODO.md.tmp` → `rename` → `TODO.md`.
7. `touch .todo-last-update`; append JSON line to `.todo-events.log`.
8. Release flock (auto on exit).

Any internal error → exit 0. Claude Code is never blocked.

---

## 4.3 · `todo-session-start.sh`

Runs on `SessionStart` in every project.

- Reads `~/Housekeeping/TODO.md`.
- Emits Claude Code `additionalContext` JSON → current TODO visible to the
  session from turn 1.
- If `TODO.md` missing → no context, non-fatal.

---

## 4.4 · Hook config (`~/.claude/settings.json`)

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "~/.claude/todo-session-start.sh" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "~/.claude/todo-update.sh stop" }] }
    ],
    "SessionEnd": [
      { "hooks": [{ "type": "command", "command": "~/.claude/todo-update.sh end" }] }
    ]
  }
}
```

Installer **merges** into existing hooks, never clobbers.

---

## 4.5 · `install.sh` / `uninstall.sh`

`install.sh`:
- Writes the two scripts to `~/.claude/`.
- Patches `~/.claude/settings.json` (merge, not overwrite).
- Creates `TODO.md` from a starter template if absent.
- Runs smoke test before exiting.

`uninstall.sh`:
- Removes hook entries + scripts.
- **Does not** delete `TODO.md` or `.todo-events.log` (user data).

---

## 5 · Data flow (one cycle)

```
User prompts Claude in ~/slides
        ▼
Claude does work
        ▼
Stop hook fires → todo-update.sh (Phase A: fork & return instantly)
        ▼ (child)
flock -n .todo-update.lock
  ├─ busy? → exit 0, retry next Stop
  └─ got it
      ▼
  mtime(.todo-last-update) <5 min?  yes → exit
  no ▼
  read transcript (last 50 turns, 30KB cap)
  timeout 60 claude -p --model haiku
  validate → TODO.md.tmp → rename
  touch .todo-last-update ; log event
  release flock
```

`SessionEnd` = same path, skips throttle → guaranteed final reconciliation.

---

## 6 · Concurrency safety

**Invariant:** at most one updater writes `TODO.md` at a time, machine-wide.

```bash
exec 200>~/Housekeeping/.todo-update.lock
flock -n 200 || exit 0
# critical section: read, reconcile, write
# lock auto-released on exit / kill
```

- `-n` = non-blocking → losing session exits, retries on next Stop.
- Kernel-held locks auto-release on death → no stale-lock recovery logic.
- Parallel sessions both contribute within a few cycles.

---

## 7 · Failure modes

| Failure | Behavior |
|---|---|
| Lock held by other session | Exit 0 silently; next Stop retries; SessionEnd = backstop |
| `claude -p` timeout/error | `timeout 60` kills it; TODO untouched; event logged |
| Malformed model output | Structure check fails; write skipped; event logged |
| Disk full / rename fails | `.tmp` lingers; next run overwrites; TODO.md never partial |
| Clock skew on `.todo-last-update` | Worst case 1 extra / 1 skipped update; self-healing |
| User edits `TODO.md` mid-update | Lock serializes; updater preserves unknown lines |
| Hook misbehaves | Exits 0 on any error; Claude Code never blocked |
| `claude` not on hook `$PATH` | Installer probes; script uses absolute path |

---

## 8 · Testing

Tests live at `~/Housekeeping/tests/`.

- **Golden file** — mock transcript + TODO.md → diff against committed expected output.
- **Lock** — spawn 2 updaters concurrently → assert exactly one wrote.
- **Throttle** — invoke twice in 10 s → 2nd is no-op; `end` trigger bypasses.
- **Malformed output** — stub `claude -p` with garbage → TODO untouched, event logged.
- **Smoke** — real end-to-end run on throwaway file, printed to stdout, auto-run by `install.sh`.

---

## 9 · Cost & performance budget

- **Model:** Haiku 4.5 — fast, cheap. Cents per update.
- **Throttle:** ≥5 min between `Stop`-triggered updates → max ~12/hr machine-wide.
- **Hook latency:** Phase A forks & exits → hook returns well under a second.
  User-facing Claude is never slowed.
- **Hang cap:** `timeout 60` on every `claude -p`.

---

## 10 · Open questions & future work

**None blocking.** Out of scope for now:

- Per-project rollups derived from the central file.
- `todo` CLI for quick view/edit from the terminal.
- Weekly auto-archival of items older than 7 days from `## Done`.

---

## End

Spec lives at: `docs/superpowers/specs/2026-04-23-background-todo-design.md`

View with:  `slides <this-file>`

Next step after approval: invoke `writing-plans` skill for implementation plan.

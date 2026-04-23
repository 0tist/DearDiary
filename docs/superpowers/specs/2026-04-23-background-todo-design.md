# Background Auto-Updating TODO — Design

**Date:** 2026-04-23
**Status:** Approved (pending user review of this written spec)
**Owner:** jayesh@aiatella.com

## 1. Purpose

Maintain a single, always-fresh TODO list at `~/Housekeeping/TODO.md` that is kept in sync automatically by every Claude Code session the user runs — across any project, any working directory — so the user stays grounded on what needs to be done without manually updating a list.

The TODO survives: long-running single sessions, parallel concurrent sessions, short throwaway sessions, and crashes.

## 2. Non-goals

- Task management features (priorities, due dates, dependencies beyond what the markdown expresses).
- Sync to any external system (Linear, Jira, Todoist, etc.).
- Per-project TODOs. One global list is the explicit choice.
- Replacing Claude Code's in-session TaskCreate tooling. This system operates at a higher level (across sessions), not inside one.

## 3. Architecture

Three cooperating pieces, orchestrated by Claude Code hooks registered in the user's global `~/.claude/settings.json` so they fire in every session regardless of project:

```
┌──────────────────────────────────────────────────────────┐
│  Any Claude Code session (slides, AortaAIM, anywhere)    │
└──────────────────────────────────────────────────────────┘
            │ SessionStart             │ Stop / SessionEnd
            ▼                          ▼
  inject current TODO         run update script
  into session context        (throttled + locked)
                                       │
                                       ▼
                          ┌───────────────────────────┐
                          │  ~/Housekeeping/          │
                          │    TODO.md           ← source of truth
                          │    .todo-update.lock │ flock target
                          │    .todo-last-update │ mtime-based throttle
                          │    .todo-events.log  │ debug trail
                          └───────────────────────────┘
```

## 4. Components

### 4.1 `~/Housekeeping/TODO.md`

Human-readable markdown, the single source of truth. Stable section headers so the updater can diff cleanly.

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

Items are tagged `[project]` for multi-project visibility. The user may edit this file manually at any time; the updater preserves unknown content.

### 4.2 `~/.claude/todo-update.sh`

Updater script. Invoked by hooks. Has two phases:

**Phase A — front end (runs synchronously in the hook, must be fast):**

1. Read hook JSON input from stdin, capture `transcript_path`, `session_id`, `cwd`, and the trigger argument (`stop` / `end`).
2. Fork a detached background child that runs Phase B. The parent returns immediately (exit 0) so the Claude Code hook is unblocked within milliseconds. Stdout/stderr of the child are redirected to `~/Housekeeping/.todo-events.log`.

**Phase B — background worker:**

1. Acquire `flock` on `~/Housekeeping/.todo-update.lock` (non-blocking). If not acquired, exit 0.
2. Throttle check: if trigger is `stop` and `mtime(~/Housekeeping/.todo-last-update)` is less than 5 minutes ago, release lock and exit 0. `end` invocations skip this check.
3. Extract the last ~50 turns of the transcript (JSONL), truncated to ~30 KB of text.
4. Run `timeout 60 claude -p --model claude-haiku-4-5-20251001` with a tight prompt: current TODO + recent activity → updated TODO that preserves structure and untouched items.
5. Validate output: must contain `# TODO` header and the three standard section headers (`## Active`, `## Blocked / Waiting`, `## Done (last 7 days)`). On failure, leave `TODO.md` untouched and log the event.
6. Atomic write: `TODO.md.tmp` → `rename` → `TODO.md`.
7. `touch ~/Housekeeping/.todo-last-update`.
8. Append a one-line JSON record to `~/Housekeeping/.todo-events.log` (timestamp, session id, cwd, trigger, result).
9. Release lock (automatic via `flock` on process exit).

Exits 0 on any internal error so Claude Code is never blocked by hook failure.

### 4.3 `~/.claude/todo-session-start.sh`

Runs on `SessionStart`. Reads `~/Housekeeping/TODO.md` and emits Claude Code `additionalContext` JSON so the current TODO is visible to the session from the first turn.

If the file does not exist, emits no context (non-fatal).

### 4.4 Hook configuration (`~/.claude/settings.json`)

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

Installer merges into any existing hook entries rather than clobbering.

### 4.5 `~/Housekeeping/install.sh` and `uninstall.sh`

- `install.sh` writes the two scripts under `~/.claude/`, patches `~/.claude/settings.json` (merging), creates `TODO.md` from a starter template if absent, and runs a smoke test.
- `uninstall.sh` is the inverse: removes the hook entries and the two scripts. Does not delete `TODO.md` or `.todo-events.log` (user data).

## 5. Data flow

```
User prompts Claude in ~/slides
        │
        ▼
Claude does work (edits files, runs commands, etc.)
        │
        ▼
Claude finishes response  ──► Stop hook fires
        │
        ▼
todo-update.sh stop
  ├─ try flock: got it? ──► no: exit 0 (another session updating)
  │                          │
  │                          ▼  (retries next turn)
  └─ got lock: mtime check
      ├─ <5 min since last update? ──► yes: release lock, exit 0
      └─ ≥5 min: proceed
          │
          ▼
     read transcript (last ~50 turns, truncated to ~30KB)
          │
          ▼
     spawn: timeout 60 claude -p --model haiku "<prompt>"
          │
          ▼
     validate output structure
          │
          ▼
     write TODO.md.tmp → rename → TODO.md
          │
          ▼
     touch .todo-last-update
     append event line to .todo-events.log
     release flock (auto on exit)
```

`SessionEnd` follows the same path but skips the mtime check, guaranteeing a final reconciliation.

## 6. Concurrency safety

The central invariant: **at most one updater writes `TODO.md` at a time, across all Claude sessions on the machine.**

Enforced by `flock`:

```bash
exec 200>~/Housekeeping/.todo-update.lock
flock -n 200 || exit 0
# critical section: read, reconcile, write TODO.md
# lock auto-released when script exits or is killed
```

- Non-blocking (`-n`) means contention never queues; instead the losing session exits 0 and retries on its next Stop.
- Kernel-held locks are released automatically on process death, so no stale-lock recovery logic is needed.
- Parallel sessions both contribute over time: within a few hook cycles, both will have been reconciled.

## 7. Failure modes

| Failure | Behavior |
|---|---|
| Lock held by other session | Current hook exits 0 silently; next Stop retries. `SessionEnd` is the backstop. |
| `claude -p` times out or errors | `timeout 60` kills it; updater exits 0; `TODO.md` untouched; event logged. |
| Model returns malformed markdown | Structure check fails; write skipped; event logged. |
| Disk full / rename fails | `.tmp` file lingers; next run overwrites it. `TODO.md` never partially written. |
| Stale `.todo-last-update` from clock skew | Worst case: one extra or one skipped update. Self-healing. |
| User manually edits `TODO.md` mid-update | Lock serializes writes. User's edits survive because the updater preserves unknown lines. |
| Hook misbehaves | All hooks exit 0 on any internal error; Claude Code is never blocked. |
| `claude` CLI not on PATH in hook env | Installer probes for it at install time; script uses an absolute path written at install. |

## 8. Testing

Tests live at `~/Housekeeping/tests/`.

- **Golden-file test:** feed a mock transcript + existing `TODO.md` into the updater; diff output against a committed golden file.
- **Lock test:** spawn two copies of the updater concurrently; assert only one wrote, and the other exited 0.
- **Throttle test:** invoke twice within 10 s; assert the second is a no-op. Then invoke with `end` trigger; assert it bypasses the throttle.
- **Malformed-output test:** stub `claude -p` to return garbage; assert `TODO.md` is untouched and an event is logged.
- **Smoke test:** real end-to-end run against a throwaway `TODO.md`; printed to stdout so the user sees the result before going live. Run automatically at the end of `install.sh`.

## 9. Cost and performance budget

- Model: Haiku 4.5 (fast, cheap). Expected per-update cost: cents.
- Throttle: 5 minutes minimum between `Stop`-triggered updates, so at most ~12 updates/hour per machine regardless of session count.
- Each update is background-spawned — the Stop hook itself returns in well under a second, so user-facing Claude is not slowed.
- `timeout 60` caps worst-case hang.

## 10. Open questions

None blocking. Possible future iterations (not in scope now):
- Per-project TODO rollups derived from the central file.
- A small CLI (`todo`) to view/edit from the terminal without opening the file.
- Weekly automatic archival of completed items older than 7 days.

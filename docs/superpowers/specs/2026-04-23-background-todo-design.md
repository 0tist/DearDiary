---
theme: default
paging: "%d / %d"
---

# Background Auto-Updating TODO

Design spec — 2026-04-23
Owner: jayesh@aiatella.com
Status: implemented (see `docs/superpowers/plans/2026-04-23-background-todo.md`)

---

## 1 · Purpose

Keep a single, always-fresh TODO at `~/Housekeeping/TODO.md` that is
updated automatically by every Claude Code session the user runs —
across any project, any working directory.

Survives: long sessions, parallel sessions, short sessions, crashes.

**The problem this solves.** Claude Code's built-in `TaskCreate` tool is
in-session only: its task list dies with the conversation. A user who
bounces between `slides`, `AortaAIM`, and ten other projects has no
durable, machine-wide record of *what's still on their plate*. They
either maintain a TODO by hand (which rots the moment they forget), or
they don't, and things fall through the cracks. This system makes the
TODO a side-effect of working — every session contributes to it, no
bookkeeping required.

---

## 2 · Non-goals

- **Full task management** (priorities, due dates, dependency graphs)
  — would overlap Linear/Jira and demand a UI. Markdown checkboxes are
  enough for a personal ground-truth.
- **Sync to external systems** (Linear, Jira, Todoist) — adds network
  failure modes and auth surface. The TODO is private, local, and
  plain-text on purpose.
- **Per-project TODOs** — the user wants *one* mental list, not a
  per-repo filing cabinet. Projects are surfaced via `[tags]`, not
  directories. One list reduces scope-switching overhead.
- **Replacing in-session `TaskCreate`** — that tool handles the
  *current turn's* work. This system handles *everything else*.

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

Three pieces, orchestrated by hooks in **global** `~/.claude/settings.json`
so they fire in every session regardless of cwd.

---

## 3b · Why these three hook events

Claude Code fires many hook events (`PreToolUse`, `PostToolUse`,
`UserPromptSubmit`, `Notification`, `Stop`, `SubagentStop`,
`SessionStart`, `SessionEnd`, `PreCompact`). We pick three with
complementary roles:

- **`SessionStart`** — runs once at session launch, before the first
  turn. We use it to *read* the TODO and inject its contents as
  context. Cheap: no write, no lock, no LLM call. Gives every session
  free awareness of outstanding work.
- **`Stop`** — fires at the end of every assistant turn. This is our
  main update cadence. Throttled to ≥5 min apart so long sessions get
  periodic reconciliation without spending tokens every turn.
- **`SessionEnd`** — fires once when the session closes. Bypasses the
  throttle so short sessions (<5 min of work) still produce one
  reconciliation. Acts as a **backstop** that guarantees no work is
  lost to a never-reached-throttle-window session.

Why not `PostToolUse`? Too chatty — fires dozens of times per turn,
adds no signal over `Stop`.

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

**Why three fixed headers.** They're a *parser contract* between the
updater's output validator and Haiku's generation. The script refuses
to write unless all three headers are present in the model's output
— that's how we detect hallucinated responses without running a full
markdown parser. Changing the header names would require updating the
prompt, the validation regex, and the installer template in lock-step.

**Why `[project]` tags.** The alternative is one `##` subsection per
project, but that breaks the "stable three headers" contract when new
projects appear. Tags are orthogonal: items flow freely between Active
/ Blocked / Done without reshuffling the structure.

**Manual edits are sacred.** The prompt explicitly instructs the model
to preserve any line it doesn't recognize. Users can add arbitrary
markdown — notes, links, sub-bullets — and subsequent updates won't
clobber it.

---

## 4.2 · `todo-update.sh` — Phase A (front end)

Runs **synchronously in the hook**. Must return in milliseconds.

1. Read hook JSON from stdin → capture `transcript_path`, `session_id`,
   `cwd`, trigger (`stop` / `end`).
2. Fork a **detached background child** that runs Phase B.
3. Redirect child's stdout/stderr to `~/Housekeeping/.todo-events.log`.
4. Parent exits 0 immediately → Claude Code hook unblocked.

**The detachment recipe (and why each piece matters):**

```bash
(
    TODO_UPDATE_PHASE=B \
    HOOK_SESSION_ID="$session_id" ... \
    "$0" "$TRIGGER" >>"$EVENT_LOG" 2>&1
) </dev/null &
disown 2>/dev/null || true
exit 0
```

- `( … )` — subshell, isolates env-var scope from the parent.
- `&` — runs the subshell in the background; shell does not wait.
- `</dev/null` — detaches stdin so the child can't be blocked on a
  closed pipe from the parent.
- `>>$EVENT_LOG 2>&1` — sends all child output to the log file; no
  pipe back to Claude Code to keep alive.
- `disown` — removes the job from the shell's job table so it won't
  receive `SIGHUP` when the parent exits.

**Why this must be fast.** Claude Code imposes a hook-execution time
budget (documented in the SDK). A hook that exceeds it gets killed and
may surface as an error to the user. Fork-and-return gives us an
effectively unbounded work budget in Phase B without ever tripping the
hook timeout.

---

## 4.2 · `todo-update.sh` — Phase B (worker)

Runs in background. Not on the hook's critical path.

1. `flock -n` on `.todo-update.lock` → exit 0 if held by another session.
2. Throttle: if trigger=`stop` and `.todo-last-update` mtime <5 min → exit.
   `end` skips this check.
3. Extract last ~50 turns of transcript, capped at ~30 KB.
4. `timeout 60 claude -p --model claude-haiku-4-5-20251001 "<prompt>"`.
5. Validate output has `# TODO` + the 3 standard headers. If not → skip write.
6. Atomic: `TODO.md.tmp` → `rename` → `TODO.md`.
7. `touch .todo-last-update`; append JSON line to `.todo-events.log`.
8. Release flock (auto on exit).

Any internal error → exit 0. Claude Code is never blocked.

---

## 4.2b · Phase B — step-by-step mechanics

**`flock -n`.** POSIX advisory file lock, non-blocking. "Advisory"
means the kernel enforces it only among processes that *also* call
`flock` on the same FD — it doesn't prevent arbitrary reads/writes.
That's fine: every writer here goes through this script.

**mtime-based throttle.** `stat -c %Y .todo-last-update` returns the
file's last-modified Unix timestamp. Subtract from `date +%s`, compare
to 300. Simple, survives reboots, no external clock needed. Cost of a
false-negative is one extra LLM call; cost of a false-positive is a
5-minute-delayed update. Both self-heal.

**Transcript format.** Claude Code writes each turn as one JSON object
per line in a `.jsonl` file at `~/.claude/projects/<slug>/*.jsonl`.
Fields include `type` (`user`/`assistant`), `message.content`, tool
uses, etc. We take the last 50 lines and cap at 30 KB — enough
context to infer TODO changes, small enough to keep prompt tokens (and
thus cost, latency) bounded.

**`claude -p` = headless mode.** `-p "<prompt>"` runs one-shot: sends
the prompt, prints the response to stdout, exits. No TUI, no session
state. Perfect for scripting. `--model claude-haiku-4-5-20251001` pins
a cheap, fast model (see §9).

**Structural validation as trust anchor.** Four `grep -q` checks
(`^# TODO`, `^## Active`, `^## Blocked / Waiting`, `^## Done (last 7
days)`) before the write. The model occasionally hallucinates
(refuses, adds code fences, drops a section). Validation catches these
cheaply; we skip the write and log `malformed_output` rather than
corrupt the file.

**Atomic rename.** `mv tmp final` on the same filesystem invokes
`rename(2)`, which POSIX guarantees is atomic: at any instant, readers
see either the old file or the new one, never a torn half-written
state. This means a crash mid-update can't leave TODO.md corrupted —
it's either the pre-update content or the post-update content.

---

## 4.3 · `todo-session-start.sh`

Runs on `SessionStart` in every project.

- Reads `~/Housekeeping/TODO.md`.
- Emits Claude Code `additionalContext` JSON → current TODO visible to
  the session from turn 1.
- If `TODO.md` missing → no context, non-fatal.

**What `additionalContext` actually does.** Claude Code's SessionStart
hook protocol accepts a JSON response of shape
`{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"<text>"}}`.
The `<text>` is prepended to the conversation as effectively a system
message before the first user turn — the model sees the TODO, the user
doesn't have to paste it in. Zero-cost awareness: each new session
knows what's pending without the user restating anything.

We JSON-escape the TODO via Python's `json.dumps` so embedded quotes,
newlines, and backslashes don't break the output.

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

**Shape.** `hooks` is a map of *event name* → list of *matcher
entries*. Each matcher has its own `hooks` array of actual handlers
(`{type, command}`). Events can have multiple matchers (e.g., to fire
different commands for different tool names in `PreToolUse`); we use
one matcher per event with one command each.

**`type: "command"`** — the only handler type we use; Claude Code
spawns a subprocess running `command` with hook JSON on stdin.
`type: "mcp"` also exists for MCP-backed handlers; out of scope here.

**Tilde expansion.** `~` in the command string is expanded by Claude
Code's shell invocation, so the same config works across users.

**Installer merges, never clobbers.** The installer walks the existing
`hooks` map, checks for a handler whose `command` already equals ours,
and appends only if absent. Running `install.sh` twice produces the
same config as running it once — safe to re-run after upgrades.

---

## 4.5 · `install.sh` / `uninstall.sh`

`install.sh`:
- Symlinks `todo-update.sh` and `todo-session-start.sh` into `~/.claude/`.
- Patches `~/.claude/settings.json` (merge, not overwrite).
- Creates `TODO.md` from a starter template if absent.
- Runs smoke test before exiting.

`uninstall.sh`:
- Removes hook entries + symlinks.
- **Does not** delete `TODO.md` or `.todo-events.log` (user data).

**Python over `jq` for JSON merge.** `jq` is common but not universal;
Python 3 is essentially guaranteed on any modern Linux. The merge
script is ~30 lines of Python, preserves unknown top-level keys
byte-for-byte, and gives us proper `JSONDecodeError` handling when the
user's existing `settings.json` is malformed.

**Symlinks over copies.** Editing a script in the repo takes effect
immediately on the next hook fire — no re-install needed. The tradeoff
is that deleting the repo breaks the hooks; that's a feature
(`uninstall.sh` is the right way to remove them anyway).

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

## 5b · Parallel-sessions scenario

```
                 Session A                         Session B
Turn ends    │   Stop hook fires                  (busy mid-turn)
             │   Phase A: fork child              …
             │   Phase A: exit 0
             │   Phase B: flock OK ✓
             │   ├─ read transcript
             │                                    Turn ends
             │                                    Stop hook fires
             │                                    Phase A: fork child
             │                                    Phase A: exit 0
             │                                    Phase B: flock FAILS ✗
             │                                    log "lock_held", exit 0
             │   ├─ claude -p
             │   ├─ validate + atomic write
             │   └─ release flock
             ▼                                    ▼
```

**Key invariants under contention:**
- Both hooks return instantly; neither user-visible Claude is blocked.
- Exactly one write occurs; B's attempted update is deferred, not lost.
- B's *next* Stop will see an unstale `.todo-last-update` (A just
  touched it) and throttle-skip, which is correct: B's context has
  already been partly reflected through the cumulative transcripts
  both sessions write.

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

## 6b · `flock` deep dive

**Advisory vs. mandatory locking.** POSIX file locks on Linux are
*advisory*: they only block other processes that also call `flock` (or
`fcntl(F_SETLK)`) on the same FD. They do **not** prevent arbitrary
reads/writes. Mandatory locking exists on Linux but requires a special
mount option (`-o mand`) and is effectively deprecated. Advisory is
the right choice because every writer to `TODO.md` goes through our
script — nobody else needs to coordinate.

**FD-bound lifetime.** The lock is associated with the *open file
description* behind the FD, not the file itself or the process. This
is why we open the lock file with `exec 200>LOCK_FILE` first: we need
a persistent FD whose lifetime matches the shell process. When the
process exits (normally, via signal, or via kernel OOM), the kernel
closes FD 200 and releases the lock automatically. **No stale-lock
recovery code needed.** No `kill -0 PID` checks. No timeouts. The
kernel handles it.

**Why `-n` (non-blocking) + skip-and-retry, not `-w` (wait).** With
`flock -w 10` the losing session would queue for up to 10 s. For this
workload that's pure overhead: we fire on *every* `Stop`, so "wait 10
s" is dominated by "next Stop fires in ~30 s anyway". Queuing also
increases tail-latency for Phase B, which can't end until the queue
drains. Skip-and-retry is cheaper and self-correcting.

**Why not PID-file locks.** A classic `if [ -f pidfile ]; then … fi`
scheme has a race (TOCTOU) and can't detect a process that died
without cleanup. You end up writing heuristics like "if mtime > 60s,
assume stale" — brittle, and we'd reinvent kernel `flock` badly.

---

## 7 · Failure modes

**Design philosophy:** silent degradation beats visible failure. A
background hook that *breaks* a user-facing Claude session is strictly
worse than one that silently skips an update — the user can always
`cat TODO.md` manually, but can't recover a turn that crashed.

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

**`PATH`-shim stubbing.** Every test builds a fake `claude` binary in
a tmp dir (e.g. `$tmp/bin/claude`), writes a tiny shell script that
`cat`s a fixture file, and prepends that dir to `$PATH`. The updater
invokes `claude -p` normally; our shim answers before the real binary
is ever hit.

This verifies **our script's I/O orchestration** — lock handling,
throttle math, prompt assembly, output validation, atomic write — in
isolation from the actual model. Things this does *not* test:
regression of Haiku's behavior (we'd need real API calls), network
flakiness, the real transcript format drift. Those are caught
empirically by the smoke test + `.todo-events.log` monitoring.

---

## 9 · Cost & performance budget

- **Model:** Haiku 4.5. Pricing (list, ~Apr 2026): ~$1/MTok input,
  ~$5/MTok output.
- **Prompt size:** template (~30 lines) + current TODO (~1–2 KB) +
  transcript (capped at 30 KB). Worst case ≈ 8 KTok input per call.
- **Output size:** the new TODO, typically <1 KTok.
- **Per-update cost:** ~$0.008 input + $0.005 output ≈ **~1.3¢**. The
  "cents per update" figure.
- **Throttle budget:** ≥5 min between `Stop` updates → max 12/hr →
  max ~$0.16/hr of active sessions. Machine-wide ceiling.
- **Hook latency:** Phase A forks & exits → observed <100 ms in
  `.todo-events.log` timestamps. Phase B takes 2–15 s depending on
  Haiku response time, entirely off the user's critical path.
- **Hang cap:** `timeout 60` on every `claude -p`. Even if the API
  stalls, Phase B exits in ≤60 s and the lock releases.
- **Prompt cache.** The template + stable parts of TODO.md hit the
  5-min Anthropic prompt cache on back-to-back updates, cutting input
  cost ~90% on the second call within the window. The 5-min throttle
  is deliberately aligned with this cache TTL.

---

## 10 · Key design decisions

| Decision | Alternative considered | Why we chose this |
|---|---|---|
| **One global TODO** | Per-project TODOs | User wants one mental list; projects become `[tags]`, not directories. |
| **Detached fork in hook** | Inline synchronous work | Claude Code kills slow hooks; fork gives us unbounded Phase B runtime. |
| **Stop + SessionEnd** | Stop only | SessionEnd is the backstop that bypasses the throttle — guarantees short sessions still reconcile. |
| **`flock` (kernel)** | PID-file lock + stale detection | No stale-lock logic; kernel releases on death; correct under every failure mode. |
| **Haiku 4.5** | Sonnet 4.6 | 5× cheaper, 3× faster; reconciliation is a structured task where the capability delta is invisible. |
| **Structural validation** | Trust model output | Catches hallucinations/refusals/code-fence wrapping for free; 4 greps, no parser. |
| **Symlinks into `~/.claude/`** | Copy scripts | Edit-in-repo workflow; uninstall cleanly removes only the links. |
| **Python over `jq`** | `jq` for JSON merge | Python 3 is universal; gives proper error handling on malformed `settings.json`. |
| **5-min throttle** | Per-turn updates | Matches Anthropic's 5-min prompt cache TTL; max 12 updates/hr machine-wide. |

---

## 11 · Open questions & future work

**One real constraint surfaced during deployment:** Claude Code
registers hooks **at session startup** by reading `settings.json`
once. Sessions that were already running when `install.sh` ran do
*not* pick up the new hooks. They need to be restarted (or, in some
configurations, may re-read settings mid-session — not reliable). This
means "install and forget" has a blind-spot window for pre-existing
sessions. A future enhancement could ship a small SIGHUP listener or
polling reload, but that adds surface area for little gain: users
restart sessions often enough.

**Out of scope for now:**
- Per-project rollups derived from the central file.
- `todo` CLI alias / `todo-slides` viewer (implemented post-hoc).
- Weekly auto-archival of items older than 7 days from `## Done`.
- Tracking time spent per item (would require parsing turn timestamps).

---

## End

Spec lives at: `docs/superpowers/specs/2026-04-23-background-todo-design.md`

View with:  `slides <this-file>`  ·  `todo-slides` for the live TODO

Implementation: `docs/superpowers/plans/2026-04-23-background-todo.md`
(executed 2026-04-23, merged to main as commit `f00d5f2`).

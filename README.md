# DearDiary

A frictionless personal capture surface backed by a Claude-driven router
and a small fleet of skills. Type a thought into the Dock window; the
right thing happens to it.

The data directory `~/DearDiary/` doubles as an Obsidian folder-vault —
notes are plain markdown, the structure is self-describing, and every
file is readable with or without DearDiary running.

---

## What it does, end-to-end

```
You type into the Dock window     ──►  diary/inbox/<id>.md
                                       │
                                       ▼
                              diary-process.sh
                              (cron every 15 min,
                               or "Process Now" button)
                                       │
                                       ▼
                              claude -p (headless)
                                       │
                              ┌────────┴────────┐
                              ▼                 ▼
                    Ideas/   Projects/      Decisions/
                    Daily/   Research/      processed/  (audit)
                                       │
                                       ▼
                              (skills may fire:
                               idea-evaluator,
                               decision-logger,
                               deardiary-fixer)
```

Twice a week (Wed + Sun, 02:00), a second cron runs over the whole vault:

- **Reconcile** — finds contradictions across `Decisions/`, `Projects/`,
  `Ideas/`, `Research/`; marks the older note `status: superseded` with
  a link forward + an `## Updates` section. Never deletes anything.
- **Synthesize** — scans the last 7 days for recurring patterns; writes
  at most one synthesis note to `Synthesis/<date>-<topic>.md` when a
  pattern crosses the significance threshold. Absence of pattern is a
  valid outcome.

Every new Claude Code session (anywhere on your machine) gets two files
auto-injected as `additionalContext`:

- **`~/DearDiary/_WORLD.md`** — your identity primer (who you are,
  values, active long-running projects, preferences for how Claude
  should respond).
- **`~/DearDiary/TODO.md`** — your auto-maintained TODO list.

So sessions don't start blind.

---

## Skills

All skills live under `claude/<name>/SKILL.md`, are symlinked into
`~/.claude/skills/` by `install.sh`, and follow the same shape as the
[`learning-finnish`](claude/learning-finnish/SKILL.md) skill.

The diary processor's prompt is built at runtime by concatenating every
`SKILL.md` under `claude/` — drop a new directory in and the next cron
tick picks it up. The skill's own description decides when it fires.

### Automatic — fire during diary processing per entry

| Skill | Triggers on | What it does |
|---|---|---|
| [`idea-evaluator`](claude/idea-evaluator/SKILL.md) | Entry routed to `Ideas/` | Appends `## Estimate` (Cost / Effort / Potential) |
| [`decision-logger`](claude/decision-logger/SKILL.md) | Entry describes a commitment ("decided", "going with", "settling on") | Files to `Decisions/` with ADR-lite shape (Decision / Context / Rationale / Consequences / Source) |
| [`deardiary-fixer`](claude/deardiary-fixer/SKILL.md) | Entry describes a task for THIS repo | Branches from `main` as `diary-fix/<slug>`, makes the change, opens a PR via `gh` for you to review. Never pushes to `main`. |

### On-demand — you ask in chat

| Skill | Ask | What it does |
|---|---|---|
| [`vault-health`](claude/vault-health/SKILL.md) | "audit my vault", "what's stale" | Read-only scan; surfaces inbox backlog, orphans, stale frontmatter, broken wikilinks, lowercase folders, contradictions |
| [`recap`](claude/recap/SKILL.md) | "recap this week", "summarize last month" | Reads vault by date; groups by folder; surfaces recurring entities and open questions. Optional save to `Daily/`. |
| [`challenge`](claude/challenge/SKILL.md) | "challenge this", "argue against", "red-team this" + a proposal | Pulls past failures / reversed decisions from the vault; pushes back with your own words |
| [`emerge`](claude/emerge/SKILL.md) | "what patterns are emerging", "what's on my mind" | Scans last 30 days for recurring entities/themes/questions. Reports above a significance threshold; says "nothing emerged" honestly when there's no signal. |
| [`graduate`](claude/graduate/SKILL.md) | "graduate this idea", "let's actually do this" | Promotes `Ideas/<id>.md` to `Projects/<title>.md` with Goal / Context / Phases / Open Questions. Updates the source with `status: graduated`. Appends a kickoff TODO. |

### Ambient — runs in conversation, not in notes

| Skill | What it does |
|---|---|
| [`learning-finnish`](claude/learning-finnish/SKILL.md) | Layers light, glossed Finnish into casual conversational moments. Never enters notes or load-bearing content. |

---

## Note format

Every note the diary processor writes follows the AI-first convention
(notes for future-Claude retrieval, not human reading):

```yaml
---
type: idea | project | decision | daily | research | note
date: 2026-05-11T19:42:00+03:00
tags: [short, lowercase]
ai-first: true
routed_to: Ideas        # which canonical folder
confidence: low|medium|high   # only when entry makes uncertain claims
---

## For future Claude

<2–3 lines: what this note is for retrieval, key claim, links>

<the user's text, preserved verbatim>

<external claims get recency markers: (as of YYYY-MM-DD) or
 (source: <url>, accessed YYYY-MM-DD)>

[[wikilinks]] for every person/project/concept referenced.
```

Canonical folders: `Ideas/`, `Projects/`, `Decisions/`, `Daily/`,
`Research/`. New PascalCase folders allowed when nothing fits.

The vault-level operating manual at `~/DearDiary/_CLAUDE.md` is the
authoritative reference; any Claude session entering `~/DearDiary/`
reads it first.

---

## Audit trail

- `~/DearDiary/diary/processed/` — every captured entry, preserved as
  originally written (no frontmatter changes). Append-only.
- `~/DearDiary/.diary-events.log` — JSONL log of every cron tick
  (processor and maintenance). One line per run; includes trigger,
  result, count, summary detail.
- `~/DearDiary/.diary-process.{stdout,stderr}` — launchd capture for the
  inbox processor.
- `~/DearDiary/.diary-maintain.{stdout,stderr}` — launchd capture for
  the Wed/Sun maintenance job.

---

## Components

### Tauri compose window (`app/`)

Always-open Dock app. Textarea + Save + Process Now. Closing hides
(keeps app live in the Dock); Cmd+Q quits.

- Build: see [`app/README.md`](app/README.md)
- Saves to `~/DearDiary/diary/inbox/<id>.md` atomically
- "Process Now" shells out to `scripts/diary-process.sh button`

### Inbox processor (`scripts/diary-process.sh`)

Phase A/B pattern with atomic `mkdir` locking. Builds a prompt from the
inbox listing + workspace tree + every installed `SKILL.md`, pipes to
`claude -p` with a scoped tool allowlist.

- launchd job: `com.deardiary.process` — every 900s (15 min)
- Routing prompt: [`scripts/lib/diary-prompt.txt`](scripts/lib/diary-prompt.txt)

### Vault maintenance (`scripts/diary-maintain.sh`)

Same Phase A/B pattern, shares the lock with `diary-process.sh` so they
can't race. Runs reconcile + synthesize in one `claude -p` invocation.

- launchd job: `com.deardiary.maintain` — Wed + Sun at 02:00 local
- Manual trigger: `bash scripts/diary-maintain.sh button`
- Maintenance prompt: [`scripts/lib/diary-maintain-prompt.txt`](scripts/lib/diary-maintain-prompt.txt)

### Background auto-TODO

Predates everything else. Global hooks (`SessionStart`, `Stop`,
`SessionEnd`) keep `~/DearDiary/TODO.md` in sync with conversation
activity via throttled Haiku updates. Time-throttled to 5 min between
Stop hooks so it doesn't thrash.

- Hook script: [`scripts/todo-update.sh`](scripts/todo-update.sh)
- SessionStart injector: [`scripts/todo-session-start.sh`](scripts/todo-session-start.sh)
  (also injects `_WORLD.md` if present)

### Global Claude rules (`claude/CLAUDE.md`)

Installed as a symlink at `~/.claude/CLAUDE.md`. Sets repo-wide
conventions for plan files (presenterm slideshow format, pre-rendered
ASCII diagrams, `<!-- comment slides: true -->` marker for tight-cap
mode) and points at the `learning-finnish` skill.

---

## Install / Uninstall

```bash
bash install.sh
```

That:
- Symlinks the auto-TODO hook scripts into `~/.claude/`
- Merges hook entries into `~/.claude/settings.json`
- Symlinks every `claude/<skill>/` into `~/.claude/skills/`
- Symlinks `claude/CLAUDE.md` into `~/.claude/CLAUDE.md`
- Creates `~/DearDiary/diary/{inbox,processed}/`
- Registers both launchd jobs (`com.deardiary.process` and
  `com.deardiary.maintain`)
- Prints next steps for building the Tauri GUI

```bash
bash uninstall.sh
```

Reverses everything except user data — `~/DearDiary/` is preserved.

---

## Tests

```bash
bash tests/run.sh
```

18 files, 127 assertions as of the last commit. Bash 3.2 compatible
(macOS default). Uses fake `claude` binaries via
[`tests/lib.sh`](tests/lib.sh) helpers.

---

## Slideshow viewer for `TODO.md` (`todo`)

```bash
todo             # alias → todo-presenterm
todo-presenterm  # same thing; pass a path to view a different md file
```

`todo-presenterm` shells out to `presenterm`. Set `PRESENTERM_THEME=dark`
or `PRESENTERM_IMAGE_PROTOCOL=ascii-blocks` to override defaults.

The `todo` alias installs via `~/.bashrc.d/deardiary-aliases.sh` — a
symlink into [`shell/deardiary-aliases.sh`](shell/deardiary-aliases.sh).

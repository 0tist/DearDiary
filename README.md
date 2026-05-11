# DearDiary

Central home for background skills, hooks, and shared workflows that keep
my Claude Code sessions honest.

## Components

### Background auto-updating TODO

A single TODO list at `~/DearDiary/TODO.md` kept fresh by every Claude
Code session I run — via global hooks (`SessionStart`, `Stop`, `SessionEnd`)
with flock-based concurrency control and time-throttled Haiku updates.

Spec: `docs/superpowers/specs/2026-04-23-background-todo-design.md`
Plan: `docs/superpowers/plans/2026-04-23-background-todo.md`

**Install:**

```bash
bash install.sh
```

**Uninstall:**

```bash
bash uninstall.sh
```

**View the spec as a presenterm slideshow:**

```bash
presenterm docs/superpowers/specs/2026-04-23-background-todo-design.md
```

**View TODO.md as a presenterm slideshow** (one slide per `## ` section):

```bash
todo             # alias → todo-presenterm
todo-presenterm  # same thing; pass a path to view a different md file
```

The `todo` alias is installed via `~/.bashrc.d/deardiary-aliases.sh`
(a symlink into `shell/deardiary-aliases.sh` in this repo).

`todo-presenterm` shells out to `presenterm`. Set `PRESENTERM_THEME=dark`
or `PRESENTERM_IMAGE_PROTOCOL=ascii-blocks` to override defaults.
Mermaid code blocks render natively in presenterm via the `mmdc` we
already have installed.

### Using with obsidian-second-brain

`~/DearDiary/` doubles as an Obsidian folder-vault. Pair it with
[`obsidian-second-brain`](https://github.com/eugeniughelbur/obsidian-second-brain)
(a 31-command Claude Code skill that runs nightly agents to rewrite, reconcile,
and synthesize the vault) to turn DearDiary's frictionless capture into a
self-maintaining second brain.

Setup (one-time):

```bash
# 1. Install obsidian-second-brain in its own location
git clone https://github.com/eugeniughelbur/obsidian-second-brain \
    ~/src/obsidian-second-brain
cd ~/src/obsidian-second-brain && bash install.sh

# 2. Configure its vault path to ~/DearDiary/ (per its docs)

# 3. Initialize the vault from a Claude Code session in ~/DearDiary/
cd ~/DearDiary && claude
> /obsidian-init
```

Day-to-day: nothing changes. DearDiary captures and files into the canonical
folders (`Ideas/`, `Projects/`, `People/`, `Decisions/`, `Daily/`, `Research/`)
with AI-first frontmatter; obsidian-second-brain's nightly agents pick the
new files up and rewrite vault pages accordingly. The two systems share a
filesystem path and run on independent schedules — no bridge daemon, no IPC.

See `scripts/lib/diary-prompt.txt` and `claude/CLAUDE.md` for the routing
rules that keep the diary processor's output compatible.

### Diary skills

Two installable skills that extend the diary processor's default routing.
Both live under `claude/<name>/SKILL.md`, are symlinked to `~/.claude/skills/`
by `install.sh`, and are auto-discovered by `scripts/diary-process.sh` at
prompt-build time (every `SKILL.md` under `claude/` is concatenated into the
prompt — drop a new directory in to add a third skill).

- [`deardiary-fixer`](claude/deardiary-fixer/SKILL.md) — when a diary entry
  describes a task for this repo, makes the change on a `diary-fix/<…>`
  branch and opens a PR via `gh` for you to review. Never pushes to `main`.
- [`idea-evaluator`](claude/idea-evaluator/SKILL.md) — when an entry is
  routed to `ideas/`, appends a structured `## Estimate` section
  (Cost / Effort / Potential) so you can triage at a glance.

### Diary GUI (Tauri)

A small always-open compose window that drops thoughts into
`~/DearDiary/diary/inbox/`. Every 15 minutes (or on-demand via the
**Process Now** button), `scripts/diary-process.sh` hands the inbox to a
headless `claude -p` run that decides — open-endedly — where each entry
belongs. Closing the window hides it (keeps the app live in the Dock).

- Build: see [`app/README.md`](app/README.md)
- launchd job: `com.deardiary.process` (registered by `install.sh`, every 900s)
- Processor script: [`scripts/diary-process.sh`](scripts/diary-process.sh)
- Routing prompt: [`scripts/lib/diary-prompt.txt`](scripts/lib/diary-prompt.txt)

### Claude default rules

`claude/CLAUDE.md` ships global rules for Claude Code sessions —
currently: plan files (`~/.claude/plans/*.md`) use `---` between
sections and Mermaid for diagrams, and tighten to ≤100-word slides
when the plan is tagged with `slides: true` frontmatter. Installed
as a symlink at `~/.claude/CLAUDE.md`.

## Tests

```bash
bash tests/run.sh
```

# Housekeeping

Central home for background skills, hooks, and shared workflows that keep
my Claude Code sessions honest.

## Components

### Background auto-updating TODO

A single TODO list at `~/Housekeeping/TODO.md` kept fresh by every Claude
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

The `todo` alias is installed via `~/.bashrc.d/housekeeping-aliases.sh`
(a symlink into `shell/housekeeping-aliases.sh` in this repo).

`todo-presenterm` shells out to `presenterm`. Set `PRESENTERM_THEME=dark`
or `PRESENTERM_IMAGE_PROTOCOL=ascii-blocks` to override defaults.
Mermaid code blocks render natively in presenterm via the `mmdc` we
already have installed.

## Tests

```bash
bash tests/run.sh
```

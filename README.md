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

**View the spec as slides:**

```bash
slides docs/superpowers/specs/2026-04-23-background-todo-design.md
```

## Tests

```bash
bash tests/run.sh
```

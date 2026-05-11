#!/usr/bin/env bash
# Inverse of install.sh. Removes the three hook entries and the two symlinks.
# Does NOT delete TODO.md or .todo-events.log — that's user data.

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

echo "==> Uninstalling auto-TODO hooks"

# Remove hook symlinks (only if they point at our scripts)
for s in todo-update.sh todo-session-start.sh; do
    target="$CLAUDE_DIR/$s"
    if [ -L "$target" ]; then
        rm -f "$target"
        echo "    removed symlink $target"
    elif [ -e "$target" ]; then
        echo "    WARNING: $target exists and is not a symlink — leaving in place"
    fi
done

# Remove user-facing CLI helper symlinks
LOCAL_BIN="$HOME/.local/bin"
for name in todo-presenterm todo-slides; do  # remove legacy todo-slides too on upgrade
    target="$LOCAL_BIN/$name"
    if [ -L "$target" ]; then
        rm -f "$target"
        echo "    removed symlink $target"
    fi
done

# Remove shell alias symlink
BASHRC_D="$HOME/.bashrc.d"
target="$BASHRC_D/deardiary-aliases.sh"
if [ -L "$target" ]; then
    rm -f "$target"
    echo "    removed symlink $target"
fi

# Remove global Claude rules symlink (only if it points at our file)
target="$CLAUDE_DIR/CLAUDE.md"
if [ -L "$target" ]; then
    rm -f "$target"
    echo "    removed symlink $target"
elif [ -e "$target" ]; then
    echo "    WARNING: $target exists and is not a symlink — leaving in place"
fi

# Remove skill symlinks (only if they point at our directories)
SKILLS_DIR="$CLAUDE_DIR/skills"
for skill in learning-finnish deardiary-fixer idea-evaluator; do
    target="$SKILLS_DIR/$skill"
    if [ -L "$target" ]; then
        rm -f "$target"
        echo "    removed symlink $target"
    elif [ -e "$target" ]; then
        echo "    WARNING: $target exists and is not a symlink — leaving in place"
    fi
done
if [ -d "$SKILLS_DIR" ] && [ -z "$(ls -A "$SKILLS_DIR" 2>/dev/null)" ]; then
    rmdir "$SKILLS_DIR"
fi

# Strip hook entries
if [ -f "$SETTINGS" ]; then
    python3 - "$SETTINGS" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)

targets = {
    "SessionStart": "~/.claude/todo-session-start.sh",
    "Stop":         "~/.claude/todo-update.sh stop",
    "SessionEnd":   "~/.claude/todo-update.sh end",
}

hooks = data.get("hooks", {})
for event, cmd in targets.items():
    if event not in hooks:
        continue
    filtered = []
    for entry in hooks[event]:
        kept = [h for h in entry.get("hooks", []) if h.get("command") != cmd]
        if kept:
            entry["hooks"] = kept
            filtered.append(entry)
    if filtered:
        hooks[event] = filtered
    else:
        del hooks[event]

if not hooks:
    data.pop("hooks", None)

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(f"    cleaned hook entries from {path}")
PY
else
    echo "    no settings.json found — nothing to clean"
fi

# Unregister and remove the diary-processor launchd plist.
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS/com.deardiary.process.plist"
if [ -f "$PLIST_PATH" ]; then
    if command -v launchctl >/dev/null 2>&1; then
        launchctl bootout "gui/$(id -u)/com.deardiary.process" 2>/dev/null || \
            launchctl unload "$PLIST_PATH" 2>/dev/null || true
        echo "    unregistered launchd job com.deardiary.process"
    fi
    rm -f "$PLIST_PATH"
    echo "    removed $PLIST_PATH"
fi

echo "==> Done. TODO.md, .todo-events.log, and ~/DearDiary/diary/ preserved."

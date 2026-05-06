#!/usr/bin/env bash
# Install the auto-TODO system:
#   1. Symlink scripts into ~/.claude/
#   2. Merge hook entries into ~/.claude/settings.json
#   3. Seed TODO.md from template if absent
#   4. Run smoke test

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
TODO_FILE="$REPO_DIR/TODO.md"

echo "==> Installing from $REPO_DIR"
mkdir -p "$CLAUDE_DIR"

# 1. Symlink hook scripts into ~/.claude/
for s in todo-update.sh todo-session-start.sh; do
    src="$REPO_DIR/scripts/$s"
    dst="$CLAUDE_DIR/$s"
    if [ ! -x "$src" ]; then
        chmod +x "$src"
    fi
    ln -sfn "$src" "$dst"
    echo "    linked $dst -> $src"
done

# 1b. Symlink user-facing CLI helpers into ~/.local/bin/
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"
for pair in "todo-presenterm.sh:todo-presenterm"; do
    src="$REPO_DIR/scripts/${pair%%:*}"
    dst="$LOCAL_BIN/${pair##*:}"
    [ -x "$src" ] || chmod +x "$src"
    ln -sfn "$src" "$dst"
    echo "    linked $dst -> $src"
done

# 1c. Symlink shell aliases into ~/.bashrc.d/ (sourced by ~/.bashrc)
BASHRC_D="$HOME/.bashrc.d"
mkdir -p "$BASHRC_D"
ln -sfn "$REPO_DIR/shell/housekeeping-aliases.sh" "$BASHRC_D/housekeeping-aliases.sh"
echo "    linked $BASHRC_D/housekeeping-aliases.sh -> $REPO_DIR/shell/housekeeping-aliases.sh"

# 2. Merge settings.json
python3 - "$SETTINGS" <<'PY'
import json, os, sys
path = sys.argv[1]
existing = {}
if os.path.exists(path):
    with open(path) as f:
        try:
            existing = json.load(f)
        except json.JSONDecodeError:
            print(f"ERROR: {path} is not valid JSON; aborting merge", file=sys.stderr)
            sys.exit(1)

hooks = existing.setdefault("hooks", {})

def add_hook(event, command):
    entries = hooks.setdefault(event, [])
    # Skip if this exact command is already present
    for entry in entries:
        for h in entry.get("hooks", []):
            if h.get("command") == command:
                return
    entries.append({"hooks": [{"type": "command", "command": command}]})

add_hook("SessionStart", "~/.claude/todo-session-start.sh")
add_hook("Stop",         "~/.claude/todo-update.sh stop")
add_hook("SessionEnd",   "~/.claude/todo-update.sh end")

with open(path, "w") as f:
    json.dump(existing, f, indent=2)
    f.write("\n")
print(f"    merged hooks into {path}")
PY

# 3. Seed TODO.md
if [ ! -f "$TODO_FILE" ]; then
    cp "$REPO_DIR/TODO.md.template" "$TODO_FILE"
    echo "    seeded $TODO_FILE"
else
    echo "    $TODO_FILE already exists (left alone)"
fi

# 4. Smoke test — one full Phase B cycle against a throwaway dir
echo "==> Smoke test"
tmp=$(mktemp -d)
trap "rm -rf '$tmp'" EXIT
cp "$REPO_DIR/TODO.md.template" "$tmp/TODO.md"
HOUSEKEEPING_DIR="$tmp" \
HOOK_SESSION_ID="install-smoke" \
HOOK_CWD="$PWD" \
TODO_UPDATE_PHASE=B \
"$REPO_DIR/scripts/todo-update.sh" end || echo "    smoke test exited non-zero (may be OK if claude CLI unavailable in this shell)"

if [ -f "$tmp/.todo-events.log" ]; then
    echo "--- last smoke event ---"
    tail -n 1 "$tmp/.todo-events.log"
fi

echo
echo "==> Done. Hooks active in future Claude Code sessions."
echo "    TODO file: $TODO_FILE"
echo "    Event log: $REPO_DIR/.todo-events.log"

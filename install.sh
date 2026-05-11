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
ln -sfn "$REPO_DIR/shell/deardiary-aliases.sh" "$BASHRC_D/deardiary-aliases.sh"
echo "    linked $BASHRC_D/deardiary-aliases.sh -> $REPO_DIR/shell/deardiary-aliases.sh"

# 1d. Symlink global Claude rules into ~/.claude/CLAUDE.md
GLOBAL_RULES="$CLAUDE_DIR/CLAUDE.md"
if [ -e "$GLOBAL_RULES" ] && [ ! -L "$GLOBAL_RULES" ]; then
    backup="$GLOBAL_RULES.pre-deardiary-install-backup"
    mv "$GLOBAL_RULES" "$backup"
    echo "    backed up existing $GLOBAL_RULES -> $backup"
fi
ln -sfn "$REPO_DIR/claude/CLAUDE.md" "$GLOBAL_RULES"
echo "    linked $GLOBAL_RULES -> $REPO_DIR/claude/CLAUDE.md"

# 1e. Symlink skills directories into ~/.claude/skills/<name>/
SKILLS_DIR="$CLAUDE_DIR/skills"
mkdir -p "$SKILLS_DIR"
for skill in learning-finnish deardiary-fixer idea-evaluator decision-logger vault-health recap challenge emerge graduate; do
    src="$REPO_DIR/claude/$skill"
    dst="$SKILLS_DIR/$skill"
    if [ ! -d "$src" ]; then
        echo "    SKIP: $src missing"
        continue
    fi
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        backup="$dst.pre-deardiary-install-backup"
        mv "$dst" "$backup"
        echo "    backed up existing $dst -> $backup"
    fi
    ln -sfn "$src" "$dst"
    echo "    linked $dst -> $src"
done

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

# 3b. Diary inbox + processed dirs (Tauri app writes inbox; processor moves to processed)
DIARY_DIR="$HOME/DearDiary/diary"
mkdir -p "$DIARY_DIR/inbox" "$DIARY_DIR/processed"
echo "    ensured $DIARY_DIR/{inbox,processed}/"

# 3c. Render and install launchd plist for the diary inbox processor.
# Runs scripts/diary-process.sh every 15 minutes. The Tauri app's "Process Now"
# button hits the same script directly, so cron is just a safety net.
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
PLIST_NAME="com.deardiary.process.plist"
PLIST_PATH="$LAUNCH_AGENTS/$PLIST_NAME"
mkdir -p "$LAUNCH_AGENTS"
sed -e "s|{{REPO_DIR}}|$REPO_DIR|g" -e "s|{{HOME}}|$HOME|g" \
    "$REPO_DIR/launchd/$PLIST_NAME.template" > "$PLIST_PATH"
echo "    rendered $PLIST_PATH"

# Reload: bootout (ignore failures — fine if not loaded) then bootstrap.
if command -v launchctl >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)/com.deardiary.process" 2>/dev/null || true
    if launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null; then
        echo "    bootstrapped launchd job com.deardiary.process (every 900s)"
    else
        # Older macOS: fall back to load
        launchctl load "$PLIST_PATH" 2>/dev/null && \
            echo "    loaded launchd job com.deardiary.process (legacy load)" || \
            echo "    WARNING: could not register launchd job — load it manually"
    fi
else
    echo "    SKIP: launchctl not found"
fi

# 4. Smoke test — one full Phase B cycle against a throwaway dir
echo "==> Smoke test"
tmp=$(mktemp -d)
trap "rm -rf '$tmp'" EXIT
cp "$REPO_DIR/TODO.md.template" "$tmp/TODO.md"
DEARDIARY_DIR="$tmp" \
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
echo "    TODO file:  $TODO_FILE"
echo "    Event log:  $REPO_DIR/.todo-events.log"
echo "    Diary dir:  $DIARY_DIR"
echo
echo "    To build the Tauri GUI:"
echo "      cd app && npm install && npm run tauri build"
echo "    Then drag app/src-tauri/target/release/bundle/macos/DearDiary.app to /Applications."

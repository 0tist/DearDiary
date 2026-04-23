#!/usr/bin/env bash
# Emits Claude Code SessionStart hook JSON with the current TODO as additionalContext.
# If TODO.md does not exist, emits nothing (exit 0).

set -u

HOUSEKEEPING_DIR="${HOUSEKEEPING_DIR:-$HOME/Housekeeping}"
TODO_FILE="$HOUSEKEEPING_DIR/TODO.md"

[ -f "$TODO_FILE" ] || exit 0

# Read TODO and JSON-escape it
todo=$(cat "$TODO_FILE")
if command -v python3 >/dev/null 2>&1; then
    escaped=$(python3 -c '
import json, sys
print(json.dumps(sys.stdin.read()), end="")
' <<< "$todo")
else
    # Minimal fallback: escape backslashes, quotes, newlines
    escaped=$(printf '%s' "$todo" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk 'BEGIN{ORS="\\n"} {print}')
    escaped="\"$escaped\""
fi

cat <<EOF
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$escaped}}
EOF

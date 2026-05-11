#!/usr/bin/env bash
# Emits Claude Code SessionStart hook JSON with the current TODO and (if
# present) the vault identity primer _WORLD.md as additionalContext.
# If both files are missing, emits nothing (exit 0).

set -u

DEARDIARY_DIR="${DEARDIARY_DIR:-$HOME/DearDiary}"
TODO_FILE="$DEARDIARY_DIR/TODO.md"
WORLD_FILE="$DEARDIARY_DIR/_WORLD.md"

have_todo=0; have_world=0
[ -f "$TODO_FILE" ]  && have_todo=1
[ -f "$WORLD_FILE" ] && have_world=1
[ $have_todo -eq 0 ] && [ $have_world -eq 0 ] && exit 0

# Concatenate _WORLD.md (identity, slower-changing) and TODO.md (current
# state, faster-changing), separated by a horizontal rule. Either part is
# omitted if its source file is absent.
combined=""
if [ $have_world -eq 1 ]; then
    combined=$(cat "$WORLD_FILE")
fi
if [ $have_todo -eq 1 ]; then
    if [ -n "$combined" ]; then
        combined="$combined"$'\n\n---\n\n'"$(cat "$TODO_FILE")"
    else
        combined=$(cat "$TODO_FILE")
    fi
fi

# JSON-escape the combined blob.
if command -v python3 >/dev/null 2>&1; then
    escaped=$(python3 -c '
import json, sys
print(json.dumps(sys.stdin.read()), end="")
' <<< "$combined")
else
    # Minimal fallback: escape backslashes, quotes, newlines.
    escaped=$(printf '%s' "$combined" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk 'BEGIN{ORS="\\n"} {print}')
    escaped="\"$escaped\""
fi

cat <<EOF
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$escaped}}
EOF

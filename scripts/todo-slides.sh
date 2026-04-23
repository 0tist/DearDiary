#!/usr/bin/env bash
# View a TODO-formatted markdown file as slides.
# Each "## " heading becomes its own slide (inserts a --- separator before it).
#
# Usage: todo-slides            # opens ~/Housekeeping/TODO.md
#        todo-slides path.md    # opens any file

set -u

FILE="${1:-$HOME/Housekeeping/TODO.md}"
if [ ! -f "$FILE" ]; then
    echo "todo-slides: no such file: $FILE" >&2
    exit 1
fi

tmp=$(mktemp --suffix=.md)
trap 'rm -f "$tmp"' EXIT

awk '
    BEGIN { FS=""; OFS="" }
    /^## / { print ""; print "---"; print "" }
    { print }
' "$FILE" > "$tmp"

slides "$tmp"

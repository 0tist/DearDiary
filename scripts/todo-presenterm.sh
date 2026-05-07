#!/usr/bin/env bash
# View a TODO-formatted markdown file as a presenterm slideshow.
# Each "## " heading becomes its own slide.
#
# Usage: todo-presenterm            # opens ~/DearDiary/TODO.md
#        todo-presenterm path.md    # opens any file
#
# Env:
#   PRESENTERM_BIN=presenterm   override the command (e.g. ~/.cargo/bin/presenterm)
#   PRESENTERM_THEME=dark       theme name (use `presenterm --list-themes` to see)
#   PRESENTERM_IMAGE_PROTOCOL=auto|ascii-blocks|iterm2|kitty-local|sixel

set -u

FILE="${1:-$HOME/DearDiary/TODO.md}"
if [ ! -f "$FILE" ]; then
    echo "todo-presenterm: no such file: $FILE" >&2
    exit 1
fi

PRESENTERM_BIN="${PRESENTERM_BIN:-presenterm}"
if ! command -v "$PRESENTERM_BIN" >/dev/null 2>&1 \
        && [ -x "$HOME/.cargo/bin/presenterm" ]; then
    PRESENTERM_BIN="$HOME/.cargo/bin/presenterm"
fi
if ! command -v "$PRESENTERM_BIN" >/dev/null 2>&1; then
    echo "todo-presenterm: presenterm not found on PATH" >&2
    echo "  install: see https://github.com/mfontanini/presenterm" >&2
    exit 127
fi

tmp=$(mktemp --suffix=.md)
trap 'rm -f "$tmp"' EXIT

# Preprocess: insert slide breaks before each '## ' heading and escape any
# '<word>' patterns that aren't inside fenced code blocks. Presenterm rejects
# unknown bare HTML-looking tags (e.g. '<session_id>'), so we backslash-escape
# them to literal angle brackets per CommonMark.
python3 - "$FILE" > "$tmp" <<'PY'
import re, sys

src = open(sys.argv[1], encoding="utf-8").read().splitlines(keepends=True)
fence = re.compile(r"^(```|~~~)")
tag   = re.compile(r"<([a-zA-Z_][a-zA-Z0-9_./-]*)>")

in_code = False
seen_h2 = False
out = []
for line in src:
    if fence.match(line):
        in_code = not in_code
        out.append(line)
        continue
    if not in_code:
        if line.startswith("## "):
            if seen_h2:
                out.append("\n<!-- end_slide -->\n\n")
            seen_h2 = True
        line = tag.sub(r"\\<\1\\>", line)
    out.append(line)

sys.stdout.write("".join(out))
PY

args=()
[ -n "${PRESENTERM_THEME:-}" ]          && args+=(--theme "$PRESENTERM_THEME")
[ -n "${PRESENTERM_IMAGE_PROTOCOL:-}" ] && args+=(--image-protocol "$PRESENTERM_IMAGE_PROTOCOL")

exec "$PRESENTERM_BIN" "${args[@]}" "$tmp"

#!/usr/bin/env bash
# todo-session-start.sh must output valid JSON with additionalContext
# containing the TODO.md contents.

set -u
source "$(dirname "$0")/lib.sh"

setup_tmp tmp
export DEARDIARY_DIR="$tmp"

fixture_dir="$(cd "$(dirname "$0")/fixtures" && pwd)"
cp "$fixture_dir/todo-before.md" "$tmp/TODO.md"

script="$(cd "$(dirname "$0")/../scripts" && pwd)/todo-session-start.sh"

output=$("$script")

# Must be valid JSON
if command -v jq >/dev/null 2>&1; then
    if echo "$output" | jq . >/dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}  PASS${NC} output is valid JSON"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}  FAIL${NC} output is not valid JSON"
        echo "    output: $output"
    fi

    additional=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // .additionalContext // ""')
    assert_contains "$additional" "wire up CLI flag" "additionalContext includes TODO content"
else
    echo "  SKIP jq not available"
fi

# Missing TODO.md case
rm "$tmp/TODO.md"
output=$("$script")
assert_eq "$output" "" "empty output when TODO.md missing"

# _WORLD.md only — should still emit, with the WORLD content
cat > "$tmp/_WORLD.md" <<EOF
# _WORLD.md
jayesh — Helsinki — terse responses, atomic commits.
EOF
output=$("$script")
if command -v jq >/dev/null 2>&1; then
    additional=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""')
    assert_contains "$additional" "Helsinki" "additionalContext includes _WORLD.md content when only WORLD exists"
fi

# Both files present — additionalContext contains both
cp "$fixture_dir/todo-before.md" "$tmp/TODO.md"
output=$("$script")
if command -v jq >/dev/null 2>&1; then
    additional=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""')
    assert_contains "$additional" "Helsinki"        "additionalContext includes WORLD content when both exist"
    assert_contains "$additional" "wire up CLI flag" "additionalContext includes TODO content when both exist"
fi

# Both files missing — empty output
rm "$tmp/TODO.md" "$tmp/_WORLD.md"
output=$("$script")
assert_eq "$output" "" "empty output when both files missing"

print_summary

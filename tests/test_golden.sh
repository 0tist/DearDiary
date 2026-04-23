#!/usr/bin/env bash
# End-to-end: given a known TODO + transcript, script produces the golden output.

set -u
source "$(dirname "$0")/lib.sh"

setup_tmp tmp
export HOUSEKEEPING_DIR="$tmp"

fixture_dir="$(cd "$(dirname "$0")/fixtures" && pwd)"
cp "$fixture_dir/todo-before.md" "$tmp/TODO.md"
cp "$fixture_dir/transcript.jsonl" "$tmp/transcript.jsonl"

fake_bin=$(make_fake_claude "$tmp" "$fixture_dir/todo-golden.md")
export PATH="$fake_bin:$PATH"

script="$(cd "$(dirname "$0")/../scripts" && pwd)/todo-update.sh"

HOOK_TRANSCRIPT_PATH="$tmp/transcript.jsonl" \
HOOK_SESSION_ID="golden" \
HOOK_CWD="$HOME/slides" \
TODO_UPDATE_PHASE=B "$script" end

# Compare (ignoring trailing newlines)
diff_output=$(diff <(cat "$tmp/TODO.md") <(cat "$fixture_dir/todo-golden.md") || true)
assert_eq "$diff_output" "" "TODO.md matches golden"

print_summary

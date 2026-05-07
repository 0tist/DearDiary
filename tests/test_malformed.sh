#!/usr/bin/env bash
# If claude -p returns garbage, TODO.md must be untouched and event logged.

set -u
source "$(dirname "$0")/lib.sh"

setup_tmp tmp
export DEARDIARY_DIR="$tmp"

fixture_dir="$(cd "$(dirname "$0")/fixtures" && pwd)"
cp "$fixture_dir/todo-before.md" "$tmp/TODO.md"
original_hash=$(sha256sum "$tmp/TODO.md" | awk '{print $1}')

fake_bin=$(make_fake_claude "$tmp" "$fixture_dir/fake-claude-garbage.txt")
export PATH="$fake_bin:$PATH"

script="$(cd "$(dirname "$0")/../scripts" && pwd)/todo-update.sh"
TODO_UPDATE_PHASE=B "$script" end

# TODO.md must be unchanged
new_hash=$(sha256sum "$tmp/TODO.md" | awk '{print $1}')
assert_eq "$new_hash" "$original_hash" "TODO.md unchanged on malformed output"

# Event log must record "malformed_output"
assert_file_contains "$tmp/.todo-events.log" '"result":"malformed_output"' "malformed event logged"

print_summary

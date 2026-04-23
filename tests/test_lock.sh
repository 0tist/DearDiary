#!/usr/bin/env bash
# Two concurrent updaters must produce exactly one write to TODO.md.

set -u
source "$(dirname "$0")/lib.sh"

setup_tmp tmp
export HOUSEKEEPING_DIR="$tmp"
export CLAUDE_MODEL_OVERRIDE="skip"  # hint to script to skip real model
printf '# TODO\n\n## Active\n\n## Blocked / Waiting\n\n## Done (last 7 days)\n' > "$tmp/TODO.md"

fixture_dir="$(cd "$(dirname "$0")/fixtures" && pwd)"
fake_bin=$(make_fake_claude "$tmp" "$fixture_dir/fake-claude-output.md")
export PATH="$fake_bin:$PATH"

script="$(cd "$(dirname "$0")/../scripts" && pwd)/todo-update.sh"

# Fire two background workers directly (bypass Phase A fork) by exporting TODO_UPDATE_PHASE=B
TODO_UPDATE_PHASE=B "$script" end &
pid1=$!
TODO_UPDATE_PHASE=B "$script" end &
pid2=$!

wait $pid1; rc1=$?
wait $pid2; rc2=$?

# Both must exit 0 (one did the work, one skipped because lock was held)
assert_eq "$rc1" "0" "worker 1 exits 0"
assert_eq "$rc2" "0" "worker 2 exits 0"

# Exactly one line should have been written to the event log indicating "wrote"
wrote_count=$(grep -c '"result":"wrote"' "$tmp/.todo-events.log" 2>/dev/null || echo 0)
skipped_count=$(grep -c '"result":"lock_held"' "$tmp/.todo-events.log" 2>/dev/null || echo 0)

assert_eq "$wrote_count" "1" "exactly one worker wrote"
assert_eq "$skipped_count" "1" "exactly one worker skipped on lock"

print_summary

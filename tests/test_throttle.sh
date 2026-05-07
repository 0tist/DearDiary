#!/usr/bin/env bash
# Two 'stop' invocations close together → second is throttled.
# 'end' invocation bypasses throttle.

set -u
source "$(dirname "$0")/lib.sh"

setup_tmp tmp
export DEARDIARY_DIR="$tmp"
printf '# TODO\n\n## Active\n\n## Blocked / Waiting\n\n## Done (last 7 days)\n' > "$tmp/TODO.md"

fixture_dir="$(cd "$(dirname "$0")/fixtures" && pwd)"
fake_bin=$(make_fake_claude "$tmp" "$fixture_dir/fake-claude-output.md")
export PATH="$fake_bin:$PATH"

script="$(cd "$(dirname "$0")/../scripts" && pwd)/todo-update.sh"

# First stop: should write
TODO_UPDATE_PHASE=B "$script" stop
count_after_first=$(grep -c '"result":"wrote"' "$tmp/.todo-events.log" 2>/dev/null || echo 0)
assert_eq "$count_after_first" "1" "first stop writes"

# Second stop immediately: should throttle
TODO_UPDATE_PHASE=B "$script" stop
throttled_count=$(grep -c '"result":"throttled"' "$tmp/.todo-events.log" 2>/dev/null || echo 0)
assert_eq "$throttled_count" "1" "second stop is throttled"

# Third call with 'end': should bypass throttle and write
TODO_UPDATE_PHASE=B "$script" end
count_after_end=$(grep -c '"result":"wrote"' "$tmp/.todo-events.log" 2>/dev/null || echo 0)
assert_eq "$count_after_end" "2" "end bypasses throttle"

print_summary

#!/usr/bin/env bash
# Concurrency: two diary-process.sh runs in parallel — exactly one should
# acquire the lock, the other should log "lock_held" and exit cleanly.

set -u
cd "$(dirname "$0")"
. ./lib.sh

REPO_DIR="$(cd .. && pwd)"
SCRIPT="$REPO_DIR/scripts/diary-process.sh"

setup_tmp tmp

# One inbox entry so the script doesn't short-circuit on inbox_empty
mkdir -p "$tmp/diary/inbox"
cat > "$tmp/diary/inbox/2026-05-10T22-56-00.md" <<EOF
---
id: 2026-05-10T22-56-00
---

a thought
EOF

# Seed empty TODO.md
echo -e "# TODO\n\n## Active\n\n## Blocked / Waiting\n\n## Done (last 7 days)" > "$tmp/TODO.md"

# Fake claude that sleeps so the lock is held long enough for the second
# invocation to bounce off it.
fake_script="$tmp/fake-claude.sh"
cat > "$fake_script" <<'EOF'
#!/usr/bin/env bash
sleep 2
EOF
chmod +x "$fake_script"
fake_bin=$(make_fake_claude_script "$tmp" "$fake_script")

run_phase_b() {
    PATH="$fake_bin:$PATH" \
    DEARDIARY_DIR="$tmp" \
    DIARY_PROCESS_PHASE=B \
    HOOK_SESSION_ID="lock-test" \
    HOOK_CWD="$PWD" \
    bash "$SCRIPT" button >/dev/null 2>&1
}

run_phase_b &
pid1=$!
sleep 0.1   # make sure pid1 has the lock before pid2 tries
run_phase_b &
pid2=$!
wait "$pid1" "$pid2"

lock_held_count=$(grep -c '"result":"lock_held"' "$tmp/.diary-events.log" 2>/dev/null || echo 0)
assert_eq "$lock_held_count" "1" "exactly one lock_held event"

# And we should still have at least one successful processing event
processed_count=$(grep -c '"result":"processed"\|"result":"inbox_empty"' "$tmp/.diary-events.log" 2>/dev/null || echo 0)
[ "$processed_count" -ge 1 ] && \
    { TESTS_PASSED=$((TESTS_PASSED+1)); echo -e "  \033[0;32mPASS\033[0m at-least-one-real-run"; } || \
    { TESTS_FAILED=$((TESTS_FAILED+1)); echo -e "  \033[0;31mFAIL\033[0m at-least-one-real-run"; cat "$tmp/.diary-events.log"; }

print_summary

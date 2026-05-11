#!/usr/bin/env bash
# End-to-end test for diary-maintain.sh.
# Fake claude simulates a reconcile (marks one note superseded) and a
# synthesize (writes one Synthesis/<date>-<topic>.md).

set -u
cd "$(dirname "$0")"
. ./lib.sh

REPO_DIR="$(cd .. && pwd)"
SCRIPT="$REPO_DIR/scripts/diary-maintain.sh"

setup_tmp tmp

# Lay out a tiny vault with two contradictory Decisions/ notes.
mkdir -p "$tmp/Decisions" "$tmp/Ideas"
cat > "$tmp/Decisions/2026-05-01.md" <<EOF
---
type: decision
date: 2026-05-01T10:00:00+00:00
status: accepted
ai-first: true
---

## For future Claude

Decided to use [[Postgres]] for the rewrite. JSONB is clean.
EOF
cat > "$tmp/Decisions/2026-05-08.md" <<EOF
---
type: decision
date: 2026-05-08T10:00:00+00:00
status: accepted
ai-first: true
---

## For future Claude

Reversing [[Postgres]] choice. ORM friction too high. Going with Mongo.
EOF
cat > "$tmp/Ideas/2026-05-09.md" <<EOF
---
type: idea
date: 2026-05-09T10:00:00+00:00
ai-first: true
---

## For future Claude

Microgreens farm idea, automated, at home.
EOF

# Fake claude script that simulates what the prompt would have claude do.
fake_script="$tmp/fake-claude.sh"
cat > "$fake_script" <<'EOF'
#!/usr/bin/env bash
set -u
ROOT="${DEARDIARY_DIR:-$HOME/DearDiary}"

# Simulate reconcile: mark the older Decision superseded.
older="$ROOT/Decisions/2026-05-01.md"
if [ -f "$older" ] && ! grep -q 'status: superseded' "$older"; then
    # Replace status line and append ## Updates section.
    sed -i.bak 's/status: accepted/status: superseded\nsuperseded_by: Decisions\/2026-05-08.md/' "$older"
    rm -f "$older.bak"
    printf '\n## Updates\n- 2026-05-11 — Superseded by [[2026-05-08]]. ORM friction was the trigger.\n' >> "$older"
fi

# Simulate synthesize: write one Synthesis note.
mkdir -p "$ROOT/Synthesis"
cat > "$ROOT/Synthesis/2026-05-11-database-choice.md" <<'NOTE'
---
type: synthesis
date: 2026-05-11T02:00:00+00:00
window_days: 7
tags: [synthesis]
ai-first: true
routed_to: Synthesis
---

## For future Claude

The user reversed a major database choice within a week; worth a moment of
reflection before the next big infra decision.
NOTE

# Echo the summary that diary-maintain.sh tees to the events log.
echo "reconcile: 1 contradictions resolved, 1 notes touched"
echo "synthesize: one synthesis note written: Synthesis/2026-05-11-database-choice.md"
EOF
chmod +x "$fake_script"
fake_bin=$(make_fake_claude_script "$tmp" "$fake_script")

# Run Phase B directly so the test is synchronous.
PATH="$fake_bin:$PATH" \
DEARDIARY_DIR="$tmp" \
DIARY_MAINTAIN_PHASE=B \
HOOK_SESSION_ID="test" \
HOOK_CWD="$PWD" \
bash "$SCRIPT" button >/dev/null 2>&1

# Assertions
assert_file_contains "$tmp/Decisions/2026-05-01.md" "status: superseded" "older decision marked superseded"
assert_file_contains "$tmp/Decisions/2026-05-01.md" "superseded_by:"     "older decision links forward"
assert_file_contains "$tmp/Decisions/2026-05-01.md" "## Updates"         "older decision has Updates section"

newer_unchanged=$(grep -c '^status: accepted$' "$tmp/Decisions/2026-05-08.md")
assert_eq "$newer_unchanged" "1" "newer decision left intact (status still accepted)"

[ -f "$tmp/Synthesis/2026-05-11-database-choice.md" ] && \
    { TESTS_PASSED=$((TESTS_PASSED+1)); echo -e "  \033[0;32mPASS\033[0m synthesis note written"; } || \
    { TESTS_FAILED=$((TESTS_FAILED+1)); echo -e "  \033[0;31mFAIL\033[0m synthesis note written"; }

assert_file_contains "$tmp/.diary-events.log" '"result":"maintained"' "events.log records maintained result"
assert_file_contains "$tmp/.diary-events.log" '"kind":"maintain"'     "events.log tags entry as maintain"
assert_file_contains "$tmp/.diary-events.log" "reconcile: 1"           "events.log captures reconcile summary"

# Lock-sharing: a maintain run while diary-process.lock.d is held should bail.
mkdir -p "$tmp/.diary-process.lock.d"
PATH="$fake_bin:$PATH" \
DEARDIARY_DIR="$tmp" \
DIARY_MAINTAIN_PHASE=B \
bash "$SCRIPT" button >/dev/null 2>&1
rmdir "$tmp/.diary-process.lock.d"

lock_held_count=$(grep -c '"result":"lock_held"' "$tmp/.diary-events.log" 2>/dev/null || echo 0)
assert_eq "$lock_held_count" "1" "maintain bails when shared lock is held"

print_summary

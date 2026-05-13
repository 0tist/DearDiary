#!/usr/bin/env bash
# End-to-end test for diary-process.sh:
# - stages two inbox entries
# - replaces `claude` with a script that simulates the file moves the prompt
#   would tell real claude to do
# - runs Phase B directly, asserts inbox empty + processed populated +
#   journal/ populated + event log entry "processed count=2"

set -u
cd "$(dirname "$0")"
. ./lib.sh

REPO_DIR="$(cd .. && pwd)"
SCRIPT="$REPO_DIR/scripts/diary-process.sh"

setup_tmp tmp

# Stage two inbox entries
mkdir -p "$tmp/diary/inbox" "$tmp/diary/processed"
cat > "$tmp/diary/inbox/2026-05-10T22-56-00.md" <<EOF
---
created_at: 2026-05-10T22:56:00-07:00
id: 2026-05-10T22-56-00
---

felt good about the demo today
EOF
cat > "$tmp/diary/inbox/2026-05-10T23-04-12.md" <<EOF
---
created_at: 2026-05-10T23:04:12-07:00
id: 2026-05-10T23-04-12
---

idea: serialize plan diffs as binary patches
EOF

# Seed an empty TODO.md so prompt rendering doesn't choke
cat > "$tmp/TODO.md" <<EOF
# TODO

## Active

## Blocked / Waiting

## Done (last 7 days)
EOF

# Build a fake-claude script that does what the real prompt would tell claude
# to do: for each inbox file, write a journal copy then mv the original to
# processed/. Output one summary line per entry.
fake_script="$tmp/fake-claude.sh"
cat > "$fake_script" <<'EOF'
#!/usr/bin/env bash
set -u
# DIARY_ROOT in the prompt now means the VAULT ROOT (where canonical
# folders live). Inbox + processed/ are DearDiary-internal, one level
# down under diary/. Files get FILED at the vault root.
VAULT_ROOT="${DEARDIARY_DIR:-$HOME/DearDiary}"
INBOX="$VAULT_ROOT/diary/inbox"
PROCESSED="$VAULT_ROOT/diary/processed"
mkdir -p "$VAULT_ROOT/journal" "$PROCESSED"
shopt -s nullglob
for f in "$INBOX"/*.md; do
    id=$(basename "$f" .md)
    cp "$f" "$VAULT_ROOT/journal/$id.md"
    mv "$f" "$PROCESSED/$id.md"
    echo "$id -> journal/$id.md"
done
EOF
chmod +x "$fake_script"
fake_bin=$(make_fake_claude_script "$tmp" "$fake_script")

# Run Phase B directly so the test is synchronous (Phase A forks and returns).
PATH="$fake_bin:$PATH" \
DEARDIARY_DIR="$tmp" \
DIARY_PROCESS_PHASE=B \
HOOK_SESSION_ID="test" \
HOOK_CWD="$PWD" \
bash "$SCRIPT" button >/dev/null 2>&1

# Assertions
inbox_count=$(find "$tmp/diary/inbox" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
assert_eq "$inbox_count" "0" "inbox emptied"

processed_count=$(find "$tmp/diary/processed" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
assert_eq "$processed_count" "2" "two files in processed/"

journal_count=$(find "$tmp/journal" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$journal_count" "2" "two files in journal/ at vault root (not inside diary/)"

assert_file_contains "$tmp/.diary-events.log" '"result":"processed"' "events.log records processed result"
assert_file_contains "$tmp/.diary-events.log" '"count":2' "events.log records count=2"

print_summary

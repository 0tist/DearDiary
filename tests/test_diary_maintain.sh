#!/usr/bin/env bash
# End-to-end test for diary-maintain.sh.
# Stages a vault with:
#   - two contradictory Decisions/ notes (for reconcile)
#   - a timestamped Ideas/ note (for rename)
#   - two same-topic Ideas/ notes (for merge into a canonical + stub redirect)
#   - an Ideas/ note and a Projects/ note about the same topic
#     (for bidirectional cross-folder wikilinks; no merge)
# Fake claude script simulates the side effects the prompt would tell
# real claude to perform.

set -u
cd "$(dirname "$0")"
. ./lib.sh

REPO_DIR="$(cd .. && pwd)"
SCRIPT="$REPO_DIR/scripts/diary-maintain.sh"

setup_tmp tmp

mkdir -p "$tmp/Decisions" "$tmp/Ideas" "$tmp/Projects"

# Reconcile fixtures
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

# Rename fixture — single timestamped Ideas/ note
cat > "$tmp/Ideas/2026-05-12T10-00-00.md" <<EOF
---
type: idea
date: 2026-05-12T10:00:00+00:00
ai-first: true
---

## For future Claude

Automate the microgreens shelf at home with cheap moisture sensors.
EOF

# Merge fixtures — two timestamped Ideas/ notes about the same topic
cat > "$tmp/Ideas/2026-05-13T09-00-00.md" <<EOF
---
type: idea
date: 2026-05-13T09:00:00+00:00
ai-first: true
---

## For future Claude

CT and MRI generalization angle for [[Aiatella]] models.
EOF
cat > "$tmp/Ideas/2026-05-13T15-00-00.md" <<EOF
---
type: idea
date: 2026-05-13T15:00:00+00:00
ai-first: true
---

## For future Claude

Different families of segmentation models and whether they survive
CT->MRI domain shift for [[Aiatella]].
EOF

# Cross-folder fixtures — Ideas/ and Projects/ about the same topic
cat > "$tmp/Ideas/api-rewrite-thoughts.md" <<EOF
---
type: idea
date: 2026-05-10T10:00:00+00:00
ai-first: true
---

## For future Claude

Sketching the API rewrite scope — what to keep, what to drop.
EOF
cat > "$tmp/Projects/api-rewrite.md" <<EOF
---
type: project
date: 2026-05-12T10:00:00+00:00
status: active
ai-first: true
---

## For future Claude

API rewrite project — phased rollout, dual-write phase, feature flag cutover.
EOF

# Fake claude — simulates the side effects the prompt would tell real
# claude to perform.
fake_script="$tmp/fake-claude.sh"
cat > "$fake_script" <<'EOF'
#!/usr/bin/env bash
set -u
ROOT="${DEARDIARY_DIR:-$HOME/DearDiary}"

# --- RECONCILE: mark the older Decision superseded ---
older="$ROOT/Decisions/2026-05-01.md"
if [ -f "$older" ] && ! grep -q 'status: superseded' "$older"; then
    sed -i.bak 's/status: accepted/status: superseded\nsuperseded_by: Decisions\/2026-05-08.md/' "$older"
    rm -f "$older.bak"
    printf '\n## Updates\n- 2026-05-14 — Superseded by [[2026-05-08]]. ORM friction was the trigger.\n' >> "$older"
fi

# --- CONSOLIDATE 2a (RENAME): single timestamped Idea -> descriptive slug ---
if [ -f "$ROOT/Ideas/2026-05-12T10-00-00.md" ]; then
    mv "$ROOT/Ideas/2026-05-12T10-00-00.md" "$ROOT/Ideas/microgreens-moisture-sensors.md"
    # Add original_id to frontmatter
    sed -i.bak '/^type: idea$/a\
original_id: 2026-05-12T10-00-00' "$ROOT/Ideas/microgreens-moisture-sensors.md"
    rm -f "$ROOT/Ideas/microgreens-moisture-sensors.md.bak"
fi

# --- CONSOLIDATE 2b (MERGE): two same-topic Ideas -> canonical + stub redirect ---
canonical="$ROOT/Ideas/ct-mri-generalization.md"
src1="$ROOT/Ideas/2026-05-13T09-00-00.md"
src2="$ROOT/Ideas/2026-05-13T15-00-00.md"
if [ -f "$src1" ] && [ -f "$src2" ] && [ ! -f "$canonical" ]; then
    # Build the canonical (using src1 as base, body merged from both)
    cat > "$canonical" <<NOTE
---
type: idea
date: 2026-05-13T09:00:00+00:00
original_id: 2026-05-13T09-00-00
merged_from: [2026-05-13T15-00-00]
ai-first: true
---

## For future Claude

Two angles on the same problem — CT/MRI generalization for [[Aiatella]] segmentation models.

## Original notes

### From 2026-05-13T09-00-00 (2026-05-13)

CT and MRI generalization angle for [[Aiatella]] models.

### From 2026-05-13T15-00-00 (2026-05-13)

Different families of segmentation models and whether they survive
CT->MRI domain shift for [[Aiatella]].
NOTE
    rm "$src1"
    # src2 becomes a stub redirect (keeps frontmatter, body replaced)
    cat > "$src2" <<NOTE
---
type: idea
date: 2026-05-13T15:00:00+00:00
merged_into: Ideas/ct-mri-generalization.md
ai-first: true
---

Moved → [[ct-mri-generalization]].
NOTE
fi

# --- CONSOLIDATE 2c (CROSS-LINK): bidirectional wikilinks; no merge ---
proj="$ROOT/Projects/api-rewrite.md"
idea="$ROOT/Ideas/api-rewrite-thoughts.md"
if [ -f "$proj" ] && [ -f "$idea" ] && ! grep -q 'Origin:' "$proj"; then
    # Insert a blockquote after the "## For future Claude" preamble in each.
    # For the Project: Origin
    awk '
        /^## For future Claude$/ { print; in_preamble=1; next }
        in_preamble && NF==0 && !done {
            print
            print "> Origin: [[Ideas/api-rewrite-thoughts]]"
            print ""
            done=1
            in_preamble=0
            next
        }
        { print }
    ' "$proj" > "$proj.tmp" && mv "$proj.tmp" "$proj"

    # For the Idea: Became
    awk '
        /^## For future Claude$/ { print; in_preamble=1; next }
        in_preamble && NF==0 && !done {
            print
            print "> Became: [[Projects/api-rewrite]]"
            print ""
            done=1
            in_preamble=0
            next
        }
        { print }
    ' "$idea" > "$idea.tmp" && mv "$idea.tmp" "$idea"
fi

# Echo the summary lines (the script tees these to the events log)
echo "reconcile: 1 contradictions resolved, 1 notes touched"
echo "consolidate: renamed 1, merged into 1 canonicals, cross-linked 1"
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

# --- Reconcile assertions ---
assert_file_contains "$tmp/Decisions/2026-05-01.md" "status: superseded" "older decision marked superseded"
assert_file_contains "$tmp/Decisions/2026-05-01.md" "superseded_by:"     "older decision links forward"

newer_unchanged=$(grep -c '^status: accepted$' "$tmp/Decisions/2026-05-08.md")
assert_eq "$newer_unchanged" "1" "newer decision left intact"

# --- Rename assertions ---
[ ! -f "$tmp/Ideas/2026-05-12T10-00-00.md" ] && \
    { TESTS_PASSED=$((TESTS_PASSED+1)); echo -e "  ${GREEN}PASS${NC} timestamped Idea was renamed away"; } || \
    { TESTS_FAILED=$((TESTS_FAILED+1)); echo -e "  ${RED}FAIL${NC} timestamped Idea was renamed away"; }

[ -f "$tmp/Ideas/microgreens-moisture-sensors.md" ] && \
    { TESTS_PASSED=$((TESTS_PASSED+1)); echo -e "  ${GREEN}PASS${NC} renamed Idea exists with descriptive slug"; } || \
    { TESTS_FAILED=$((TESTS_FAILED+1)); echo -e "  ${RED}FAIL${NC} renamed Idea exists with descriptive slug"; }

assert_file_contains "$tmp/Ideas/microgreens-moisture-sensors.md" "original_id:" "renamed note preserves original_id"

# --- Merge assertions ---
[ -f "$tmp/Ideas/ct-mri-generalization.md" ] && \
    { TESTS_PASSED=$((TESTS_PASSED+1)); echo -e "  ${GREEN}PASS${NC} merged canonical exists"; } || \
    { TESTS_FAILED=$((TESTS_FAILED+1)); echo -e "  ${RED}FAIL${NC} merged canonical exists"; }

assert_file_contains "$tmp/Ideas/ct-mri-generalization.md" "## Original notes" "canonical has Original notes section"
assert_file_contains "$tmp/Ideas/ct-mri-generalization.md" "From 2026-05-13T09-00-00" "canonical preserves source 1 verbatim"
assert_file_contains "$tmp/Ideas/ct-mri-generalization.md" "From 2026-05-13T15-00-00" "canonical preserves source 2 verbatim"

# Non-canonical source: deleted (merged into canonical body)
[ ! -f "$tmp/Ideas/2026-05-13T09-00-00.md" ] && \
    { TESTS_PASSED=$((TESTS_PASSED+1)); echo -e "  ${GREEN}PASS${NC} canonical's original path freed"; } || \
    { TESTS_FAILED=$((TESTS_FAILED+1)); echo -e "  ${RED}FAIL${NC} canonical's original path freed"; }

# Non-canonical source: stub redirect (β)
assert_file_contains "$tmp/Ideas/2026-05-13T15-00-00.md" "merged_into:"               "non-canonical source has merged_into frontmatter"
assert_file_contains "$tmp/Ideas/2026-05-13T15-00-00.md" "Moved → [[ct-mri"           "non-canonical source body is a stub redirect"

# --- Cross-folder link assertions ---
assert_file_contains "$tmp/Projects/api-rewrite.md"        "Origin: [[Ideas/api-rewrite-thoughts]]" "Project note got Origin wikilink to Idea"
assert_file_contains "$tmp/Ideas/api-rewrite-thoughts.md"  "Became: [[Projects/api-rewrite]]"       "Idea note got Became wikilink to Project"

# Files in different folders should remain separate (no merge)
[ -f "$tmp/Projects/api-rewrite.md" ] && [ -f "$tmp/Ideas/api-rewrite-thoughts.md" ] && \
    { TESTS_PASSED=$((TESTS_PASSED+1)); echo -e "  ${GREEN}PASS${NC} cross-folder notes stay independent (no merge)"; } || \
    { TESTS_FAILED=$((TESTS_FAILED+1)); echo -e "  ${RED}FAIL${NC} cross-folder notes stay independent (no merge)"; }

# --- Events log ---
assert_file_contains "$tmp/.diary-events.log" '"result":"maintained"' "events.log records maintained result"
assert_file_contains "$tmp/.diary-events.log" '"kind":"maintain"'     "events.log tags entry as maintain"
assert_file_contains "$tmp/.diary-events.log" "consolidate: renamed 1" "events.log captures consolidate summary"

# --- Lock-sharing: a maintain run while diary-process.lock.d is held should bail ---
mkdir -p "$tmp/.diary-process.lock.d"
PATH="$fake_bin:$PATH" \
DEARDIARY_DIR="$tmp" \
DIARY_MAINTAIN_PHASE=B \
bash "$SCRIPT" button >/dev/null 2>&1
rmdir "$tmp/.diary-process.lock.d"

lock_held_count=$(grep -c '"result":"lock_held"' "$tmp/.diary-events.log" 2>/dev/null || echo 0)
assert_eq "$lock_held_count" "1" "maintain bails when shared lock is held"

print_summary

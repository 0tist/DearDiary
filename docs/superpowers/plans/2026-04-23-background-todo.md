# Background Auto-Updating TODO — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a cross-session TODO system that every Claude Code session auto-updates via hooks, with flock-based concurrency and Haiku-powered reconciliation.

**Architecture:** Source scripts live in `~/Housekeeping/scripts/`, symlinked into `~/.claude/` by `install.sh`. Global hooks in `~/.claude/settings.json` trigger the updater on `SessionStart`, `Stop`, and `SessionEnd`. Updater runs a fast Phase A (fork & return) in-hook and a slow Phase B (lock, throttle, `claude -p`, atomic write) in a detached background process.

**Tech Stack:** Bash 4+, `flock`, `jq` (for transcript JSONL parsing), Python 3 (for safe JSON merge of `settings.json`), `claude` CLI (Haiku 4.5 model).

**Spec:** `docs/superpowers/specs/2026-04-23-background-todo-design.md`

---

## File Structure

**Source (committed to repo):**

| Path | Responsibility |
|---|---|
| `scripts/todo-update.sh` | Phase A hook entry + Phase B background worker. One file, two phases gated by an env var. |
| `scripts/todo-session-start.sh` | Emits current TODO as `additionalContext` for SessionStart. |
| `scripts/lib/prompt.txt` | The exact prompt template handed to `claude -p`. Kept as a data file so it can be edited without touching shell quoting. |
| `install.sh` | Symlinks scripts into `~/.claude/`, merges hook entries into `~/.claude/settings.json`, seeds `TODO.md`, runs smoke test. |
| `uninstall.sh` | Inverse of install. Never deletes `TODO.md` or `.todo-events.log`. |
| `TODO.md.template` | Starter content copied to `~/Housekeeping/TODO.md` on first install. |
| `tests/run.sh` | Runs all tests, returns non-zero on any failure. |
| `tests/lib.sh` | Shared helpers: `assert_eq`, `assert_contains`, `make_fake_claude`, `setup_tmp`. |
| `tests/test_lock.sh` | Two concurrent updaters → exactly one writes. |
| `tests/test_throttle.sh` | Two `stop` invocations within 10 s → second is no-op; `end` bypasses. |
| `tests/test_golden.sh` | Mock transcript + TODO.md → diff against committed golden output. |
| `tests/test_malformed.sh` | Stub `claude` returns garbage → TODO untouched, event logged. |
| `tests/test_session_start.sh` | `todo-session-start.sh` produces valid `additionalContext` JSON. |
| `tests/fixtures/transcript.jsonl` | Sample 10-turn Claude Code transcript. |
| `tests/fixtures/todo-before.md` | Input TODO.md for golden test. |
| `tests/fixtures/todo-golden.md` | Expected output TODO.md after reconciliation. |
| `tests/fixtures/fake-claude-output.md` | Canned Haiku output used by fake `claude` shim. |
| `tests/fixtures/fake-claude-garbage.txt` | Malformed output for test_malformed. |
| `.gitignore` | Ignore `TODO.md`, `.todo-update.lock`, `.todo-last-update`, `.todo-events.log`, `TODO.md.tmp`. |

**Installed (not in repo):**

| Path | Source |
|---|---|
| `~/.claude/todo-update.sh` | symlink → `~/Housekeeping/scripts/todo-update.sh` |
| `~/.claude/todo-session-start.sh` | symlink → `~/Housekeeping/scripts/todo-session-start.sh` |
| `~/.claude/settings.json` | patched in place (merge) |

**Runtime state (not in repo, gitignored):**

| Path | Purpose |
|---|---|
| `~/Housekeeping/TODO.md` | Source of truth |
| `~/Housekeeping/.todo-update.lock` | flock target |
| `~/Housekeeping/.todo-last-update` | mtime drives throttle |
| `~/Housekeeping/.todo-events.log` | JSONL audit trail |

---

## Task 1: Repo skeleton and `.gitignore`

**Files:**
- Create: `scripts/` (directory)
- Create: `scripts/lib/` (directory)
- Create: `tests/fixtures/` (directory)
- Create: `.gitignore`

- [ ] **Step 1: Create directories**

```bash
cd ~/Housekeeping
mkdir -p scripts/lib tests/fixtures
```

- [ ] **Step 2: Write `.gitignore`**

Create `/home/jayesh0vasudeva/Housekeeping/.gitignore`:

```gitignore
# Runtime state for the auto-TODO system
TODO.md
TODO.md.tmp
.todo-update.lock
.todo-last-update
.todo-events.log

# Editor / OS
.DS_Store
*.swp
```

- [ ] **Step 3: Verify structure**

Run: `find ~/Housekeeping -maxdepth 2 -type d | sort`
Expected output includes: `scripts`, `scripts/lib`, `tests`, `tests/fixtures`, `docs/superpowers/plans`, `docs/superpowers/specs`.

- [ ] **Step 4: Commit**

```bash
cd ~/Housekeeping
git add .gitignore
git commit -m "chore: scaffold dirs and gitignore runtime state"
```

---

## Task 2: Test harness (`tests/lib.sh`, `tests/run.sh`)

**Files:**
- Create: `tests/lib.sh`
- Create: `tests/run.sh`

- [ ] **Step 1: Write `tests/lib.sh`**

Create `/home/jayesh0vasudeva/Housekeeping/tests/lib.sh`:

```bash
#!/usr/bin/env bash
# Shared test helpers. Sourced by each test_*.sh file.

set -u

# Colors for output
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; NC=''
fi

TESTS_PASSED=0
TESTS_FAILED=0

assert_eq() {
    local actual="$1" expected="$2" msg="${3:-}"
    if [ "$actual" = "$expected" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}  PASS${NC} ${msg:-assert_eq}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}  FAIL${NC} ${msg:-assert_eq}"
        echo "    expected: $expected"
        echo "    actual:   $actual"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "$haystack" == *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}  PASS${NC} ${msg:-assert_contains}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}  FAIL${NC} ${msg:-assert_contains}"
        echo "    looking for: $needle"
        echo "    in:          $haystack"
    fi
}

assert_file_contains() {
    local file="$1" needle="$2" msg="${3:-}"
    assert_contains "$(cat "$file" 2>/dev/null || echo)" "$needle" "$msg"
}

# Create a temp workspace and cleanup on EXIT. Returns path via echo.
setup_tmp() {
    local tmp
    tmp=$(mktemp -d)
    trap "rm -rf '$tmp'" EXIT
    echo "$tmp"
}

# Build a fake `claude` binary that echoes the file at $1 and put it first on PATH.
# Returns the PATH-prefixed dir. Caller must export PATH.
make_fake_claude() {
    local tmpdir="$1" output_file="$2"
    local bin="$tmpdir/bin"
    mkdir -p "$bin"
    cat > "$bin/claude" <<EOF
#!/usr/bin/env bash
# Fake claude CLI for tests. Ignores all args, just outputs the fixture.
cat "$output_file"
EOF
    chmod +x "$bin/claude"
    echo "$bin"
}

print_summary() {
    echo
    echo "----------------------------------------"
    echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"
    echo "----------------------------------------"
    [ "$TESTS_FAILED" -eq 0 ]
}
```

- [ ] **Step 2: Write `tests/run.sh`**

Create `/home/jayesh0vasudeva/Housekeeping/tests/run.sh`:

```bash
#!/usr/bin/env bash
# Run all test_*.sh files. Exit non-zero on any failure.

set -u
cd "$(dirname "$0")"

overall_failed=0

for t in test_*.sh; do
    [ -f "$t" ] || continue
    echo "=== $t ==="
    if bash "$t"; then
        :
    else
        overall_failed=$((overall_failed + 1))
    fi
    echo
done

if [ "$overall_failed" -gt 0 ]; then
    echo "FAILED: $overall_failed test file(s) had failures"
    exit 1
fi

echo "All test files passed."
```

- [ ] **Step 3: Make executable and smoke-run**

```bash
chmod +x ~/Housekeeping/tests/run.sh
bash ~/Housekeeping/tests/run.sh
```

Expected: prints `All test files passed.` (no tests exist yet, so nothing runs).

- [ ] **Step 4: Commit**

```bash
cd ~/Housekeeping
git add tests/lib.sh tests/run.sh
git commit -m "test: add shared test harness and runner"
```

---

## Task 3: Prompt template

**Files:**
- Create: `scripts/lib/prompt.txt`

- [ ] **Step 1: Write the prompt template**

Create `/home/jayesh0vasudeva/Housekeeping/scripts/lib/prompt.txt`:

```
You are maintaining a personal TODO list for a developer. You will be given:

  1. The CURRENT TODO (markdown with stable section headers)
  2. RECENT ACTIVITY from a Claude Code session transcript

Your job: produce an UPDATED TODO that reflects the recent activity.

RULES:
- Preserve the three section headers exactly: "## Active", "## Blocked / Waiting", "## Done (last 7 days)".
- Keep the `# TODO` top header.
- Update the `_Last updated: ..._` metadata line with: the timestamp provided in {{NOW}}, session id {{SESSION_ID}}, cwd {{CWD}}.
- Tag every item with `[project]` where project is inferred from the cwd or transcript (fall back to `[misc]`).
- Move completed items to `## Done (last 7 days)` with `- [x] YYYY-MM-DD` prefix.
- Add new items mentioned in the activity to `## Active`.
- Move blocked items to `## Blocked / Waiting` (with a short reason in parentheses).
- PRESERVE any existing items that the activity does not clearly address — do not delete them.
- PRESERVE any unrecognized content the user may have written manually.
- Output ONLY the updated markdown. No commentary, no code fences, no explanation.

CURRENT TODO:
---
{{CURRENT_TODO}}
---

RECENT ACTIVITY (last 50 turns, may be truncated):
---
{{TRANSCRIPT}}
---

Output the updated TODO now.
```

- [ ] **Step 2: Commit**

```bash
cd ~/Housekeeping
git add scripts/lib/prompt.txt
git commit -m "feat: prompt template for TODO reconciliation"
```

---

## Task 4: TODO.md starter template

**Files:**
- Create: `TODO.md.template`

- [ ] **Step 1: Write the template**

Create `/home/jayesh0vasudeva/Housekeeping/TODO.md.template`:

```markdown
# TODO

_Last updated: never — freshly installed_

## Active

## Blocked / Waiting

## Done (last 7 days)
```

- [ ] **Step 2: Commit**

```bash
cd ~/Housekeeping
git add TODO.md.template
git commit -m "feat: starter template for TODO.md"
```

---

## Task 5: Test — lock (write the failing test)

**Files:**
- Create: `tests/test_lock.sh`
- Create: `tests/fixtures/fake-claude-output.md`

- [ ] **Step 1: Write `fixtures/fake-claude-output.md`**

Create `/home/jayesh0vasudeva/Housekeeping/tests/fixtures/fake-claude-output.md`:

```markdown
# TODO

_Last updated: 2026-04-23 00:00 UTC by session test (cwd: /tmp)_

## Active
- [ ] [test] fake output

## Blocked / Waiting

## Done (last 7 days)
```

- [ ] **Step 2: Write `tests/test_lock.sh`**

Create `/home/jayesh0vasudeva/Housekeeping/tests/test_lock.sh`:

```bash
#!/usr/bin/env bash
# Two concurrent updaters must produce exactly one write to TODO.md.

set -u
source "$(dirname "$0")/lib.sh"

tmp=$(setup_tmp)
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
```

- [ ] **Step 3: Run the test — it must fail because the script does not exist yet**

Run: `bash ~/Housekeeping/tests/test_lock.sh`
Expected: FAIL (script missing, both workers return non-zero).

- [ ] **Step 4: Commit**

```bash
cd ~/Housekeeping
git add tests/test_lock.sh tests/fixtures/fake-claude-output.md
git commit -m "test: failing test for lock-based concurrency"
```

---

## Task 6: Implement `todo-update.sh` minimal — lock + write loop

**Files:**
- Create: `scripts/todo-update.sh`

- [ ] **Step 1: Write the script**

Create `/home/jayesh0vasudeva/Housekeeping/scripts/todo-update.sh`:

```bash
#!/usr/bin/env bash
# todo-update.sh [stop|end]
#
# Phase A (default): read hook JSON, fork Phase B in background, return instantly.
# Phase B (TODO_UPDATE_PHASE=B): acquire lock, throttle, run claude -p, atomic write.

set -u

TRIGGER="${1:-end}"
HOUSEKEEPING_DIR="${HOUSEKEEPING_DIR:-$HOME/Housekeeping}"
TODO_FILE="$HOUSEKEEPING_DIR/TODO.md"
LOCK_FILE="$HOUSEKEEPING_DIR/.todo-update.lock"
MTIME_FILE="$HOUSEKEEPING_DIR/.todo-last-update"
EVENT_LOG="$HOUSEKEEPING_DIR/.todo-events.log"
TMP_FILE="$HOUSEKEEPING_DIR/TODO.md.tmp"
THROTTLE_SECONDS=300
PROMPT_TEMPLATE="$(dirname "$(readlink -f "$0")")/lib/prompt.txt"

mkdir -p "$HOUSEKEEPING_DIR" 2>/dev/null || true

log_event() {
    local result="$1" detail="${2:-}"
    local ts session_id cwd
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    session_id="${HOOK_SESSION_ID:-unknown}"
    cwd="${HOOK_CWD:-$PWD}"
    printf '{"ts":"%s","trigger":"%s","session":"%s","cwd":"%s","result":"%s","detail":"%s"}\n' \
        "$ts" "$TRIGGER" "$session_id" "$cwd" "$result" "$detail" \
        >> "$EVENT_LOG" 2>/dev/null || true
}

phase_a() {
    # Parse hook JSON from stdin (best-effort)
    local stdin_json=""
    if [ ! -t 0 ]; then
        stdin_json=$(cat)
    fi
    local session_id="" cwd="" transcript_path=""
    if [ -n "$stdin_json" ] && command -v jq >/dev/null 2>&1; then
        session_id=$(echo "$stdin_json" | jq -r '.session_id // ""' 2>/dev/null || echo "")
        cwd=$(echo "$stdin_json" | jq -r '.cwd // ""' 2>/dev/null || echo "")
        transcript_path=$(echo "$stdin_json" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
    fi

    # Fork Phase B fully detached
    (
        TODO_UPDATE_PHASE=B \
        HOOK_SESSION_ID="$session_id" \
        HOOK_CWD="$cwd" \
        HOOK_TRANSCRIPT_PATH="$transcript_path" \
        "$0" "$TRIGGER" >>"$EVENT_LOG" 2>&1
    ) </dev/null &
    disown 2>/dev/null || true
    exit 0
}

phase_b() {
    # Acquire lock, non-blocking
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        log_event "lock_held"
        exit 0
    fi

    # Throttle (skip for 'end' trigger)
    if [ "$TRIGGER" = "stop" ] && [ -f "$MTIME_FILE" ]; then
        local last_update_ts now diff
        last_update_ts=$(stat -c %Y "$MTIME_FILE" 2>/dev/null || echo 0)
        now=$(date +%s)
        diff=$((now - last_update_ts))
        if [ "$diff" -lt "$THROTTLE_SECONDS" ]; then
            log_event "throttled" "age=${diff}s"
            exit 0
        fi
    fi

    # Read current TODO (or seed from template/empty)
    local current_todo=""
    if [ -f "$TODO_FILE" ]; then
        current_todo=$(cat "$TODO_FILE")
    else
        current_todo=$'# TODO\n\n## Active\n\n## Blocked / Waiting\n\n## Done (last 7 days)\n'
    fi

    # Read transcript (best effort — may be empty in tests)
    local transcript=""
    if [ -n "${HOOK_TRANSCRIPT_PATH:-}" ] && [ -f "$HOOK_TRANSCRIPT_PATH" ]; then
        # Last ~50 lines; truncate to 30KB
        transcript=$(tail -n 50 "$HOOK_TRANSCRIPT_PATH" | head -c 30720)
    fi

    # Build prompt
    local now session_id cwd
    now=$(date -u +"%Y-%m-%d %H:%M UTC")
    session_id="${HOOK_SESSION_ID:-unknown}"
    cwd="${HOOK_CWD:-$PWD}"

    local prompt
    prompt=$(cat "$PROMPT_TEMPLATE")
    prompt="${prompt//\{\{NOW\}\}/$now}"
    prompt="${prompt//\{\{SESSION_ID\}\}/$session_id}"
    prompt="${prompt//\{\{CWD\}\}/$cwd}"
    prompt="${prompt//\{\{CURRENT_TODO\}\}/$current_todo}"
    prompt="${prompt//\{\{TRANSCRIPT\}\}/$transcript}"

    # Call claude -p (60s timeout)
    local new_todo
    if ! new_todo=$(timeout 60 claude -p --model claude-haiku-4-5-20251001 "$prompt" 2>/dev/null); then
        log_event "claude_error"
        exit 0
    fi

    # Validate output structure
    if ! echo "$new_todo" | grep -q '^# TODO' \
       || ! echo "$new_todo" | grep -q '^## Active' \
       || ! echo "$new_todo" | grep -q '^## Blocked / Waiting' \
       || ! echo "$new_todo" | grep -q '^## Done (last 7 days)'; then
        log_event "malformed_output"
        exit 0
    fi

    # Atomic write
    printf '%s' "$new_todo" > "$TMP_FILE"
    # Ensure trailing newline
    [ -z "$(tail -c 1 "$TMP_FILE")" ] || printf '\n' >> "$TMP_FILE"
    mv "$TMP_FILE" "$TODO_FILE"
    touch "$MTIME_FILE"
    log_event "wrote"
    exit 0
}

if [ "${TODO_UPDATE_PHASE:-A}" = "B" ]; then
    phase_b
else
    phase_a
fi
```

- [ ] **Step 2: Make executable**

```bash
chmod +x ~/Housekeeping/scripts/todo-update.sh
```

- [ ] **Step 3: Run the lock test — it should pass**

Run: `bash ~/Housekeeping/tests/test_lock.sh`
Expected: both assertions PASS, exit 0.

- [ ] **Step 4: Commit**

```bash
cd ~/Housekeeping
git add scripts/todo-update.sh
git commit -m "feat: todo-update.sh with two-phase design and flock"
```

---

## Task 7: Test — throttle (failing, then passing)

**Files:**
- Create: `tests/test_throttle.sh`

- [ ] **Step 1: Write `tests/test_throttle.sh`**

Create `/home/jayesh0vasudeva/Housekeeping/tests/test_throttle.sh`:

```bash
#!/usr/bin/env bash
# Two 'stop' invocations close together → second is throttled.
# 'end' invocation bypasses throttle.

set -u
source "$(dirname "$0")/lib.sh"

tmp=$(setup_tmp)
export HOUSEKEEPING_DIR="$tmp"
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
```

- [ ] **Step 2: Run it — should pass already because Task 6 implemented throttle**

Run: `bash ~/Housekeeping/tests/test_throttle.sh`
Expected: 3 PASS, exit 0.

- [ ] **Step 3: Commit**

```bash
cd ~/Housekeeping
git add tests/test_throttle.sh
git commit -m "test: throttle and end-bypass behavior"
```

---

## Task 8: Test — golden-file reconciliation

**Files:**
- Create: `tests/fixtures/todo-before.md`
- Create: `tests/fixtures/transcript.jsonl`
- Create: `tests/fixtures/todo-golden.md`
- Create: `tests/test_golden.sh`

- [ ] **Step 1: Write `fixtures/todo-before.md`**

Create `/home/jayesh0vasudeva/Housekeeping/tests/fixtures/todo-before.md`:

```markdown
# TODO

_Last updated: 2026-04-22 10:00 UTC by session old (cwd: ~/slides)_

## Active
- [ ] [slides] wire up CLI flag `--theme`
- [ ] [AortaAIM] regenerate landmark JSON

## Blocked / Waiting

## Done (last 7 days)
```

- [ ] **Step 2: Write `fixtures/transcript.jsonl`**

Create `/home/jayesh0vasudeva/Housekeeping/tests/fixtures/transcript.jsonl`:

```jsonl
{"type":"user","message":{"content":"finish wiring the --theme flag"}}
{"type":"assistant","message":{"content":"Done, flag is parsed and applied."}}
{"type":"user","message":{"content":"start on --output flag next"}}
```

- [ ] **Step 3: Write `fixtures/todo-golden.md`**

This is what the fake `claude` will return (so the golden test checks our script's I/O, not the model). Create `/home/jayesh0vasudeva/Housekeeping/tests/fixtures/todo-golden.md`:

```markdown
# TODO

_Last updated: 2026-04-23 12:00 UTC by session golden (cwd: ~/slides)_

## Active
- [ ] [slides] `--output` flag
- [ ] [AortaAIM] regenerate landmark JSON

## Blocked / Waiting

## Done (last 7 days)
- [x] 2026-04-23 [slides] wire up `--theme` flag
```

- [ ] **Step 4: Write `tests/test_golden.sh`**

Create `/home/jayesh0vasudeva/Housekeeping/tests/test_golden.sh`:

```bash
#!/usr/bin/env bash
# End-to-end: given a known TODO + transcript, script produces the golden output.

set -u
source "$(dirname "$0")/lib.sh"

tmp=$(setup_tmp)
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
```

- [ ] **Step 5: Run it**

Run: `bash ~/Housekeeping/tests/test_golden.sh`
Expected: 1 PASS, exit 0.

- [ ] **Step 6: Commit**

```bash
cd ~/Housekeeping
git add tests/test_golden.sh tests/fixtures/todo-before.md tests/fixtures/transcript.jsonl tests/fixtures/todo-golden.md
git commit -m "test: golden-file end-to-end reconciliation"
```

---

## Task 9: Test — malformed output

**Files:**
- Create: `tests/fixtures/fake-claude-garbage.txt`
- Create: `tests/test_malformed.sh`

- [ ] **Step 1: Write `fixtures/fake-claude-garbage.txt`**

Create `/home/jayesh0vasudeva/Housekeeping/tests/fixtures/fake-claude-garbage.txt`:

```
I don't want to output a TODO. Here is a recipe for pancakes instead.
1. Mix flour and milk.
2. Pour into pan.
```

- [ ] **Step 2: Write `tests/test_malformed.sh`**

Create `/home/jayesh0vasudeva/Housekeeping/tests/test_malformed.sh`:

```bash
#!/usr/bin/env bash
# If claude -p returns garbage, TODO.md must be untouched and event logged.

set -u
source "$(dirname "$0")/lib.sh"

tmp=$(setup_tmp)
export HOUSEKEEPING_DIR="$tmp"

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
```

- [ ] **Step 3: Run it**

Run: `bash ~/Housekeeping/tests/test_malformed.sh`
Expected: 2 PASS, exit 0.

- [ ] **Step 4: Commit**

```bash
cd ~/Housekeeping
git add tests/test_malformed.sh tests/fixtures/fake-claude-garbage.txt
git commit -m "test: malformed claude output leaves TODO untouched"
```

---

## Task 10: SessionStart hook script (test first)

**Files:**
- Create: `tests/test_session_start.sh`
- Create: `scripts/todo-session-start.sh`

- [ ] **Step 1: Write `tests/test_session_start.sh`**

Create `/home/jayesh0vasudeva/Housekeeping/tests/test_session_start.sh`:

```bash
#!/usr/bin/env bash
# todo-session-start.sh must output valid JSON with additionalContext
# containing the TODO.md contents.

set -u
source "$(dirname "$0")/lib.sh"

tmp=$(setup_tmp)
export HOUSEKEEPING_DIR="$tmp"

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

print_summary
```

- [ ] **Step 2: Run it — must fail (script does not exist)**

Run: `bash ~/Housekeeping/tests/test_session_start.sh`
Expected: FAIL.

- [ ] **Step 3: Write `scripts/todo-session-start.sh`**

Create `/home/jayesh0vasudeva/Housekeeping/scripts/todo-session-start.sh`:

```bash
#!/usr/bin/env bash
# Emits Claude Code SessionStart hook JSON with the current TODO as additionalContext.
# If TODO.md does not exist, emits nothing (exit 0).

set -u

HOUSEKEEPING_DIR="${HOUSEKEEPING_DIR:-$HOME/Housekeeping}"
TODO_FILE="$HOUSEKEEPING_DIR/TODO.md"

[ -f "$TODO_FILE" ] || exit 0

# Read TODO and JSON-escape it
todo=$(cat "$TODO_FILE")
if command -v python3 >/dev/null 2>&1; then
    escaped=$(python3 -c '
import json, sys
print(json.dumps(sys.stdin.read()), end="")
' <<< "$todo")
else
    # Minimal fallback: escape backslashes, quotes, newlines
    escaped=$(printf '%s' "$todo" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk 'BEGIN{ORS="\\n"} {print}')
    escaped="\"$escaped\""
fi

cat <<EOF
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$escaped}}
EOF
```

- [ ] **Step 4: Make executable, run test**

```bash
chmod +x ~/Housekeeping/scripts/todo-session-start.sh
bash ~/Housekeeping/tests/test_session_start.sh
```

Expected: 3 PASS, exit 0.

- [ ] **Step 5: Commit**

```bash
cd ~/Housekeeping
git add tests/test_session_start.sh scripts/todo-session-start.sh
git commit -m "feat: SessionStart hook emits TODO as additionalContext"
```

---

## Task 11: `install.sh` — merge hooks into `~/.claude/settings.json`

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Write the installer**

Create `/home/jayesh0vasudeva/Housekeeping/install.sh`:

```bash
#!/usr/bin/env bash
# Install the auto-TODO system:
#   1. Symlink scripts into ~/.claude/
#   2. Merge hook entries into ~/.claude/settings.json
#   3. Seed TODO.md from template if absent
#   4. Run smoke test

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
TODO_FILE="$REPO_DIR/TODO.md"

echo "==> Installing from $REPO_DIR"
mkdir -p "$CLAUDE_DIR"

# 1. Symlink scripts
for s in todo-update.sh todo-session-start.sh; do
    src="$REPO_DIR/scripts/$s"
    dst="$CLAUDE_DIR/$s"
    if [ ! -x "$src" ]; then
        chmod +x "$src"
    fi
    ln -sfn "$src" "$dst"
    echo "    linked $dst -> $src"
done

# 2. Merge settings.json
python3 - "$SETTINGS" <<'PY'
import json, os, sys
path = sys.argv[1]
existing = {}
if os.path.exists(path):
    with open(path) as f:
        try:
            existing = json.load(f)
        except json.JSONDecodeError:
            print(f"ERROR: {path} is not valid JSON; aborting merge", file=sys.stderr)
            sys.exit(1)

hooks = existing.setdefault("hooks", {})

def add_hook(event, command):
    entries = hooks.setdefault(event, [])
    # Skip if this exact command is already present
    for entry in entries:
        for h in entry.get("hooks", []):
            if h.get("command") == command:
                return
    entries.append({"hooks": [{"type": "command", "command": command}]})

add_hook("SessionStart", "~/.claude/todo-session-start.sh")
add_hook("Stop",         "~/.claude/todo-update.sh stop")
add_hook("SessionEnd",   "~/.claude/todo-update.sh end")

with open(path, "w") as f:
    json.dump(existing, f, indent=2)
    f.write("\n")
print(f"    merged hooks into {path}")
PY

# 3. Seed TODO.md
if [ ! -f "$TODO_FILE" ]; then
    cp "$REPO_DIR/TODO.md.template" "$TODO_FILE"
    echo "    seeded $TODO_FILE"
else
    echo "    $TODO_FILE already exists (left alone)"
fi

# 4. Smoke test — one full Phase B cycle against a throwaway dir
echo "==> Smoke test"
tmp=$(mktemp -d)
trap "rm -rf '$tmp'" EXIT
cp "$REPO_DIR/TODO.md.template" "$tmp/TODO.md"
HOUSEKEEPING_DIR="$tmp" \
HOOK_SESSION_ID="install-smoke" \
HOOK_CWD="$PWD" \
TODO_UPDATE_PHASE=B \
"$REPO_DIR/scripts/todo-update.sh" end || echo "    smoke test exited non-zero (may be OK if claude CLI unavailable in this shell)"

if [ -f "$tmp/.todo-events.log" ]; then
    echo "--- last smoke event ---"
    tail -n 1 "$tmp/.todo-events.log"
fi

echo
echo "==> Done. Hooks active in future Claude Code sessions."
echo "    TODO file: $TODO_FILE"
echo "    Event log: $REPO_DIR/.todo-events.log"
```

- [ ] **Step 2: Make executable and dry-run**

```bash
chmod +x ~/Housekeeping/install.sh
# Don't actually run against live settings yet — inspect first
cat ~/Housekeeping/install.sh | head -5
```

- [ ] **Step 3: Commit**

```bash
cd ~/Housekeeping
git add install.sh
git commit -m "feat: install.sh — symlink scripts, merge hooks, seed TODO"
```

---

## Task 12: `uninstall.sh`

**Files:**
- Create: `uninstall.sh`

- [ ] **Step 1: Write the uninstaller**

Create `/home/jayesh0vasudeva/Housekeeping/uninstall.sh`:

```bash
#!/usr/bin/env bash
# Inverse of install.sh. Removes the three hook entries and the two symlinks.
# Does NOT delete TODO.md or .todo-events.log — that's user data.

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

echo "==> Uninstalling auto-TODO hooks"

# Remove symlinks (only if they point at our scripts)
for s in todo-update.sh todo-session-start.sh; do
    target="$CLAUDE_DIR/$s"
    if [ -L "$target" ]; then
        rm -f "$target"
        echo "    removed symlink $target"
    elif [ -e "$target" ]; then
        echo "    WARNING: $target exists and is not a symlink — leaving in place"
    fi
done

# Strip hook entries
if [ -f "$SETTINGS" ]; then
    python3 - "$SETTINGS" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)

targets = {
    "SessionStart": "~/.claude/todo-session-start.sh",
    "Stop":         "~/.claude/todo-update.sh stop",
    "SessionEnd":   "~/.claude/todo-update.sh end",
}

hooks = data.get("hooks", {})
for event, cmd in targets.items():
    if event not in hooks:
        continue
    filtered = []
    for entry in hooks[event]:
        kept = [h for h in entry.get("hooks", []) if h.get("command") != cmd]
        if kept:
            entry["hooks"] = kept
            filtered.append(entry)
    if filtered:
        hooks[event] = filtered
    else:
        del hooks[event]

if not hooks:
    data.pop("hooks", None)

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(f"    cleaned hook entries from {path}")
PY
else
    echo "    no settings.json found — nothing to clean"
fi

echo "==> Done. TODO.md and .todo-events.log preserved."
```

- [ ] **Step 2: Make executable**

```bash
chmod +x ~/Housekeeping/uninstall.sh
```

- [ ] **Step 3: Commit**

```bash
cd ~/Housekeeping
git add uninstall.sh
git commit -m "feat: uninstall.sh — remove hooks and symlinks, preserve data"
```

---

## Task 13: Run full test suite

- [ ] **Step 1: Run everything**

Run: `bash ~/Housekeeping/tests/run.sh`
Expected: every test PASSes, final line `All test files passed.`, exit 0.

- [ ] **Step 2: Inspect any failures**

If any test fails, read its output, find the first FAIL line, fix the underlying script (not the test), re-run, commit the fix with `fix: ...` message.

- [ ] **Step 3: Commit nothing if all green**

No commit needed if all tests pass — this is a verification step.

---

## Task 14: Install for real + live smoke test

- [ ] **Step 1: Run `install.sh`**

```bash
bash ~/Housekeeping/install.sh
```

Expected: symlinks created, settings.json merged, TODO.md seeded, smoke test output printed.

- [ ] **Step 2: Verify symlinks**

```bash
ls -l ~/.claude/todo-update.sh ~/.claude/todo-session-start.sh
```

Expected: both are symlinks pointing into `~/Housekeeping/scripts/`.

- [ ] **Step 3: Verify `settings.json`**

```bash
python3 -c "import json; print(json.dumps(json.load(open('$HOME/.claude/settings.json'))['hooks'], indent=2))"
```

Expected: `hooks` contains `SessionStart`, `Stop`, `SessionEnd` entries with our commands.

- [ ] **Step 4: Verify TODO.md seeded**

```bash
cat ~/Housekeeping/TODO.md
```

Expected: matches the template — `# TODO`, empty sections.

- [ ] **Step 5: Manual live trigger test**

Open a new Claude Code session (any directory), send one short message, wait for response, then end the session with `/exit`. In the original shell:

```bash
tail -n 5 ~/Housekeeping/.todo-events.log
cat ~/Housekeeping/TODO.md
```

Expected: at least one event line with `"result":"wrote"` OR `"result":"throttled"` (depending on timing). TODO.md may have updated content.

- [ ] **Step 6: Commit any residual changes**

```bash
cd ~/Housekeeping
git status
# If scripts had permission bit changes, commit them:
git add -A
git diff --cached --name-only
git commit -m "chore: ensure scripts are executable" || true
```

---

## Task 15: README update

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace README with useful content**

Read current: `cat ~/Housekeeping/README.md`

Write `/home/jayesh0vasudeva/Housekeeping/README.md`:

```markdown
# Housekeeping

Central home for background skills, hooks, and shared workflows that keep
my Claude Code sessions honest.

## Components

### Background auto-updating TODO

A single TODO list at `~/Housekeeping/TODO.md` kept fresh by every Claude
Code session I run. See `docs/superpowers/specs/2026-04-23-background-todo-design.md`.

**Install:**

```bash
bash install.sh
```

**Uninstall:**

```bash
bash uninstall.sh
```

**View the spec as slides:**

```bash
slides docs/superpowers/specs/2026-04-23-background-todo-design.md
```

## Tests

```bash
bash tests/run.sh
```
```

- [ ] **Step 2: Commit**

```bash
cd ~/Housekeeping
git add README.md
git commit -m "docs: README covers auto-TODO install and tests"
```

---

## Self-Review

**Spec coverage check:**

- §1 Purpose → Tasks 6, 11, 14 (cross-session state via hooks + install)
- §2 Non-goals → N/A (nothing to implement)
- §3 Architecture → Tasks 6, 10, 11 (scripts + hooks + settings merge)
- §4.1 TODO schema → Task 4 (template), Task 3 (prompt enforces headers), Task 6 (validation)
- §4.2 Phase A + Phase B → Task 6 (both phases in one script, gated by `TODO_UPDATE_PHASE`)
- §4.3 SessionStart → Task 10
- §4.4 Hook config → Task 11 (install.sh merge)
- §4.5 install / uninstall → Tasks 11 and 12
- §5 Data flow → Task 6 covers the full chain
- §6 Concurrency → Task 5 (lock test) + Task 6 (implementation)
- §7 Failure modes:
  - Lock held → Task 5 + Task 6
  - Timeout → Task 6 (`timeout 60`)
  - Malformed → Task 9 (test) + Task 6 (validation)
  - Rename fails → Task 6 uses `mv` (atomic on same fs); `.tmp` lingers and is overwritten
  - Clock skew → self-healing, no code needed
  - User edit mid-update → lock + prompt's "preserve unknown content" rule (Task 3)
  - Hook error → Task 6 exits 0 on every failure path
  - `claude` not on PATH → install smoke test (Task 11 step 4) will show error in event log
- §8 Testing → Tasks 5, 7, 8, 9, 10, plus runner in Task 2
- §9 Cost budget → implicit in Task 6 (Haiku model + 5-min throttle + 60s timeout)
- §10 Open questions → out of scope (noted)

**Placeholder scan:** none found.

**Type consistency:**
- Script env vars: `HOUSEKEEPING_DIR`, `HOOK_SESSION_ID`, `HOOK_CWD`, `HOOK_TRANSCRIPT_PATH`, `TODO_UPDATE_PHASE` — all used consistently across Task 6, Task 8, Task 9, Task 10.
- Event-log `result` values: `wrote`, `lock_held`, `throttled`, `claude_error`, `malformed_output` — consistent across script and all tests.
- File paths: `TODO.md`, `.todo-update.lock`, `.todo-last-update`, `.todo-events.log`, `TODO.md.tmp` — consistent everywhere.
- Script commands in `settings.json`: `~/.claude/todo-session-start.sh`, `~/.claude/todo-update.sh stop`, `~/.claude/todo-update.sh end` — match between install.sh (Task 11) and uninstall.sh (Task 12).

No issues found.

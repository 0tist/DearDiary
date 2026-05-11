#!/usr/bin/env bash
# diary-process.sh [cron|button]
#
# Phase A (default): fork Phase B in background, return instantly. Used by
#   launchd (cron) and by the Tauri app's "Process Now" button.
# Phase B (DIARY_PROCESS_PHASE=B): acquire flock, build prompt from inbox,
#   shell out to `claude -p` with a tight tool allowlist; Claude itself
#   reads/writes/moves the diary files.

set -u

TRIGGER="${1:-cron}"
DEARDIARY_DIR="${DEARDIARY_DIR:-$HOME/DearDiary}"
DIARY_ROOT="$DEARDIARY_DIR/diary"
INBOX_DIR="$DIARY_ROOT/inbox"
PROCESSED_DIR="$DIARY_ROOT/processed"
TODO_FILE="$DEARDIARY_DIR/TODO.md"
LOCK_DIR="$DEARDIARY_DIR/.diary-process.lock.d"
EVENT_LOG="$DEARDIARY_DIR/.diary-events.log"
SCRIPT_REAL="$(readlink -f "$0" 2>/dev/null || echo "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_REAL")"
PROMPT_TEMPLATE="$SCRIPT_DIR/lib/diary-prompt.txt"
SKILLS_DIR="$(dirname "$SCRIPT_DIR")/claude"

mkdir -p "$INBOX_DIR" "$PROCESSED_DIR" 2>/dev/null || true

log_event() {
    local result="$1" detail="${2:-}" count="${3:-0}"
    local ts session_id cwd
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    session_id="${HOOK_SESSION_ID:-unknown}"
    cwd="${HOOK_CWD:-$PWD}"
    printf '{"ts":"%s","trigger":"%s","session":"%s","cwd":"%s","result":"%s","count":%s,"detail":"%s"}\n' \
        "$ts" "$TRIGGER" "$session_id" "$cwd" "$result" "$count" "$detail" \
        >> "$EVENT_LOG" 2>/dev/null || true
}

phase_a() {
    # Fork Phase B fully detached and return immediately so the caller
    # (launchd / the Tauri app) is never blocked on `claude -p`.
    # Use SCRIPT_REAL (absolute path) — if the user invoked us via a
    # bare filename, $0 has no path component and bash would fail the
    # subshell exec with "command not found".
    (
        DIARY_PROCESS_PHASE=B \
        HOOK_SESSION_ID="${HOOK_SESSION_ID:-$TRIGGER}" \
        HOOK_CWD="${HOOK_CWD:-$PWD}" \
        "$SCRIPT_REAL" "$TRIGGER" >>"$EVENT_LOG" 2>&1
    ) </dev/null &
    disown 2>/dev/null || true
    exit 0
}

phase_b() {
    # Acquire lock via atomic mkdir. mkdir(2) returns EEXIST if the directory
    # exists, and the create-or-fail semantics are atomic on macOS and Linux.
    # Avoids depending on flock(1), which macOS doesn't ship by default.
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        log_event "lock_held"
        exit 0
    fi
    # shellcheck disable=SC2064
    trap "rmdir '$LOCK_DIR' 2>/dev/null" EXIT

    # Pre-flight: empty inbox is a no-op.
    shopt -s nullglob
    local inbox_files=("$INBOX_DIR"/*.md)
    if [ "${#inbox_files[@]}" -eq 0 ]; then
        log_event "inbox_empty"
        exit 0
    fi

    # Build prompt
    local now workspace_tree inbox_listing prompt
    now=$(date -u +"%Y-%m-%d %H:%M UTC")

    # Workspace tree: existing top-level folders under diary root, excluding
    # inbox/ (uninteresting). Use ls instead of `tree` (not always installed).
    workspace_tree=$(cd "$DIARY_ROOT" && ls -1 | grep -v '^inbox$' | sed 's/^/- /' || true)
    [ -z "$workspace_tree" ] && workspace_tree="(no folders yet — first run)"

    # Inbox listing: file paths + first few lines of each, so claude has
    # context without us needing a separate Read call per file.
    inbox_listing=""
    local f id body
    for f in "${inbox_files[@]}"; do
        id=$(basename "$f" .md)
        body=$(head -c 2048 "$f")
        inbox_listing+="--- $f"$'\n'"$body"$'\n\n'
    done

    # Concatenate every claude/<skill>/SKILL.md so the prompt picks them up
    # without us having to re-edit the script when a new skill is added.
    local skills_block="" skill_file skill_name
    if [ -d "$SKILLS_DIR" ]; then
        for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
            [ -f "$skill_file" ] || continue
            skill_name=$(basename "$(dirname "$skill_file")")
            skills_block+="### Skill: $skill_name"$'\n'
            skills_block+="(source: $skill_file)"$'\n\n'
            skills_block+="$(cat "$skill_file")"$'\n\n'
            skills_block+="---"$'\n\n'
        done
    fi
    [ -z "$skills_block" ] && skills_block="(no skills installed; default routing only)"

    prompt=$(cat "$PROMPT_TEMPLATE")
    prompt="${prompt//\{\{NOW\}\}/$now}"
    prompt="${prompt//\{\{DIARY_ROOT\}\}/$DIARY_ROOT}"
    prompt="${prompt//\{\{TODO_FILE\}\}/$TODO_FILE}"
    prompt="${prompt//\{\{WORKSPACE_TREE\}\}/$workspace_tree}"
    prompt="${prompt//\{\{INBOX_LISTING\}\}/$inbox_listing}"
    prompt="${prompt//\{\{SKILLS\}\}/$skills_block}"

    # Shell out to claude. Tools are scoped tightly: read/write under the
    # diary tree, plus mkdir/mv for filing. acceptEdits skips the per-tool
    # interactive permission prompt that would otherwise block headless runs.
    # Wrap with `timeout`/`gtimeout` if either is on PATH; macOS ships neither.
    local claude_stdout claude_stderr timeout_cmd
    claude_stdout=$(mktemp)
    claude_stderr=$(mktemp)
    if command -v timeout >/dev/null 2>&1; then
        timeout_cmd="timeout 180"
    elif command -v gtimeout >/dev/null 2>&1; then
        timeout_cmd="gtimeout 180"
    else
        timeout_cmd=""
    fi
    # Pipe the prompt via stdin (not as a positional) so it can't get
    # swallowed by a variadic flag like --allowedTools.
    # `acceptEdits` auto-accepts file Read/Write/Edit; the Bash patterns
    # below are the only shell commands the installed skills should need
    # (filing entries: mkdir+mv; deardiary-fixer: git+gh).
    if ! (cd "$DEARDIARY_DIR" && printf '%s' "$prompt" | $timeout_cmd claude -p \
            --model claude-haiku-4-5-20251001 \
            --permission-mode acceptEdits \
            --allowedTools "Read,Write,Edit,Glob,Bash(mkdir:*),Bash(mv:*),Bash(git:*),Bash(gh:*)" \
            >"$claude_stdout" 2>"$claude_stderr"); then
        local stderr_tail
        stderr_tail=$(tail -c 400 "$claude_stderr" 2>/dev/null | tr '\n"' ' ' | sed 's/[[:space:]]\+/ /g')
        rm -f "$claude_stdout" "$claude_stderr"
        log_event "claude_error" "${stderr_tail:-no_stderr}"
        exit 0
    fi

    # Tee claude's per-entry summary into the events log as a detail field.
    local summary
    summary=$(tr '\n"' ' ' < "$claude_stdout" | sed 's/[[:space:]]\+/ /g' | head -c 400)
    rm -f "$claude_stdout" "$claude_stderr"

    # Count what got moved out of the inbox.
    local processed_count
    processed_count=$(find "$INBOX_DIR" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    processed_count=$(( ${#inbox_files[@]} - processed_count ))

    log_event "processed" "$summary" "$processed_count"
    exit 0
}

if [ "${DIARY_PROCESS_PHASE:-A}" = "B" ]; then
    phase_b
else
    phase_a
fi

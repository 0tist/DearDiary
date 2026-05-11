#!/usr/bin/env bash
# todo-update.sh [stop|end]
#
# Phase A (default): read hook JSON, fork Phase B in background, return instantly.
# Phase B (TODO_UPDATE_PHASE=B): acquire lock, throttle, run claude -p, atomic write.

set -u

TRIGGER="${1:-end}"
DEARDIARY_DIR="${DEARDIARY_DIR:-$HOME/DearDiary}"
TODO_FILE="$DEARDIARY_DIR/TODO.md"
LOCK_DIR="$DEARDIARY_DIR/.todo-update.lock.d"
MTIME_FILE="$DEARDIARY_DIR/.todo-last-update"
EVENT_LOG="$DEARDIARY_DIR/.todo-events.log"
TMP_FILE="$DEARDIARY_DIR/TODO.md.tmp"
THROTTLE_SECONDS=300
PROMPT_TEMPLATE="$(dirname "$(readlink -f "$0")")/lib/prompt.txt"

mkdir -p "$DEARDIARY_DIR" 2>/dev/null || true

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
    # Acquire lock via atomic mkdir (portable; macOS doesn't ship flock(1)).
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        log_event "lock_held"
        exit 0
    fi
    # shellcheck disable=SC2064
    trap "rmdir '$LOCK_DIR' 2>/dev/null" EXIT

    # Throttle (skip for 'end' trigger)
    if [ "$TRIGGER" = "stop" ] && [ -f "$MTIME_FILE" ]; then
        local last_update_ts now diff
        # GNU stat (-c %Y) on Linux, BSD stat (-f %m) on macOS — try both.
        last_update_ts=$(stat -c %Y "$MTIME_FILE" 2>/dev/null \
            || stat -f %m "$MTIME_FILE" 2>/dev/null \
            || echo 0)
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

    # Call claude -p from a neutral cwd so the headless invocation does not
    # cold-start against the triggering session's plugins / hooks / CLAUDE.md.
    # 180s budget covers slower cold-starts on the first call after the
    # binary's session cache is empty.
    local new_todo claude_stderr claude_stderr_tail timeout_cmd
    claude_stderr=$(mktemp)
    if command -v timeout >/dev/null 2>&1; then
        timeout_cmd="timeout 180"
    elif command -v gtimeout >/dev/null 2>&1; then
        timeout_cmd="gtimeout 180"
    else
        timeout_cmd=""
    fi
    if ! new_todo=$(cd "$DEARDIARY_DIR" && $timeout_cmd claude -p --model claude-haiku-4-5-20251001 "$prompt" 2>"$claude_stderr"); then
        claude_stderr_tail=$(tail -c 400 "$claude_stderr" 2>/dev/null | tr '\n"' ' ' | sed 's/[[:space:]]\+/ /g')
        rm -f "$claude_stderr"
        log_event "claude_error" "${claude_stderr_tail:-no_stderr}"
        exit 0
    fi
    rm -f "$claude_stderr"

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

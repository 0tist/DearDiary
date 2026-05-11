#!/usr/bin/env bash
# diary-maintain.sh [cron|button]
#
# Phase A (default): fork Phase B in background, return instantly. Used by
#   launchd (cron, Wed 02:00 + Sun 02:00) and by manual button trigger.
# Phase B (DIARY_MAINTAIN_PHASE=B): acquire lock, scan vault for recent
#   notes, shell out to `claude -p` with the reconcile+synthesize prompt.
# Shares the lock dir with diary-process.sh so the two can't race.

set -u

TRIGGER="${1:-cron}"
DEARDIARY_DIR="${DEARDIARY_DIR:-$HOME/DearDiary}"
DIARY_ROOT="$DEARDIARY_DIR"
LOCK_DIR="$DEARDIARY_DIR/.diary-process.lock.d"   # shared with diary-process.sh
EVENT_LOG="$DEARDIARY_DIR/.diary-events.log"
PROMPT_TEMPLATE="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")/lib/diary-maintain-prompt.txt"
RECENT_DAYS="${RECENT_DAYS:-7}"   # window for synthesize step

log_event() {
    local result="$1" detail="${2:-}" count="${3:-0}"
    local ts session_id cwd
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    session_id="${HOOK_SESSION_ID:-maintain}"
    cwd="${HOOK_CWD:-$PWD}"
    printf '{"ts":"%s","trigger":"%s","session":"%s","cwd":"%s","result":"%s","count":%s,"detail":"%s","kind":"maintain"}\n' \
        "$ts" "$TRIGGER" "$session_id" "$cwd" "$result" "$count" "$detail" \
        >> "$EVENT_LOG" 2>/dev/null || true
}

phase_a() {
    (
        DIARY_MAINTAIN_PHASE=B \
        HOOK_SESSION_ID="${HOOK_SESSION_ID:-$TRIGGER}" \
        HOOK_CWD="${HOOK_CWD:-$PWD}" \
        "$0" "$TRIGGER" >>"$EVENT_LOG" 2>&1
    ) </dev/null &
    disown 2>/dev/null || true
    exit 0
}

phase_b() {
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        log_event "lock_held"
        exit 0
    fi
    # shellcheck disable=SC2064
    trap "rmdir '$LOCK_DIR' 2>/dev/null" EXIT

    [ -d "$DIARY_ROOT" ] || { log_event "no_vault"; exit 0; }

    # Vault tree: top-level folders only, excluding noisy infra.
    local vault_tree
    vault_tree=$(cd "$DIARY_ROOT" && ls -1d */ 2>/dev/null \
        | grep -Ev '^(diary|\.obsidian|node_modules)/$' \
        | sed 's|/$||; s|^|- |')
    [ -z "$vault_tree" ] && vault_tree="(no top-level folders yet)"

    # Recent notes: anything modified in the last $RECENT_DAYS days,
    # excluding diary/ subtree (DearDiary infra), .obsidian/, dotfiles.
    local recent_notes
    recent_notes=$(find "$DIARY_ROOT" \
            -type f -name '*.md' \
            -not -path "$DIARY_ROOT/diary/*" \
            -not -path "$DIARY_ROOT/.obsidian/*" \
            -not -name '.*' \
            -mtime "-$RECENT_DAYS" 2>/dev/null \
        | sort \
        | while read -r f; do
            rel="${f#$DIARY_ROOT/}"
            head -c 800 "$f" | sed "s|^|    |"
            printf -- "--- end: %s ---\n\n" "$rel"
        done)
    [ -z "$recent_notes" ] && recent_notes="(no notes modified in the last $RECENT_DAYS days)"

    local now
    now=$(date -u +"%Y-%m-%d %H:%M UTC")

    local prompt
    prompt=$(cat "$PROMPT_TEMPLATE")
    prompt="${prompt//\{\{NOW\}\}/$now}"
    prompt="${prompt//\{\{DIARY_ROOT\}\}/$DIARY_ROOT}"
    prompt="${prompt//\{\{RECENT_DAYS\}\}/$RECENT_DAYS}"
    prompt="${prompt//\{\{VAULT_TREE\}\}/$vault_tree}"
    prompt="${prompt//\{\{RECENT_NOTES\}\}/$recent_notes}"

    local claude_stdout claude_stderr timeout_cmd
    claude_stdout=$(mktemp)
    claude_stderr=$(mktemp)
    if command -v timeout >/dev/null 2>&1; then
        timeout_cmd="timeout 300"
    elif command -v gtimeout >/dev/null 2>&1; then
        timeout_cmd="gtimeout 300"
    else
        timeout_cmd=""
    fi
    if ! (cd "$DIARY_ROOT" && printf '%s' "$prompt" | $timeout_cmd claude -p \
            --model claude-haiku-4-5-20251001 \
            --permission-mode acceptEdits \
            --allowedTools "Read,Write,Edit,Glob,Bash(mkdir:*)" \
            >"$claude_stdout" 2>"$claude_stderr"); then
        local stderr_tail
        stderr_tail=$(tail -c 400 "$claude_stderr" 2>/dev/null | tr '\n"' ' ' | sed 's/[[:space:]]\+/ /g')
        rm -f "$claude_stdout" "$claude_stderr"
        log_event "claude_error" "${stderr_tail:-no_stderr}"
        exit 0
    fi

    local summary
    summary=$(tr '\n"' ' ' < "$claude_stdout" | sed 's/[[:space:]]\+/ /g' | head -c 400)
    rm -f "$claude_stdout" "$claude_stderr"

    log_event "maintained" "$summary"
    exit 0
}

if [ "${DIARY_MAINTAIN_PHASE:-A}" = "B" ]; then
    phase_b
else
    phase_a
fi

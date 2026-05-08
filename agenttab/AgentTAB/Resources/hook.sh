#!/bin/sh
# AgentTAB hook fanout — writes to local socket and (if in Zellij) to zellij pipe.
[ -t 0 ] && exit 0
INPUT=$(cat 2>/dev/null) || exit 0
PAYLOAD=$(printf '%s' "$INPUT" | jq -c \
  --arg pid "${ZELLIJ_PANE_ID:-0}" \
  --arg term "${TERM_PROGRAM:-unknown}" \
  '
  select(.hook_event_name) | {
    pane_id:    ($pid | tonumber),
    session_id: .session_id,
    hook_event: .hook_event_name,
    tool_name:  .tool_name,
    term_program: $term
  }' 2>/dev/null) || exit 0
[ -z "$PAYLOAD" ] && exit 0

printf '%s' "$PAYLOAD" | nc -U "$HOME/Library/Application Support/AgentTAB/hook.sock" -w 1 \
  >/dev/null 2>&1

[ -n "$ZELLIJ_PANE_ID" ] && command -v zellij >/dev/null 2>&1 && \
  zellij pipe --name "claude-tab-status" -- "$PAYLOAD" >/dev/null 2>&1

exit 0

#!/usr/bin/env bash
# claude-zj-hook.sh — Claude Code hook → zellij pipe bridge
# Forwards hook events to the claude-tab-status Zellij plugin.

# Exit silently if not running inside Zellij
[ -z "$ZELLIJ_SESSION_NAME" ] && exit 0
[ -z "$ZELLIJ_PANE_ID" ] && exit 0

# Read hook JSON from stdin, suppress errors
INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

# Single jq invocation: validate hook_event, reshape payload
PAYLOAD=$(echo "$INPUT" | jq -c --arg pid "$ZELLIJ_PANE_ID" '
  select(.hook_event_name != null and .hook_event_name != "") |
  {
    pane_id: ($pid | tonumber),
    session_id: .session_id,
    hook_event: .hook_event_name,
    tool_name: .tool_name
  }
' 2>/dev/null) || exit 0
[ -z "$PAYLOAD" ] && exit 0

# Send to plugin via zellij pipe, suppress all output and errors
zellij pipe --name "claude-tab-status" -- "$PAYLOAD" 2>/dev/null >/dev/null || exit 0

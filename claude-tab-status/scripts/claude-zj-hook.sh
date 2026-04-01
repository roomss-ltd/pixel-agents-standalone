#!/usr/bin/env bash
# claude-zj-hook.sh — Claude Code hook → zellij pipe bridge
# Forwards hook events to the claude-tab-status Zellij plugin.

# Exit silently if not running inside Zellij
[ -z "$ZELLIJ_SESSION_NAME" ] && exit 0
[ -z "$ZELLIJ_PANE_ID" ] && exit 0

# Read hook JSON from stdin
INPUT=$(cat)

# Extract fields with jq (required dependency)
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

[ -z "$HOOK_EVENT" ] && exit 0

# Build compact JSON payload
PAYLOAD=$(jq -nc \
  --arg pane_id "$ZELLIJ_PANE_ID" \
  --arg session_id "$SESSION_ID" \
  --arg hook_event "$HOOK_EVENT" \
  --arg tool_name "$TOOL_NAME" \
  '{
    pane_id: ($pane_id | tonumber),
    session_id: (if $session_id == "" then null else $session_id end),
    hook_event: $hook_event,
    tool_name: (if $tool_name == "" then null else $tool_name end)
  }')

# Send to plugin via zellij pipe
zellij pipe --name "claude-tab-status" -- "$PAYLOAD"

#!/usr/bin/env bash
# codex-zj-hook.sh — Codex CLI hook → zellij pipe bridge
# Forwards Codex hook events to the claude-tab-status Zellij plugin.
#
# Codex CLI hook payload uses the same field names as Claude Code
# (hook_event_name, session_id, tool_name), so the reshape is identical.
# Codex emits: PreToolUse, PostToolUse, UserPromptSubmit, Stop,
# SessionStart, PermissionRequest. There is no SessionEnd or SubagentStop —
# use codex-wrapper.sh to synthesise a SessionEnd on process exit.

[ -z "$ZELLIJ_SESSION_NAME" ] && exit 0
[ -z "$ZELLIJ_PANE_ID" ] && exit 0

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

PAYLOAD=$(echo "$INPUT" | jq -c --arg pid "$ZELLIJ_PANE_ID" '
  select(.hook_event_name != null and .hook_event_name != "") |
  {
    pane_id: ($pid | tonumber),
    session_id: .session_id,
    hook_event: .hook_event_name,
    tool_name: .tool_name,
    cwd: .cwd
  }
' 2>/dev/null) || exit 0
[ -z "$PAYLOAD" ] && exit 0

zellij pipe --name "agent-tab-status-v2" -- "$PAYLOAD" 2>/dev/null >/dev/null || exit 0

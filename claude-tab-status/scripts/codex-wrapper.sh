#!/usr/bin/env bash
# codex-wrapper.sh — wraps `codex` to emit a synthetic SessionEnd hook event
# on process exit. Codex CLI does not have a SessionEnd hook event, so
# without this wrapper, sessions accumulate in the plugin's session map
# until Zellij is restarted.
#
# Usage: alias codex='~/.config/zellij/plugins/codex-wrapper.sh'

[ -z "$ZELLIJ_SESSION_NAME" ] || [ -z "$ZELLIJ_PANE_ID" ] && exec codex "$@"

HOOK="$HOME/.config/zellij/plugins/codex-zj-hook.sh"

emit_session_end() {
  [ -z "${CODEX_SESSION_ID:-}" ] && return 0
  jq -nc --arg sid "$CODEX_SESSION_ID" '{
    hook_event_name: "SessionEnd",
    session_id: $sid
  }' | "$HOOK" 2>/dev/null || true
}

# Best-effort session id capture: Codex writes rollouts to ~/.codex/sessions/.
# We snapshot the newest session file *after* codex starts, then replay its id
# into the synthetic SessionEnd event.
trap emit_session_end EXIT INT TERM

# Run codex in foreground; capture session id from the most recently created
# rollout file once it appears.
codex "$@" &
CODEX_PID=$!

# Poll briefly for the new session file (Codex creates it on first turn).
for _ in $(seq 1 30); do
  sleep 0.5
  NEWEST=$(ls -t "$HOME/.codex/sessions"/**/rollout-*.jsonl 2>/dev/null | head -1)
  if [ -n "$NEWEST" ]; then
    CODEX_SESSION_ID=$(jq -r 'select(.session_id) | .session_id' "$NEWEST" 2>/dev/null | head -1)
    [ -n "$CODEX_SESSION_ID" ] && break
  fi
  kill -0 "$CODEX_PID" 2>/dev/null || break
done

wait "$CODEX_PID"

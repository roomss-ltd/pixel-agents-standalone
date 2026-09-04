#!/usr/bin/env bash
# codex-wrapper.sh — wraps `codex` to emit a synthetic SessionEnd hook event
# on process exit. Codex CLI does not have a SessionEnd hook event, so
# without this wrapper, sessions accumulate in the plugin's session map
# until Zellij is restarted.
#
# Usage: alias codex='~/.config/zellij/plugins/codex-wrapper.sh'

CODEX_BIN=$(type -P codex) || {
  echo "codex-wrapper: codex executable not found" >&2
  exit 127
}

[ -z "$ZELLIJ_SESSION_NAME" ] || [ -z "$ZELLIJ_PANE_ID" ] && exec "$CODEX_BIN" "$@"

# Keep Codex in Zellij's primary screen buffer and stop it from competing with
# the status plugin for terminal/tab titles.
CODEX_ZELLIJ_ARGS=(--no-alt-screen -c 'tui.terminal_title=[]')

HOOK="$HOME/.config/zellij/plugins/codex-zj-hook.sh"

emit_session_end() {
  [ -z "${CODEX_SESSION_ID:-}" ] && return 0
  jq -nc --arg sid "$CODEX_SESSION_ID" '{
    hook_event_name: "SessionEnd",
    session_id: $sid
  }' | "$HOOK" 2>/dev/null || true
}

# Best-effort session id capture: only consider rollout files created or touched
# after this wrapper starts. The old glob did not descend through Codex's
# year/month/day hierarchy and could clean up a different live session.
SESSION_MARKER=$(mktemp "${TMPDIR:-/tmp}/codex-zellij-session.XXXXXX")
cleanup() {
  emit_session_end
  rm -f "$SESSION_MARKER"
}
trap cleanup EXIT

# Codex must remain the foreground process so it retains the pane's TTY.
"$CODEX_BIN" "${CODEX_ZELLIJ_ARGS[@]}" "$@"
CODEX_EXIT=$?

# Resolve the session only after Codex exits. Running it in the background to
# poll here detaches stdin and makes the TUI fail with "stdin is not a terminal".
NEWEST=$(find "$HOME/.codex/sessions" -type f -name 'rollout-*.jsonl' -newer "$SESSION_MARKER" -print 2>/dev/null \
  | while IFS= read -r file; do stat -f '%m %N' "$file"; done \
  | sort -rn \
  | sed -n '1s/^[0-9][0-9]* //p')
if [ -n "$NEWEST" ]; then
  CODEX_SESSION_ID=$(jq -r 'select(.session_id) | .session_id' "$NEWEST" 2>/dev/null | head -1)
fi

exit "$CODEX_EXIT"

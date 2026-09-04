#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ACTIVATE_SCRIPT="$SCRIPT_DIR/activate-zellij-0.45.1.sh"
CURRENT_ZELLIJ="$HOME/.local/bin/zellij"

if [ "${1:-}" != "--replace-session" ] || [ -z "${2:-}" ] || [ "${3:-}" != "--confirmed" ]; then
  echo "Usage: $0 --replace-session SESSION_NAME --confirmed" >&2
  echo "WARNING: this intentionally terminates the named session." >&2
  exit 2
fi

SESSION_NAME="$2"
LOG_DIR="$HOME/.local/state/pixel-agents"
LOG_FILE="$LOG_DIR/zellij-0.45.1-restart.log"

# Detach the worker from the pane before terminating the session that owns it.
if [ "${ZELLIJ_RESTART_WORKER:-0}" != "1" ]; then
  mkdir -p "$LOG_DIR"
  nohup env ZELLIJ_RESTART_WORKER=1 "$0" \
    --replace-session "$SESSION_NAME" --confirmed \
    >"$LOG_FILE" 2>&1 </dev/null &
  echo "Detached restart worker started: $LOG_FILE"
  echo "This session will close. After returning to the shell, wait for 'Activated' in the log, then run:"
  echo "  zellij attach --create $SESSION_NAME"
  exit 0
fi

sleep 2
echo "Stopping Zellij session: $SESSION_NAME"
env -u ZELLIJ -u ZELLIJ_SESSION_NAME -u ZELLIJ_PANE_ID \
  "$CURRENT_ZELLIJ" kill-session "$SESSION_NAME"

# The activation script independently refuses to proceed while any server is
# alive. This wait only makes the normal handoff deterministic.
for _ in $(seq 1 100); do
  if ! ps -axo command= | awk '/[z]ellij --server / { found=1 } END { exit found ? 0 : 1 }'; then
    break
  fi
  sleep 0.1
done

"$ACTIVATE_SCRIPT" --activate
echo "Ready. Reattach with: zellij attach --create $SESSION_NAME"

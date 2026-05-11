#!/bin/zsh
# uninstall.sh — remove AgentTab from /Applications, strip its Claude
# Code hook scripts, clear stored preferences.

set -euo pipefail

DEST="/Applications/AgentTAB.app"
BUNDLE_ID="com.roomss.agenttab"
HOOK_DIR="$HOME/Library/Application Support/AgentTAB"
HOOK_SCRIPT="$HOME/.claude/hooks/agenttab-hook.sh"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

# Quit running instance.
echo "[uninstall] Quitting AgentTab..."
pkill -x AgentTAB 2>/dev/null || true
sleep 0.5

# Remove the .app.
if [[ -d "$DEST" ]]; then
    echo "[uninstall] Removing $DEST..."
    if ! rm -rf "$DEST" 2>/dev/null; then
        DEST_ESC="${DEST//\"/\\\"}"
        osascript -e "do shell script \"rm -rf '$DEST_ESC'\" with administrator privileges"
    fi
else
    echo "[uninstall] $DEST not present."
fi

# Strip hook commands from ~/.claude/settings.json (if our installer
# wrote any) and remove the hook script itself.
if [[ -d "$HOOK_DIR" ]]; then
    echo "[uninstall] Removing $HOOK_DIR..."
    rm -rf "$HOOK_DIR"
fi

if [[ -f "$HOOK_SCRIPT" ]]; then
    echo "[uninstall] Removing $HOOK_SCRIPT..."
    rm -f "$HOOK_SCRIPT"
fi

# Clear stored preferences for the bundle id (defaults are written
# under both the global domain and the bundle-id domain).
if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
    echo "[uninstall] Clearing preferences for $BUNDLE_ID..."
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

echo "[uninstall] Done."
echo ""
echo "If Claude Code's settings.json still has AgentTab hook entries,"
echo "open  ~/.claude/settings.json  and remove any block that references"
echo "agenttab-hook.sh  (the file is already deleted)."

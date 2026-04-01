#!/usr/bin/env bash
set -euo pipefail

PLUGIN_DIR="$HOME/.config/zellij/plugins"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$PLUGIN_DIR/claude-zj-hook.sh"

echo "=== claude-tab-status installer ==="

# 1. Build the WASM plugin
echo "[1/4] Building WASM plugin..."
cd "$SCRIPT_DIR"
cargo build --release
WASM_FILE="$SCRIPT_DIR/target/wasm32-wasip1/release/claude-tab-status.wasm"
if [ ! -f "$WASM_FILE" ]; then
    echo "ERROR: Build failed — WASM file not found."
    exit 1
fi

# 2. Copy artifacts
echo "[2/4] Installing to $PLUGIN_DIR..."
mkdir -p "$PLUGIN_DIR"
cp "$WASM_FILE" "$PLUGIN_DIR/claude-tab-status.wasm"
cp "$SCRIPT_DIR/scripts/claude-zj-hook.sh" "$HOOK_SCRIPT"
chmod +x "$HOOK_SCRIPT"

# 3. Register hooks in Claude settings
echo "[3/4] Registering Claude Code hooks..."
if [ ! -f "$CLAUDE_SETTINGS" ]; then
    echo "{}" > "$CLAUDE_SETTINGS"
fi

# Use jq to merge hooks — preserves existing hooks
HOOK_EVENTS='["PreToolUse","PostToolUse","UserPromptSubmit","PermissionRequest","Stop","SubagentStop","SessionStart","SessionEnd"]'

UPDATED=$(jq --arg hook_script "$HOOK_SCRIPT" --argjson events "$HOOK_EVENTS" '
  .hooks //= {} |
  reduce ($events[]) as $event (.;
    .hooks[$event] //= [] |
    if (.hooks[$event] | map(select(.hooks[]?.command == $hook_script)) | length) > 0
    then .
    else .hooks[$event] += [{"hooks": [{"type": "command", "command": $hook_script}]}]
    end
  )
' "$CLAUDE_SETTINGS")

echo "$UPDATED" > "$CLAUDE_SETTINGS"

# 4. Print config snippet
echo "[4/4] Done!"
echo ""
echo "Add this to your Zellij config (~/.config/zellij/config.kdl):"
echo ""
echo '  load_plugins {'
echo "      \"file:$PLUGIN_DIR/claude-tab-status.wasm\""
echo '  }'
echo ""
echo "Then restart Zellij. The plugin will ask for permissions on first load — press 'y' to grant."

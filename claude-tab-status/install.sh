#!/usr/bin/env bash
set -euo pipefail

PLUGIN_DIR="$HOME/.config/zellij/plugins"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CODEX_HOOKS="$HOME/.codex/hooks.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$PLUGIN_DIR/claude-zj-hook.sh"
CODEX_HOOK_SCRIPT="$PLUGIN_DIR/codex-zj-hook.sh"
CODEX_WRAPPER="$PLUGIN_DIR/codex-wrapper.sh"

echo "=== claude-tab-status installer ==="

# 1. Build the WASM plugin
echo "[1/6] Building WASM plugin..."
cd "$SCRIPT_DIR"
cargo build --release
WASM_FILE="$SCRIPT_DIR/target/wasm32-wasip1/release/claude-tab-status.wasm"
if [ ! -f "$WASM_FILE" ]; then
    echo "ERROR: Build failed — WASM file not found."
    exit 1
fi

# 2. Copy artifacts
echo "[2/6] Installing to $PLUGIN_DIR..."
mkdir -p "$PLUGIN_DIR"
cp "$WASM_FILE" "$PLUGIN_DIR/claude-tab-status-v2.wasm"
cp "$SCRIPT_DIR/scripts/claude-zj-hook.sh" "$HOOK_SCRIPT"
cp "$SCRIPT_DIR/scripts/codex-zj-hook.sh" "$CODEX_HOOK_SCRIPT"
cp "$SCRIPT_DIR/scripts/codex-wrapper.sh" "$CODEX_WRAPPER"
chmod +x "$HOOK_SCRIPT" "$CODEX_HOOK_SCRIPT" "$CODEX_WRAPPER"

# 3. Register hooks in Claude settings
echo "[3/6] Registering Claude Code hooks..."
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

# 4. Register hooks in Codex CLI settings
echo "[4/6] Registering Codex CLI hooks..."
mkdir -p "$(dirname "$CODEX_HOOKS")"
if [ ! -f "$CODEX_HOOKS" ]; then
    echo "{}" > "$CODEX_HOOKS"
fi

# Codex emits 6 events (no SessionEnd, no SubagentStop). PreToolUse/PostToolUse
# get a "*" matcher so all supported tools (Bash, apply_patch, MCP) are covered.
CODEX_EVENTS='["SessionStart","UserPromptSubmit","PermissionRequest","Stop"]'
CODEX_TOOL_EVENTS='["PreToolUse","PostToolUse"]'

UPDATED_CODEX=$(jq \
  --arg hook_script "$CODEX_HOOK_SCRIPT" \
  --argjson events "$CODEX_EVENTS" \
  --argjson tool_events "$CODEX_TOOL_EVENTS" '
  .hooks //= {} |
  reduce ($events[]) as $event (.;
    .hooks[$event] //= [] |
    if (.hooks[$event] | map(select(.hooks[]?.command == $hook_script)) | length) > 0
    then .
    else .hooks[$event] += [{"hooks": [{"type": "command", "command": $hook_script}]}]
    end
  ) |
  reduce ($tool_events[]) as $event (.;
    .hooks[$event] //= [] |
    if (.hooks[$event] | map(select(.hooks[]?.command == $hook_script)) | length) > 0
    then .
    else .hooks[$event] += [{"matcher": "*", "hooks": [{"type": "command", "command": $hook_script}]}]
    end
  )
' "$CODEX_HOOKS")

echo "$UPDATED_CODEX" > "$CODEX_HOOKS"

echo "  Codex hooks registered. Optional: add this alias to your shell rc"
echo "  to get SessionEnd cleanup when 'codex' exits:"
echo ""
echo "      alias codex='$CODEX_WRAPPER'"
echo ""

# 5. Print config snippet
echo "[5/6] Zellij plugin installed!"
echo ""
echo "Add this to your Zellij config (~/.config/zellij/config.kdl):"
echo ""
echo '  load_plugins {'
echo "      \"file:$PLUGIN_DIR/claude-tab-status-v2.wasm\""
echo '  }'
echo ""
echo "Then restart Zellij. The plugin will ask for permissions on first load — press 'y' to grant."

# 6. Install Hammerspoon module
echo "[6/6] Installing Hammerspoon module..."
HS_DIR="$HOME/.hammerspoon"
HS_MODULE="$HS_DIR/claude-status.lua"
SOURCE_MODULE="$SCRIPT_DIR/hammerspoon/claude-status.lua"

if [ -d "$HS_DIR" ]; then
    # Symlink so updates propagate automatically
    ln -sf "$SOURCE_MODULE" "$HS_MODULE"

    # Add require to init.lua if not present
    if ! grep -q 'claude-status' "$HS_DIR/init.lua" 2>/dev/null; then
        echo 'require("claude-status")' >> "$HS_DIR/init.lua"
    fi

    echo "  Hammerspoon module installed. Reload Hammerspoon to activate."
    echo "  Toggle visibility: Ctrl+Option+C"
else
    echo "  Hammerspoon not found at $HS_DIR — skipping overlay install."
    echo "  Install Hammerspoon and re-run to enable the macOS overlay."
fi

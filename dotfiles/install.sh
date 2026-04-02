#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Dev Environment Setup ==="
echo "This installs: Ghostty config, Zellij config + plugins, Claude Code hooks, Hammerspoon overlay"
echo ""

# ── Prerequisites check ───────────────────────────────────────────────
check_cmd() {
    if ! command -v "$1" &>/dev/null; then
        echo "WARNING: $1 not found. $2"
        return 1
    fi
    return 0
}

check_cmd "ghostty" "Install from https://ghostty.org" || true
check_cmd "zellij" "Install via: brew install zellij" || true
check_cmd "jq" "Install via: brew install jq (required for hooks)" || exit 1
check_cmd "cargo" "Install via: rustup (required to build WASM plugin)" || exit 1

# Ensure wasm32 target is available
if ! rustup target list --installed 2>/dev/null | grep -q wasm32-wasip1; then
    echo "Adding wasm32-wasip1 target..."
    rustup target add wasm32-wasip1
fi

echo ""

# ── 1. Ghostty ────────────────────────────────────────────────────────
echo "[1/6] Ghostty config..."
GHOSTTY_DIR="$HOME/.config/ghostty"
mkdir -p "$GHOSTTY_DIR"
if [ -f "$GHOSTTY_DIR/config" ] && ! diff -q "$SCRIPT_DIR/ghostty/config" "$GHOSTTY_DIR/config" &>/dev/null; then
    echo "  Backing up existing config to $GHOSTTY_DIR/config.bak"
    cp "$GHOSTTY_DIR/config" "$GHOSTTY_DIR/config.bak"
fi
cp "$SCRIPT_DIR/ghostty/config" "$GHOSTTY_DIR/config"
echo "  Installed."

# ── 2. Zellij config ─────────────────────────────────────────────────
echo "[2/6] Zellij config..."
ZELLIJ_DIR="$HOME/.config/zellij"
mkdir -p "$ZELLIJ_DIR/layouts" "$ZELLIJ_DIR/plugins"

if [ -f "$ZELLIJ_DIR/config.kdl" ] && ! diff -q "$SCRIPT_DIR/zellij/config.kdl" "$ZELLIJ_DIR/config.kdl" &>/dev/null; then
    echo "  Backing up existing config.kdl"
    cp "$ZELLIJ_DIR/config.kdl" "$ZELLIJ_DIR/config.kdl.bak"
fi
# Replace __HOME__ placeholder with actual home directory
sed "s|__HOME__|$HOME|g" "$SCRIPT_DIR/zellij/config.kdl" > "$ZELLIJ_DIR/config.kdl"
cp "$SCRIPT_DIR/zellij/layouts/default.kdl" "$ZELLIJ_DIR/layouts/default.kdl"
echo "  Installed."

# ── 3. zjstatus plugin ───────────────────────────────────────────────
echo "[3/6] zjstatus (status bar plugin)..."
ZJSTATUS_DIR="$HOME/zellij-plugins"
mkdir -p "$ZJSTATUS_DIR"
if [ ! -f "$ZJSTATUS_DIR/zjstatus.wasm" ]; then
    echo "  Downloading latest zjstatus..."
    ZJSTATUS_URL=$(curl -s https://api.github.com/repos/dj95/zjstatus/releases/latest \
        | jq -r '.assets[] | select(.name | endswith(".wasm")) | .browser_download_url' | head -1)
    if [ -n "$ZJSTATUS_URL" ]; then
        curl -sL "$ZJSTATUS_URL" -o "$ZJSTATUS_DIR/zjstatus.wasm"
        echo "  Downloaded."
    else
        echo "  WARNING: Could not fetch zjstatus. Download manually from https://github.com/dj95/zjstatus/releases"
    fi
else
    echo "  Already installed."
fi

# ── 4. room plugin (fuzzy tab switcher) ──────────────────────────────
echo "[4/6] room plugin (fuzzy tab switcher)..."
if [ ! -f "$ZELLIJ_DIR/plugins/room.wasm" ]; then
    echo "  Downloading latest room..."
    ROOM_URL=$(curl -s https://api.github.com/repos/rvcas/room/releases/latest \
        | jq -r '.assets[] | select(.name | endswith(".wasm")) | .browser_download_url' | head -1)
    if [ -n "$ROOM_URL" ]; then
        curl -sL "$ROOM_URL" -o "$ZELLIJ_DIR/plugins/room.wasm"
        echo "  Downloaded."
    else
        echo "  WARNING: Could not fetch room. Download manually from https://github.com/rvcas/room/releases"
    fi
else
    echo "  Already installed."
fi

# ── 5. claude-tab-status (WASM plugin + hook + Hammerspoon) ──────────
echo "[5/6] claude-tab-status plugin..."
CTS_DIR="$REPO_DIR/claude-tab-status"
if [ -f "$CTS_DIR/install.sh" ]; then
    bash "$CTS_DIR/install.sh"
else
    echo "  WARNING: claude-tab-status/install.sh not found — skipping."
fi

# ── 6. Verify Claude Code hooks ──────────────────────────────────────
echo "[6/6] Verifying Claude Code hooks..."
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

if [ -f "$CLAUDE_SETTINGS" ] && jq -e '.hooks.PreToolUse' "$CLAUDE_SETTINGS" &>/dev/null; then
    echo "  Hooks registered successfully."
else
    echo "  WARNING: Hooks not found in $CLAUDE_SETTINGS"
    echo "  You may need to manually merge dotfiles/claude/settings-hooks.json into your settings."
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Restart Ghostty (if open)"
echo "  2. Start a new Zellij session (existing sessions use old config)"
echo "  3. Grant permissions when Zellij prompts for claude-tab-status plugin"
echo "  4. Reload Hammerspoon (Ctrl+Option+C to toggle overlay)"
echo ""
echo "Keyboard shortcuts:"
echo "  Ctrl+Option+C  — Toggle Hammerspoon overlay visibility"
echo "  Ctrl+Option+R  — Reset overlay (clear stale sessions)"
echo "  Ctrl+R         — Room (fuzzy tab switcher in Zellij)"
echo "  Ctrl+G         — Lock/unlock Zellij keybinds"

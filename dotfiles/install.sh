#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Dev Environment Setup ==="
echo "This installs: Zsh + p10k, Ghostty, Zellij + plugins, Claude Code hooks, Hammerspoon overlay"
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

# ── 1. Oh My Zsh + Powerlevel10k + plugins ───────────────────────────
echo "[1/8] Zsh shell setup..."

# Install Oh My Zsh if not present
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "  Installing Oh My Zsh..."
    RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    echo "  Oh My Zsh already installed."
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# Install Powerlevel10k theme
if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
    echo "  Installing Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
else
    echo "  Powerlevel10k already installed."
fi

# Install zsh plugins (bash 3.2 compatible — no associative arrays)
ZSH_PLUGIN_NAMES=("zsh-autosuggestions" "fast-syntax-highlighting" "you-should-use" "zsh-bat")
ZSH_PLUGIN_URLS=(
    "https://github.com/zsh-users/zsh-autosuggestions"
    "https://github.com/zdharma-continuum/fast-syntax-highlighting"
    "https://github.com/MichaelAqworthy/you-should-use"
    "https://github.com/fdellwing/zsh-bat"
)

for i in "${!ZSH_PLUGIN_NAMES[@]}"; do
    plugin="${ZSH_PLUGIN_NAMES[$i]}"
    url="${ZSH_PLUGIN_URLS[$i]}"
    if [ ! -d "$ZSH_CUSTOM/plugins/$plugin" ]; then
        echo "  Installing $plugin..."
        git clone --depth=1 "$url" "$ZSH_CUSTOM/plugins/$plugin"
    fi
done

echo "  Plugins installed."

# ── 2. Zsh config files ─────────────────────────────────────────────
echo "[2/8] Zsh config files..."

# .zshrc — only install if user doesn't have one, otherwise warn
if [ -f "$HOME/.zshrc" ]; then
    echo "  .zshrc already exists — not overwriting."
    echo "  Review dotfiles/zsh/.zshrc and merge relevant parts manually."
else
    cp "$SCRIPT_DIR/zsh/.zshrc" "$HOME/.zshrc"
    echo "  Installed .zshrc"
fi

# .p10k.zsh — Powerlevel10k prompt config
if [ -f "$HOME/.p10k.zsh" ]; then
    echo "  Backing up existing .p10k.zsh"
    cp "$HOME/.p10k.zsh" "$HOME/.p10k.zsh.bak"
fi
cp "$SCRIPT_DIR/zsh/.p10k.zsh" "$HOME/.p10k.zsh"
echo "  Installed .p10k.zsh"

# ── 3. Ghostty ────────────────────────────────────────────────────────
echo "[3/8] Ghostty config..."
GHOSTTY_DIR="$HOME/.config/ghostty"
mkdir -p "$GHOSTTY_DIR"
if [ -f "$GHOSTTY_DIR/config" ] && ! diff -q "$SCRIPT_DIR/ghostty/config" "$GHOSTTY_DIR/config" &>/dev/null; then
    echo "  Backing up existing config to $GHOSTTY_DIR/config.bak"
    cp "$GHOSTTY_DIR/config" "$GHOSTTY_DIR/config.bak"
fi
cp "$SCRIPT_DIR/ghostty/config" "$GHOSTTY_DIR/config"
echo "  Installed."

# ── 4. Zellij config ─────────────────────────────────────────────────
echo "[4/8] Zellij config..."
ZELLIJ_DIR="$HOME/.config/zellij"
mkdir -p "$ZELLIJ_DIR/layouts" "$ZELLIJ_DIR/plugins"

if [ -f "$ZELLIJ_DIR/config.kdl" ] && ! diff -q "$SCRIPT_DIR/zellij/config.kdl" "$ZELLIJ_DIR/config.kdl" &>/dev/null; then
    echo "  Backing up existing config.kdl"
    cp "$ZELLIJ_DIR/config.kdl" "$ZELLIJ_DIR/config.kdl.bak"
fi
# Replace __HOME__ placeholder with actual home directory
sed "s|__HOME__|$HOME|g" "$SCRIPT_DIR/zellij/config.kdl" > "$ZELLIJ_DIR/config.kdl"
sed "s|__HOME__|$HOME|g" "$SCRIPT_DIR/zellij/layouts/default.kdl" > "$ZELLIJ_DIR/layouts/default.kdl"
echo "  Installed."

# ── 5. zjstatus plugin ───────────────────────────────────────────────
echo "[5/8] zjstatus (status bar plugin)..."
ZJSTATUS_DIR="$HOME/zellij-plugins"
mkdir -p "$ZJSTATUS_DIR"
if [ ! -f "$ZJSTATUS_DIR/zjstatus.wasm" ]; then
    echo "  Downloading latest zjstatus..."
    ZJSTATUS_URL=$(curl -s https://api.github.com/repos/dj95/zjstatus/releases/latest \
        | jq -r '.assets[] | select(.name == "zjstatus.wasm") | .browser_download_url')
    if [ -n "$ZJSTATUS_URL" ]; then
        curl -sL "$ZJSTATUS_URL" -o "$ZJSTATUS_DIR/zjstatus.wasm"
        echo "  Downloaded."
    else
        echo "  WARNING: Could not fetch zjstatus. Download manually from https://github.com/dj95/zjstatus/releases"
    fi
else
    echo "  Already installed."
fi

# ── 6. room plugin (fuzzy tab switcher) ──────────────────────────────
echo "[6/8] room plugin (fuzzy tab switcher)..."
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

# ── 7. claude-tab-status (WASM plugin + hook + Hammerspoon) ──────────
echo "[7/8] claude-tab-status plugin..."
CTS_DIR="$REPO_DIR/claude-tab-status"
if [ -f "$CTS_DIR/install.sh" ]; then
    bash "$CTS_DIR/install.sh"
else
    echo "  WARNING: claude-tab-status/install.sh not found — skipping."
fi

# ── 8. Verify Claude Code hooks ──────────────────────────────────────
echo "[8/8] Verifying Claude Code hooks..."
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

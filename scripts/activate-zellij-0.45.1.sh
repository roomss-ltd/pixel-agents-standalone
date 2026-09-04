#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STAGED_BINARY="$REPO_DIR/.staged/zellij-v0.45.1/target/release/zellij"
INSTALL_BINARY="$REPO_DIR/zellij-patched/target/release/zellij"
ZELLIJ_CONFIG_DIR="$HOME/.config/zellij"
SOURCE_CONFIG="$REPO_DIR/dotfiles/zellij/config.kdl"
SOURCE_LAYOUT="$REPO_DIR/dotfiles/zellij/layouts/default.kdl"
PLUGIN_SOURCE="$REPO_DIR/claude-tab-status/target/wasm32-wasip1/release/claude-tab-status.wasm"
PLUGIN_INSTALL="$ZELLIJ_CONFIG_DIR/plugins/claude-tab-status-v2.wasm"
WRAPPER_SOURCE="$REPO_DIR/claude-tab-status/scripts/codex-wrapper.sh"
WRAPPER_INSTALL="$ZELLIJ_CONFIG_DIR/plugins/codex-wrapper.sh"

if [ "${1:-}" != "--activate" ]; then
  echo "Usage: $0 --activate" >&2
  echo "No changes made. This command deliberately requires an explicit activation flag." >&2
  exit 2
fi

if [ ! -x "$STAGED_BINARY" ]; then
  echo "ERROR: staged Zellij 0.45.1 binary is missing: $STAGED_BINARY" >&2
  exit 1
fi

STAGED_VERSION=$($STAGED_BINARY --version)
if [ "$STAGED_VERSION" != "zellij 0.45.1" ]; then
  echo "ERROR: expected staged zellij 0.45.1, got: $STAGED_VERSION" >&2
  exit 1
fi

(cd "$REPO_DIR/claude-tab-status" && cargo build --release)
if [ ! -f "$PLUGIN_SOURCE" ]; then
  echo "ERROR: claude-tab-status build did not produce: $PLUGIN_SOURCE" >&2
  exit 1
fi

# Validate the to-be-installed configuration before touching the current
# binary or dotfiles.
"$STAGED_BINARY" --config "$SOURCE_CONFIG" setup --check >/dev/null

# Never replace the client while a server is alive: mixed client/server
# versions can make an existing session inaccessible.
ACTIVE_SERVERS=$(ps -axo pid=,command= | awk '/[z]ellij --server / { print }')
if [ -n "$ACTIVE_SERVERS" ]; then
  echo "REFUSING TO ACTIVATE: a Zellij server is still running:" >&2
  echo "$ACTIVE_SERVERS" >&2
  echo "Stop the session intentionally, then run this command again." >&2
  exit 3
fi

BACKUP_DIR="$HOME/.local/state/pixel-agents/zellij-0.45.1-backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR" "$ZELLIJ_CONFIG_DIR/layouts" "$ZELLIJ_CONFIG_DIR/plugins" "$(dirname "$INSTALL_BINARY")"

if [ -f "$INSTALL_BINARY" ]; then
  cp "$INSTALL_BINARY" "$BACKUP_DIR/zellij"
fi
if [ -f "$ZELLIJ_CONFIG_DIR/config.kdl" ]; then
  cp "$ZELLIJ_CONFIG_DIR/config.kdl" "$BACKUP_DIR/config.kdl"
fi
if [ -f "$ZELLIJ_CONFIG_DIR/layouts/default.kdl" ]; then
  cp "$ZELLIJ_CONFIG_DIR/layouts/default.kdl" "$BACKUP_DIR/default.kdl"
fi
if [ -f "$PLUGIN_INSTALL" ]; then
  cp "$PLUGIN_INSTALL" "$BACKUP_DIR/claude-tab-status.wasm"
fi
if [ -f "$WRAPPER_INSTALL" ]; then
  cp "$WRAPPER_INSTALL" "$BACKUP_DIR/codex-wrapper.sh"
fi

BINARY_TMP="$INSTALL_BINARY.new"
CONFIG_TMP="$ZELLIJ_CONFIG_DIR/config.kdl.new"
LAYOUT_TMP="$ZELLIJ_CONFIG_DIR/layouts/default.kdl.new"
PLUGIN_TMP="$PLUGIN_INSTALL.new"
WRAPPER_TMP="$WRAPPER_INSTALL.new"

cp "$STAGED_BINARY" "$BINARY_TMP"
chmod 755 "$BINARY_TMP"
sed "s|__HOME__|$HOME|g" "$SOURCE_CONFIG" > "$CONFIG_TMP"
sed "s|__HOME__|$HOME|g" "$SOURCE_LAYOUT" > "$LAYOUT_TMP"
cp "$PLUGIN_SOURCE" "$PLUGIN_TMP"
cp "$WRAPPER_SOURCE" "$WRAPPER_TMP"
chmod 755 "$WRAPPER_TMP"

mv "$BINARY_TMP" "$INSTALL_BINARY"
mv "$CONFIG_TMP" "$ZELLIJ_CONFIG_DIR/config.kdl"
mv "$LAYOUT_TMP" "$ZELLIJ_CONFIG_DIR/layouts/default.kdl"
mv "$PLUGIN_TMP" "$PLUGIN_INSTALL"
mv "$WRAPPER_TMP" "$WRAPPER_INSTALL"

"$INSTALL_BINARY" setup --check >/dev/null

echo "Activated $($INSTALL_BINARY --version)."
echo "Backup: $BACKUP_DIR"
echo "Start a fresh session with: zellij attach --create circular-cactus"

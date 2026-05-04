# Pixel Agents Standalone

A standalone web application for visualizing Claude Code AI agents as pixel art characters in a virtual office — plus a full dev environment setup for running Claude Code inside Zellij with real-time session tracking.

## Features

- **Auto-detect Claude Code sessions** running in any terminal (Ghostty, Zellij, iTerm, etc.)
- **Real-time activity tracking** - characters animate based on actual tool usage
- **Multi-project support** - displays sessions from all your git worktrees
- **Office layout editor** - customize your pixel art office
- **WebSocket updates** - instant synchronization between backend and frontend

## Dev Environment Setup

The `dotfiles/` directory contains a complete, reproducible dev environment configuration for running Claude Code with full session visibility across Zellij tabs.

### What's included

| Component | Purpose |
|-----------|---------|
| **Zsh + Oh My Zsh** | Shell with Powerlevel10k prompt, autosuggestions, syntax highlighting |
| **Ghostty** | Terminal emulator config with Catppuccin Mocha theme, Monaco font |
| **Roomss patched Zellij** | Private Zellij fork with visual-position tab renames, plus custom keybinds and mocha-custom theme |
| **zjstatus** | Zellij status bar plugin with Catppuccin Mocha palette |
| **room** | Fuzzy tab switcher plugin for Zellij (`Ctrl+R`) |
| **claude-tab-status** | Zellij WASM plugin that tracks Claude Code session activity per tab |
| **Claude Code hooks** | Hook scripts that pipe session events to the Zellij plugin |
| **Hammerspoon overlay** | macOS floating widget showing all Claude sessions in real-time |

### Prerequisites

- macOS
- [Homebrew](https://brew.sh)
- [Rust toolchain](https://rustup.rs) (for building the WASM plugin)

### Installation

```bash
# 1. Install required tools. Do not install/use Homebrew Zellij for this setup.
brew install ghostty jq
brew install --cask hammerspoon
rustup target add wasm32-wasip1

# 2. Clone with the private patched Zellij submodule
git clone --recurse-submodules git@github.com:roomss-ltd/pixel-agents-standalone.git
cd pixel-agents-standalone

# 3. Build and install Roomss patched Zellij from the local submodule
git submodule update --init --recursive
(cd zellij-patched && cargo build --release --bin zellij)
mkdir -p "$HOME/.local/bin"
if [ -e "$HOME/.local/bin/zellij" ] && [ ! -L "$HOME/.local/bin/zellij" ]; then
  mv "$HOME/.local/bin/zellij" "$HOME/.local/bin/zellij.pre-roomss.bak"
fi
ln -sf "$PWD/zellij-patched/target/release/zellij" "$HOME/.local/bin/zellij"
export PATH="$HOME/.local/bin:$PATH"
hash -r
which zellij
zellij --version

# 4. Run the environment installer
./dotfiles/install.sh
```

The install script will:
- Copy Ghostty config (`~/.config/ghostty/config`)
- Copy Zellij config and layout (`~/.config/zellij/`)
- Download zjstatus and room plugins if not already installed
- Build and install the claude-tab-status WASM plugin
- Install the Claude Code hook script and register hooks in `~/.claude/settings.json`
- Symlink the Hammerspoon overlay module and patch `~/.hammerspoon/init.lua`

The patched Zellij fork lives at `zellij-patched/` and is pinned by this repo as a submodule:

- Source: `git@github.com:roomss-ltd/zellij-patched.git`
- Patch commit: `296fc3a Preserve tab position on rename`
- Required behavior: `RenameTab(N)` resolves `N` by one-based visual tab position, which lets `claude-tab-status` rename the correct tab without the old bootstrap probe workaround.

### Existing Zellij users

If Zellij is already installed, replace only the binary path and keep the rest of the setup intact:

```bash
cd pixel-agents-standalone
git pull origin main
git submodule update --init --recursive
(cd zellij-patched && cargo build --release --bin zellij)

mkdir -p "$HOME/.local/bin"
if [ -e "$HOME/.local/bin/zellij" ] && [ ! -L "$HOME/.local/bin/zellij" ]; then
  mv "$HOME/.local/bin/zellij" "$HOME/.local/bin/zellij.pre-roomss.bak"
fi
ln -sf "$PWD/zellij-patched/target/release/zellij" "$HOME/.local/bin/zellij"
export PATH="$HOME/.local/bin:$PATH"
hash -r
which zellij
zellij --version

./dotfiles/install.sh
```

Start a fresh Zellij session after this. Existing Zellij sessions keep using their already-running server process.

### Agent install checklist

For Opus 4.7 or any other installing agent, use this order exactly:

1. Verify GitHub access to `roomss-ltd/pixel-agents-standalone` and `roomss-ltd/zellij-patched`.
2. Clone with `--recurse-submodules`, or run `git submodule update --init --recursive` in an existing clone.
3. Build `zellij-patched` with `cargo build --release --bin zellij`.
4. Symlink `~/.local/bin/zellij` to `zellij-patched/target/release/zellij`.
5. Ensure `~/.local/bin` precedes Homebrew paths in the shell used to launch Zellij.
6. Run `./dotfiles/install.sh`.
7. Reload Hammerspoon.
8. Start a new Zellij session and grant the `claude-tab-status` plugin permissions.
9. Open Claude Code in a Zellij tab and confirm tab names update and the Hammerspoon widget appears.

### Post-install

1. **Start a new Zellij session** — existing sessions use their old server process; press `y` when prompted to grant claude-tab-status plugin permissions
2. **Reload Hammerspoon** (or it reloads automatically on config change)
3. **Open Claude Code** in any Zellij tab — the overlay appears in the bottom-right corner

### Keyboard shortcuts

| Shortcut | Context | Action |
|----------|---------|--------|
| `Ctrl+G` | Zellij | Toggle locked mode |
| `Ctrl+T` | Zellij | Tab mode (then `n` new, `r` rename, `x` close, `1-9` jump) |
| `Ctrl+P` | Zellij | Pane mode (then `n` new, `r` right, `d` down, `x` close) |
| `Ctrl+N` | Zellij | Resize mode |
| `Ctrl+H` | Zellij | Move mode |
| `Ctrl+S` | Zellij | Scroll mode |
| `Ctrl+R` | Zellij | Room (fuzzy tab switcher) |
| `Ctrl+Option+C` | macOS | Toggle Hammerspoon overlay visibility |
| `Ctrl+Option+R` | macOS | Reset overlay (clear stale sessions) |

### Hammerspoon overlay

The overlay shows a floating widget in the bottom-right corner of your screen:

- **Collapsed pill**: icon counts (active/waiting/done)
- **Hover**: expands to show all sessions
- **Click**: pins the expanded view
- **Drag**: reposition the widget
- **Long press (3s)**: dismiss a specific session

Sessions are split into two tiers:
- **Active tier** (top): Thinking, Tool, Waiting, Init — full-size rows
- **Inactive tier** (bottom): Done, Idle — compact dimmed rows, sorted by most recent

Multiple Claude Code panes in the same tab display as `3.1`, `3.2`, etc.

### File structure

```
dotfiles/
  install.sh                      # One-command setup script
  zsh/.zshrc                      # Oh My Zsh + p10k + plugins config (template)
  zsh/.p10k.zsh                   # Powerlevel10k prompt theme (nerdfont-v3 mode)
  ghostty/config                  # Catppuccin Mocha theme, Monaco font, macOS option-as-alt
  zellij/config.kdl               # Keybinds, mocha-custom theme, plugin loading
  zellij/layouts/default.kdl      # zjstatus bar with Catppuccin Mocha palette
  claude/settings-hooks.json      # Claude Code hooks template for claude-tab-status
  hammerspoon/init.lua            # Loads rcmd + claude-status modules

zellij-patched/                   # Private Roomss Zellij fork, pinned as a submodule

claude-tab-status/
  src/                            # Rust WASM plugin source
  scripts/claude-zj-hook.sh       # Hook script (pipes events to plugin)
  hammerspoon/claude-status.lua   # macOS overlay module
  install.sh                      # Plugin-specific installer
```

## Pixel Agents Web App

### Quick Start

```bash
# Install dependencies
npm run install:all

# Start development server
npm run dev

# Open browser to http://localhost:5173
```

### Production

```bash
# Build
npm run build:standalone

# Run
npm start

# Open browser to http://localhost:3001
```

### How It Works

- **Backend** (Node.js + Express + WebSocket): Scans `~/.claude/projects/` for active sessions, watches JSONL transcripts
- **Frontend** (React + TypeScript + Canvas): Renders pixel art office with animated characters

### Requirements

- Node.js 18+
- Claude Code CLI installed
- Active Claude Code sessions (modified in last 30 minutes)

## Documentation

See [docs/plans/](docs/plans/) for design and implementation plans.

## License

MIT

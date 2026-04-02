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
| **Zellij** | Terminal multiplexer config with custom keybinds and mocha-custom theme |
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
# 1. Install required tools
brew install ghostty zellij jq
brew install --cask hammerspoon
rustup target add wasm32-wasip1

# 2. Clone and run the installer
git clone <repo-url>
cd pixel-agents-standalone
./dotfiles/install.sh
```

The install script will:
- Copy Ghostty config (`~/.config/ghostty/config`)
- Copy Zellij config and layout (`~/.config/zellij/`)
- Download zjstatus and room plugins if not already installed
- Build and install the claude-tab-status WASM plugin
- Install the Claude Code hook script and register hooks in `~/.claude/settings.json`
- Symlink the Hammerspoon overlay module and patch `~/.hammerspoon/init.lua`

### Post-install

1. **Start a new Zellij session** — press `y` when prompted to grant claude-tab-status plugin permissions
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

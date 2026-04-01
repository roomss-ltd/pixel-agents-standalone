# Pixel Agents Standalone

A standalone web application for visualizing Claude Code AI agents as pixel art characters in a virtual office.

## Features

- **Auto-detect Claude Code sessions** running in any terminal (Ghostty, Zellij, iTerm, etc.)
- **Real-time activity tracking** - characters animate based on actual tool usage
- **Multi-project support** - displays sessions from all your git worktrees
- **Office layout editor** - customize your pixel art office
- **WebSocket updates** - instant synchronization between backend and frontend

## Quick Start

```bash
# Install dependencies
npm run install:all

# Start development server
npm run dev

# Open browser to http://localhost:5173
```

## Production

```bash
# Build
npm run build:standalone

# Run
npm start

# Open browser to http://localhost:3001
```

## How It Works

- **Backend** (Node.js + Express + WebSocket): Scans `~/.claude/projects/` for active sessions, watches JSONL transcripts
- **Frontend** (React + TypeScript + Canvas): Renders pixel art office with animated characters

## Requirements

- Node.js 18+
- Claude Code CLI installed
- Active Claude Code sessions (modified in last 30 minutes)

## Documentation

See [docs/plans/standalone-setup.md](docs/plans/standalone-setup.md) for full setup instructions.

## License

MIT

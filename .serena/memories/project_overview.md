# pixel-agents-standalone

## Purpose
Standalone web server for visualizing Claude Code session activity. Originally a VS Code extension ("pixel agents"), adapted by the team to work in terminal/Zellij environments.

## Tech Stack
- **Server:** Node.js + Express + WebSocket (TypeScript), in `server/`
- **Frontend:** Vite + TypeScript (likely Vue/React), in `webview-ui/`
- **Shared:** Asset loading utilities in `shared/`
- **Build:** tsx for dev, TypeScript compiler

## How State Tracking Works
The server polls `~/.claude/projects/` for `.jsonl` transcript files. It reads new bytes from file offsets, parses JSON lines to determine session state (tool_use, tool_result, turn_duration, etc.), and broadcasts state changes via WebSocket.

Key files:
- `server/src/sessionManager.ts` — Scans for sessions, manages agent lifecycle
- `server/src/fileWatcher.ts` — Polls .jsonl files for new lines
- `server/src/transcriptParser.ts` — Parses JSONL records into state transitions
- `server/src/types.ts` — AgentState and SessionInfo interfaces

## Code Style
- TypeScript with explicit types
- camelCase for variables/functions
- PascalCase for interfaces/types
- Functional utilities where appropriate
- Console.log with `[Component]` prefixes for logging

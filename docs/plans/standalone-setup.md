# Pixel Agents Standalone Setup

## Overview

Pixel Agents standalone version auto-detects Claude Code sessions running in any terminal (Ghostty, Zellij, iTerm, etc.) and visualizes them in a web browser.

## Requirements

- Node.js 18+
- npm 9+
- Claude Code CLI

## Installation

```bash
# Clone repository
git clone https://github.com/pablodelucca/pixel-agents.git
cd pixel-agents

# Install dependencies for all packages
npm run install:all
```

## Development

```bash
# Start dev server (backend + frontend)
npm run dev

# Backend runs on http://localhost:3001
# Frontend dev server on http://localhost:5173 (proxies to backend)
```

Open browser to `http://localhost:5173`

## Production

```bash
# Build both frontend and backend
npm run build:standalone

# Start production server
npm start
```

Open browser to `http://localhost:3001`

## How It Works

1. **Session Discovery**: Backend scans `~/.claude/projects/` for JSONL transcript files every second
2. **File Watching**: Monitors transcripts for tool usage and status updates using triple-watching (fs.watch + fs.watchFile + polling)
3. **WebSocket Updates**: Pushes real-time updates to browser
4. **Visualization**: React frontend displays agents as pixel art characters with animations

## Data Storage

All persistent data stored in `~/.pixel-agents/`:

- `layout.json` - Office layout (floor tiles, walls, furniture placement)
- `agent-seats.json` - Agent seat assignments and color palettes
- `settings.json` - User preferences (sound notifications, etc.)

## Multi-Project Support

Pixel Agents detects sessions from all projects simultaneously. Each agent shows a label with the project name.

## Interaction

- **Click an agent**: View session details (session ID, project path, last activity, transcript size)
- **To respond to prompts**: Switch to the terminal running that Claude session
- **Permission requests**: Visual indicator appears; type "yes"/"no"/"yes for all" in your terminal
- **Inactive sessions**: Agents that haven't been active for > 1 hour appear semi-transparent

## Features

### Visual Indicators
- **Green dot (pulsing)**: Agent is actively running a tool
- **Amber dots**: Agent needs permission approval
- **Green checkmark**: Agent is waiting for your input
- **Semi-transparent**: Session has been inactive for > 1 hour

### Editor Mode
- Click "Layout" button to enter edit mode
- Customize your office: add/remove furniture, change floor/wall colors
- Changes auto-save to `~/.pixel-agents/layout.json`
- Changes sync across all browser windows automatically

### Settings
- Sound notifications (chime when agent completes a turn)
- Export/import layouts
- Debug mode for development

## Troubleshooting

### Server won't start
- Check if port 3000 is already in use: `lsof -i :3000`
- Kill the process or change the PORT in `server/src/index.ts`

### No agents appear
- Verify Claude sessions are running: `ls ~/.claude/projects/*/`
- Check server logs for errors
- Ensure JSONL files exist and are being written to

### WebSocket connection fails
- Check browser console for connection errors
- Verify backend server is running on port 3000
- Check firewall settings

### Assets not loading
- Run `npm run build:frontend` to rebuild assets
- Verify `webview-ui/public/assets/` directory exists
- Check for PNG decoding errors in server logs

## Development Tips

### Backend Development
```bash
cd server
npm run dev  # Auto-reloads on file changes
```

### Frontend Development
```bash
cd webview-ui
npm run dev  # Hot module replacement enabled
```

### Building for Production
```bash
npm run build:standalone  # Builds both server and frontend
```

### File Structure
```
server/                  # Node.js backend
  src/
    index.ts            # Express + WebSocket server
    sessionManager.ts   # Session discovery and tracking
    fileWatcher.ts      # JSONL file monitoring
    transcriptParser.ts # JSONL parsing logic
    assetLoader.ts      # PNG decoding and asset loading
    persistence.ts      # JSON file storage

webview-ui/             # React frontend
  src/
    App.tsx             # Main application component
    hooks/
      useWebSocket.ts   # WebSocket connection hook
    office/             # Office rendering engine
      engine/
        renderer.ts     # Canvas rendering
        characters.ts   # Character AI and animation
      components/
        OfficeCanvas.tsx # Main canvas component
```

## Architecture

The standalone version is a web application with:
- **Backend**: Node.js server (Express + WebSocket) that monitors Claude sessions
- **Frontend**: React SPA that renders the pixel art office

The backend and frontend communicate via WebSocket for real-time updates. All game state is managed client-side, while the backend handles session discovery, file watching, and persistence.

## Differences from VS Code Extension

- ✅ Works with any terminal (not just VS Code integrated terminal)
- ✅ Auto-detects sessions (no need to create terminals)
- ✅ Shows all projects simultaneously
- ❌ Cannot programmatically create new Claude sessions
- ❌ Cannot focus terminals on agent click
- ⚡ Session info panel instead of terminal focus

## Contributing

When adding features to the standalone version:

1. Backend changes go in `server/src/`
2. Frontend changes go in `webview-ui/src/`
3. Shared types should be duplicated (backend and frontend are separate packages)
4. Test both dev and production builds
5. Update this documentation

## License

MIT

# Setup Guide

## Prerequisites

- Node.js 18+ installed
- Claude Code CLI installed and configured
- Active Claude Code sessions running in your terminals

## Installation

```bash
# 1. Install dependencies for all packages
npm run install:all

# 2. Start the development server
npm run dev
```

The application will start on:
- **Frontend**: http://localhost:5173 (Vite dev server)
- **Backend**: http://localhost:3001 (Express + WebSocket)

Open your browser to http://localhost:5173 to see your agents!

## Production Build

```bash
# Build both frontend and backend
npm run build:standalone

# Start the production server
npm start
```

In production mode, everything runs on http://localhost:3001

## Troubleshooting

### No agents appearing?

1. **Check Claude sessions are running**: Open terminals with active Claude Code sessions
2. **Verify session files exist**: `ls ~/.claude/projects/*/`
3. **Check server logs**: Look for "New session:" messages
4. **Browser console**: Open DevTools (F12) and check for errors

### Port already in use?

If port 3001 is taken, edit `server/src/index.ts` and change:
```typescript
const PORT = 3001; // Change this to another port
```

Also update the WebSocket URL in `webview-ui/src/App.tsx`:
```typescript
const WS_URL = import.meta.env.DEV ? 'ws://localhost:5173/ws' : `ws://${window.location.host}`;
```

And the Vite proxy in `webview-ui/vite.config.ts`:
```typescript
server: {
  proxy: {
    '/ws': {
      target: 'ws://localhost:3001', // Update this
      ws: true,
    },
  },
}
```

### Sessions not updating?

The server only shows sessions modified in the last **30 minutes**. If you have old Claude sessions that haven't been used recently, they won't appear.

To change this threshold, edit `server/src/sessionManager.ts`:
```typescript
const ACTIVE_THRESHOLD_MS = 30 * 60 * 1000; // Change 30 to desired minutes
```

## Next Steps

See [docs/plans/standalone-setup.md](docs/plans/standalone-setup.md) for detailed documentation on:
- Architecture overview
- WebSocket message protocol
- Adding new features
- Contributing guidelines

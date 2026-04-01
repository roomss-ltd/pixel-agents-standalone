import express from 'express';
import { WebSocketServer, WebSocket } from 'ws';
import { createServer } from 'http';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { SessionManager } from './sessionManager.js';
import { loadAssets } from './assetLoader.js';
import {
  readLayout,
  writeLayout,
  readAgentSeats,
  writeAgentSeats,
  readSettings,
  writeSettings,
  watchLayoutFile,
} from './persistence.js';

const PORT = 3001;
const app = express();
const server = createServer(app);
const wss = new WebSocketServer({ server });

const clients = new Set<WebSocket>();

// Broadcast to all connected clients
function broadcast(message: any): void {
  const data = JSON.stringify(message);
  clients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(data);
    }
  });
}

const sessionManager = new SessionManager(broadcast);

// Load assets once at startup
console.log('[Server] Loading assets...');
const assets = loadAssets();
console.log(
  `[Server] Loaded ${assets.characterSprites.length} character sprites, ${assets.floorTiles.length ? 'floor tiles' : 'no floor tiles'}, ${assets.wallTiles.length ? 'wall tiles' : 'no wall tiles'}, furniture catalog`,
);

// Load persisted data at startup
const persistedLayout = readLayout();
const persistedSeats = readAgentSeats();
const persistedSettings = readSettings();

// Watch layout file for external changes
const layoutWatcher = watchLayoutFile((layout) => {
  broadcast({ type: 'layoutLoaded', layout, wasReset: false });
});

app.use(express.static('../webview-ui/dist'));

wss.on('connection', (ws) => {
  console.log('Client connected');
  clients.add(ws);

  // Send assets
  ws.send(
    JSON.stringify({
      type: 'characterSpritesLoaded',
      sprites: assets.characterSprites,
    }),
  );

  ws.send(
    JSON.stringify({
      type: 'floorTilesLoaded',
      sprites: assets.floorTiles,
    }),
  );

  ws.send(
    JSON.stringify({
      type: 'wallTilesLoaded',
      sprites: assets.wallTiles,
    }),
  );

  ws.send(
    JSON.stringify({
      type: 'furnitureAssetsLoaded',
      catalog: assets.furnitureCatalog,
      sprites: {},
    }),
  );

  // Send existing sessions BEFORE layoutLoaded so frontend can buffer them
  const agentsMap = sessionManager.getAgents();
  const agents = Array.from(agentsMap.keys());
  const folderNames: Record<number, string> = {};
  for (const [id, agent] of agentsMap) {
    folderNames[id] = agent.projectName;
  }
  console.log(`[Server] Sending existingAgents with ${agents.length} agents to new client`);

  ws.send(
    JSON.stringify({
      type: 'existingAgents',
      agents,
      folderNames,
    }),
  );

  // Send persisted layout if available, otherwise default
  const layout = persistedLayout || assets.defaultLayout;
  ws.send(
    JSON.stringify({
      type: 'layoutLoaded',
      layout,
      wasReset: false,
    }),
  );

  // Send agent seats
  ws.send(
    JSON.stringify({
      type: 'agentSeatsLoaded',
      seats: persistedSeats,
    }),
  );

  // Send settings
  ws.send(
    JSON.stringify({
      type: 'settingsLoaded',
      settings: persistedSettings,
    }),
  );

  ws.on('message', (data) => {
    try {
      const message = JSON.parse(data.toString());
      handleClientMessage(message, ws);
    } catch (err) {
      console.error('Failed to parse message:', err);
    }
  });

  ws.on('close', () => {
    console.log('Client disconnected');
    clients.delete(ws);
  });
});

function handleClientMessage(message: any, ws: WebSocket): void {
  if (message.type === 'getSessionInfo') {
    const info = sessionManager.getSessionInfo(message.id);
    ws.send(
      JSON.stringify({
        type: 'sessionInfo',
        id: message.id,
        info,
      }),
    );
  } else if (message.type === 'saveLayout') {
    writeLayout(message.layout);
  } else if (message.type === 'saveAgentSeats') {
    const current = readAgentSeats();
    const updated = { ...current, ...message.seats };
    writeAgentSeats(updated);
  } else if (message.type === 'setSoundEnabled') {
    const settings = readSettings();
    settings.soundEnabled = message.enabled;
    writeSettings(settings);
  } else if (message.type === 'exportLayout') {
    const layout = readLayout();
    ws.send(
      JSON.stringify({
        type: 'layoutExported',
        layout,
      }),
    );
  } else if (message.type === 'importLayout') {
    try {
      const layout = JSON.parse(message.layoutJson);
      writeLayout(layout);
      broadcast({ type: 'layoutLoaded', layout, wasReset: false });
    } catch (err) {
      console.error('Failed to import layout:', err);
    }
  }
}

// SPA fallback - serve index.html for all non-API routes
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
app.use((_req, res) => {
  res.sendFile(path.join(__dirname, '../../webview-ui/dist/index.html'));
});

server.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
  sessionManager.start();
});

process.on('SIGINT', () => {
  console.log('Shutting down...');
  sessionManager.stop();
  layoutWatcher?.close();
  server.close();
  process.exit(0);
});

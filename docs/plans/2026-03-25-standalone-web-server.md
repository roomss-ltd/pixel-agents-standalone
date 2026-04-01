# Pixel Agents Standalone Web Server Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Convert Pixel Agents from a VS Code extension to a standalone web application that auto-detects Claude Code sessions running in any terminal (Ghostty, Zellij, etc.) and visualizes them in a browser.

**Architecture:** Node.js backend with Express (serves React app) + WebSocket (real-time updates). Backend scans `~/.claude/projects/` for JSONL files, watches them for changes, parses transcripts, and pushes agent status updates to connected browsers. React frontend connects via WebSocket instead of VS Code message passing.

**Tech Stack:** Node.js, Express, ws (WebSocket), React (existing), TypeScript, fs/path for file operations

---

## Phase 1: Backend Foundation

### Task 1: Server Project Structure

**Files:**
- Create: `server/package.json`
- Create: `server/tsconfig.json`
- Create: `server/src/index.ts`
- Create: `server/src/types.ts`

**Step 1: Create server directory and package.json**

```bash
mkdir -p server/src
cd server
npm init -y
```

**Step 2: Install dependencies**

```bash
npm install express ws cors
npm install -D @types/express @types/ws @types/node typescript tsx
```

**Step 3: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "node",
    "esModuleInterop": true,
    "strict": true,
    "skipLibCheck": true,
    "outDir": "./dist",
    "rootDir": "./src",
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules"]
}
```

**Step 4: Create basic server entry point**

File: `server/src/index.ts`

```typescript
import express from 'express';
import { WebSocketServer } from 'ws';
import { createServer } from 'http';

const PORT = 3000;
const app = express();
const server = createServer(app);
const wss = new WebSocketServer({ server });

// Serve static files (React build)
app.use(express.static('../webview-ui/dist'));

wss.on('connection', (ws) => {
  console.log('Client connected');

  ws.on('message', (data) => {
    console.log('Received:', data.toString());
  });

  ws.on('close', () => {
    console.log('Client disconnected');
  });
});

server.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
```

**Step 5: Create shared types**

File: `server/src/types.ts`

```typescript
export interface SessionInfo {
  id: number;
  sessionId: string;
  projectPath: string;
  projectName: string;
  jsonlFile: string;
  lastModified: number;
  fileSize: number;
  isActive: boolean;
}

export interface AgentState {
  id: number;
  sessionId: string;
  projectDir: string;
  projectName: string;
  jsonlFile: string;
  fileOffset: number;
  lineBuffer: string;
  activeToolIds: Set<string>;
  activeToolStatuses: Map<string, string>;
  activeToolNames: Map<string, string>;
  activeSubagentToolIds: Map<string, Set<string>>;
  activeSubagentToolNames: Map<string, Map<string, string>>;
  isWaiting: boolean;
  permissionSent: boolean;
  hadToolsInTurn: boolean;
  lastActivity: number;
}

export type WebSocketMessage =
  | { type: 'sessionCreated'; id: number; projectName: string }
  | { type: 'sessionClosed'; id: number }
  | { type: 'sessionInactive'; id: number }
  | { type: 'agentToolStart'; id: number; toolId: string; status: string }
  | { type: 'agentToolDone'; id: number; toolId: string }
  | { type: 'agentToolClear'; id: number }
  | { type: 'agentStatus'; id: number; status: 'waiting' | 'permission' }
  | { type: 'agentToolPermissionClear'; id: number }
  | { type: 'existingSessions'; sessions: SessionInfo[] }
  | { type: 'layoutLoaded'; layout: unknown; wasReset: boolean }
  | { type: 'sessionInfo'; id: number; info: SessionInfo };
```

**Step 6: Add dev script to package.json**

Edit `server/package.json`:

```json
{
  "type": "module",
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js"
  }
}
```

**Step 7: Test server starts**

Run: `npm run dev`
Expected: "Server running on http://localhost:3000"
Visit: http://localhost:3000 (should show 404 or empty page, that's OK)

**Step 8: Commit**

```bash
git add server/
git commit -m "feat: initialize Node.js server with Express and WebSocket"
```

---

### Task 2: Session Discovery Module

**Files:**
- Create: `server/src/sessionManager.ts`
- Modify: `server/src/index.ts`

**Step 1: Create sessionManager module**

File: `server/src/sessionManager.ts`

```typescript
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import type { SessionInfo, AgentState } from './types.js';

const CLAUDE_PROJECTS_DIR = path.join(os.homedir(), '.claude', 'projects');
const SCAN_INTERVAL_MS = 1000;
const INACTIVE_THRESHOLD_MS = 60 * 60 * 1000; // 1 hour

export class SessionManager {
  private agents = new Map<number, AgentState>();
  private knownJsonlFiles = new Set<string>();
  private nextAgentId = 1;
  private scanInterval: NodeJS.Timeout | null = null;
  private broadcastCallback: (message: any) => void;

  constructor(broadcastCallback: (message: any) => void) {
    this.broadcastCallback = broadcastCallback;
  }

  start(): void {
    console.log('[SessionManager] Starting session discovery...');
    this.scanForSessions();
    this.scanInterval = setInterval(() => {
      this.scanForSessions();
    }, SCAN_INTERVAL_MS);
  }

  stop(): void {
    if (this.scanInterval) {
      clearInterval(this.scanInterval);
      this.scanInterval = null;
    }
  }

  private scanForSessions(): void {
    try {
      if (!fs.existsSync(CLAUDE_PROJECTS_DIR)) {
        return;
      }

      const projectDirs = fs.readdirSync(CLAUDE_PROJECTS_DIR);

      for (const projectDir of projectDirs) {
        const fullPath = path.join(CLAUDE_PROJECTS_DIR, projectDir);
        if (!fs.statSync(fullPath).isDirectory()) continue;

        const jsonlFiles = fs.readdirSync(fullPath).filter(f => f.endsWith('.jsonl'));

        for (const jsonlFile of jsonlFiles) {
          const jsonlPath = path.join(fullPath, jsonlFile);
          this.handleJsonlFile(jsonlPath, fullPath, projectDir);
        }
      }
    } catch (err) {
      console.error('[SessionManager] Scan error:', err);
    }
  }

  private handleJsonlFile(jsonlPath: string, projectDir: string, projectHash: string): void {
    if (this.knownJsonlFiles.has(jsonlPath)) {
      // Existing session - check for activity
      this.checkSessionActivity(jsonlPath);
      return;
    }

    // New session discovered
    this.knownJsonlFiles.add(jsonlPath);
    const sessionId = path.basename(jsonlPath, '.jsonl');
    const projectName = this.hashToProjectName(projectHash);

    const id = this.nextAgentId++;
    const agent: AgentState = {
      id,
      sessionId,
      projectDir,
      projectName,
      jsonlFile: jsonlPath,
      fileOffset: 0,
      lineBuffer: '',
      activeToolIds: new Set(),
      activeToolStatuses: new Map(),
      activeToolNames: new Map(),
      activeSubagentToolIds: new Map(),
      activeSubagentToolNames: new Map(),
      isWaiting: false,
      permissionSent: false,
      hadToolsInTurn: false,
      lastActivity: Date.now(),
    };

    this.agents.set(id, agent);
    console.log(`[SessionManager] New session: ${sessionId} (${projectName})`);

    this.broadcastCallback({
      type: 'sessionCreated',
      id,
      projectName,
    });
  }

  private checkSessionActivity(jsonlPath: string): void {
    try {
      const stats = fs.statSync(jsonlPath);
      const agent = Array.from(this.agents.values()).find(a => a.jsonlFile === jsonlPath);

      if (!agent) return;

      const now = Date.now();
      const timeSinceModified = now - stats.mtimeMs;

      // Check if session became inactive
      if (timeSinceModified > INACTIVE_THRESHOLD_MS && agent.lastActivity < now - INACTIVE_THRESHOLD_MS) {
        console.log(`[SessionManager] Session ${agent.id} inactive`);
        this.broadcastCallback({
          type: 'sessionInactive',
          id: agent.id,
        });
      }
    } catch (err) {
      // File might have been deleted
      console.log(`[SessionManager] File no longer exists: ${jsonlPath}`);
    }
  }

  private hashToProjectName(hash: string): string {
    // Convert hash back to readable path
    // -Users-adrianzabica-Desktop-pixel-agents → pixel-agents
    const parts = hash.split('-').filter(p => p);
    return parts[parts.length - 1] || hash;
  }

  getAgents(): Map<number, AgentState> {
    return this.agents;
  }

  getSessionInfo(id: number): SessionInfo | null {
    const agent = this.agents.get(id);
    if (!agent) return null;

    try {
      const stats = fs.statSync(agent.jsonlFile);
      return {
        id: agent.id,
        sessionId: agent.sessionId,
        projectPath: agent.projectDir,
        projectName: agent.projectName,
        jsonlFile: agent.jsonlFile,
        lastModified: stats.mtimeMs,
        fileSize: stats.size,
        isActive: Date.now() - stats.mtimeMs < 5 * 60 * 1000,
      };
    } catch {
      return null;
    }
  }
}
```

**Step 2: Integrate SessionManager into server**

Edit `server/src/index.ts`:

```typescript
import express from 'express';
import { WebSocketServer, WebSocket } from 'ws';
import { createServer } from 'http';
import { SessionManager } from './sessionManager.js';

const PORT = 3000;
const app = express();
const server = createServer(app);
const wss = new WebSocketServer({ server });

const clients = new Set<WebSocket>();

// Broadcast to all connected clients
function broadcast(message: any): void {
  const data = JSON.stringify(message);
  clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(data);
    }
  });
}

const sessionManager = new SessionManager(broadcast);

app.use(express.static('../webview-ui/dist'));

wss.on('connection', (ws) => {
  console.log('Client connected');
  clients.add(ws);

  // Send existing sessions to new client
  const sessions = Array.from(sessionManager.getAgents().values()).map(agent => ({
    id: agent.id,
    projectName: agent.projectName,
  }));

  ws.send(JSON.stringify({
    type: 'existingSessions',
    sessions,
  }));

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
    ws.send(JSON.stringify({
      type: 'sessionInfo',
      id: message.id,
      info,
    }));
  }
}

server.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
  sessionManager.start();
});

process.on('SIGINT', () => {
  console.log('Shutting down...');
  sessionManager.stop();
  server.close();
  process.exit(0);
});
```

**Step 3: Test session discovery**

Run: `npm run dev`
Expected: Console shows "[SessionManager] Starting session discovery..."

If you have any Claude sessions running, it should detect them:
"[SessionManager] New session: abc123 (pixel-agents)"

**Step 4: Commit**

```bash
git add server/src/
git commit -m "feat: add session discovery and management"
```

---

### Task 3: File Watching & JSONL Parsing

**Files:**
- Create: `server/src/fileWatcher.ts`
- Copy: `src/transcriptParser.ts` → `server/src/transcriptParser.ts`
- Copy: `src/timerManager.ts` → `server/src/timerManager.ts`
- Copy: `src/constants.ts` → `server/src/constants.ts` (partial)
- Modify: `server/src/sessionManager.ts`

**Step 1: Copy and adapt constants**

Create `server/src/constants.ts`:

```typescript
// File watching
export const FILE_WATCHER_POLL_INTERVAL_MS = 2000;

// Tool status
export const TOOL_DONE_DELAY_MS = 300;
export const TEXT_IDLE_DELAY_MS = 5000;
export const PERMISSION_TIMER_DELAY_MS = 5000;
export const WAITING_TIMER_DELAY_MS = 2000;

// Display truncation
export const TOOL_STATUS_TRUNCATE_LENGTH = 50;

// Exempt tools (don't trigger permission timer)
export const EXEMPT_TOOLS = new Set([
  'AskUserQuestion',
  'Read',
  'Grep',
  'Glob',
  'ListDir',
  'GetCurrentDir',
]);
```

**Step 2: Copy and adapt timerManager**

Copy `src/timerManager.ts` to `server/src/timerManager.ts` and update imports:

```typescript
import { PERMISSION_TIMER_DELAY_MS, WAITING_TIMER_DELAY_MS } from './constants.js';
import type { AgentState } from './types.js';

// Remove vscode import, replace webview with broadcast callback
type BroadcastCallback = (message: any) => void;

export function startPermissionTimer(
  agentId: number,
  permissionTimers: Map<number, NodeJS.Timeout>,
  agents: Map<number, AgentState>,
  broadcast: BroadcastCallback,
): void {
  cancelPermissionTimer(agentId, permissionTimers);
  const timer = setTimeout(() => {
    const agent = agents.get(agentId);
    if (!agent) return;
    if (agent.permissionSent) return;
    agent.permissionSent = true;
    broadcast({ type: 'agentStatus', id: agentId, status: 'permission' });
  }, PERMISSION_TIMER_DELAY_MS);
  permissionTimers.set(agentId, timer);
}

export function cancelPermissionTimer(
  agentId: number,
  permissionTimers: Map<number, NodeJS.Timeout>,
): void {
  const timer = permissionTimers.get(agentId);
  if (timer) {
    clearTimeout(timer);
    permissionTimers.delete(agentId);
  }
}

export function startWaitingTimer(
  agentId: number,
  waitingTimers: Map<number, NodeJS.Timeout>,
  agents: Map<number, AgentState>,
  broadcast: BroadcastCallback,
): void {
  cancelWaitingTimer(agentId, waitingTimers);
  const timer = setTimeout(() => {
    const agent = agents.get(agentId);
    if (!agent) return;
    agent.isWaiting = true;
    broadcast({ type: 'agentStatus', id: agentId, status: 'waiting' });
  }, WAITING_TIMER_DELAY_MS);
  waitingTimers.set(agentId, timer);
}

export function cancelWaitingTimer(
  agentId: number,
  waitingTimers: Map<number, NodeJS.Timeout>,
): void {
  const timer = waitingTimers.get(agentId);
  if (timer) {
    clearTimeout(timer);
    waitingTimers.delete(agentId);
  }
}

export function clearAgentActivity(
  agent: AgentState,
  agentId: number,
  permissionTimers: Map<number, NodeJS.Timeout>,
  broadcast: BroadcastCallback,
): void {
  agent.activeToolIds.clear();
  agent.activeToolStatuses.clear();
  agent.activeToolNames.clear();
  agent.activeSubagentToolIds.clear();
  agent.activeSubagentToolNames.clear();
  agent.isWaiting = false;
  agent.permissionSent = false;
  agent.hadToolsInTurn = false;
  cancelPermissionTimer(agentId, permissionTimers);
  broadcast({ type: 'agentToolClear', id: agentId });
}
```

**Step 3: Copy and adapt transcriptParser**

Copy `src/transcriptParser.ts` to `server/src/transcriptParser.ts` and update:

```typescript
import {
  EXEMPT_TOOLS,
  TOOL_DONE_DELAY_MS,
  TOOL_STATUS_TRUNCATE_LENGTH,
  TEXT_IDLE_DELAY_MS,
} from './constants.js';
import {
  cancelPermissionTimer,
  cancelWaitingTimer,
  clearAgentActivity,
  startPermissionTimer,
  startWaitingTimer,
} from './timerManager.js';
import type { AgentState } from './types.js';

// Remove vscode import, add broadcast callback type
type BroadcastCallback = (message: any) => void;

// Rest of the file remains the same, but replace all:
// - webview?.postMessage(...) → broadcast(...)
// - vscode.Webview | undefined → BroadcastCallback

export function processTranscriptLine(
  agentId: number,
  line: string,
  agents: Map<number, AgentState>,
  waitingTimers: Map<number, NodeJS.Timeout>,
  permissionTimers: Map<number, NodeJS.Timeout>,
  broadcast: BroadcastCallback,
): void {
  // ... (copy full implementation from src/transcriptParser.ts)
  // Replace all webview?.postMessage with broadcast
}

// ... (copy all other functions)
```

**Step 4: Create fileWatcher module**

Copy `src/fileWatcher.ts` to `server/src/fileWatcher.ts` and adapt:

```typescript
import * as fs from 'fs';
import { FILE_WATCHER_POLL_INTERVAL_MS } from './constants.js';
import { cancelPermissionTimer, cancelWaitingTimer } from './timerManager.js';
import { processTranscriptLine } from './transcriptParser.js';
import type { AgentState } from './types.js';

type BroadcastCallback = (message: any) => void;

export function startFileWatching(
  agentId: number,
  filePath: string,
  agents: Map<number, AgentState>,
  fileWatchers: Map<number, fs.FSWatcher>,
  pollingTimers: Map<number, NodeJS.Timeout>,
  waitingTimers: Map<number, NodeJS.Timeout>,
  permissionTimers: Map<number, NodeJS.Timeout>,
  broadcast: BroadcastCallback,
): void {
  // Primary: fs.watch
  try {
    const watcher = fs.watch(filePath, () => {
      readNewLines(agentId, agents, waitingTimers, permissionTimers, broadcast);
    });
    fileWatchers.set(agentId, watcher);
  } catch (e) {
    console.log(`[FileWatcher] fs.watch failed for agent ${agentId}: ${e}`);
  }

  // Secondary: fs.watchFile
  try {
    fs.watchFile(filePath, { interval: FILE_WATCHER_POLL_INTERVAL_MS }, () => {
      readNewLines(agentId, agents, waitingTimers, permissionTimers, broadcast);
    });
  } catch (e) {
    console.log(`[FileWatcher] fs.watchFile failed for agent ${agentId}: ${e}`);
  }

  // Tertiary: manual poll
  const interval = setInterval(() => {
    if (!agents.has(agentId)) {
      clearInterval(interval);
      try {
        fs.unwatchFile(filePath);
      } catch {
        /* ignore */
      }
      return;
    }
    readNewLines(agentId, agents, waitingTimers, permissionTimers, broadcast);
  }, FILE_WATCHER_POLL_INTERVAL_MS);
  pollingTimers.set(agentId, interval);
}

export function readNewLines(
  agentId: number,
  agents: Map<number, AgentState>,
  waitingTimers: Map<number, NodeJS.Timeout>,
  permissionTimers: Map<number, NodeJS.Timeout>,
  broadcast: BroadcastCallback,
): void {
  const agent = agents.get(agentId);
  if (!agent) return;

  try {
    const stat = fs.statSync(agent.jsonlFile);
    if (stat.size <= agent.fileOffset) return;

    const buf = Buffer.alloc(stat.size - agent.fileOffset);
    const fd = fs.openSync(agent.jsonlFile, 'r');
    fs.readSync(fd, buf, 0, buf.length, agent.fileOffset);
    fs.closeSync(fd);
    agent.fileOffset = stat.size;

    const text = agent.lineBuffer + buf.toString('utf-8');
    const lines = text.split('\n');
    agent.lineBuffer = lines.pop() || '';

    const hasLines = lines.some((l) => l.trim());
    if (hasLines) {
      agent.lastActivity = Date.now();
      cancelWaitingTimer(agentId, waitingTimers);
      cancelPermissionTimer(agentId, permissionTimers);
      if (agent.permissionSent) {
        agent.permissionSent = false;
        broadcast({ type: 'agentToolPermissionClear', id: agentId });
      }
    }

    for (const line of lines) {
      if (!line.trim()) continue;
      processTranscriptLine(agentId, line, agents, waitingTimers, permissionTimers, broadcast);
    }
  } catch (e) {
    console.log(`[FileWatcher] Read error for agent ${agentId}: ${e}`);
  }
}

export function stopFileWatching(
  agentId: number,
  agent: AgentState,
  fileWatchers: Map<number, fs.FSWatcher>,
  pollingTimers: Map<number, NodeJS.Timeout>,
): void {
  fileWatchers.get(agentId)?.close();
  fileWatchers.delete(agentId);

  const timer = pollingTimers.get(agentId);
  if (timer) {
    clearInterval(timer);
    pollingTimers.delete(agentId);
  }

  try {
    fs.unwatchFile(agent.jsonlFile);
  } catch {
    /* ignore */
  }
}
```

**Step 5: Integrate file watching into SessionManager**

Edit `server/src/sessionManager.ts`, add at top:

```typescript
import { startFileWatching, stopFileWatching } from './fileWatcher.js';
```

Add class properties:

```typescript
export class SessionManager {
  private agents = new Map<number, AgentState>();
  private knownJsonlFiles = new Set<string>();
  private nextAgentId = 1;
  private scanInterval: NodeJS.Timeout | null = null;
  private broadcastCallback: (message: any) => void;

  // Add these:
  private fileWatchers = new Map<number, fs.FSWatcher>();
  private pollingTimers = new Map<number, NodeJS.Timeout>();
  private waitingTimers = new Map<number, NodeJS.Timeout>();
  private permissionTimers = new Map<number, NodeJS.Timeout>();

  // ...
```

Update `handleJsonlFile` to start watching:

```typescript
private handleJsonlFile(jsonlPath: string, projectDir: string, projectHash: string): void {
  if (this.knownJsonlFiles.has(jsonlPath)) {
    this.checkSessionActivity(jsonlPath);
    return;
  }

  this.knownJsonlFiles.add(jsonlPath);
  const sessionId = path.basename(jsonlPath, '.jsonl');
  const projectName = this.hashToProjectName(projectHash);

  const id = this.nextAgentId++;
  const agent: AgentState = {
    id,
    sessionId,
    projectDir,
    projectName,
    jsonlFile: jsonlPath,
    fileOffset: 0,
    lineBuffer: '',
    activeToolIds: new Set(),
    activeToolStatuses: new Map(),
    activeToolNames: new Map(),
    activeSubagentToolIds: new Map(),
    activeSubagentToolNames: new Map(),
    isWaiting: false,
    permissionSent: false,
    hadToolsInTurn: false,
    lastActivity: Date.now(),
  };

  this.agents.set(id, agent);
  console.log(`[SessionManager] New session: ${sessionId} (${projectName})`);

  this.broadcastCallback({
    type: 'sessionCreated',
    id,
    projectName,
  });

  // Start watching the file
  startFileWatching(
    id,
    jsonlPath,
    this.agents,
    this.fileWatchers,
    this.pollingTimers,
    this.waitingTimers,
    this.permissionTimers,
    this.broadcastCallback,
  );
}
```

Update `stop()` method:

```typescript
stop(): void {
  if (this.scanInterval) {
    clearInterval(this.scanInterval);
    this.scanInterval = null;
  }

  // Stop all file watchers
  for (const [id, agent] of this.agents) {
    stopFileWatching(id, agent, this.fileWatchers, this.pollingTimers);
  }
}
```

**Step 6: Test with a Claude session**

1. Run a Claude Code session in your terminal: `claude --session-id test123`
2. Run the server: `npm run dev`
3. Expected console output:
   - "[SessionManager] New session: test123 (your-project)"
   - "[FileWatcher] Reading new lines..." (when you interact with Claude)

**Step 7: Commit**

```bash
git add server/src/
git commit -m "feat: add file watching and JSONL parsing"
```

---

## Phase 2: Frontend Adaptation

### Task 4: WebSocket Hook

**Files:**
- Create: `webview-ui/src/hooks/useWebSocket.ts`
- Modify: `webview-ui/src/App.tsx`

**Step 1: Create WebSocket hook**

File: `webview-ui/src/hooks/useWebSocket.ts`

```typescript
import { useEffect, useRef, useState } from 'react';

export interface WebSocketMessage {
  type: string;
  [key: string]: any;
}

export function useWebSocket(url: string, onMessage: (message: WebSocketMessage) => void) {
  const [isConnected, setIsConnected] = useState(false);
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  useEffect(() => {
    function connect() {
      const ws = new WebSocket(url);
      wsRef.current = ws;

      ws.onopen = () => {
        console.log('[WebSocket] Connected');
        setIsConnected(true);
      };

      ws.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data);
          onMessage(message);
        } catch (err) {
          console.error('[WebSocket] Failed to parse message:', err);
        }
      };

      ws.onclose = () => {
        console.log('[WebSocket] Disconnected');
        setIsConnected(false);
        wsRef.current = null;

        // Reconnect after 2 seconds
        reconnectTimeoutRef.current = setTimeout(() => {
          console.log('[WebSocket] Reconnecting...');
          connect();
        }, 2000);
      };

      ws.onerror = (err) => {
        console.error('[WebSocket] Error:', err);
      };
    }

    connect();

    return () => {
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
      }
      if (wsRef.current) {
        wsRef.current.close();
      }
    };
  }, [url]);

  const sendMessage = (message: WebSocketMessage) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify(message));
    } else {
      console.warn('[WebSocket] Cannot send message, not connected');
    }
  };

  return { isConnected, sendMessage };
}
```

**Step 2: Update App.tsx to use WebSocket**

Edit `webview-ui/src/App.tsx`:

Find the `useExtensionMessages` hook import and replace with:

```typescript
import { useWebSocket } from './hooks/useWebSocket';
```

Replace the hook usage:

```typescript
// OLD:
// const { agents, tools, ... } = useExtensionMessages(...);

// NEW:
const WS_URL = import.meta.env.DEV
  ? 'ws://localhost:3000'
  : `ws://${window.location.host}`;

const handleWebSocketMessage = (message: any) => {
  // Forward to existing message handler logic
  // (we'll migrate useExtensionMessages logic here)
};

const { isConnected, sendMessage } = useWebSocket(WS_URL, handleWebSocketMessage);
```

**Step 3: Migrate useExtensionMessages to standalone hook**

Rename `webview-ui/src/hooks/useExtensionMessages.ts` to `useAgentState.ts`:

```typescript
// Remove VS Code specific logic
// Keep all state management (agents, tools, etc.)
// Return state + handlers that accept messages

export function useAgentState() {
  const [agents, setAgents] = useState<Map<number, Character>>(new Map());
  const [tools, setTools] = useState<Map<number, Set<string>>>(new Map());
  // ... all other state

  const handleMessage = (message: any) => {
    switch (message.type) {
      case 'sessionCreated':
        // Same as 'agentCreated' handler
        break;
      case 'agentToolStart':
        // Existing handler
        break;
      // ... all other cases
    }
  };

  return {
    agents,
    tools,
    // ... all state
    handleMessage,
  };
}
```

**Step 4: Wire up in App.tsx**

```typescript
function App() {
  const { agents, tools, handleMessage, ... } = useAgentState();

  const WS_URL = import.meta.env.DEV
    ? 'ws://localhost:3000'
    : `ws://${window.location.host}`;

  const { isConnected, sendMessage } = useWebSocket(WS_URL, handleMessage);

  // Pass sendMessage to components that need to send (like BottomToolbar)
  // ...
}
```

**Step 5: Update BottomToolbar**

Edit `webview-ui/src/components/BottomToolbar.tsx`:

Remove "+ Agent" button (can't create terminals anymore):

```typescript
// Remove this:
// <button onClick={() => postMessage({ type: 'openClaude' })}>
//   + Agent
// </button>

// Replace with connection indicator:
<div style={{
  padding: '4px 8px',
  backgroundColor: isConnected ? '#2a9d8f' : '#e76f51',
  color: 'white',
  fontSize: '12px',
  borderRadius: 0,
  border: '2px solid var(--pixel-border)',
}}>
  {isConnected ? '● Connected' : '○ Disconnected'}
</div>
```

**Step 6: Test frontend connection**

1. Run server: `cd server && npm run dev`
2. Run frontend: `cd webview-ui && npm run dev`
3. Open browser to `http://localhost:5173`
4. Check console for "[WebSocket] Connected"
5. Check server console for "Client connected"

**Step 7: Commit**

```bash
git add webview-ui/src/
git commit -m "feat: replace VS Code messaging with WebSocket"
```

---

### Task 5: Asset Loading in Standalone

**Files:**
- Create: `server/src/assetLoader.ts`
- Modify: `server/src/index.ts`

**Step 1: Copy asset loading logic**

Create `server/src/assetLoader.ts` (adapted from `src/assetLoader.ts`):

```typescript
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { PNG } from 'pngjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Assets are in project root
const ASSETS_DIR = path.join(__dirname, '../../webview-ui/public/assets');

export function loadAssets() {
  const assets = {
    characterSprites: loadCharacterSprites(),
    floorTiles: loadFloorTiles(),
    wallTiles: loadWallTiles(),
    furnitureCatalog: loadFurnitureCatalog(),
    defaultLayout: loadDefaultLayout(),
  };

  return assets;
}

function loadCharacterSprites(): string[][][] {
  // Returns base64 encoded sprite data for 6 character palettes
  const sprites: string[][][] = [];

  for (let i = 0; i < 6; i++) {
    const filePath = path.join(ASSETS_DIR, `characters/char_${i}.png`);
    if (fs.existsSync(filePath)) {
      const png = PNG.sync.read(fs.readFileSync(filePath));
      // Convert to sprite data format (same as extension)
      const spriteData = pngToSpriteData(png);
      sprites.push(spriteData);
    }
  }

  return sprites;
}

function loadFloorTiles(): string[][] {
  const filePath = path.join(ASSETS_DIR, 'floors.png');
  if (fs.existsSync(filePath)) {
    const png = PNG.sync.read(fs.readFileSync(filePath));
    return pngToSpriteData(png);
  }
  return [];
}

function loadWallTiles(): string[][] {
  const filePath = path.join(ASSETS_DIR, 'walls.png');
  if (fs.existsSync(filePath)) {
    const png = PNG.sync.read(fs.readFileSync(filePath));
    return pngToSpriteData(png);
  }
  return [];
}

function loadFurnitureCatalog(): any {
  const filePath = path.join(ASSETS_DIR, 'furniture-catalog.json');
  if (fs.existsSync(filePath)) {
    return JSON.parse(fs.readFileSync(filePath, 'utf-8'));
  }
  return { entries: [] };
}

function loadDefaultLayout(): any {
  const filePath = path.join(ASSETS_DIR, 'default-layout.json');
  if (fs.existsSync(filePath)) {
    return JSON.parse(fs.readFileSync(filePath, 'utf-8'));
  }
  return null;
}

function pngToSpriteData(png: PNG): string[][] {
  const { width, height, data } = png;
  const sprites: string[][] = [];

  for (let y = 0; y < height; y++) {
    const row: string[] = [];
    for (let x = 0; x < width; x++) {
      const idx = (y * width + x) * 4;
      const r = data[idx];
      const g = data[idx + 1];
      const b = data[idx + 2];
      const a = data[idx + 3];

      if (a < 2) {
        row.push(''); // Transparent
      } else {
        const hex = `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;
        row.push(a < 255 ? `${hex}${a.toString(16).padStart(2, '0')}` : hex);
      }
    }
    sprites.push(row);
  }

  return sprites;
}
```

**Step 2: Install pngjs**

```bash
cd server
npm install pngjs
npm install -D @types/pngjs
```

**Step 3: Serve assets on WebSocket connect**

Edit `server/src/index.ts`:

```typescript
import { loadAssets } from './assetLoader.js';

// Load assets once at startup
const assets = loadAssets();

wss.on('connection', (ws) => {
  console.log('Client connected');
  clients.add(ws);

  // Send assets
  ws.send(JSON.stringify({
    type: 'characterSpritesLoaded',
    sprites: assets.characterSprites,
  }));

  ws.send(JSON.stringify({
    type: 'floorTilesLoaded',
    sprites: assets.floorTiles,
  }));

  ws.send(JSON.stringify({
    type: 'wallTilesLoaded',
    sprites: assets.wallTiles,
  }));

  ws.send(JSON.stringify({
    type: 'furnitureAssetsLoaded',
    catalog: assets.furnitureCatalog,
  }));

  ws.send(JSON.stringify({
    type: 'layoutLoaded',
    layout: assets.defaultLayout,
    wasReset: false,
  }));

  // Send existing sessions
  const sessions = Array.from(sessionManager.getAgents().values()).map(agent => ({
    id: agent.id,
    projectName: agent.projectName,
  }));

  ws.send(JSON.stringify({
    type: 'existingSessions',
    sessions,
  }));

  // ... rest of connection handler
});
```

**Step 4: Test asset loading**

Run server and frontend, check browser console for:
- "Loaded character sprites"
- "Loaded floor tiles"
- "Loaded wall tiles"
- "Loaded furniture catalog"

**Step 5: Commit**

```bash
git add server/src/assetLoader.ts server/package.json
git commit -m "feat: add asset loading for standalone server"
```

---

## Phase 3: Persistence Layer

### Task 6: JSON File Storage

**Files:**
- Create: `server/src/persistence.ts`
- Modify: `server/src/index.ts`

**Step 1: Create persistence module**

File: `server/src/persistence.ts`

```typescript
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

const PIXEL_AGENTS_DIR = path.join(os.homedir(), '.pixel-agents');
const LAYOUT_FILE = path.join(PIXEL_AGENTS_DIR, 'layout.json');
const AGENT_SEATS_FILE = path.join(PIXEL_AGENTS_DIR, 'agent-seats.json');
const SETTINGS_FILE = path.join(PIXEL_AGENTS_DIR, 'settings.json');

// Ensure directory exists
if (!fs.existsSync(PIXEL_AGENTS_DIR)) {
  fs.mkdirSync(PIXEL_AGENTS_DIR, { recursive: true });
}

export interface AgentSeatData {
  seatId?: string;
  palette?: number;
  hueShift?: number;
}

export interface Settings {
  soundEnabled: boolean;
  showInactiveSessions: boolean;
}

// Layout persistence
export function readLayout(): any {
  try {
    if (fs.existsSync(LAYOUT_FILE)) {
      return JSON.parse(fs.readFileSync(LAYOUT_FILE, 'utf-8'));
    }
  } catch (err) {
    console.error('[Persistence] Failed to read layout:', err);
  }
  return null;
}

export function writeLayout(layout: any): void {
  try {
    const tmpFile = `${LAYOUT_FILE}.tmp`;
    fs.writeFileSync(tmpFile, JSON.stringify(layout, null, 2));
    fs.renameSync(tmpFile, LAYOUT_FILE);
    console.log('[Persistence] Layout saved');
  } catch (err) {
    console.error('[Persistence] Failed to write layout:', err);
  }
}

// Agent seats persistence
export function readAgentSeats(): Record<string, AgentSeatData> {
  try {
    if (fs.existsSync(AGENT_SEATS_FILE)) {
      return JSON.parse(fs.readFileSync(AGENT_SEATS_FILE, 'utf-8'));
    }
  } catch (err) {
    console.error('[Persistence] Failed to read agent seats:', err);
  }
  return {};
}

export function writeAgentSeats(seats: Record<string, AgentSeatData>): void {
  try {
    fs.writeFileSync(AGENT_SEATS_FILE, JSON.stringify(seats, null, 2));
    console.log('[Persistence] Agent seats saved');
  } catch (err) {
    console.error('[Persistence] Failed to write agent seats:', err);
  }
}

// Settings persistence
export function readSettings(): Settings {
  try {
    if (fs.existsSync(SETTINGS_FILE)) {
      return JSON.parse(fs.readFileSync(SETTINGS_FILE, 'utf-8'));
    }
  } catch (err) {
    console.error('[Persistence] Failed to read settings:', err);
  }
  return {
    soundEnabled: true,
    showInactiveSessions: true,
  };
}

export function writeSettings(settings: Settings): void {
  try {
    fs.writeFileSync(SETTINGS_FILE, JSON.stringify(settings, null, 2));
    console.log('[Persistence] Settings saved');
  } catch (err) {
    console.error('[Persistence] Failed to write settings:', err);
  }
}

// Watch layout file for external changes
export function watchLayoutFile(callback: (layout: any) => void): fs.FSWatcher | null {
  try {
    let lastMtime = fs.existsSync(LAYOUT_FILE) ? fs.statSync(LAYOUT_FILE).mtimeMs : 0;

    return fs.watch(LAYOUT_FILE, () => {
      try {
        const currentMtime = fs.statSync(LAYOUT_FILE).mtimeMs;
        if (currentMtime !== lastMtime) {
          lastMtime = currentMtime;
          const layout = readLayout();
          if (layout) {
            callback(layout);
          }
        }
      } catch {
        /* ignore */
      }
    });
  } catch (err) {
    console.error('[Persistence] Failed to watch layout file:', err);
    return null;
  }
}
```

**Step 2: Integrate persistence into server**

Edit `server/src/index.ts`:

```typescript
import {
  readLayout,
  writeLayout,
  readAgentSeats,
  writeAgentSeats,
  readSettings,
  writeSettings,
  watchLayoutFile,
} from './persistence.js';

// Load persisted data at startup
const persistedLayout = readLayout();
const persistedSeats = readAgentSeats();
const persistedSettings = readSettings();

// Watch layout file for external changes
const layoutWatcher = watchLayoutFile((layout) => {
  broadcast({ type: 'layoutLoaded', layout, wasReset: false });
});

// Update handleClientMessage function
function handleClientMessage(message: any, ws: WebSocket): void {
  if (message.type === 'getSessionInfo') {
    const info = sessionManager.getSessionInfo(message.id);
    ws.send(JSON.stringify({
      type: 'sessionInfo',
      id: message.id,
      info,
    }));
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
    ws.send(JSON.stringify({
      type: 'layoutExported',
      layout,
    }));
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

// Send persisted data on connect
wss.on('connection', (ws) => {
  // ... existing asset loading

  // Send persisted layout if available
  const layout = persistedLayout || assets.defaultLayout;
  ws.send(JSON.stringify({
    type: 'layoutLoaded',
    layout,
    wasReset: false,
  }));

  // Send agent seats
  ws.send(JSON.stringify({
    type: 'agentSeatsLoaded',
    seats: persistedSeats,
  }));

  // Send settings
  ws.send(JSON.stringify({
    type: 'settingsLoaded',
    settings: persistedSettings,
  }));

  // ... rest of connection handler
});

// Cleanup on shutdown
process.on('SIGINT', () => {
  console.log('Shutting down...');
  sessionManager.stop();
  layoutWatcher?.close();
  server.close();
  process.exit(0);
});
```

**Step 3: Test persistence**

1. Run server
2. Open browser, arrange some furniture
3. Close browser
4. Reopen browser
5. Expected: Layout is restored

**Step 4: Commit**

```bash
git add server/src/persistence.ts server/src/index.ts
git commit -m "feat: add JSON file persistence for layout, seats, and settings"
```

---

## Phase 4: Polish & Testing

### Task 7: Session Info Panel

**Files:**
- Create: `webview-ui/src/components/SessionInfoPanel.tsx`
- Modify: `webview-ui/src/App.tsx`

**Step 1: Create session info panel component**

File: `webview-ui/src/components/SessionInfoPanel.tsx`

```typescript
import { useEffect, useState } from 'react';

interface SessionInfo {
  id: number;
  sessionId: string;
  projectPath: string;
  projectName: string;
  jsonlFile: string;
  lastModified: number;
  fileSize: number;
  isActive: boolean;
}

interface Props {
  agentId: number | null;
  sendMessage: (message: any) => void;
  onClose: () => void;
}

export function SessionInfoPanel({ agentId, sendMessage, onClose }: Props) {
  const [info, setInfo] = useState<SessionInfo | null>(null);

  useEffect(() => {
    if (agentId === null) return;

    // Request session info
    sendMessage({ type: 'getSessionInfo', id: agentId });

    // Listen for response
    const handleMessage = (event: MessageEvent) => {
      try {
        const message = JSON.parse(event.data);
        if (message.type === 'sessionInfo' && message.id === agentId) {
          setInfo(message.info);
        }
      } catch {
        /* ignore */
      }
    };

    // Note: In real implementation, this should be integrated with the WebSocket hook
    // For now, this is a placeholder showing the UI structure

    return () => {
      // cleanup
    };
  }, [agentId, sendMessage]);

  if (!info) return null;

  const lastActiveAgo = Math.floor((Date.now() - info.lastModified) / 1000);
  const lastActiveText =
    lastActiveAgo < 60 ? `${lastActiveAgo}s ago` :
    lastActiveAgo < 3600 ? `${Math.floor(lastActiveAgo / 60)}m ago` :
    `${Math.floor(lastActiveAgo / 3600)}h ago`;

  return (
    <div style={{
      position: 'fixed',
      top: '50%',
      left: '50%',
      transform: 'translate(-50%, -50%)',
      backgroundColor: 'var(--pixel-bg)',
      border: '2px solid var(--pixel-border)',
      boxShadow: '4px 4px 0px var(--pixel-shadow)',
      padding: '16px',
      minWidth: '400px',
      zIndex: 10000,
    }}>
      <div style={{
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        marginBottom: '12px',
      }}>
        <h3 style={{ margin: 0, fontSize: '16px' }}>Agent #{info.id}</h3>
        <button
          onClick={onClose}
          style={{
            background: '#e76f51',
            border: '2px solid var(--pixel-border)',
            color: 'white',
            padding: '4px 8px',
            cursor: 'pointer',
            fontSize: '14px',
          }}
        >
          ✕
        </button>
      </div>

      <div style={{ fontSize: '14px', lineHeight: '1.6' }}>
        <div><strong>Session ID:</strong> {info.sessionId}</div>
        <div><strong>Project:</strong> {info.projectName}</div>
        <div><strong>Path:</strong> {info.projectPath}</div>
        <div><strong>Status:</strong> {info.isActive ? '🟢 Active' : '🟡 Idle'}</div>
        <div><strong>Last Activity:</strong> {lastActiveText}</div>
        <div><strong>Transcript Size:</strong> {Math.round(info.fileSize / 1024)} KB</div>
      </div>

      <div style={{
        marginTop: '16px',
        padding: '12px',
        backgroundColor: 'rgba(255,255,255,0.05)',
        border: '2px solid var(--pixel-border)',
        fontSize: '12px',
      }}>
        <div style={{ marginBottom: '8px' }}>
          <strong>To interact with this agent:</strong>
        </div>
        <div>Go to your terminal running this Claude session</div>
        <div style={{ marginTop: '4px', fontFamily: 'monospace', color: '#8be9fd' }}>
          Session: {info.sessionId}
        </div>
      </div>
    </div>
  );
}
```

**Step 2: Integrate into App.tsx**

Edit `webview-ui/src/App.tsx`:

```typescript
import { SessionInfoPanel } from './components/SessionInfoPanel';

function App() {
  const [selectedAgentForInfo, setSelectedAgentForInfo] = useState<number | null>(null);

  // ... existing code

  // Handle agent click to show info
  const handleAgentClick = (agentId: number) => {
    setSelectedAgentForInfo(agentId);
  };

  return (
    <div>
      {/* ... existing UI */}

      {selectedAgentForInfo !== null && (
        <SessionInfoPanel
          agentId={selectedAgentForInfo}
          sendMessage={sendMessage}
          onClose={() => setSelectedAgentForInfo(null)}
        />
      )}
    </div>
  );
}
```

**Step 3: Wire up click handler in OfficeCanvas**

Edit `webview-ui/src/office/components/OfficeCanvas.tsx`:

When an agent character is clicked, call `onAgentClick(agentId)` prop.

**Step 4: Test session info panel**

1. Start a Claude session
2. Click on the agent character
3. Expected: Panel appears with session details

**Step 5: Commit**

```bash
git add webview-ui/src/components/SessionInfoPanel.tsx webview-ui/src/App.tsx
git commit -m "feat: add session info panel for agent clicks"
```

---

### Task 8: Inactive Session Handling

**Files:**
- Modify: `webview-ui/src/office/engine/characters.ts`
- Modify: `webview-ui/src/hooks/useAgentState.ts`

**Step 1: Add inactive visual state**

Edit `webview-ui/src/hooks/useAgentState.ts`:

```typescript
// Add handler for sessionInactive message
case 'sessionInactive': {
  const agent = agents.get(message.id);
  if (agent) {
    agent.isInactive = true;  // Add this field to Character type
    setAgents(new Map(agents));
  }
  break;
}

// Also handle sessionCreated to mark as active
case 'sessionCreated': {
  // ... existing creation logic
  newAgent.isInactive = false;
  // ...
}
```

**Step 2: Update Character type**

Edit `webview-ui/src/office/types.ts`:

```typescript
export interface Character {
  id: number;
  x: number;
  y: number;
  // ... existing fields
  isInactive?: boolean;  // Add this
}
```

**Step 3: Render inactive agents differently**

Edit `webview-ui/src/office/engine/renderer.ts`:

In the character rendering section:

```typescript
// When rendering character sprite
if (ch.isInactive) {
  ctx.globalAlpha = 0.4;  // Gray out inactive agents
}

// Draw character sprite
// ...

if (ch.isInactive) {
  ctx.globalAlpha = 1.0;  // Reset
}
```

**Step 4: Test inactive state**

1. Start a Claude session
2. Let it idle for > 1 hour (or temporarily change INACTIVE_THRESHOLD_MS to 10 seconds for testing)
3. Expected: Agent becomes semi-transparent

**Step 5: Commit**

```bash
git add webview-ui/src/
git commit -m "feat: visually indicate inactive sessions"
```

---

### Task 9: Multi-Project Labels

**Files:**
- Modify: `webview-ui/src/office/components/ToolOverlay.tsx`

**Step 1: Show project name in overlay**

Edit `webview-ui/src/office/components/ToolOverlay.tsx`:

```typescript
// Add projectName to the displayed info
<div style={...}>
  {character.projectName && (
    <div style={{
      fontSize: '10px',
      color: '#8be9fd',
      marginBottom: '2px',
    }}>
      [{character.projectName}]
    </div>
  )}
  {/* ... existing tool status */}
</div>
```

**Step 2: Pass projectName from backend**

Edit `server/src/sessionManager.ts`:

Make sure `sessionCreated` message includes `projectName`, and frontend stores it on the Character object.

**Step 3: Test multi-project view**

1. Start Claude sessions in 2 different project directories
2. Expected: Each agent shows its project name label

**Step 4: Commit**

```bash
git add webview-ui/src/office/components/ToolOverlay.tsx
git commit -m "feat: display project labels for multi-project support"
```

---

### Task 10: Root Orchestration & Build Scripts

**Files:**
- Modify: `package.json` (root)
- Create: `server/build.js`
- Modify: `webview-ui/vite.config.ts`

**Step 1: Update root package.json**

Edit `package.json`:

```json
{
  "name": "pixel-agents",
  "version": "2.0.0",
  "scripts": {
    "dev": "concurrently \"npm run dev:server\" \"npm run dev:frontend\"",
    "dev:server": "cd server && npm run dev",
    "dev:frontend": "cd webview-ui && npm run dev",
    "build": "npm run build:server && npm run build:frontend",
    "build:server": "cd server && npm run build",
    "build:frontend": "cd webview-ui && npm run build",
    "start": "cd server && npm start",
    "install:all": "npm install && cd server && npm install && cd ../webview-ui && npm install"
  },
  "devDependencies": {
    "concurrently": "^8.2.0"
  }
}
```

**Step 2: Install concurrently**

```bash
npm install -D concurrently
```

**Step 3: Update Vite config for production**

Edit `webview-ui/vite.config.ts`:

```typescript
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
  server: {
    proxy: {
      '/ws': {
        target: 'ws://localhost:3000',
        ws: true,
      },
    },
  },
});
```

**Step 4: Update server to serve built frontend**

Edit `server/src/index.ts`:

```typescript
// Serve static files (React build)
app.use(express.static(path.join(__dirname, '../../webview-ui/dist')));

// Fallback to index.html for SPA routing
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '../../webview-ui/dist/index.html'));
});
```

**Step 5: Test production build**

```bash
npm run build
npm start
```

Visit http://localhost:3000 — should see the full app.

**Step 6: Commit**

```bash
git add package.json server/ webview-ui/vite.config.ts
git commit -m "feat: add build scripts and production setup"
```

---

### Task 11: Documentation

**Files:**
- Create: `docs/standalone-setup.md`
- Modify: `README.md`

**Step 1: Create setup documentation**

File: `docs/standalone-setup.md`

```markdown
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
git clone https://github.com/yourusername/pixel-agents.git
cd pixel-agents

# Install dependencies
npm run install:all
```

## Development

```bash
# Start dev server (backend + frontend)
npm run dev

# Backend runs on http://localhost:3000
# Frontend dev server on http://localhost:5173 (proxies to backend)
```

Open browser to `http://localhost:5173`

## Production

```bash
# Build both frontend and backend
npm run build

# Start production server
npm start
```

Open browser to `http://localhost:3000`

## How It Works

1. **Session Discovery**: Backend scans `~/.claude/projects/` for JSONL transcript files
2. **File Watching**: Monitors transcripts for tool usage and status updates
3. **WebSocket Updates**: Pushes real-time updates to browser
4. **Visualization**: React frontend displays agents as pixel art characters

## Data Storage

All persistent data stored in `~/.pixel-agents/`:

- `layout.json` - Office layout
- `agent-seats.json` - Agent seat assignments
- `settings.json` - User preferences

## Multi-Project Support

Pixel Agents detects sessions from all projects simultaneously. Each agent shows a label with the project name.

## Interaction

Click an agent to view session details. To respond to prompts or permissions, switch to the terminal running that Claude session.
```

**Step 2: Update main README**

Edit `README.md`:

Add section:

```markdown
## Standalone Version

The standalone version works with any terminal (Ghostty, Zellij, iTerm, etc.).

See [docs/standalone-setup.md](docs/standalone-setup.md) for setup instructions.

Quick start:
```bash
npm run install:all
npm run dev
```

Open http://localhost:5173
```

**Step 3: Commit**

```bash
git add docs/standalone-setup.md README.md
git commit -m "docs: add standalone version setup guide"
```

---

## Execution Summary

**Total Tasks:** 11
**Estimated Time:** 2-3 days

**Phase 1 (Backend):** Tasks 1-3 — ~1 day
**Phase 2 (Frontend):** Tasks 4-5 — ~0.5 days
**Phase 3 (Persistence):** Task 6 — ~0.5 days
**Phase 4 (Polish):** Tasks 7-11 — ~1 day

**Testing Strategy:**
- Test each task individually before committing
- Run end-to-end test after each phase
- Test with multiple Claude sessions across different projects

**Key Dependencies:**
- Node.js 18+
- Express, ws, pngjs
- Existing React frontend (minimal changes)

**Risks:**
- File watching reliability on different platforms (mitigated by triple-watching)
- WebSocket reconnection handling (included in hook)
- JSONL parsing edge cases (reusing battle-tested extension code)

---

Plan complete and saved to `docs/plans/2026-03-25-standalone-web-server.md`.

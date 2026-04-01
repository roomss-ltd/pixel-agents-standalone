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

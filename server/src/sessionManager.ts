import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import type { SessionInfo, AgentState } from './types.js';
import { startFileWatching, stopFileWatching } from './fileWatcher.js';

const CLAUDE_PROJECTS_DIR = path.join(os.homedir(), '.claude', 'projects');
const SCAN_INTERVAL_MS = 1000;
const INACTIVE_THRESHOLD_MS = 60 * 60 * 1000; // 1 hour

export class SessionManager {
  private agents = new Map<number, AgentState>();
  private knownJsonlFiles = new Set<string>();
  private nextAgentId = 1;
  private scanInterval: NodeJS.Timeout | null = null;
  private broadcastCallback: (message: any) => void;

  // File watching
  private fileWatchers = new Map<number, fs.FSWatcher>();
  private pollingTimers = new Map<number, NodeJS.Timeout>();
  private waitingTimers = new Map<number, NodeJS.Timeout>();
  private permissionTimers = new Map<number, NodeJS.Timeout>();

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

    // Stop all file watchers
    for (const [id, agent] of this.agents) {
      stopFileWatching(id, agent, this.fileWatchers, this.pollingTimers);
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

        const jsonlFiles = fs.readdirSync(fullPath).filter((f) => f.endsWith('.jsonl'));

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

    // Check if file is recently active (modified in last 5 minutes)
    try {
      const stats = fs.statSync(jsonlPath);
      const timeSinceModified = Date.now() - stats.mtimeMs;
      const ACTIVE_THRESHOLD_MS = 30 * 60 * 1000; // 30 minutes

      if (timeSinceModified > ACTIVE_THRESHOLD_MS) {
        // Skip old/inactive session files
        return;
      }
    } catch (err) {
      // File doesn't exist or can't be read - skip it
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

  private checkSessionActivity(jsonlPath: string): void {
    try {
      const stats = fs.statSync(jsonlPath);
      const agent = Array.from(this.agents.values()).find((a) => a.jsonlFile === jsonlPath);

      if (!agent) return;

      const now = Date.now();
      const timeSinceModified = now - stats.mtimeMs;

      // Check if session became inactive
      if (
        timeSinceModified > INACTIVE_THRESHOLD_MS &&
        agent.lastActivity < now - INACTIVE_THRESHOLD_MS
      ) {
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
    // Pattern: -Users-adrianzabica-Desktop-{repo}--worktrees-{branch}
    // Result: "{repo}/{branch}" or just "{repo}"

    const parts = hash.split('-').filter((p) => p);

    // Find "Desktop" to locate the start of repo name
    const desktopIdx = parts.findIndex((p) => p === 'Desktop');
    if (desktopIdx === -1) {
      // Fallback to last part
      return parts[parts.length - 1] || hash;
    }

    // Everything after Desktop
    const afterDesktop = parts.slice(desktopIdx + 1);

    // Check for worktree separator (e.g., ['alven', 'estate', 'agent', 'worktrees', 'feat', 'x'])
    const worktreeIdx = afterDesktop.findIndex((p) => p === 'worktrees' || p === 'worktree');

    if (worktreeIdx === -1) {
      // No worktree - just return repo name
      return afterDesktop.join('-');
    }

    // Has worktree - format as repo/branch
    const repoName = afterDesktop.slice(0, worktreeIdx).join('-');
    const branchName = afterDesktop.slice(worktreeIdx + 1).join('-');

    return branchName ? `${repoName}/${branchName}` : repoName;
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

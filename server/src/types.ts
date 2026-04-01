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

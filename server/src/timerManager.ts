import { PERMISSION_TIMER_DELAY_MS, WAITING_TIMER_DELAY_MS, EXEMPT_TOOLS } from './constants.js';
import type { AgentState } from './types.js';

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

    // Only flag if there are still active non-exempt tools (parent or sub-agent)
    let hasNonExempt = false;
    for (const toolId of agent.activeToolIds) {
      const toolName = agent.activeToolNames.get(toolId);
      if (!EXEMPT_TOOLS.has(toolName || '')) {
        hasNonExempt = true;
        break;
      }
    }

    // Check sub-agent tools for non-exempt tools
    for (const [, subToolNames] of agent.activeSubagentToolNames) {
      for (const [, toolName] of subToolNames) {
        if (!EXEMPT_TOOLS.has(toolName)) {
          hasNonExempt = true;
          break;
        }
      }
    }

    if (hasNonExempt) {
      agent.permissionSent = true;
      broadcast({ type: 'agentStatus', id: agentId, status: 'permission' });
    }
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

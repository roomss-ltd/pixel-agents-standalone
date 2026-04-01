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

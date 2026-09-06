use serde::Deserialize;
use std::collections::{BTreeMap, HashMap};
use std::time::{SystemTime, UNIX_EPOCH};
use zellij_tile::prelude::InputMode;

pub fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// How long a "Done" status lingers before clearing (seconds).
pub const DONE_TIMEOUT: u64 = 30;

/// Sessions whose pane is no longer in the manifest are removed after this
/// many seconds of silence. Catches Codex (no SessionEnd) and force-killed
/// Claude panes. Generous enough to survive transient PaneUpdate gaps.
pub const GHOST_TIMEOUT: u64 = 60;

/// How long a manually dismissed pane_id stays blocked from re-creation.
/// 30 min handles the "stuck Init from a process I can't find" case without
/// permanently consuming pane_ids the user may reuse later.
pub const DISMISS_BLOCK_SECS: u64 = 30 * 60;

/// Timer tick interval (seconds).
pub const TIMER_INTERVAL: f64 = 5.0;
pub const DEVIN_POLL_INTERVAL: u64 = 15;

#[derive(Debug, Clone, PartialEq)]
pub enum Activity {
    Init,
    Thinking,
    Tool(String),
    Waiting,
    Done,
    Idle,
}

#[derive(Debug, Clone)]
pub struct SessionInfo {
    pub session_id: String,
    pub run_id: String,
    pub agent_kind: String,
    pub agent_title: Option<String>,
    pub pane_id: u32,
    pub activity: Activity,
    pub last_event_ts: u64,
    /// Last tool name used — carried across Tool→Thinking transitions.
    pub last_tool_name: Option<String>,
    /// Working directory of the agent, from the Claude/Codex hook's
    /// `cwd` field. Surfaced in the status file so the AgentTAB overlay
    /// can open the worktree in Finder / an editor.
    pub cwd: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct HookPayload {
    pub pane_id: u32,
    pub session_id: Option<String>,
    pub run_id: Option<String>,
    pub hook_event: String,
    pub tool_name: Option<String>,
    pub agent_kind: Option<String>,
    /// Agent working directory — forwarded by the hook scripts from the
    /// Claude/Codex hook JSON's `cwd` field.
    pub cwd: Option<String>,
    /// Keeps status output attached to the right session after a hot reload.
    pub zellij_session_name: Option<String>,
}

#[derive(Default)]
pub struct PluginState {
    /// pane_id → session info
    pub sessions: BTreeMap<u32, SessionInfo>,
    /// pane_id → tab_index (lightweight — no tab name cloning)
    pub pane_to_tab: HashMap<u32, usize>,
    /// stable tab id → user-owned name without our working marker
    pub tab_base_names: HashMap<usize, String>,
    /// Cached tab list from Zellij
    pub tabs: Vec<zellij_tile::prelude::TabInfo>,
    /// Cached pane manifest
    pub pane_manifest: Option<zellij_tile::prelude::PaneManifest>,
    /// Currently active tab index (for detecting tab switches)
    pub active_tab_index: Option<usize>,
    /// Tracked tab count for structural change detection
    pub known_tab_count: usize,
    /// Tracked pane count for structural change detection
    pub known_pane_count: usize,
    /// Suppresses marker updates while the user is editing a tab or pane name.
    pub input_mode: InputMode,
    /// Zellij session name — used for status file naming
    pub zellij_session_name: String,
    /// Monotonic in-memory counter used to disambiguate agent runs that start
    /// in the same pane and second.
    pub run_seq: u64,
    /// pane_id → unix timestamp when block expires. Set by the "Dismiss" pipe
    /// event from the overlay; entries are cleaned in cleanup_stale_sessions.
    pub dismissed_until: HashMap<u32, u64>,
    pub last_devin_poll: u64,
    pub devin_poll_in_flight: bool,
}

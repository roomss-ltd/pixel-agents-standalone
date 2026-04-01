use serde::Deserialize;
use std::collections::{BTreeMap, HashMap};
use std::time::{SystemTime, UNIX_EPOCH};

pub fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// How long a "Done" status lingers before clearing (seconds).
pub const DONE_TIMEOUT: u64 = 30;

/// How long before a session with no events is considered stale (seconds).
pub const STALE_TIMEOUT: u64 = 60;

/// Timer tick interval (seconds).
pub const TIMER_INTERVAL: f64 = 1.0;

/// Known status icons — used to strip our own suffixes when detecting base names.
pub const STATUS_ICONS: &[&str] = &["\u{26A1}", "\u{2699}", "\u{23F3}", "\u{2713}"];
// ⚡, ⚙, ⏳, ✓

#[derive(Debug, Clone, PartialEq)]
pub enum Activity {
    Init,
    Thinking,
    Tool(String),
    Waiting,
    Done,
    Idle,
}

impl Activity {
    /// Priority for display (higher = takes precedence).
    pub fn priority(&self) -> u8 {
        match self {
            Activity::Idle => 0,
            Activity::Init => 1,
            Activity::Done => 2,
            Activity::Thinking => 3,
            Activity::Tool(_) => 4,
            Activity::Waiting => 5,
        }
    }

    pub fn icon(&self) -> Option<&'static str> {
        match self {
            Activity::Thinking => Some("\u{26A1}"),  // ⚡
            Activity::Tool(_) => Some("\u{2699}"),   // ⚙
            Activity::Waiting => Some("\u{23F3}"),   // ⏳
            Activity::Done => Some("\u{2713}"),      // ✓
            _ => None,
        }
    }
}

#[derive(Debug, Clone)]
pub struct SessionInfo {
    pub session_id: String,
    pub pane_id: u32,
    pub activity: Activity,
    pub last_event_ts: u64,
}

#[derive(Debug, Deserialize)]
pub struct HookPayload {
    pub pane_id: u32,
    pub session_id: Option<String>,
    pub hook_event: String,
    pub tool_name: Option<String>,
}

#[derive(Default)]
pub struct PluginState {
    /// pane_id → session info
    pub sessions: BTreeMap<u32, SessionInfo>,
    /// pane_id → (tab_index, tab_name)
    pub pane_to_tab: HashMap<u32, (usize, String)>,
    /// tab_index → original name without status icons
    pub tab_base_names: HashMap<usize, String>,
    /// Cached tab list from Zellij
    pub tabs: Vec<zellij_tile::prelude::TabInfo>,
    /// Cached pane manifest
    pub pane_manifest: Option<zellij_tile::prelude::PaneManifest>,
}

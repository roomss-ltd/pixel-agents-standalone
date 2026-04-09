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

/// Timer tick interval (seconds).
pub const TIMER_INTERVAL: f64 = 5.0;

/// Known status icons — used to strip our own suffixes when detecting base names.
pub const STATUS_ICONS: &[&str] = &["\u{25CF}", "\u{26A1}", "\u{23F8}", "\u{2713}"];
// ●, ⚡, ⏸, ✓

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
            Activity::Thinking => Some("\u{25CF}"),  // ●
            Activity::Tool(_) => Some("\u{26A1}"),   // ⚡
            Activity::Waiting => Some("\u{23F8}"),   // ⏸
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
    /// Last tool name used — carried across Tool→Thinking transitions.
    pub last_tool_name: Option<String>,
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
    /// pane_id → tab_index (lightweight — no tab name cloning)
    pub pane_to_tab: HashMap<u32, usize>,
    /// tab_index → original name without status icons
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
    /// position → Zellij internal tab key.
    /// Workaround for Zellij bug: rename_tab() uses BTreeMap keys (internal indices)
    /// instead of visual positions. We extract keys from auto-named tabs ("Tab #N").
    pub tab_internal_keys: HashMap<usize, usize>,
    /// Current input mode — suppress renames during RenameTab/RenamePane
    pub input_mode: InputMode,
    /// Zellij session name — used for status file naming
    pub zellij_session_name: String,
}

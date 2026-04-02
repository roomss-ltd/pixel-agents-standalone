# Claude Tab Status — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a background Zellij WASM plugin that appends Claude Code session status icons to tab names, driven by Claude Code hooks.

**Architecture:** Claude Code hooks fire a bash script that pipes JSON events into a background Zellij WASM plugin. The plugin maps pane IDs to tabs and renames tabs to include unicode status icons. zjstatus renders the updated names with zero modifications.

**Tech Stack:** Rust (wasm32-wasip1 target), zellij-tile 0.43.1, serde/serde_json, bash + jq for hook script.

---

### Task 0: Project scaffolding

**Files:**
- Create: `claude-tab-status/Cargo.toml`
- Create: `claude-tab-status/.cargo/config.toml`
- Create: `claude-tab-status/src/main.rs` (minimal stub)

**Step 1: Add the wasm32-wasip1 target**

Run: `rustup target add wasm32-wasip1`
Expected: "installed" or "already installed"

**Step 2: Create project directory**

Run: `mkdir -p /Users/cr1g/Projects/own/pixel-agents-standalone/claude-tab-status/{src,.cargo,scripts}`

**Step 3: Create `.cargo/config.toml`**

Create `claude-tab-status/.cargo/config.toml`:
```toml
[build]
target = "wasm32-wasip1"
```

**Step 4: Create `Cargo.toml`**

Create `claude-tab-status/Cargo.toml`:
```toml
[package]
name = "claude-tab-status"
version = "0.1.0"
edition = "2021"

[dependencies]
zellij-tile = "0.43.1"
serde = { version = "1", features = ["derive"] }
serde_json = "1"

[profile.release]
opt-level = "s"
lto = true
```

**Step 5: Create minimal `src/main.rs` that compiles**

Create `claude-tab-status/src/main.rs`:
```rust
use zellij_tile::prelude::*;

#[derive(Default)]
struct State;

register_plugin!(State);

impl ZellijPlugin for State {
    fn load(&mut self, _configuration: std::collections::BTreeMap<String, String>) {}
    fn update(&mut self, _event: Event) -> bool { false }
    fn render(&mut self, _rows: usize, _cols: usize) {}
}
```

**Step 6: Verify it compiles**

Run: `cd /Users/cr1g/Projects/own/pixel-agents-standalone/claude-tab-status && cargo build --release`
Expected: Compiles successfully, produces `target/wasm32-wasip1/release/claude_tab_status.wasm`

**Step 7: Commit**

```bash
git add claude-tab-status/
git commit -m "feat: scaffold claude-tab-status Zellij WASM plugin"
```

---

### Task 1: State module — data structures

**Files:**
- Create: `claude-tab-status/src/state.rs`
- Modify: `claude-tab-status/src/main.rs` (add `mod state`)

**Step 1: Create `src/state.rs` with all data types**

Create `claude-tab-status/src/state.rs`:
```rust
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
```

**Step 2: Add `mod state` to `main.rs`**

Update `claude-tab-status/src/main.rs` — add `mod state;` after the use statement:
```rust
use zellij_tile::prelude::*;

mod state;

#[derive(Default)]
struct State;

register_plugin!(State);

impl ZellijPlugin for State {
    fn load(&mut self, _configuration: std::collections::BTreeMap<String, String>) {}
    fn update(&mut self, _event: Event) -> bool { false }
    fn render(&mut self, _rows: usize, _cols: usize) {}
}
```

**Step 3: Verify it compiles**

Run: `cd /Users/cr1g/Projects/own/pixel-agents-standalone/claude-tab-status && cargo build --release`
Expected: Compiles successfully.

**Step 4: Commit**

```bash
git add claude-tab-status/src/state.rs claude-tab-status/src/main.rs
git commit -m "feat: add state module with Activity enum, SessionInfo, HookPayload"
```

---

### Task 2: Tab manager — pane-to-tab mapping and rename logic

**Files:**
- Create: `claude-tab-status/src/tab_manager.rs`
- Modify: `claude-tab-status/src/main.rs` (add `mod tab_manager`)

**Step 1: Create `src/tab_manager.rs`**

Create `claude-tab-status/src/tab_manager.rs`:
```rust
use crate::state::{PluginState, STATUS_ICONS};
use zellij_tile::prelude::*;

/// Rebuild the pane_id → (tab_index, tab_name) mapping from current tabs + pane manifest.
pub fn rebuild_pane_map(state: &mut PluginState) {
    state.pane_to_tab.clear();

    let manifest = match &state.pane_manifest {
        Some(m) => m,
        None => return,
    };

    for tab in &state.tabs {
        let tab_index = tab.position;
        let tab_name = &tab.name;

        // Capture base name (strip any status icon suffix we may have added).
        let base = strip_status_suffix(tab_name);
        state.tab_base_names.insert(tab_index, base);

        // Map all panes in this tab to the tab.
        // PaneManifest.panes is keyed by tab_index.
        if let Some(panes) = manifest.panes.get(&tab_index) {
            for pane in panes {
                if !pane.is_plugin {
                    state.pane_to_tab.insert(
                        pane.id,
                        (tab_index, tab_name.clone()),
                    );
                }
            }
        }
    }
}

/// Strip any trailing status icon we may have appended.
fn strip_status_suffix(name: &str) -> String {
    let trimmed = name.trim_end();
    for icon in STATUS_ICONS {
        if let Some(base) = trimmed.strip_suffix(icon) {
            return base.trim_end().to_string();
        }
    }
    trimmed.to_string()
}

/// Determine the highest-priority icon for a given tab and rename it.
pub fn update_tab_name(state: &PluginState, tab_index: usize) {
    let base = match state.tab_base_names.get(&tab_index) {
        Some(b) => b,
        None => return,
    };

    // Find the highest-priority activity among all sessions in this tab.
    let best_activity = state
        .sessions
        .values()
        .filter(|s| {
            state
                .pane_to_tab
                .get(&s.pane_id)
                .map(|(idx, _)| *idx == tab_index)
                .unwrap_or(false)
        })
        .max_by_key(|s| s.activity.priority());

    let new_name = match best_activity.and_then(|s| s.activity.icon()) {
        Some(icon) => format!("{} {}", base, icon),
        None => base.clone(),
    };

    rename_tab(tab_index as u32, &new_name);
}

/// Update all tabs that have sessions.
pub fn update_all_tab_names(state: &PluginState) {
    let tab_indices: Vec<usize> = state.tab_base_names.keys().copied().collect();
    for tab_index in tab_indices {
        update_tab_name(state, tab_index);
    }
}
```

**Step 2: Add `mod tab_manager` to `main.rs`**

Add `mod tab_manager;` after `mod state;`.

**Step 3: Verify it compiles**

Run: `cd /Users/cr1g/Projects/own/pixel-agents-standalone/claude-tab-status && cargo build --release`
Expected: Compiles (with unused warnings, that's fine).

**Step 4: Commit**

```bash
git add claude-tab-status/src/tab_manager.rs claude-tab-status/src/main.rs
git commit -m "feat: add tab_manager with pane mapping and tab rename logic"
```

---

### Task 3: Event handler — hook payload processing

**Files:**
- Create: `claude-tab-status/src/event_handler.rs`
- Modify: `claude-tab-status/src/main.rs` (add `mod event_handler`)

**Step 1: Create `src/event_handler.rs`**

Create `claude-tab-status/src/event_handler.rs`:
```rust
use crate::state::{unix_now, Activity, HookPayload, PluginState, SessionInfo};
use crate::tab_manager;

pub fn handle_hook_event(state: &mut PluginState, payload: HookPayload) {
    let event = payload.hook_event.as_str();

    // SessionEnd → remove session, restore tab name.
    if event == "SessionEnd" {
        if let Some(session) = state.sessions.remove(&payload.pane_id) {
            if let Some((tab_index, _)) = state.pane_to_tab.get(&session.pane_id) {
                tab_manager::update_tab_name(state, *tab_index);
            }
        }
        return;
    }

    let activity = match event {
        "SessionStart" => Activity::Init,
        "UserPromptSubmit" => Activity::Thinking,
        "PreToolUse" => Activity::Tool(payload.tool_name.clone().unwrap_or_default()),
        "PostToolUse" | "PostToolUseFailure" => Activity::Thinking,
        "PermissionRequest" => Activity::Waiting,
        "Stop" => Activity::Done,
        "SubagentStop" => Activity::Done,
        _ => Activity::Idle,
    };

    let session = state
        .sessions
        .entry(payload.pane_id)
        .or_insert_with(|| SessionInfo {
            session_id: payload.session_id.clone().unwrap_or_default(),
            pane_id: payload.pane_id,
            activity: Activity::Init,
            last_event_ts: 0,
        });

    session.activity = activity;
    session.last_event_ts = unix_now();
    if let Some(sid) = &payload.session_id {
        session.session_id = sid.clone();
    }

    // Update the tab name for the pane that changed.
    if let Some((tab_index, _)) = state.pane_to_tab.get(&payload.pane_id) {
        tab_manager::update_tab_name(state, *tab_index);
    }
}

/// Clean up stale sessions. Returns true if any state changed.
pub fn cleanup_stale_sessions(state: &mut PluginState) -> bool {
    let now = unix_now();
    let mut changed = false;
    let mut to_remove: Vec<u32> = Vec::new();

    for (pane_id, session) in state.sessions.iter_mut() {
        let elapsed = now.saturating_sub(session.last_event_ts);
        match session.activity {
            Activity::Done => {
                if elapsed >= crate::state::DONE_TIMEOUT {
                    session.activity = Activity::Idle;
                    changed = true;
                }
            }
            Activity::Idle => {
                if elapsed >= crate::state::STALE_TIMEOUT {
                    to_remove.push(*pane_id);
                    changed = true;
                }
            }
            _ => {}
        }
    }

    for pane_id in to_remove {
        state.sessions.remove(&pane_id);
    }

    changed
}
```

**Step 2: Add `mod event_handler` to `main.rs`**

Add `mod event_handler;` after `mod tab_manager;`.

**Step 3: Verify it compiles**

Run: `cd /Users/cr1g/Projects/own/pixel-agents-standalone/claude-tab-status && cargo build --release`
Expected: Compiles successfully.

**Step 4: Commit**

```bash
git add claude-tab-status/src/event_handler.rs claude-tab-status/src/main.rs
git commit -m "feat: add event_handler for hook payload processing and stale cleanup"
```

---

### Task 4: Wire everything together in `main.rs`

**Files:**
- Modify: `claude-tab-status/src/main.rs` (full rewrite)

**Step 1: Rewrite `main.rs` with full plugin implementation**

Replace `claude-tab-status/src/main.rs` with:
```rust
use std::collections::BTreeMap;
use zellij_tile::prelude::*;

mod event_handler;
mod state;
mod tab_manager;

use state::{HookPayload, PluginState, TIMER_INTERVAL};

register_plugin!(PluginState);

impl ZellijPlugin for PluginState {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
            PermissionType::ReadCliPipes,
        ]);
        subscribe(&[
            EventType::TabUpdate,
            EventType::PaneUpdate,
            EventType::Timer,
            EventType::PermissionRequestResult,
        ]);
        set_timeout(TIMER_INTERVAL);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::TabUpdate(tabs) => {
                self.tabs = tabs;
                tab_manager::rebuild_pane_map(self);
                tab_manager::update_all_tab_names(self);
                false // no rendering needed — we're invisible
            }
            Event::PaneUpdate(manifest) => {
                self.pane_manifest = Some(manifest);
                tab_manager::rebuild_pane_map(self);
                tab_manager::update_all_tab_names(self);
                false
            }
            Event::Timer(_) => {
                let changed = event_handler::cleanup_stale_sessions(self);
                if changed {
                    tab_manager::update_all_tab_names(self);
                }
                set_timeout(TIMER_INTERVAL);
                false
            }
            Event::PermissionRequestResult(_) => {
                // Permissions granted — re-subscribe now that we have access.
                subscribe(&[
                    EventType::TabUpdate,
                    EventType::PaneUpdate,
                    EventType::Timer,
                ]);
                false
            }
            _ => false,
        }
    }

    fn pipe(&mut self, pipe_message: PipeMessage) -> bool {
        if pipe_message.name.as_str() != "claude-tab-status" {
            return false;
        }

        let payload_str = match pipe_message.payload {
            Some(ref s) => s,
            None => return false,
        };

        let payload: HookPayload = match serde_json::from_str(payload_str) {
            Ok(p) => p,
            Err(_) => return false,
        };

        event_handler::handle_hook_event(self, payload);
        false
    }

    fn render(&mut self, _rows: usize, _cols: usize) {
        // This plugin is invisible — no rendering.
    }
}
```

**Step 2: Verify it compiles**

Run: `cd /Users/cr1g/Projects/own/pixel-agents-standalone/claude-tab-status && cargo build --release`
Expected: Compiles successfully.

**Step 3: Verify WASM file exists**

Run: `ls -lh /Users/cr1g/Projects/own/pixel-agents-standalone/claude-tab-status/target/wasm32-wasip1/release/claude_tab_status.wasm`
Expected: File exists, size roughly 1-3 MB.

**Step 4: Commit**

```bash
git add claude-tab-status/src/main.rs
git commit -m "feat: wire up ZellijPlugin with pipe handling, tab updates, and timer cleanup"
```

---

### Task 5: Hook script

**Files:**
- Create: `claude-tab-status/scripts/claude-zj-hook.sh`

**Step 1: Create the hook script**

Create `claude-tab-status/scripts/claude-zj-hook.sh`:
```bash
#!/usr/bin/env bash
# claude-zj-hook.sh — Claude Code hook → zellij pipe bridge
# Forwards hook events to the claude-tab-status Zellij plugin.

# Exit silently if not running inside Zellij
[ -z "$ZELLIJ_SESSION_NAME" ] && exit 0
[ -z "$ZELLIJ_PANE_ID" ] && exit 0

# Read hook JSON from stdin
INPUT=$(cat)

# Extract fields with jq (required dependency)
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

[ -z "$HOOK_EVENT" ] && exit 0

# Build compact JSON payload
PAYLOAD=$(jq -nc \
  --arg pane_id "$ZELLIJ_PANE_ID" \
  --arg session_id "$SESSION_ID" \
  --arg hook_event "$HOOK_EVENT" \
  --arg tool_name "$TOOL_NAME" \
  '{
    pane_id: ($pane_id | tonumber),
    session_id: (if $session_id == "" then null else $session_id end),
    hook_event: $hook_event,
    tool_name: (if $tool_name == "" then null else $tool_name end)
  }')

# Send to plugin via zellij pipe
zellij pipe --name "claude-tab-status" -- "$PAYLOAD"
```

**Step 2: Make it executable**

Run: `chmod +x /Users/cr1g/Projects/own/pixel-agents-standalone/claude-tab-status/scripts/claude-zj-hook.sh`

**Step 3: Commit**

```bash
git add claude-tab-status/scripts/claude-zj-hook.sh
git commit -m "feat: add hook bridge script for Claude Code → zellij pipe"
```

---

### Task 6: Install script

**Files:**
- Create: `claude-tab-status/install.sh`

**Step 1: Create the install script**

Create `claude-tab-status/install.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

PLUGIN_DIR="$HOME/.config/zellij/plugins"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$PLUGIN_DIR/claude-zj-hook.sh"

echo "=== claude-tab-status installer ==="

# 1. Build the WASM plugin
echo "[1/4] Building WASM plugin..."
cd "$SCRIPT_DIR"
cargo build --release
WASM_FILE="$SCRIPT_DIR/target/wasm32-wasip1/release/claude_tab_status.wasm"
if [ ! -f "$WASM_FILE" ]; then
    echo "ERROR: Build failed — WASM file not found."
    exit 1
fi

# 2. Copy artifacts
echo "[2/4] Installing to $PLUGIN_DIR..."
mkdir -p "$PLUGIN_DIR"
cp "$WASM_FILE" "$PLUGIN_DIR/claude_tab_status.wasm"
cp "$SCRIPT_DIR/scripts/claude-zj-hook.sh" "$HOOK_SCRIPT"
chmod +x "$HOOK_SCRIPT"

# 3. Register hooks in Claude settings
echo "[3/4] Registering Claude Code hooks..."
if [ ! -f "$CLAUDE_SETTINGS" ]; then
    echo "{}" > "$CLAUDE_SETTINGS"
fi

# Use jq to merge hooks — preserves existing hooks
HOOK_EVENTS='["PreToolUse","PostToolUse","UserPromptSubmit","PermissionRequest","Stop","SubagentStop","SessionStart","SessionEnd"]'

UPDATED=$(jq --arg hook_script "$HOOK_SCRIPT" --argjson events "$HOOK_EVENTS" '
  .hooks //= {} |
  reduce ($events[]) as $event (.;
    .hooks[$event] //= [] |
    if (.hooks[$event] | map(select(.hooks[]?.command == $hook_script)) | length) > 0
    then .
    else .hooks[$event] += [{"hooks": [{"type": "command", "command": $hook_script}]}]
    end
  )
' "$CLAUDE_SETTINGS")

echo "$UPDATED" > "$CLAUDE_SETTINGS"

# 4. Print config snippet
echo "[4/4] Done!"
echo ""
echo "Add this to your Zellij config (~/.config/zellij/config.kdl):"
echo ""
echo '  load_plugins {'
echo "      \"file:$PLUGIN_DIR/claude_tab_status.wasm\""
echo '  }'
echo ""
echo "Then restart Zellij. The plugin will ask for permissions on first load — press 'y' to grant."
```

**Step 2: Make it executable**

Run: `chmod +x /Users/cr1g/Projects/own/pixel-agents-standalone/claude-tab-status/install.sh`

**Step 3: Commit**

```bash
git add claude-tab-status/install.sh
git commit -m "feat: add install script for one-command setup"
```

---

### Task 7: Build, install, and smoke test

**Step 1: Run the installer**

Run: `cd /Users/cr1g/Projects/own/pixel-agents-standalone/claude-tab-status && ./install.sh`
Expected: All 4 steps pass, prints Zellij config snippet.

**Step 2: Verify files are in place**

Run: `ls -lh ~/.config/zellij/plugins/claude_tab_status.wasm ~/.config/zellij/plugins/claude-zj-hook.sh`
Expected: Both files present.

**Step 3: Verify Claude hooks are registered**

Run: `jq '.hooks | keys' ~/.claude/settings.json`
Expected: Contains "PreToolUse", "PostToolUse", "UserPromptSubmit", "PermissionRequest", "Stop", "SubagentStop", "SessionStart", "SessionEnd".

**Step 4: Add `load_plugins` to Zellij config**

Manually add the snippet printed by the installer to `~/.config/zellij/config.kdl`. If `load_plugins` already exists, add the line inside it.

**Step 5: Restart Zellij and grant permissions**

Open a new Zellij session. Navigate to the plugin permission prompt and press 'y'.

**Step 6: Smoke test — start Claude Code in a tab**

Open a tab, run `claude`, submit a prompt. Watch for the tab name to change (e.g., `MyTab ⚡` → `MyTab ⚙` → `MyTab ⏳` or `MyTab ✓`).

**Step 7: Final commit**

```bash
git add -A
git commit -m "feat: complete claude-tab-status v0.1.0 — Zellij plugin for Claude Code session status"
```

---

### Troubleshooting notes (for the implementer)

- **`rename_tab` API:** In zellij-tile 0.43.1, the function signature is `rename_tab(tab_index: u32, name: &str)`. The `tab_index` is the `position` field from `TabInfo`, which is 0-indexed.
- **`PipeMessage` not received:** Make sure the hook script sends with `--name "claude-tab-status"` and the plugin checks `pipe_message.name == "claude-tab-status"` in the `pipe()` method.
- **Icons not appearing:** Check that the terminal supports unicode. Run `echo "⚡ ⚙ ⏳ ✓"` in the terminal to verify.
- **Permission prompt not appearing:** The plugin needs `ChangeApplicationState` permission to rename tabs. If not granted, the `rename_tab` calls are silently dropped.
- **`load_plugins` not working:** Requires Zellij 0.40.0+. User has 0.43.1 so this is fine.

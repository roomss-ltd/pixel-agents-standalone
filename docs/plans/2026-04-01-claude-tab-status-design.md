# Claude Tab Status — Zellij Plugin Design

## Problem

We run many Claude Code sessions across Zellij tabs and need at-a-glance status for each session — without replacing or modifying zjstatus, which already handles the status bar.

## Decision: Hooks over file-watching

The pixel-agents project tracks state by polling `.jsonl` transcript files in `~/.claude/projects/`. Zellaude uses Claude Code's hook API to receive events in real-time via `zellij pipe`.

**Hooks win on every axis:**

| Criterion | File-watching (pixel-agents) | Hooks (zellaude-style) |
|-----------|------------------------------|------------------------|
| Latency | 250ms polling worst-case | Instant (synchronous) |
| API stability | Internal JSONL format (undocumented) | Official hook API |
| Efficiency | Continuous filesystem scanning | Zero CPU when idle |
| Pane mapping | No concept of which terminal owns a session | `$ZELLIJ_PANE_ID` for free |
| Reliability | Partial reads, race conditions possible | Events arrive in order |
| Dependencies | Node.js server process | None (bash + jq) |

The only thing lost: full tool input arguments (e.g., "Reading file X" vs just "Read"). Not worth the architectural cost.

## Solution: Background WASM plugin + tab renaming

A lightweight Zellij WASM plugin runs in the background (via `load_plugins`). It receives Claude Code hook events through `zellij pipe` and appends unicode status icons to Zellij tab names. zjstatus renders `{name}` which now includes the icon — zero zjstatus modifications needed.

### Data flow

```
Claude Code event (e.g., PreToolUse)
    |
Claude Code hook (configured in ~/.claude/settings.json)
    |
Hook bash script (~30 lines, thin bridge)
    |
zellij pipe --name "claude-tab-status" --payload "$PAYLOAD"
    |
Background WASM plugin receives PipeMessage
    |
Plugin updates internal state (pane_id -> Activity)
    |
Plugin maps pane_id -> tab_index via Zellij's TabUpdate/PaneUpdate events
    |
Plugin calls rename_tab(tab_index, "{base_name} {icon}")
    |
zjstatus sees TabUpdate with new name, renders it with its own formatting
```

### Status icons

| Activity | Icon | Triggered by hook |
|----------|------|-------------------|
| Thinking | `⚡` | `UserPromptSubmit` |
| Tool running | `⚙` | `PreToolUse` |
| Waiting for permission | `⏳` | `PermissionRequest` |
| Done | `✓` | `Stop` |
| Idle (no session) | *(no icon)* | `SessionEnd` or timeout |

Priority when multiple Claude sessions share a tab:
`⏳` > `⚙` > `⚡` > `✓` > none

## Components

### 1. Hook script (`claude-zj-hook.sh`)

Bash script registered in `~/.claude/settings.json`. Reads hook JSON from stdin, extracts fields with `jq`, builds compact payload, sends via `zellij pipe`. Exits silently if not in Zellij (`$ZELLIJ_SESSION_NAME` unset).

Registered for: `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `PermissionRequest`, `Stop`, `SubagentStop`, `SessionStart`, `SessionEnd`.

### 2. WASM Plugin (Rust, ~400 lines)

**State:**
```rust
struct State {
    sessions: BTreeMap<u32, SessionInfo>,       // pane_id -> session
    pane_to_tab: HashMap<u32, (usize, String)>, // pane_id -> (tab_index, name)
    tab_base_names: HashMap<usize, String>,     // tab_index -> original name
    tabs: Vec<TabInfo>,
}

struct SessionInfo {
    session_id: String,
    pane_id: u32,
    activity: Activity,
    last_event_ts: u64,
}

enum Activity {
    Init,
    Thinking,
    Tool(String),
    Waiting,
    Done,
    Idle,
}
```

**Event handling:**
- `TabUpdate` / `PaneUpdate` — rebuild pane-to-tab mapping, capture base names
- `PipeMessage` — parse hook payload, update activity, rename tab
- `Timer` (1s) — clean up Done sessions after 30s, remove stale sessions after 60s

**Tab rename logic:**
```rust
fn update_tab_name(&self, tab_index: usize) {
    let base = &self.tab_base_names[&tab_index];
    match self.highest_priority_icon_for_tab(tab_index) {
        Some(icon) => rename_tab(tab_index, format!("{base} {icon}")),
        None => rename_tab(tab_index, base.clone()),
    }
}
```

### 3. Installer (`install.sh`)

One-command setup:
1. Builds or downloads `.wasm` to `~/.config/zellij/plugins/`
2. Copies hook script to `~/.config/zellij/plugins/`
3. Merges hook entries into `~/.claude/settings.json`
4. Prints `load_plugins` snippet to add to Zellij config

## Edge cases

- **User renames tab manually:** `TabUpdate` detected; base name updated (filtered to not capture our own icon suffix).
- **Claude crashes without `SessionEnd`:** Timer removes sessions with no event for 60s.
- **Tab closed:** `TabUpdate` arrives with fewer tabs; stale sessions cleaned up.
- **Multiple Zellij sessions:** Each loads its own plugin instance. `$ZELLIJ_PANE_ID` scopes events.

## Project structure

```
claude-tab-status/
├── Cargo.toml
├── .cargo/
│   └── config.toml              # wasm32-wasi target
├── src/
│   ├── main.rs                   # ZellijPlugin impl, event dispatch
│   ├── state.rs                   # State, SessionInfo, Activity
│   ├── event_handler.rs           # Hook payload -> state transitions
│   └── tab_manager.rs            # pane->tab mapping, rename logic
├── scripts/
│   └── claude-zj-hook.sh
└── install.sh
```

## Build

```bash
cargo build --release --target wasm32-wasip1
cp target/wasm32-wasip1/release/claude_tab_status.wasm ~/.config/zellij/plugins/
```

## Zellij config (one line added)

```kdl
load_plugins {
    "file:~/.config/zellij/plugins/claude_tab_status.wasm"
}
```

## Intentionally excluded (YAGNI)

- Desktop notifications
- Settings UI / config file
- Multi-instance sync between Zellij sessions
- Click handling (zjstatus handles tab clicks)
- Elapsed time display

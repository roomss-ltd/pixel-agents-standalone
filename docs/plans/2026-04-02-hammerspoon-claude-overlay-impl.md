# Hammerspoon Claude Status Overlay — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a macOS-level floating overlay (via Hammerspoon) that shows real-time status of all Claude Code sessions across Zellij tabs.

**Architecture:** The Zellij plugin gains a `status_writer` module that serializes session state to `/tmp/claude-tab-status/{session}.json` via `run_command`. A Hammerspoon Lua module watches that directory and renders a toggleable canvas overlay pinned to the top-right corner.

**Tech Stack:** Rust/WASM (Zellij plugin), Lua (Hammerspoon), JSON (interchange format)

**Design doc:** `docs/plans/2026-04-02-hammerspoon-claude-overlay-design.md`

---

### Task 1: Add `status_writer` Module to Plugin

**Files:**
- Create: `claude-tab-status/src/status_writer.rs`
- Modify: `claude-tab-status/src/main.rs:1-8` (add mod + use)
- Modify: `claude-tab-status/src/state.rs:76-96` (add field)

**Step 1: Add `zellij_session_name` to `PluginState`**

In `claude-tab-status/src/state.rs`, add a new field to `PluginState`:

```rust
#[derive(Default)]
pub struct PluginState {
    // ... all existing fields stay unchanged ...
    /// Zellij session name — used for status file naming
    pub zellij_session_name: String,
}
```

Note: `String` defaults to `""` which is fine — we'll populate it from ModeUpdate.

**Step 2: Capture session name from ModeUpdate**

In `claude-tab-status/src/main.rs`, inside the `Event::ModeUpdate` arm (line 75-86), add after line 80 (`self.input_mode = mode_info.mode;`):

```rust
if let Some(name) = mode_info.session_name {
    self.zellij_session_name = name;
}
```

**Step 3: Create `status_writer.rs`**

Create `claude-tab-status/src/status_writer.rs`:

```rust
use std::collections::BTreeMap;
use zellij_tile::prelude::run_command;

use crate::state::{unix_now, Activity, PluginState};

/// Write aggregated session status to /tmp/claude-tab-status/{session}.json.
/// Uses run_command to execute a bash write-then-mv for atomicity.
pub fn write_status_file(state: &PluginState) {
    let session_name = if state.zellij_session_name.is_empty() {
        "default"
    } else {
        &state.zellij_session_name
    };

    let json = build_status_json(state);
    let dir = "/tmp/claude-tab-status";
    let tmp_path = format!("{}/{}.tmp", dir, session_name);
    let final_path = format!("{}/{}.json", dir, session_name);

    let script = format!(
        "mkdir -p {} && printf '%s' '{}' > {} && mv {} {}",
        dir,
        json.replace('\'', "'\"'\"'"),
        tmp_path,
        tmp_path,
        final_path,
    );

    run_command(&["bash", "-c", &script], BTreeMap::new());
}

fn build_status_json(state: &PluginState) -> String {
    let now = unix_now();
    let mut sessions_json: Vec<String> = Vec::new();
    let mut count_active: u32 = 0;
    let mut count_waiting: u32 = 0;
    let mut count_done: u32 = 0;

    for session in state.sessions.values() {
        // Resolve tab name for this session.
        let tab_name = state
            .pane_to_tab
            .get(&session.pane_id)
            .and_then(|idx| state.tab_base_names.get(idx))
            .map(|s| s.as_str())
            .unwrap_or("unknown");

        let (icon, detail, activity_str) = match &session.activity {
            Activity::Thinking => {
                count_active += 1;
                ("\u{25CF}", String::new(), "Thinking")
            }
            Activity::Tool(name) => {
                count_active += 1;
                ("\u{26A1}", name.clone(), "Tool")
            }
            Activity::Waiting => {
                count_waiting += 1;
                ("\u{23F8}", String::new(), "Waiting")
            }
            Activity::Done => {
                count_done += 1;
                let elapsed = now.saturating_sub(session.last_event_ts);
                let detail = format_elapsed(elapsed);
                ("\u{2713}", detail, "Done")
            }
            Activity::Init => {
                count_active += 1;
                ("\u{25CB}", String::new(), "Init")
            }
            Activity::Idle => continue, // Don't include idle sessions in output
        };

        let detail_json = if detail.is_empty() {
            "null".to_string()
        } else {
            format!("\"{}\"", detail)
        };

        sessions_json.push(format!(
            "{{\"tab_name\":\"{}\",\"icon\":\"{}\",\"detail\":{},\"activity\":\"{}\"}}",
            escape_json_string(tab_name),
            icon,
            detail_json,
            activity_str,
        ));
    }

    format!(
        "{{\"sessions\":[{}],\"counts\":{{\"active\":{},\"waiting\":{},\"done\":{}}},\"updated_at\":{}}}",
        sessions_json.join(","),
        count_active,
        count_waiting,
        count_done,
        now,
    )
}

fn format_elapsed(secs: u64) -> String {
    if secs < 60 {
        format!("{}s ago", secs)
    } else if secs < 3600 {
        format!("{}m ago", secs / 60)
    } else {
        format!("{}h ago", secs / 3600)
    }
}

fn escape_json_string(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
}
```

**Step 4: Register the module in `main.rs`**

Add `mod status_writer;` after line 6 (`mod tab_manager;`) in `main.rs`.

**Step 5: Add `RunCommands` permission**

In `main.rs` line 14-17, add to `request_permission`:

```rust
request_permission(&[
    PermissionType::ReadApplicationState,
    PermissionType::ChangeApplicationState,
    PermissionType::RunCommands,
]);
```

**Step 6: Build and verify compilation**

Run: `cd claude-tab-status && cargo build --release --target wasm32-wasip1`
Expected: clean compile, no errors.

**Step 7: Commit**

```bash
git add claude-tab-status/src/status_writer.rs claude-tab-status/src/main.rs claude-tab-status/src/state.rs
git commit -m "feat: add status_writer module for Hammerspoon overlay data"
```

---

### Task 2: Wire Up Write Triggers in Plugin

**Files:**
- Modify: `claude-tab-status/src/event_handler.rs:4-54` (add write calls on activity change)
- Modify: `claude-tab-status/src/main.rs:88-93` (add write call on timer)

**Step 1: Add write trigger on activity transition in `handle_hook_event`**

In `claude-tab-status/src/event_handler.rs`, add `use crate::status_writer;` at the top (after line 2).

Then modify `handle_hook_event` to track whether the activity actually changed. Replace lines 28-42 with:

```rust
    let session = state
        .sessions
        .entry(payload.pane_id)
        .or_insert_with(|| SessionInfo {
            session_id: payload.session_id.clone().unwrap_or_default(),
            pane_id: payload.pane_id,
            activity: Activity::Init,
            last_event_ts: 0,
        });

    let activity_changed = session.activity != activity;
    session.activity = activity;
    session.last_event_ts = unix_now();
    if let Some(sid) = &payload.session_id {
        session.session_id = sid.clone();
    }
```

Note: `Activity` already derives `PartialEq`, so the comparison works. For `Tool(name)`, this means a change from `Tool("Bash")` to `Tool("Read")` is detected — good.

Then after line 53 (the closing `}` of the tab name update block), add:

```rust
    // Write status file on activity transitions (real-time updates).
    if activity_changed {
        status_writer::write_status_file(state);
    }
```

Also add a write trigger in the `SessionEnd` branch. After line 13 (the closing `}` of the SessionEnd block, before `return;`), add:

```rust
        status_writer::write_status_file(state);
```

**Step 2: Add write trigger on timer**

In `claude-tab-status/src/main.rs`, replace the Timer arm (lines 88-93) with:

```rust
            Event::Timer(_) => {
                if event_handler::cleanup_stale_sessions(self) {
                    tab_manager::update_all_tab_names(self);
                }
                // Always write status file on timer — keeps relative times fresh.
                status_writer::write_status_file(self);
                set_timeout(TIMER_INTERVAL);
                false
            }
```

**Step 3: Build and verify**

Run: `cd claude-tab-status && cargo build --release --target wasm32-wasip1`
Expected: clean compile.

**Step 4: Manual smoke test**

1. Run `bash claude-tab-status/install.sh` to install the updated plugin.
2. Restart Zellij. Grant the new `RunCommands` permission when prompted.
3. Open a Claude Code session in a tab.
4. Check: `cat /tmp/claude-tab-status/*.json | python3 -m json.tool`
5. Verify JSON contains the session with correct tab name, icon, and activity.

**Step 5: Commit**

```bash
git add claude-tab-status/src/event_handler.rs claude-tab-status/src/main.rs
git commit -m "feat: wire status file writes on activity transitions and timer"
```

---

### Task 3: Create Hammerspoon Claude Status Module

**Files:**
- Create: `claude-tab-status/hammerspoon/claude-status.lua`

This is the complete Hammerspoon module. It will be symlinked to `~/.hammerspoon/` during install.

**Step 1: Create the module**

Create `claude-tab-status/hammerspoon/claude-status.lua`:

```lua
-- claude-status.lua — macOS overlay for Claude Code session status
-- Reads JSON from /tmp/claude-tab-status/*.json, renders a floating canvas.

local M = {}

-- Config
local STATUS_DIR = "/tmp/claude-tab-status"
local STALE_THRESHOLD = 120 -- seconds
local OFFSET_X = 10
local OFFSET_Y = 10
local PILL_WIDTH = 210
local EXPANDED_WIDTH = 290
local ROW_HEIGHT = 22
local HEADER_HEIGHT = 28
local FONT_SIZE = 13
local FONT = { name = "Menlo", size = FONT_SIZE }
local FONT_SMALL = { name = "Menlo", size = 11 }
local BG_COLOR = { red = 0.10, green = 0.10, blue = 0.18, alpha = 0.88 }
local TEXT_COLOR = { red = 1, green = 1, blue = 1, alpha = 0.95 }
local MUTED_COLOR = { red = 1, green = 1, blue = 1, alpha = 0.45 }
local SEPARATOR_COLOR = { red = 1, green = 1, blue = 1, alpha = 0.15 }
local CORNER_RADIUS = 8

-- State
local canvas = nil
local pathwatcher = nil
local visible = true
local expanded = false
local sessions = {}
local counts = { active = 0, waiting = 0, done = 0 }

-- Icon colors for the expanded view
local ICON_COLORS = {
    ["\u{25CF}"] = { red = 0.40, green = 0.70, blue = 1.0, alpha = 1 },  -- ● blue
    ["\u{26A1}"] = { red = 1.0,  green = 0.80, blue = 0.20, alpha = 1 }, -- ⚡ yellow
    ["\u{23F8}"] = { red = 1.0,  green = 0.50, blue = 0.30, alpha = 1 }, -- ⏸ orange
    ["\u{2713}"] = { red = 0.40, green = 0.85, blue = 0.45, alpha = 1 }, -- ✓ green
    ["\u{25CB}"] = { red = 0.60, green = 0.60, blue = 0.60, alpha = 1 }, -- ○ gray (Init)
}

---------------------------------------------------------------------------
-- Data loading
---------------------------------------------------------------------------

local function loadSessions()
    sessions = {}
    counts = { active = 0, waiting = 0, done = 0 }

    local now = os.time()

    -- Read all JSON files in the status directory
    local iter, dir = pcall(require("hs.fs").dir, STATUS_DIR)
    if not iter then return end

    for file in dir do
        if file:match("%.json$") then
            local path = STATUS_DIR .. "/" .. file
            local data = hs.json.read(path)
            if data and data.updated_at then
                local age = now - data.updated_at
                if age <= STALE_THRESHOLD and data.sessions then
                    for _, s in ipairs(data.sessions) do
                        table.insert(sessions, s)
                    end
                    -- Use the pre-computed counts from the plugin
                    counts.active = counts.active + (data.counts and data.counts.active or 0)
                    counts.waiting = counts.waiting + (data.counts and data.counts.waiting or 0)
                    counts.done = counts.done + (data.counts and data.counts.done or 0)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Canvas rendering
---------------------------------------------------------------------------

local function screenTopRight()
    local screen = hs.screen.mainScreen():frame()
    return screen.x + screen.w, screen.y
end

local function buildSummaryText()
    local parts = {}
    if counts.active > 0 then
        table.insert(parts, "\u{25CF} " .. counts.active)
    end
    if counts.waiting > 0 then
        table.insert(parts, "\u{23F8} " .. counts.waiting)
    end
    if counts.done > 0 then
        table.insert(parts, "\u{2713} " .. counts.done)
    end
    if #parts == 0 then
        return "0 active"
    end
    return table.concat(parts, "  ")
end

local function redraw()
    if not canvas then return end

    -- Determine dimensions
    local width = expanded and EXPANDED_WIDTH or PILL_WIDTH
    local height = HEADER_HEIGHT
    if expanded and #sessions > 0 then
        height = HEADER_HEIGHT + 1 + (#sessions * ROW_HEIGHT) + 6
    end

    -- Position: top-right corner
    local rx, ry = screenTopRight()
    canvas:frame({
        x = rx - width - OFFSET_X,
        y = ry + OFFSET_Y,
        w = width,
        h = height,
    })

    -- Clear and rebuild elements
    while canvas:elementCount() > 0 do
        canvas:removeElement(1)
    end

    -- Background
    canvas:appendElements({
        type = "rectangle",
        frame = { x = 0, y = 0, w = width, h = height },
        fillColor = BG_COLOR,
        roundedRectRadii = { xRadius = CORNER_RADIUS, yRadius = CORNER_RADIUS },
        strokeWidth = 0,
    })

    -- Summary text
    local summaryText = buildSummaryText()
    local summaryColor = (#sessions == 0) and MUTED_COLOR or TEXT_COLOR
    canvas:appendElements({
        type = "text",
        frame = { x = 12, y = 4, w = width - 24, h = HEADER_HEIGHT },
        text = hs.styledtext.new(summaryText, {
            font = FONT,
            color = summaryColor,
        }),
    })

    -- Expanded: separator + session rows
    if expanded and #sessions > 0 then
        local sep_y = HEADER_HEIGHT
        canvas:appendElements({
            type = "rectangle",
            frame = { x = 8, y = sep_y, w = width - 16, h = 1 },
            fillColor = SEPARATOR_COLOR,
            strokeWidth = 0,
        })

        for i, s in ipairs(sessions) do
            local row_y = sep_y + 4 + ((i - 1) * ROW_HEIGHT)

            -- Tab name (left, truncated)
            local name = s.tab_name or "?"
            if #name > 22 then
                name = name:sub(1, 20) .. "\u{2026}"
            end
            canvas:appendElements({
                type = "text",
                frame = { x = 12, y = row_y, w = width - 100, h = ROW_HEIGHT },
                text = hs.styledtext.new(name, {
                    font = FONT_SMALL,
                    color = TEXT_COLOR,
                }),
            })

            -- Icon + detail (right)
            local icon = s.icon or ""
            local detail = s.detail or ""
            local right_text = icon
            if detail ~= "" and detail ~= hs.json.encode(nil) then
                right_text = icon .. " " .. detail
            end
            local icon_color = ICON_COLORS[icon] or TEXT_COLOR
            canvas:appendElements({
                type = "text",
                frame = { x = width - 100, y = row_y, w = 88, h = ROW_HEIGHT },
                text = hs.styledtext.new(right_text, {
                    font = FONT_SMALL,
                    color = icon_color,
                    paragraphStyle = { alignment = "right" },
                }),
            })
        end
    end

    if visible then
        canvas:show()
    else
        canvas:hide()
    end
end

---------------------------------------------------------------------------
-- Event handlers
---------------------------------------------------------------------------

local function onFileChange(paths, flagTables)
    loadSessions()
    redraw()
end

local function onClick()
    expanded = not expanded
    loadSessions()
    redraw()
end

local function toggleVisibility()
    visible = not visible
    if visible then
        loadSessions()
        redraw()
        canvas:show()
    else
        canvas:hide()
    end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function M.start()
    -- Ensure status dir exists
    os.execute("mkdir -p " .. STATUS_DIR)

    -- Create canvas
    local rx, ry = screenTopRight()
    canvas = hs.canvas.new({
        x = rx - PILL_WIDTH - OFFSET_X,
        y = ry + OFFSET_Y,
        w = PILL_WIDTH,
        h = HEADER_HEIGHT,
    })
    canvas:level(hs.canvas.windowLevels.floating)
    canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
    canvas:mouseCallback(function(c, msg)
        if msg == "mouseUp" then onClick() end
    end)

    -- Load initial data and draw
    loadSessions()
    redraw()

    -- Watch for file changes (FSEvents — no polling)
    pathwatcher = hs.pathwatcher.new(STATUS_DIR, onFileChange)
    pathwatcher:start()

    -- Bind hotkey: Ctrl+Option+C
    hs.hotkey.bind({ "ctrl", "alt" }, "c", toggleVisibility)
end

function M.stop()
    if pathwatcher then pathwatcher:stop() end
    if canvas then canvas:delete() end
    canvas = nil
    pathwatcher = nil
end

-- Auto-start
M.start()

return M
```

**Step 2: Commit**

```bash
git add claude-tab-status/hammerspoon/claude-status.lua
git commit -m "feat: add Hammerspoon overlay module for Claude session status"
```

---

### Task 4: Update Install Script and Wire Everything

**Files:**
- Modify: `claude-tab-status/install.sh` (add Hammerspoon install step)

**Step 1: Add Hammerspoon install step to `install.sh`**

After the existing step 4, add a step 5 that symlinks the Lua module and patches `init.lua`:

```bash
# 5. Install Hammerspoon module
echo "[5/5] Installing Hammerspoon module..."
HS_DIR="$HOME/.hammerspoon"
HS_MODULE="$HS_DIR/claude-status.lua"
SOURCE_MODULE="$SCRIPT_DIR/hammerspoon/claude-status.lua"

if [ -d "$HS_DIR" ]; then
    # Symlink so updates propagate automatically
    ln -sf "$SOURCE_MODULE" "$HS_MODULE"

    # Add require to init.lua if not present
    if ! grep -q 'claude-status' "$HS_DIR/init.lua" 2>/dev/null; then
        echo 'require("claude-status")' >> "$HS_DIR/init.lua"
    fi

    echo "  Hammerspoon module installed. Reload Hammerspoon to activate."
    echo "  Toggle visibility: Ctrl+Option+C"
else
    echo "  Hammerspoon not found at $HS_DIR — skipping overlay install."
    echo "  Install Hammerspoon and re-run to enable the macOS overlay."
fi
```

Also update the step numbers in the echo messages (change `[1/4]` through `[4/4]` to `[1/5]` through `[4/5]`).

**Step 2: Build, install, and test end-to-end**

```bash
cd claude-tab-status
cargo build --release --target wasm32-wasip1
bash install.sh
```

Then:
1. Restart Zellij. Grant `RunCommands` permission when prompted.
2. Reload Hammerspoon (click menubar icon → Reload Config).
3. Open a Claude Code session in a Zellij tab.
4. Verify: the overlay appears in the top-right showing "● 1" or similar.
5. Click the overlay — verify it expands showing the tab name and status.
6. Press `Ctrl+Option+C` — verify it hides. Press again — verify it shows.
7. Stop the Claude session — verify the overlay updates to show "✓ 1".
8. Wait 30s — verify Done clears to "0 active".

**Step 3: Commit**

```bash
git add claude-tab-status/install.sh
git commit -m "feat: add Hammerspoon overlay to install script"
```

---

### Task 5: Final Review and Cleanup

**Step 1: Run code review**

Use `superpowers:requesting-code-review` to verify:
- Plugin compiles cleanly
- No performance regressions (write only on activity transitions + timer)
- JSON escaping handles all edge cases (tab names with quotes, backslashes)
- Atomic file write (tmp + mv) is correct
- Hammerspoon module handles missing files, empty dir, malformed JSON gracefully
- Pathwatcher doesn't fire excessively

**Step 2: Verify no impact on core functionality**

The status file writer is a pure side-channel. Verify:
- Tab icons still work correctly (rename_tab flow unchanged)
- Performance is still good (no extra work in the hot path unless activity changed)
- Plugin works normally if `/tmp/claude-tab-status/` is not writable (run_command fails silently)

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: Hammerspoon overlay for Claude session status

Adds a macOS-level floating overlay showing real-time status of all
Claude Code sessions across Zellij tabs. The plugin writes aggregated
JSON to /tmp/claude-tab-status/ and Hammerspoon renders a toggleable
canvas using FSEvents file watching."
```

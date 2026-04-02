# Hammerspoon Claude Status Overlay

**Date:** 2026-04-02
**Status:** Approved

## Overview

A macOS-level floating overlay that shows the status of all Claude Code sessions across Zellij tabs. Pinned to the top-right corner, always visible, real-time updates.

## Data Pipeline

```
Claude hook event
  -> claude-zj-hook.sh -> zellij pipe (existing, unchanged)
  -> Plugin processes event, updates internal state
  -> Plugin writes /tmp/claude-tab-status/{zellij_session}.json
      (on every activity transition + every timer tick)
  -> Hammerspoon pathwatcher detects change -> redraws overlay
```

### Status File Format

One file per Zellij session. Plugin pre-computes everything — Hammerspoon is a dumb renderer.

```json
{
  "sessions": [
    {"tab_name": "Unified Agent", "icon": "\u26a1", "detail": "Bash", "activity": "Tool"},
    {"tab_name": "Tab #5", "icon": "\u25cf", "detail": null, "activity": "Thinking"},
    {"tab_name": "Buildium", "icon": "\u23f8", "detail": null, "activity": "Waiting"},
    {"tab_name": "Hello Kitty", "icon": "\u2713", "detail": "2m ago", "activity": "Done"}
  ],
  "counts": {"active": 3, "waiting": 1, "done": 1},
  "updated_at": 1743600002
}
```

### Write Triggers

- **Activity transition** in `handle_hook_event` — only when activity actually changed (real-time, ~2-5 writes/sec during active use)
- **Timer tick** every 5s — keeps "2m ago" strings fresh even when nothing changes
- **SessionEnd** — immediate removal from the file

### Write Method

`run_command(&["bash", "-c", "..."])` with write-to-temp-then-`mv` for atomicity. If Hammerspoon isn't running or the file fails to write, zero impact on core tab status functionality.

### Stale File Handling

- `SessionEnd` hook removes the session from the file
- Timer-based cleanup removes Idle sessions after 120s
- Hammerspoon ignores files with `updated_at` older than 120s
- Files are in `/tmp/` — cleaned on reboot

## UI Design

### Summary Pill (Default State)

Pinned top-right, semi-transparent dark background with rounded corners. Compact.

```
 \u25cf 2  \u23f8 1  \u2713 3
```

- Icon + count for each active state
- States with 0 count are hidden
- When no sessions: `0 active` in muted text

### Expanded View (On Click)

Pill grows downward into a compact list:

```
 \u25cf 2  \u23f8 1  \u2713 3
\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
 Unified Agent    \u26a1 Bash
 Tab #5           \u25cf
 Buildium         \u23f8
 Hello Kitty      \u2713  2m ago
```

- Each row: tab name (left-aligned, truncated if long) + status icon + context
- Only tabs with Claude sessions appear

### Interactions

- **Click overlay** -> toggle summary/expanded
- **Ctrl+Option+C** -> toggle entire overlay visible/hidden
- Overlay always present (even with 0 sessions)

### Styling

- Background: `#1a1a2e` at 85% opacity
- Text: white, monospace font
- Status icons in natural colors
- Width: ~200px summary, ~280px expanded
- Anchored top-right: grows downward and leftward

## Plugin Changes

### New Permission

Add `PermissionType::RunCommands` to `request_permission` in `load()`. Zellij will prompt once on first load.

### New State Fields

```rust
pub struct PluginState {
    // ... existing fields ...
    /// Zellij session name for status file naming
    pub zellij_session_name: Option<String>,
}
```

Captured from `ModeUpdate` event (already subscribed).

### Status File Writer

New function `write_status_file(state: &PluginState)`:

1. Build JSON from `state.sessions`, `state.pane_to_tab`, `state.tab_base_names`
2. Compute relative time strings for Done sessions
3. Aggregate counts by activity type
4. Serialize to JSON string
5. Call `run_command` to write atomically:
   ```
   bash -c 'echo '{json}' > /tmp/claude-tab-status/.tmp && mv /tmp/claude-tab-status/.tmp /tmp/claude-tab-status/{session}.json'
   ```

### Write Call Sites

- `handle_hook_event` — after updating session, only if activity changed
- Timer handler — every tick (after cleanup)
- SessionEnd — after removing session

### What Stays Unchanged

The existing pipe -> plugin -> rename_tab flow is untouched. The status file is a read-only side channel with zero impact on core functionality.

## Hammerspoon Module

### File Structure

Single file: `~/.hammerspoon/claude-status.lua`, loaded via `require("claude-status")` in `init.lua`.

### Components

- `hs.canvas` — draws the overlay (background + text elements)
- `hs.pathwatcher` — watches `/tmp/claude-tab-status/` for changes (uses macOS FSEvents, no polling)
- `hs.hotkey` — binds Ctrl+Option+C to toggle visibility
- Click handler on canvas — toggles summary/expanded

### Lifecycle

1. **On load:** create canvas, position top-right (10px offset), start pathwatcher, bind hotkey
2. **On file change:** read all `*.json` files, filter stale (>120s), merge sessions, aggregate counts, redraw
3. **On click:** flip `expanded` boolean, resize canvas height, redraw with per-tab rows
4. **On hotkey:** flip `visible` boolean, show/hide canvas

### Canvas Sizing

- Summary mode: ~200x30px
- Expanded mode: 280x(30 + 24 * session_count)px
- Anchored from top-right corner

### Multi-Session Support

Multiple Zellij sessions each write their own JSON file. Hammerspoon reads all files and merges into one unified view.

## Edge Cases

| Case | Handling |
|------|----------|
| Multiple Zellij sessions | Scoped filenames, Hammerspoon merges all |
| File write during read | Atomic write-then-mv |
| Zellij crash (stale file) | `updated_at` check, 120s expiry |
| No Claude sessions | Show "0 active" in muted text |
| Long tab names | Truncate with ellipsis at ~20 chars |
| Permission prompt | `RunCommands` permission requested on first load |
| Hammerspoon not running | Zero impact on plugin — file writes are fire-and-forget |
| Plugin not loaded yet | Hammerspoon shows "0 active" (no files to read) |

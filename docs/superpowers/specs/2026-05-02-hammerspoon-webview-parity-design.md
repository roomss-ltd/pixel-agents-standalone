# Hammerspoon Webview Parity Design

**Goal:** Rebuild the Hammerspoon webview renderer so it visually and behaviorally matches the accepted canvas widget before adding webview-only improvements.

**Decision:** Keep Hammerspoon as the runtime and continue the `hs.webview` port. Do not move to Tauri for this phase.

**Canvas Baseline:** `claude-tab-status/hammerspoon/archive/claude-status-canvas-baseline-2026-05-02.lua` is the preserved visual and behavioral reference. The live canvas renderer remains available through `claude-status-loader.lua` with `hs.settings.set("claudeStatus.renderer", "canvas")`.

## Recommendation

Use Hammerspoon webview, not Tauri, for the next phase.

Tauri becomes attractive if this needs to become a distributable macOS app with app packaging, autostart, native settings, update flow, and teammate installation. That is not the immediate problem. The immediate problem is that the current webview renderer is not organized enough to reach canvas parity safely.

Hammerspoon webview keeps the useful parts already working:

- Existing `/tmp/claude-tab-status/*.json` contract.
- Existing Hammerspoon ownership of sounds, reminders, hotkeys, settings, Spaces behavior, and local files.
- Existing canvas fallback.
- Faster iteration on HTML/CSS without adding app packaging and native window lifecycle work.

## Current Webview Problems

- The current webview is a rough renderer, not a visual port of the canvas widget.
- Header text is too verbose and loses the compact icon/count treatment from canvas.
- Row hierarchy is weaker: tab badge, title, status, active/done grouping, and divider need to match the canvas baseline first.
- The fixed webview frame does not respond cleanly to dynamic data.
- Dragging depends on JS bridge messages and currently feels fragile.
- Dismiss controls are too visually loud.
- HTML, CSS, JS, state shaping, bridge handling, and Hammerspoon lifecycle all live in one large Lua file.

## Target Architecture

Keep one public Hammerspoon module:

- `claude-tab-status/hammerspoon/claude-status-webview.lua`

Split renderer internals into focused helpers:

- `claude-tab-status/hammerspoon/webview/html.lua`: HTML shell and script loader string.
- `claude-tab-status/hammerspoon/webview/styles.lua`: CSS sections for shell, header, rows, settings, and effects.
- `claude-tab-status/hammerspoon/webview/state.lua`: turns raw sessions/settings/effects into renderable sections.
- `claude-tab-status/hammerspoon/webview/bridge.lua`: validates JS action messages and maps them to Lua-owned actions.

The split is a webview-only refactor. Do not change Rust/Zellij plugin code unless the JSON contract proves insufficient.

## UI Sections

### Header

The header has two formats:

- Collapsed: compact status summary matching the canvas baseline, with active and done counts as icon/count pairs plus an expand button.
- Expanded: same summary plus controls that are only useful when inspecting the widget, such as pin/settings.

### Rows

Rows render from normalized sections:

- Active/waiting rows first.
- Divider when active/waiting and completed rows are both present.
- Completed rows after the divider.

Each row should match the canvas baseline first:

- Left tab badge.
- Session title.
- Right-side status text.
- Strong active color for active/waiting.
- Green completed treatment.
- 10 second high-contrast completion highlight.
- Waiting pulse when enabled.

Dismiss buttons should be secondary and should not dominate the row by default.

### Settings

Settings are a separate section, not mixed into row rendering. The section should use the existing Hammerspoon-owned settings:

- Sounds.
- Waiting reminders.
- Waiting pulse.
- Finish flash.

### Effects

Effects remain driven by Lua state:

- 1.5 second full widget flash.
- 10 second completion highlight.
- Waiting pulse class.
- Repeating waiting reminder sound.

CSS should only render effect state. Timing decisions stay in Lua.

## Dynamic Sizing

The webview should compute frame height from renderable content:

- Header height is fixed.
- Row height is fixed.
- Divider height is fixed and only counted when present.
- Settings height is counted only when expanded.
- Height is clamped to a sane maximum so it does not cover the screen.

The widget should preserve the same bottom-right anchor behavior as canvas unless the user drags it. After drag, the saved custom position should remain the anchor.

## Interaction Rules

- `ctrl+alt+c`: toggle visibility.
- `ctrl+alt+r`: reset status JSON files.
- Hover expands when not pinned.
- Pin keeps expanded state.
- Drag should work from the shell/header area and should not start from buttons or settings controls.
- JS may request actions, but Lua remains the owner of state changes.

## Testing

Keep source-level tests for:

- Canvas baseline archive exists and remains referenced in docs.
- Webview renderer imports helper modules instead of embedding one large HTML/CSS blob.
- State helper emits header, active rows, completed rows, divider flag, settings items, and effect classes.
- Dynamic frame sizing uses row/settings counts and clamps to a maximum.
- Bridge helper accepts only known action types.
- Loader keeps canvas fallback available.

Manual Hammerspoon smoke testing remains required for:

- Visual parity against the canvas screenshot.
- Dragging.
- Hover expand/collapse.
- Pin behavior.
- Settings persistence after reload.
- Sounds and reminder cadence.
- Spaces behavior.

## First Implementation Pass

Start with structure and parity, not polish:

1. Preserve the canvas baseline.
2. Add tests proving the webview code has section helpers.
3. Extract CSS/HTML/state/bridge helpers.
4. Rebuild header and rows to match the canvas screenshot.
5. Add dynamic frame sizing.
6. Restore interaction confidence: drag, hover, pin, settings, fallback.
7. Only then make visual refinements.

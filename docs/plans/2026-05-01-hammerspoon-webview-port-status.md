# Hammerspoon Webview Port Status

> **Planner note:** This document is the source of truth for porting the Hammerspoon status widget from `hs.canvas` to `hs.webview`. Executor agents must update this file as they complete tasks.

## Goal

Replace the live Hammerspoon canvas renderer with a CSS/HTML `hs.webview` renderer while preserving the existing Zellij/Rust plugin contract and Hammerspoon-owned local behavior.

## Current Recommendation

Do not rewrite the Rust/Zellij plugin. Keep `/tmp/claude-tab-status/*.json` as the data contract. Port only the Hammerspoon presentation layer from manual canvas drawing to webview HTML/CSS/JS.

Implementation now uses a loader entrypoint with webview as the default renderer. Keep the current canvas widget available as a fallback for this iteration.

Default UI decision: webview is the default renderer via `claude-status-loader.lua`.

Canvas fallback: set `claudeStatus.renderer` to `canvas` in `hs.settings`, then reload Hammerspoon.

2026-05-02 update: the first webview pass is not visually accepted. Treat the canvas screenshot/current canvas widget as the visual baseline, preserve it permanently, and rebuild the webview around sectioned helpers before further visual tuning. The parity design lives in `docs/superpowers/specs/2026-05-02-hammerspoon-webview-parity-design.md`.

## Current Files

- `claude-tab-status/hammerspoon/claude-status.lua`: live Hammerspoon canvas widget. Owns data loading, transition detection, sounds, reminders, settings, denylist, drag/pin/dismiss behavior, and canvas rendering.
- `claude-tab-status/hammerspoon/archive/claude-status-canvas-baseline-2026-05-02.lua`: preserved canvas baseline for visual/behavioral reference. Do not delete this file while the webview port is in progress.
- `claude-tab-status/hammerspoon/claude-status-loader.lua`: Hammerspoon entrypoint. Defaults to `claude-status-webview` and can fall back to `claude-status`.
- `claude-tab-status/hammerspoon/completion_flash.test.mjs`: source-level tests for current Hammerspoon behavior.
- `claude-tab-status/hammerspoon/claude-status-webview.lua`: production webview path. Owns real status JSON loading, view-state generation, webview lifecycle, and JS rendering updates.
- `claude-tab-status/hammerspoon/webview/html.lua`: webview HTML shell and JavaScript renderer helper.
- `claude-tab-status/hammerspoon/webview/styles.lua`: webview CSS helper.
- `claude-tab-status/hammerspoon/webview/state.lua`: serializable render-state helper.
- `claude-tab-status/hammerspoon/webview/bridge.lua`: controlled JS action normalization helper.
- `claude-tab-status/hammerspoon/webview_port.test.mjs`: source-level tests for the production webview path.
- `claude-tab-status/hammerspoon/phase_a_structure.test.mjs`: source-level tests for the parity-rebuild structure split and canvas baseline archive.
- `claude-tab-status/hammerspoon/phase_b_rendering.test.mjs`: source-level tests for render sections, dynamic frame sizing, and canvas-parity CSS structure.
- `claude-tab-status/hammerspoon/phase_c_visual_parity.test.mjs`: source-level tests for compact header markup, canvas-parity CSS tokens, subdued dismiss controls, and row hierarchy.
- `claude-tab-status/hammerspoon/phase7_switchover.test.mjs`: source-level tests for default renderer selection, canvas fallback, demo-only marking, and switchover documentation.
- `claude-tab-status/hammerspoon/webview-demo.lua`: isolated proof-of-concept webview mockup. It is only a visual demo, not production code.
- `claude-tab-status/hammerspoon/webview_demo.test.mjs`: source-level tests for the demo.
- `claude-tab-status/src/*.rs`: Rust/Zellij plugin code. Out of scope for the webview port unless audit reveals a missing field in the JSON contract.

## Audit: What Exists Now

### Data And State

- Reads session JSON files from `/tmp/claude-tab-status/*.json`.
- JSON contract is sufficient for the webview port and should not require Rust changes:
  - top level: `sessions`, `counts.active`, `counts.waiting`, `counts.done`, `updated_at`.
  - session rows: `pane_id`, `tab_num`, `tab_name`, `icon`, `detail`, `activity`.
  - activities: `Thinking`, `Tool`, `Waiting`, `Done`, `Init`, `Idle`.
- Drops stale files using `STALE_THRESHOLD`.
- Removes stale JSON files from disk when they exceed `STALE_THRESHOLD`.
- Maintains counts for active, waiting, and done sessions.
- Sorts sessions by tab number.
- Assigns display labels like `3`, `3.1`, `3.2`.
- Splits sessions into active and inactive tiers.
- Active tier is `Thinking`, `Tool`, `Waiting`, and `Init`.
- Inactive tier is `Done` and `Idle`, sorted by elapsed detail where possible.
- Persists dismissed sessions in `~/.hammerspoon/claude-status-denylist.json`.
- Prunes denylist entries after `DENYLIST_TTL`.
- Detects activity transitions using `prevActivities`.
- Tracks transient completion flash state in Lua, keyed by `zj_session:pane_id`.
- Persists settings with `hs.settings` key `claudeStatus.settings`.

### Visual Behavior

- Collapsed pill with counts and spinner.
- Expanded widget with active rows, separator, inactive rows.
- Waiting rows pulse using the waiting color.
- Completion event creates a camera-like widget flash.
- Completion row becomes high-contrast white with inverted text for 10 seconds.
- Done/Idle rows remain visible and counted.
- Settings drawer with toggles.
- Header button toggles the settings drawer.
- Row names and details are truncated in the renderer.
- Widget anchors near the bottom-right of the main screen by default.
- User-dragged position overrides the default anchor until reset.
- These rendering concerns move to HTML/CSS/JS: shell layout, collapsed/expanded views, rows, separator, settings drawer, pulse animation, completion flash animation, text truncation, and compact spacing.

### Interaction Behavior

- Mouse enter expands when not pinned.
- Mouse exit collapses when not pinned.
- Click toggles pin.
- Drag moves widget and stores custom position in memory.
- Long press dismisses a session.
- Dismiss sends a `Dismiss` pipe payload to Zellij when possible.
- Dismiss also rewrites/removes the local JSON file and ignores watcher updates briefly.
- Header settings button expands/collapses settings.
- Settings rows toggle persisted settings.
- Hotkeys:
  - `ctrl+alt+c`: show/hide widget.
  - `ctrl+alt+r`: reset sessions.
- Reset deletes `/tmp/claude-tab-status/*.json`; the plugin rewrites live sessions on the next tick.
- `M.start()` creates the status directory, loads settings, creates the renderer, starts the path watcher, and binds hotkeys.
- `M.stop()` must clean up timers, hotkeys, watchers, renderer windows, drag/event taps, and pending long-press timers.

### Notification Behavior

- Hammerspoon owns sounds.
- Done transition plays `sounds/Glass.wav`.
- Waiting transition plays `Ping`.
- Waiting reminder sound repeats every 30 seconds while input is still needed.
- Sounds, reminders, waiting pulse, and finish flash can be toggled from settings.
- Sound playback honors `SOUND_ENABLED`, `settings.soundsEnabled`, per-kind cooldowns, named sounds, and optional file paths.
- Reminder checks stay in Lua; webview code must not own notification timing.

## Audit: What Needs To Be Added

### Production Webview Renderer

- Create a production webview renderer separate from `webview-demo.lua`.
- Render real sessions, not hardcoded demo rows.
- Preserve collapsed and expanded modes.
- Preserve active/inactive tiers.
- Preserve settings drawer.
- Preserve flash and pulse animations with CSS.
- Preserve row text truncation and compact layout.
- Keep the visual style close to the demo, not the broken canvas toggle rendering.

### Lua To Webview Bridge

- Lua must generate a state payload and send it to JS.
- JS must render from the payload.
- JS setting clicks must call back to Lua.
- JS should not read files or own business logic.
- Lua remains the owner of settings, sounds, reminders, file watching, transition detection, and denylist.

### Lifecycle And Fallback

- Keep canvas implementation available until webview parity is verified.
- Add an explicit switch or separate entrypoint for webview mode.
- Ensure Hammerspoon reload does not create duplicate webviews.
- Ensure `M.stop()` cleans up webview, watchers, timers, hotkeys, and event taps.

### Tests

- Add source-level tests for production webview code.
- Keep existing canvas behavior tests passing until switchover.
- Add tests for bridge strings/actions so future agents do not regress settings callbacks.
- Continue using:
  - `node --test claude-tab-status/hammerspoon/*.test.mjs`
  - `cd claude-tab-status && cargo build`
  - `cd claude-tab-status && cargo test --no-run`

## Porting Strategy

### Phase 1: Audit And Boundaries

Status: Completed.

Tasks:

- [x] Audit `claude-status.lua` and list every non-rendering behavior that must stay in Lua.
- [x] Audit current visual behavior and identify what becomes HTML/CSS/JS.
- [x] Confirm JSON shape produced by `/tmp/claude-tab-status/*.json`.
- [x] Update this document with any missing behavior discovered during audit.

Exit criteria:

- The executor can point to a complete behavior list in this file.
- No implementation changes beyond test scaffolding and documentation.

### Phase 2: Start Over With Production Webview Code

Status: Completed.

Tasks:

- [x] Treat `webview-demo.lua` as reference only. Do not evolve it into production code.
- [x] Create `claude-tab-status/hammerspoon/claude-status-webview.lua`.
- [x] Create `claude-tab-status/hammerspoon/webview_port.test.mjs`.
- [x] Implement webview lifecycle: `start`, `stop`, `toggle`, no duplicate windows on reload.
- [x] Render a static shell from production code.
- [x] Verify tests fail before implementation and pass after implementation.
- [x] Update this document with completed items and any new risks.

Exit criteria:

- A production webview module exists.
- It can be loaded independently from Hammerspoon.
- It does not alter live canvas behavior.

### Phase 3: Real Data Rendering

Status: Completed.

Tasks:

- [x] Move or reuse session loading/counting/partitioning logic without changing the JSON contract.
- [x] Build a `buildViewState()` Lua function that returns a serializable table for the webview.
- [x] Add JS `window.renderStatus(state)` to render rows from state.
- [x] Push updates with `webview:evaluateJavaScript(...)`.
- [x] Preserve empty/hidden behavior.
- [x] Ensure counts and rows match the canvas widget for the same JSON input.
- [x] Update this document.

Exit criteria:

- Webview displays real current sessions.
- File changes update the webview.
- Counts and rows match the canvas widget for the same JSON input.

### Phase 4: Settings And Callbacks

Status: Completed.

Tasks:

- [x] Render settings from Lua-owned settings state.
- [x] Add JS click handlers for settings toggles.
- [x] Bridge JS to Lua with a controlled callback path.
- [x] Persist settings with `hs.settings` using the existing settings key unless audit finds a reason to change it.
- [x] Verify toggles affect sound, waiting reminders, waiting pulse, and finish flash.
- [x] Update this document.

Exit criteria:

- Settings work in webview and persist after Hammerspoon reload.
- Canvas settings behavior remains unaffected until switchover.

### Phase 5: Attention Effects

Status: Completed.

Tasks:

- [x] Port waiting pulse to CSS animation.
- [x] Port completion row highlight to CSS class/state.
- [x] Port widget flash to CSS overlay animation.
- [x] Preserve the current durations:
  - widget flash: 1.5 seconds.
  - completion row high contrast: 10 seconds.
- [x] Ensure sounds remain Lua-owned.
- [x] Ensure `waitingPulse` and `completionFlash` settings control attention visuals.
- [x] Detect active to `Done`/`Idle` transitions in Lua and expose flash/highlight state through `buildViewState()`.
- [x] Update this document.

Exit criteria:

- Waiting and completion attention effects are visibly stronger than passive color changes.
- Existing sound/reminder behavior remains unchanged.

### Phase 6: Window Interaction Parity

Status: Completed. Manual Spaces smoke test pending.

Tasks:

- [x] Preserve hover expand/collapse through controlled JS `expand.set` messages while allowing pin state to override collapse.
- [x] Preserve pin/unpin behavior with an explicit header pin button and Lua-owned `pinned` state.
- [x] Preserve drag repositioning with controlled JS drag messages and Lua-owned `customPos` state.
- [x] Replace long-press/session dismiss with an explicit row dismiss button bridged to Lua.
- [x] Preserve hotkeys:
  - `ctrl+alt+c`: show/hide widget.
  - `ctrl+alt+r`: reset sessions.
- [x] Preserve lifecycle cleanup for webview, pathwatcher, hotkeys, timers, drag/event taps, and duplicate-window prevention.
- [ ] Test behavior across normal desktop Spaces.
- [x] Update this document.

Exit criteria:

- The webview can be used as the daily driver without losing current workflow controls.

### Phase 7: Switchover

Status: Completed. Manual Hammerspoon smoke test pending.

Tasks:

- [x] Add `claude-status-loader.lua` as the single entrypoint with `STATUS_RENDERER = "webview"`.
- [x] Keep canvas fallback available for one iteration through `hs.settings.set("claudeStatus.renderer", "canvas")`.
- [x] Update install/reload instructions in the loader comments.
- [x] Mark `webview-demo.lua` as demo-only.
- [x] Update this document with final status, default decision, fallback instructions, manual smoke checklist, and remaining risks.

Default UI decision: webview is the default renderer.

Canvas fallback: set `claudeStatus.renderer` to `canvas`, reload Hammerspoon, and continue loading `claude-status-loader.lua`.

Hammerspoon load/reload instructions:

```lua
package.path = package.path .. ";/Users/cr1g/Projects/own/pixel-agents-standalone/claude-tab-status/hammerspoon/?.lua"
require("claude-status-loader").start()
```

Current local Hammerspoon wiring:

- `~/.hammerspoon/init.lua` loads `require("claude-status-loader").start()`.
- `~/.hammerspoon/claude-status-loader.lua` symlinks to `claude-tab-status/hammerspoon/claude-status-loader.lua`.
- `~/.hammerspoon/claude-status-webview.lua` symlinks to `claude-tab-status/hammerspoon/claude-status-webview.lua`.
- `~/.hammerspoon/claude-status.lua` still symlinks to the canvas renderer for fallback.

Manual smoke-test checklist:

- [ ] Load webview renderer in Hammerspoon.
- [ ] Confirm widget appears.
- [ ] Confirm hover expand/collapse.
- [ ] Confirm pin/unpin.
- [ ] Confirm settings toggles persist after reload.
- [ ] Confirm waiting pulse.
- [ ] Confirm completion flash/highlight.
- [ ] Confirm dismiss button removes a row.
- [ ] Confirm drag repositioning.
- [ ] Confirm `ctrl+alt+c` show/hide.
- [ ] Confirm `ctrl+alt+r` reset.
- [ ] Confirm behavior on at least two normal desktop Spaces.

Exit criteria:

- Webview is the default Hammerspoon UI.
- Canvas fallback is documented.
- Tests and build verification pass.
- Do not claim full runtime success until manual Hammerspoon smoke testing is complete.

### Phase A: Parity Rebuild Structure

Status: Completed. Visual tuning intentionally not started.

Tasks:

- [x] Add tests proving the canvas baseline archive exists and is documented.
- [x] Add tests proving `claude-status-webview.lua` delegates to helper modules.
- [x] Create helper module structure:
  - `claude-tab-status/hammerspoon/webview/html.lua`
  - `claude-tab-status/hammerspoon/webview/styles.lua`
  - `claude-tab-status/hammerspoon/webview/state.lua`
  - `claude-tab-status/hammerspoon/webview/bridge.lua`
- [x] Move structure first while keeping behavior tests passing.
- [x] Run verification:
  - `node --test claude-tab-status/hammerspoon/*.test.mjs`: 42 passing.
  - `cd claude-tab-status && cargo build`: passed.
  - `cd claude-tab-status && cargo test --no-run`: passed.
- [x] Update this document with files changed, verification, and remaining risks.

Files changed:

- `claude-tab-status/hammerspoon/claude-status-webview.lua`
- `claude-tab-status/hammerspoon/webview/html.lua`
- `claude-tab-status/hammerspoon/webview/styles.lua`
- `claude-tab-status/hammerspoon/webview/state.lua`
- `claude-tab-status/hammerspoon/webview/bridge.lua`
- `claude-tab-status/hammerspoon/webview_port.test.mjs`
- `claude-tab-status/hammerspoon/phase_a_structure.test.mjs`
- `docs/plans/2026-05-01-hammerspoon-webview-port-status.md`

Remaining risks:

- Visual parity work has not started.
- Manual Hammerspoon smoke testing has not been performed.
- The helper split is structural only; later phases still need state section helpers, dynamic sizing, and canvas-parity styling.

### Phase B: Canvas-Parity Rendering Structure

Status: Completed. Pixel-level tuning and manual runtime smoke testing intentionally deferred to Phase C.

Tasks:

- [x] Add failing tests for `webview/state.lua` render sections:
  - `header`
  - `activeRows`
  - `completedRows`
  - `showDivider`
  - `settings`
  - `effects`
- [x] Add failing tests for dynamic frame sizing:
  - fixed header height
  - active row count
  - completed row count
  - divider height only when shown
  - settings height only when expanded
  - max height clamp
- [x] Add failing tests for `webview/styles.lua` canvas-parity sections/classes:
  - header
  - tab badge
  - active row
  - completed row
  - divider
  - completion highlight
  - waiting pulse
  - settings
- [x] Implement minimal state/style/render changes for canvas-parity structure.
- [x] Wire `claude-status-webview.lua` to use state-helper frame sizing before pushing state to JS.
- [x] Keep existing JS bridge behavior working.
- [x] Run verification:
  - `node --test claude-tab-status/hammerspoon/*.test.mjs`: 47 passing.
  - `cd claude-tab-status && cargo build`: passed.
  - `cd claude-tab-status && cargo test --no-run`: passed.
- [x] Update this document with completed tasks, files changed, verification, and remaining risks.

Files changed:

- `claude-tab-status/hammerspoon/claude-status-webview.lua`
- `claude-tab-status/hammerspoon/webview/html.lua`
- `claude-tab-status/hammerspoon/webview/styles.lua`
- `claude-tab-status/hammerspoon/webview/state.lua`
- `claude-tab-status/hammerspoon/webview_port.test.mjs`
- `claude-tab-status/hammerspoon/phase_b_rendering.test.mjs`
- `docs/plans/2026-05-01-hammerspoon-webview-port-status.md`

Remaining risks:

- Runtime visual parity has not been manually checked in Hammerspoon.
- Phase B adds structure and sizing only; Phase C still needs pixel-level visual refinement against the archived canvas baseline.
- Dynamic sizing is source-tested, but Spaces behavior and drag behavior with changing frame sizes still need runtime smoke testing.

### Phase C: First Visual Parity Pass

Status: Completed. Source-level visual parity assertions are green; manual Hammerspoon smoke testing is still required before claiming runtime acceptance.

Tasks:

- [x] Add failing tests proving header markup no longer renders verbose `active 0`, `waiting 0`, or `done 0` labels.
- [x] Add failing tests proving compact active/completed count targets/classes exist in the header.
- [x] Add failing tests proving CSS exposes canvas-parity tokens for panel background, border, radius, row heights, row gap, and badge color treatments.
- [x] Add failing tests proving row, divider, and dismiss-button styling match the subdued canvas hierarchy.
- [x] Confirm RED with the new source-level tests.
- [x] Update `webview/html.lua` so the header uses compact icon/count markup, row titles stay separate from right-side status, and status text carries icon/detail or activity.
- [x] Update `webview/styles.lua` to match the archived canvas baseline more closely:
  - dark translucent panel with visible border and 12px radius.
  - compact centered header counts with active dot and completed check.
  - 30px active rows, 26px completed rows, and 4px row rhythm.
  - blue active/waiting treatment and green completed treatment.
  - subtle dashed divider between active/waiting and completed tiers.
  - dismiss controls hidden by default and revealed on row hover.
  - settings section kept visually quieter than rows.
- [x] Keep `claude-status-webview.lua` lifecycle, bridge, sizing, hotkeys, settings, and loader fallback unchanged.
- [x] Run verification:
  - `node --test claude-tab-status/hammerspoon/*.test.mjs`: 51 passing.
  - `cd claude-tab-status && cargo build`: passed.
  - `cd claude-tab-status && cargo test --no-run`: passed.
- [x] Update this document with completed tasks, files changed, verification, and remaining risks.

Files changed:

- `claude-tab-status/hammerspoon/webview/html.lua`
- `claude-tab-status/hammerspoon/webview/styles.lua`
- `claude-tab-status/hammerspoon/phase_c_visual_parity.test.mjs`
- `docs/plans/2026-05-01-hammerspoon-webview-port-status.md`

Remaining risks:

- Manual Hammerspoon smoke testing has not been performed in this coding session.
- Visual acceptance still depends on a real desktop smoke test against the archived canvas baseline/screenshot.
- Dynamic resize, drag, pin, hover, and Spaces behavior remain source-tested only and may need runtime tuning.

### Phase D: Runtime Smoke Blocker Fix

Status: Accepted. Runtime smoke found one blocking issue; source-level fix was implemented and the user accepted Phase D after manual smoke verification.

Runtime smoke evidence:

- Webview loads.
- Visual parity is much closer to the archived canvas baseline.
- Dragging works.
- Blocking issue: expanded/pinned rows were clipped at the bottom because the Hammerspoon webview frame height did not grow enough for the rendered panel content.
- User post-fix smoke result: dynamic height clipping is fixed for the current dataset; bottom row and panel border are visible; webview is usable enough to move to Phase E.

Fix:

- Added Phase D regression tests for dynamic frame sizing and internal overflow behavior.
- Updated `webview/state.lua` frame sizing to account for:
  - panel top/bottom padding.
  - fixed header height.
  - active row count using 30px rows.
  - completed row count using 26px rows.
  - 4px row gap rhythm.
  - divider height when shown.
  - settings section height when expanded.
  - border/shadow safety allowance.
  - max height clamp.
- Raised the webview max frame clamp from 380px to 700px so the observed 1 active + 14 completed row case no longer clamps below rendered content.
- Updated `webview/styles.lua` so `.widget` and `.rows` use `overflow: visible`; clipping should now be owned by the outer Hammerspoon frame size rather than accidental panel-level CSS overflow.
- Kept Rust/Zellij code, archived canvas baseline, canvas fallback, loader, bridge, hotkeys, settings, and attention effects unchanged.

Files changed:

- `claude-tab-status/hammerspoon/webview/state.lua`
- `claude-tab-status/hammerspoon/webview/styles.lua`
- `claude-tab-status/hammerspoon/phase_b_rendering.test.mjs`
- `claude-tab-status/hammerspoon/phase_d_runtime_smoke.test.mjs`
- `docs/plans/2026-05-01-hammerspoon-webview-port-status.md`

Verification:

- RED confirmed: `node --test claude-tab-status/hammerspoon/*.test.mjs` failed before implementation on the new clipping/overflow assertions.
- GREEN: `node --test claude-tab-status/hammerspoon/*.test.mjs`: 56 passing.
- `cd claude-tab-status && cargo build`: passed.
- `cd claude-tab-status && cargo test --no-run`: passed.

Manual smoke status:

- Post-fix Hammerspoon reload was not performed by the executor because the local CLI reports `can't access Hammerspoon message port Hammerspoon; is it running with the ipc module loaded?`.
- User manually verified webview mode after the fix:
  - bottom row is not cut off.
  - dragging still works.
  - bottom panel border is visible.
- Canvas fallback still needs re-check after Phase E with `hs.settings.set("claudeStatus.renderer", "canvas"); hs.reload()`.

Remaining risks:

- If a session list exceeds the 700px clamp, the outer webview frame will still clip by design; scrolling or a screen-relative clamp may be needed in a later phase.
- User-noted visual refinements remain deferred: rows are a little tall/dense-green, and duplicate `5`/`3` badges suggest decimal display labels may be collapsing.

### Phase E: Final Polish And Acceptance

Status: Implemented and source-verified. Manual Phase E smoke testing is still pending.

Tasks:

- [x] Fix tab badge display identity:
  - `webview/state.lua` now derives `display_label` from canvas-style `_display_num` first, preserving labels like `5.2`, `3.1`, `3.3`, `2.1`, and `2.2`.
  - `webview/html.lua` now falls back through `display_label`, `_display_num`, then `tab_num`.
- [x] Tighten row density:
  - active row token changed from 30px to 28px.
  - completed row token changed from 26px to 24px.
  - row gap changed from 4px to 3px.
  - frame sizing constants were kept aligned with CSS tokens.
- [x] Fix settings sizing ownership:
  - `claude-status-webview.lua` now owns `settingsOpen`.
  - `webview/bridge.lua` accepts only the controlled `settings.toggle` action for drawer open/close.
  - `webview/html.lua` no longer keeps a JS-local `settingsOpen` boolean.
  - `webview/state.lua` reserves settings height only when `settings.open` is true and the widget is expanded.
  - `M.stop()` clears `settingsOpen` during lifecycle cleanup.
- [x] Keep dismiss controls low-emphasis; Phase C hover-revealed styling remains in place.
- [x] Fix top-right control-label defect found during manual smoke:
  - Defect: header rendered visible placeholder text controls (`v` for expand/settings and `p` for pin).
  - `webview/html.lua` now renders separate empty icon buttons with accessible labels/titles for expand/collapse, settings, and pin.
  - Collapsed state shows only the expand chevron; expanded state reveals settings and pin controls.
  - The chevron posts controlled `expand.toggle`; settings opens only from the gear with `settings.toggle`; pin remains limited to `pin.toggle`.
- [x] Fix follow-up top-right icon quality defect found during manual smoke:
  - Defect: CSS-drawn gear/pin controls read as an eye/target and broken tool, and the header controls still felt too loud.
  - Added `webview/icons.lua` as a local inline SVG helper with Lucide-style `chevron-up`, `chevron-down`, `settings`, and `pin` icons using `stroke="currentColor"`.
  - `webview/html.lua` now renders the header controls through the icon helper; no network assets or build step are required.
  - `webview/styles.lua` no longer draws header icons with pseudo-elements; icon buttons are transparent by default, 15-16px SVGs, low opacity for settings/pin until hover, and pinned state gets only a subtle blue accent.
- [x] Preserve canvas fallback through `claude-status-loader.lua`; no Rust/Zellij code or archived canvas baseline changed.

Files changed:

- `claude-tab-status/hammerspoon/claude-status-webview.lua`
- `claude-tab-status/hammerspoon/webview/bridge.lua`
- `claude-tab-status/hammerspoon/webview/html.lua`
- `claude-tab-status/hammerspoon/webview/icons.lua`
- `claude-tab-status/hammerspoon/webview/state.lua`
- `claude-tab-status/hammerspoon/webview/styles.lua`
- `claude-tab-status/hammerspoon/phase_b_rendering.test.mjs`
- `claude-tab-status/hammerspoon/phase_c_visual_parity.test.mjs`
- `claude-tab-status/hammerspoon/phase_d_runtime_smoke.test.mjs`
- `claude-tab-status/hammerspoon/phase_e_polish.test.mjs`
- `claude-tab-status/hammerspoon/webview_port.test.mjs`
- `docs/plans/2026-05-01-hammerspoon-webview-port-status.md`

Verification:

- RED confirmed: `node --test claude-tab-status/hammerspoon/*.test.mjs` failed before implementation on the new Phase E badge, settings ownership, density, visible text control, and local inline SVG icon assertions.
- GREEN: `node --test claude-tab-status/hammerspoon/*.test.mjs`: 62 passing.
- `cd claude-tab-status && cargo build`: passed.
- `cd claude-tab-status && cargo test --no-run`: passed.

Manual Phase E smoke status:

- Executor could not reload Hammerspoon because `hs` reports `can't access Hammerspoon message port Hammerspoon; is it running with the ipc module loaded?`.
- Still needs user/manual smoke:
  - reload Hammerspoon in webview mode.
  - confirm decimal badges render correctly.
  - confirm row density feels closer to canvas.
  - confirm settings open/close changes height correctly.
  - confirm top-right controls render as professional Lucide-style chevron, gear, and pin icons, not `v`/`p` text or CSS-drawn pseudo-icons.
  - confirm collapsed state shows only the expand chevron and expanded state shows gear/pin.
  - confirm dragging still works.
  - confirm canvas fallback works with `hs.settings.set("claudeStatus.renderer", "canvas"); hs.reload()`.

Final recommendation:

- Phase E is superseded by Phase F because manual review found the fixed-size expansion placement model flawed near screen edges.
- Keep canvas fallback available through `claudeStatus.renderer = "canvas"` for this iteration.

### Phase F: Anchor-Aware Placement And Settings Sidecar

Status: Implemented and source-verified. Manual Hammerspoon smoke testing is still pending; Phase F needs user screenshot/runtime review before acceptance.

Problem:

- The webview expanded/collapsed as a fixed frame.
- Near screen edges, expansion could grow in the wrong direction or drift after dragging.
- The settings drawer at the bottom of the main panel made height ownership and placement more fragile.

Tasks completed:

- [x] Added `webview/placement.lua` with helpers for:
  - `frameForWidget(screenFrame, size, placementState, padding)`.
  - `inferAnchor(frame, screenFrame, padding)`.
  - `clampFrame(frame, screenFrame, padding)`.
  - `placePopover(screenFrame, anchorFrame, popoverSize, options)`.
- [x] Changed default placement to top-right.
- [x] Added anchor-preserving frame calculation:
  - top-right grows left/down.
  - top-left grows right/down.
  - bottom-right grows left/up.
  - bottom-left grows right/up.
  - custom middle placement clamps onscreen without snapping to a corner.
- [x] Updated drag end behavior to infer the nearest corner anchor or preserve a custom position.
- [x] Removed settings from the bottom of the main panel height calculation.
- [x] Added a separate settings sidecar webview:
  - created lazily only when expanded and settings are open.
  - placed around the main widget using right, left, below, above preference order.
  - hidden when the main widget is hidden or settings are closed.
  - deleted on stop/reload.
- [x] Replaced the three header controls with a single low-emphasis ellipsis options button.
- [x] Kept pin behavior available in the settings sidecar instead of as a header button.
- [x] Split settings sidecar JavaScript from main widget JavaScript so sidecar interaction does not post drag or hover-collapse actions.
- [x] Fixed collapsed header runtime defect from user screenshot:
  - Cause: the header grid had three columns, but the markup only rendered two children, so counts were placed in the 24px spacer column and the ellipsis overlapped the status counts.
  - Fix: added an explicit left spacer, centered count column, and right ellipsis column.
  - Fix: collapsed ellipsis/header clicks now expand first instead of trying to open settings while collapsed.
  - Fix: drag handling now uses Hammerspoon-compatible mouse events instead of pointer-only events.
- [x] Fixed follow-up drag regression from manual smoke:
  - Cause: drag motion was still owned by webview `mousemove` events and repeated custom-scheme bridge navigation, which is unreliable in Hammerspoon webviews.
  - Fix: JS now posts only `drag.start` on `mousedown`; Lua starts an `hs.eventtap` for `leftMouseDragged`/`leftMouseUp`, reads `hs.mouse.absolutePosition()`, moves the webview frame, infers placement on mouse-up, and stops the tap.
- [x] Fixed follow-up options-button drag conflict from manual smoke:
  - Cause: the main `mousedown` handler ignored all buttons, including the visible ellipsis/options button, so pressing the obvious handle never started drag.
  - Fix: the main header/options area now participates in drag; only labels, inputs, and row dismiss buttons are excluded.
  - Fix: local JS tracks small mouse movement only to suppress the options click after a drag; Lua still owns actual frame movement through `hs.eventtap`.
  - Fix: hover expand/collapse messages are ignored while a drag is active.
- [x] Fixed collapsed options visibility and added bridge diagnostics:
  - Cause: Phase F still displayed the options ellipsis in the collapsed pill, contradicting the accepted collapsed behavior.
  - Fix: `.widget:not(.expanded) .more-toggle` is hidden; collapsed interaction is now the header/pill itself.
  - Added opt-in debug logging with `hs.settings.set("claudeStatus.debug", true)` to trace policy callback URLs, bridge actions, and drag start/move/end checkpoints in Hammerspoon Console.
- [x] Fixed root collapsed hit-area regression from anchor-aware placement:
  - Cause: `webview/state.lua` still computed collapsed frame height from hidden active/completed rows. The Hammerspoon webview frame could be tall and transparent while CSS placed the visible 30px pill inside it, so the painted pill and the native window hit model diverged.
  - Fix: collapsed frame sizing now returns compact pill dimensions before counting rows.
  - Fix: body alignment changed from `place-items: end` to `place-items: start` so painted pixels begin at the native webview frame origin.
- [x] Fixed follow-up stuck collapsed pill regression from manual smoke:
  - Cause: collapsed click/drag still depended on the webview custom-scheme bridge firing first. When Hammerspoon/WebKit did not deliver the bridge navigation, there were no click logs and no state change.
  - Fix: added a Lua-owned native `hs.eventtap` for the collapsed pill frame. Mouse-down inside the native frame now logs before JavaScript, starts drag tracking, and click-without-drag expands the widget.
  - Fix: debug logging still writes to Hammerspoon Console when `hs.settings.set("claudeStatus.debug", true)` is enabled, and now also appends to `/tmp/claude-status-webview-debug.log` so bridge/native event checkpoints can be checked outside the console.
  - Note: the visible side shadow comes from `.widget` CSS `box-shadow` in `webview/styles.lua`; it is not Rust/Zellij output.
- [x] Fixed follow-up collapsed click/data visibility investigation:
  - Cause found in source path: after a native click expands the widget, WebKit can emit an immediate hover-collapse event from the pre-resize frame. That can undo the native click before the expanded panel is usable.
  - Fix: native click expansion now suppresses hover-collapse for 0.6 seconds, while preserving normal hover collapse after that window.
  - Added debug checkpoints around `loadSessions()` and `refreshWebview()` so runtime logs show whether `/tmp/claude-tab-status/*.json` files are read, skipped as stale/unreadable, filtered, and how many rows are rendered.
  - Follow-up: click/drag threshold increased to 8px and mouse-up now logs whether the native interaction was treated as a click or drag.
  - Follow-up: refresh logs now include the native webview frame so runtime review can confirm whether expansion resized the Hammerspoon window.
- [x] Fixed follow-up static `0 / 0` DOM defect from manual logs:
  - Evidence: Lua logs showed `sessions=15` and `completedRows=15`, while the collapsed header still painted static `0 / 0`.
  - Cause: production HTML used JavaScript nullish coalescing (`??`) inside `renderRows()`. Older Hammerspoon/WebKit builds can fail to parse that syntax, preventing the whole script from defining `window.renderStatus()`.
  - Fix: replaced the modern operator with ES5-compatible conditional syntax and added a source test forbidding `??` in production webview JavaScript.
  - Follow-up: removed additional older-WebKit runtime hazards before count rendering: `Object.assign`, `classList.toggle(name, boolean)`, and `dataset` writes. Replaced them with small local helpers and `setAttribute()` calls so `renderStatus()` can update counts on older embedded WebKit.
  - Follow-up: wrapped `evaluateJavaScript()` calls with callbacks and in-page `try/catch` diagnostics. Runtime logs now report `render eval result=missing-renderStatus`, `render eval result=error:<name>:<message>`, or `render eval result=ok active=<n> completed=<n>`.
  - Follow-up: user runtime logs reported `render eval result=missing-renderStatus` after the syntax compatibility pass, proving Lua data loading was correct but the webview document still had no renderer installed.
  - Fix: exported the production renderer JavaScript from `webview/html.lua` and inject it through `evaluateJavaScript()` before each state render, with an install guard to avoid duplicate event listeners. This makes rendering independent of whether Hammerspoon/WebKit executes inline `<script>` tags from `webview:html(...)`.
- [x] Fixed follow-up row-end spacing defect from manual screenshot:
  - Evidence: completed row timestamps had a visible gap before the right edge because every row reserved an invisible dismiss-button column.
  - Fix: removed the visible row dismiss button and the reserved grid column from the production webview renderer/styles. The controlled `row.dismiss` bridge action and Lua denylist/zellij cleanup handler remain available behind the scenes.
- [x] Fixed follow-up bottom-border dark tail from manual screenshot:
  - Evidence: a dark rectangular/shadow-like area remained visible below the rounded panel border.
  - Fix: removed the external drop shadow from the main widget/settings panel and reduced the frame safety allowance from 16px to 6px. The inset border remains, so the panel keeps definition without painting outside the rounded border.
- [x] Preserved canvas fallback; no Rust/Zellij code or archived canvas baseline changed.

Files changed:

- `claude-tab-status/hammerspoon/claude-status-webview.lua`
- `claude-tab-status/hammerspoon/webview/html.lua`
- `claude-tab-status/hammerspoon/webview/icons.lua`
- `claude-tab-status/hammerspoon/webview/placement.lua`
- `claude-tab-status/hammerspoon/webview/state.lua`
- `claude-tab-status/hammerspoon/webview/styles.lua`
- `claude-tab-status/hammerspoon/phase_b_rendering.test.mjs`
- `claude-tab-status/hammerspoon/phase_d_runtime_smoke.test.mjs`
- `claude-tab-status/hammerspoon/phase_e_polish.test.mjs`
- `claude-tab-status/hammerspoon/phase_f_placement.test.mjs`
- `claude-tab-status/hammerspoon/webview_port.test.mjs`
- `docs/plans/2026-05-01-hammerspoon-webview-port-status.md`

Verification:

- RED confirmed: `node --test claude-tab-status/hammerspoon/*.test.mjs` failed before implementation on the new Phase F placement helper, anchor behavior, settings sidecar, and single ellipsis header assertions.
- GREEN: `node --test claude-tab-status/hammerspoon/*.test.mjs`: 69 passing.
- Follow-up RED confirmed from collapsed-header screenshot: source tests failed for missing `header-spacer`, collapsed ellipsis expansion, and pointer-only drag handling.
- Follow-up GREEN: `node --test claude-tab-status/hammerspoon/*.test.mjs`: 71 passing.
- Follow-up RED confirmed for drag: source tests failed while motion depended on webview `mousemove`; GREEN after moving drag tracking to Lua `hs.eventtap`.
- Follow-up RED confirmed for options-button drag: source tests failed while `mousedown` excluded all buttons and hover messages could fire during drag; GREEN after allowing header/options drag and suppressing click only after movement.
- Follow-up RED confirmed for collapsed options/debug trace: source tests failed while collapsed options remained visible and debug checkpoints were absent; GREEN after hiding collapsed options and adding opt-in bridge/drag logging.
- Follow-up RED confirmed for collapsed hit-area regression: source tests failed while collapsed frame still reserved hidden row height; GREEN after adding compact collapsed frame sizing and top-left body alignment.
- Follow-up RED confirmed for stuck collapsed interaction: source tests failed while file-backed debug logging and a native collapsed-pill `hs.eventtap` were absent; GREEN after adding both.
- Follow-up RED confirmed for click expand/data diagnostics: source tests failed while immediate hover-collapse suppression and JSON load/render diagnostics were absent; GREEN after adding both.
- Follow-up RED confirmed for click outcome/frame diagnostics: source tests failed while native mouse-up movement result and frame dimensions were absent; GREEN after adding both.
- Follow-up RED confirmed for static `0 / 0` DOM defect: source tests failed while production HTML contained unsupported `??`; GREEN after replacing it with ES5-compatible syntax.
- Follow-up RED confirmed for older-WebKit render hazards: source tests failed while production HTML still used `Object.assign`, `classList.toggle(name, boolean)`, and `dataset`; GREEN after replacing them with compatibility helpers.
- Follow-up RED confirmed for missing eval diagnostics: source tests failed while `evaluateJavaScript()` had no callback/result logging; GREEN after adding wrapped render execution and callback logs.
- Follow-up RED confirmed for `missing-renderStatus`: source tests failed while renderer JavaScript was only installed through inline HTML; GREEN after exporting/injecting the renderer script before state rendering.
- Follow-up RED confirmed for row-end spacing: source tests failed while row markup/styles still exposed `.dismiss-button` and reserved a fourth grid column; GREEN after removing the visible button/column while keeping the bridge handler.
- Follow-up RED confirmed for bottom-border tail: source tests failed while the widget still painted an external `0 12px 34px` drop shadow and used a 16px frame safety allowance; GREEN after using inset-only shadow and a 6px safety allowance.
- Follow-up RED confirmed for webview sounds: source tests failed while the webview renderer had settings and transition tracking but no `hs.sound` playback path; GREEN after porting the canvas `Glass` done sound, `Ping` waiting sound, cooldown, and waiting reminder loop into Lua.
- Follow-up RED confirmed for completion-highlight contrast: source tests failed while the webview white completion highlight did not explicitly invert row title text and painted a grey status block; GREEN after matching the canvas behavior with dark title/status text, transparent status, and a subtle dark badge fill.
- Follow-up RED confirmed for runtime `string.format` crash: source tests failed while large JavaScript blobs in `webview/html.lua` still used `%s` with `string.format`; GREEN after switching bridge scheme replacement to a literal `__BRIDGE_SCHEME__` token and `gsub`.
- GREEN: `node --test claude-tab-status/hammerspoon/*.test.mjs`: 94 passing.
- `cd claude-tab-status && cargo build`: passed.
- `cd claude-tab-status && cargo test --no-run`: passed.

## Phase H: Collapsed Event Notifications

Status: source/build complete. Manual Hammerspoon visual smoke testing is pending.

Scope:

- [x] Added collapsed-only notification events without changing the stable header count layout.
- [x] Kept event ownership in Lua:
  - finished events expire after 15 seconds.
  - waiting/input events are sticky while the matching session remains in `Waiting`.
  - events dedupe by session/pane identity and event kind.
  - maximum visible events is three; overflow renders as `+N more`.
- [x] Added a separate `eventWebview` popover instead of resizing the collapsed pill.
- [x] Reused `webview/placement.lua` popover placement so the notification stack chooses available space around the main widget.
- [x] Event placement now prefers vertical space first: below, above, then left, then right. Vertical candidates clamp horizontally into the screen before falling back sideways.
- [x] Event visuals now use the same row language as the main widget: left badge, centered title/subline, right status mark, and a quiet dismiss control that only asserts itself on hover.
- [x] Added controlled `event.focus` and `event.dismiss` bridge actions.
- [x] Event click reuses the existing focus path: activate Ghostty, go to Zellij tab as fallback, then pipe `Focus` with `pane_id`.
- [x] Kept existing finish flash, completion highlight, sounds, and waiting reminders unchanged.
- [x] Preserved canvas fallback; no Rust/Zellij code changed.

Files changed:

- `claude-tab-status/hammerspoon/claude-status-webview.lua`
- `claude-tab-status/hammerspoon/webview/html.lua`
- `claude-tab-status/hammerspoon/webview/styles.lua`
- `claude-tab-status/hammerspoon/webview/state.lua`
- `claude-tab-status/hammerspoon/webview/bridge.lua`
- `claude-tab-status/hammerspoon/phase_h_event_notifications.test.mjs`
- `docs/plans/2026-05-01-hammerspoon-webview-port-status.md`

Verification:

- RED confirmed: `node --test claude-tab-status/hammerspoon/phase_h_event_notifications.test.mjs` failed on all five new assertions before implementation.
- GREEN: `node --test claude-tab-status/hammerspoon/phase_h_event_notifications.test.mjs`: 5 passing.
- GREEN: `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs`: 103 passing.
- Follow-up RED confirmed for event placement priority: source tests failed while event popovers used the default side-first popover order; GREEN after adding ordered popover candidates and event-specific `below`, `above`, `left`, `right` priority.
- Follow-up GREEN: `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs`: 111 passing.
- Follow-up RED confirmed for event visual polish: source tests failed while the toast used a generic icon/copy/dismiss layout; GREEN after narrowing the popover and switching to badge/title/detail/status/dismiss row structure with softer framing.
- Follow-up GREEN: `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs`: 112 passing.
- `cd claude-tab-status && cargo build`: passed.
- `cd claude-tab-status && cargo test --no-run`: passed.

Manual Phase H smoke checklist:

- Collapse the widget and trigger a worker completion; a compact event popover should appear near the pill for about 15 seconds.
- Trigger a waiting/input state; the waiting event should remain visible until the row leaves `Waiting`, the event is dismissed, or it is clicked.
- Click an event; Ghostty/Zellij should focus the corresponding tab/pane using the same row focus path.
- Dismiss an event with its `x`; only that event should disappear.
- Move the widget near screen edges; the event popover should prefer below/above, clamp horizontally when needed, and only then use left/right.
- Expand the widget; the event popover should hide while the full panel is visible.

Manual Phase F smoke status:

- Executor has not reloaded Hammerspoon in this environment.
- Required manual/user checks:
  - default collapsed widget appears top-right.
  - expand near top-right grows left/down and remains onscreen.
  - collapse returns the header to the same top-right anchor, not lower.
  - drag expanded widget, then collapse/expand again; anchor inference remains sensible.
  - settings opens as a sidecar from the ellipsis.
  - sidecar chooses right/left/below/above based on available space.
  - collapsing or hiding the main widget closes/hides the sidecar.
- dragging still works.
- collapsed click/drag emits native checkpoints in `/tmp/claude-status-webview-debug.log` when `claudeStatus.debug` is enabled.
- debug log should show `loadSessions result sessions=<n> active=<n> waiting=<n> done=<n>` matching `/tmp/claude-tab-status/*.json`.
- waiting/input and completion sounds should play from Hammerspoon Lua when `soundsEnabled` is on; waiting reminder repeats should respect `waitingReminderSound`.
- canvas fallback still works with `hs.settings.set("claudeStatus.renderer", "canvas"); hs.reload()`.

Remaining risks:

- Runtime behavior for the second `hs.webview` sidecar still needs real Hammerspoon validation.
- Runtime behavior for the new collapsed native `hs.eventtap` needs user smoke validation.
- The sidecar may need pixel-level placement tuning after screenshot review.
- Hover-collapse while settings are open is intentionally suppressed so the sidecar can be used; manual review should confirm this feels right.
- Very long session lists can still hit the 700px clamp; scrolling or screen-relative max height may be needed later.

Recommendation:

- Keep webview as default only after Phase F manual smoke passes.
- Keep canvas fallback available through `claudeStatus.renderer = "canvas"`.

## Phase I: Attention Tiers

Status: source/build complete. Manual Hammerspoon visual smoke testing is pending.

Scope:

- [x] Split expanded rows by attention value without changing the `/tmp/claude-tab-status/*.json` contract.
- [x] Kept running rows first:
  - `Thinking`
  - `Tool`
  - `Waiting`
  - `Init`
- [x] Added a one-hour recent-finished tier for `Done`/`Idle` rows whose elapsed `detail` parses to `<= 3600` seconds.
- [x] Added an older-finished tier for `Done`/`Idle` rows older than one hour.
- [x] Collapsed the older-finished tier by default behind a quiet `Show all` control.
- [x] Kept older-tier expanded/collapsed state Lua-owned through a narrow `older.toggle` bridge action.
- [x] Updated dynamic frame sizing so older rows count toward height only when the older tier is expanded.
- [x] Changed the header completed count to show recently finished rows, while keeping the total completed count available in state.
- [x] Fixed the first runtime click blocker for the older-tier control:
  - debug log showed refresh/render activity but no `bridge action=older.toggle`, meaning the click was not reaching Lua.
  - root cause was fragile `event.target.closest(...)` usage in older WebKit plus mousedown drag ownership on the older-tier control.
  - fixed with a `closestTarget(...)` compatibility helper and by excluding the older-tier control from drag start.
- [x] Replaced the visible `Older finished` row with a quieter row-height `Show all` / `Collapse` control.
- [x] Added a second dashed divider between recent finished rows and the older-finished tier, matching the active/finished separator language.
- [x] Fixed the follow-up clipping regression where the second divider rendered in HTML but was not included in Lua-owned frame height.
- [x] Polished the older-tier control after screenshot review:
  - replaced the full-width row treatment with a centered compact pill.
  - removed the far-right plus/minus affordance.
  - kept the `Show all` / `Collapse` label and count in the center of the panel.
- [x] Added extra bottom padding and expanded older-tier frame safety so the bottom border has breathing room after the final row.
- [x] Fixed the collapsed older-tier bottom-border defect from runtime screenshot review:
  - moved the older-tier toggle into a Lua-sized bottom action row.
  - rendered older Tier 3 rows above the bottom action row when expanded.
  - moved the options ellipsis out of the header and into the bottom-right of the same action row.
  - kept the header centered on status counts and loader only.
- [x] Fixed the follow-up collapsed older-tier bottom-border clipping seen with active + recent + older tiers:
  - root cause was the Lua frame height counting the bottom action row height but not its CSS grid gap and border breathing room.
  - added bottom-action frame safety in `webview/state.lua` so the outer Hammerspoon frame leaves room for the rounded bottom border.
- [x] Added an expanded-state top-right collapse control after screenshot review:
  - rendered a quiet local inline SVG chevron-up button in the header.
  - kept the options ellipsis in the bottom-right action row.
  - hid the collapse button while collapsed.
  - wired the button through the existing controlled `expand.toggle` bridge action.
  - excluded the collapse button from drag start so clicking it does not begin a move gesture.
- [x] Preserved canvas fallback; no Rust/Zellij code changed.

Files changed:

- `claude-tab-status/hammerspoon/claude-status-webview.lua`
- `claude-tab-status/hammerspoon/webview/state.lua`
- `claude-tab-status/hammerspoon/webview/html.lua`
- `claude-tab-status/hammerspoon/webview/styles.lua`
- `claude-tab-status/hammerspoon/webview/bridge.lua`
- `claude-tab-status/hammerspoon/phase_b_rendering.test.mjs`
- `claude-tab-status/hammerspoon/phase_d_runtime_smoke.test.mjs`
- `claude-tab-status/hammerspoon/phase_e_polish.test.mjs`
- `claude-tab-status/hammerspoon/phase_f_placement.test.mjs`
- `claude-tab-status/hammerspoon/phase_g_attention_tiers.test.mjs`
- `claude-tab-status/hammerspoon/row_focus.test.mjs`
- `claude-tab-status/hammerspoon/webview_port.test.mjs`
- `docs/plans/2026-05-01-hammerspoon-webview-port-status.md`

Verification:

- RED confirmed: `node --test claude-tab-status/hammerspoon/*.test.mjs` failed before implementation on the new attention-tier state, sizing, HTML, bridge, and style assertions.
- Follow-up RED confirmed: `node --test claude-tab-status/hammerspoon/phase_g_attention_tiers.test.mjs` failed on the refined older-tier control label, divider, and click compatibility assertions before implementation.
- Follow-up RED confirmed: `node --test claude-tab-status/hammerspoon/phase_g_attention_tiers.test.mjs` failed while the older-tier divider rendered without state/frame sizing ownership.
- Follow-up RED confirmed: `node --test claude-tab-status/hammerspoon/phase_g_attention_tiers.test.mjs` failed while the bottom action row, bottom-right options placement, and bottom-action frame allowance were missing.
- Follow-up RED confirmed: `node --test claude-tab-status/hammerspoon/phase_g_attention_tiers.test.mjs` failed while bottom action frame sizing omitted the row gap and border safety allowance.
- Follow-up RED confirmed: `node --test claude-tab-status/hammerspoon/phase_f_placement.test.mjs` failed while the expanded header lacked a top-right collapse button, hide rule, and drag exclusion.
- GREEN: `node --test claude-tab-status/hammerspoon/*.test.mjs`: 119 passing.
- `cd claude-tab-status && cargo build`: passed.
- `cd claude-tab-status && cargo test --no-run`: passed.

Manual Phase I smoke checklist:

- With a mix of running and finished sessions, expanded view shows running rows first.
- Finished rows from the last hour appear directly below the active/finished divider.
- Finished rows older than one hour are hidden behind `Show all` by default.
- Clicking `Show all` expands older rows, changes the control to `Collapse`, and resizes the panel without clipping.
- In collapsed older-tier mode, the bottom border remains visible below the bottom action row.
- In expanded older-tier mode, Tier 3 rows render above the `Collapse` control.
- The options ellipsis appears at the bottom-right in the same action row as `Show all` / `Collapse`, not in the header.
- Expanded mode shows a top-right chevron collapse button that collapses the widget without opening settings or starting drag.
- Collapsed header green count reflects recently finished rows rather than all old completed history.
- Waiting pulse, completion highlight, sounds, settings sidecar, dragging, and canvas fallback still work.

Remaining risks:

- The one-hour split currently derives from the existing human `detail` field such as `2m ago`, `1h ago`, or `27h ago`; a real timestamp would be more precise if the JSON contract ever adds one.
- Manual Hammerspoon visual smoke testing has not been performed by the executor.
- Very long older-finished lists can still hit the 700px clamp; scrolling or a screen-relative max height remains a possible later improvement.

## Risks And Decisions

- Decision: Keep Rust/Zellij plugin unchanged unless audit proves the JSON contract is insufficient.
- Decision: Keep Hammerspoon as the runtime for now.
- Decision: Lua owns data, settings, sounds, timers, and macOS window lifecycle.
- Decision: HTML/CSS/JS owns layout, controls, and visual animations.
- Decision: Webview is the default Hammerspoon renderer through `claude-status-loader.lua`; canvas remains available through `claudeStatus.renderer = "canvas"`.
- Decision: Phase A split the production webview internals into `webview/html.lua`, `webview/styles.lua`, `webview/state.lua`, and `webview/bridge.lua` before visual tuning.
- Decision: Phase B made `webview/state.lua` the owner of render sections and dynamic frame size, while keeping bridge actions Lua-owned and narrowly validated.
- Decision: Phase C changed only webview HTML/CSS visual presentation and source tests; Rust/Zellij, canvas fallback, loader, lifecycle, and Lua-owned behavior remain unchanged.
- Decision: Phase D keeps sizing ownership in `webview/state.lua`; the outer Hammerspoon frame is responsible for clipping at the max clamp, not internal `.widget`/`.rows` CSS overflow.
- Decision: Phase E kept settings drawer open/closed state Lua-owned through a narrow `settings.toggle` bridge action, so frame sizing was declarative and not JS-local.
- Decision: Phase F moved placement ownership into `webview/placement.lua`; the main widget now stores an anchor/custom placement state instead of a bottom-right custom position.
- Decision: Phase F moved settings out of the main panel into a separate sidecar `hs.webview` placed around the main widget.
- Decision: Phase I moved the ellipsis/options button out of the header and into the bottom-right action row next to the older-tier `Show all` / `Collapse` control. Expanded mode keeps a separate top-right chevron collapse button because collapse is a primary window action, while options remain secondary. Pin behavior remains available from the settings sidecar instead of as a separate header button.
- Decision: Row click focus is implemented as a controlled `row.focus` webview action. Lua activates Ghostty, optionally runs `zellij -s <session> action go-to-tab <tab_num>` as a tab fallback, then pipes `{"hook_event":"Focus","pane_id":...}` to the target Zellij session. The Rust plugin calls `focus_terminal_pane(payload.pane_id, false)` without mutating status state.
- Decision: Phase G uses the `ldrs` package only as a local build source. The current web-component loader cycle is bundled into `webview/ldrs.lua` with an ES2017 target and embedded directly into the Hammerspoon webview so the widget does not depend on a CDN or runtime module resolution.
- Decision: Phase G treats the header loader as ambient "active work" personality, not as an alert. The loader is active only when `active + waiting > 0`, rotates every 15 seconds, and keeps the header count centered.
- Decision: Phase H keeps the collapsed header stable and renders attention events in a separate collapsed-only `eventWebview` popover. Lua owns event creation, expiry, stickiness, dedupe, and focus/dismiss actions.
- Decision: Phase I splits finished rows into recent and older tiers using a one-hour elapsed-detail window, keeps running rows first, makes the older tier collapsed by default with Lua-owned toggle state, and renders older Tier 3 rows above the bottom action row when expanded.
- Decision: Phase J adds automatic Peek mode between collapsed and expanded. When the widget is not expanded and live/waiting agents or fresh events exist, `webview/state.lua` emits `viewMode = "peek"` with a wider 326px by 58px frame, a cycling ticker, stable counts, and waiting-first priority.
- Decision: Phase J keeps Peek mode HTML/CSS-only for visuals and JavaScript-only for local cycling. Lua still owns the source state, focus identity, frame size, event expiry, and all bridge actions.
- Decision: Phase J polish makes Peek render as a compact row-native card instead of a stretched header: loader left, stable counts right, and a middle card with kind marker, tab badge, title, and detail. The frame is now 70px tall with a 64px header to avoid the underwhelming empty-header layout seen in runtime.
- Decision: Phase J layout fix pins the Peek loader, ticker, and counts to `grid-row: 1`. The first row-native card polish let CSS Grid auto-place the ticker into an implicit second row, which pushed the card below the webview frame and clipped it.
- Decision: Phase J standalone Peek fix removes duplicated status concerns. In Peek mode the global compact loader and icon count cluster are hidden, the ticker spans the header by itself, the card owns the single status marker, and count context is rendered as quiet metadata inside the card.
- Decision: Phase J Peek semantic polish keeps local and global meaning separate. The left marker uses the cycling LDRS loader for running work, the badge owns the tab number, the title omits the repeated tab number, and the global active/done summary sits at the far right of the card.
- Decision: Phase J Peek count polish renders the global summary as two compact colored pills (`active` blue and `done` green) instead of monotone text, preserving the far-right global position while matching the widget's existing count language.
- Decision: Phase J Peek loader stability fix preserves the running loader DOM across the one-second Lua refresh loop. The custom element is only recreated when entering/leaving running mode or when the 15-second loader variant changes, so the animation no longer jumps back to frame zero every second.
- Decision: Phase J Peek hover interaction makes the Peek card the primary focus action. Hover now reveals a compact recent-finished history and an explicit `Expand` button; automatic hover expansion is disabled while in Peek mode.
- Decision: Phase J Peek hover frame experiment moves hover ownership into Lua through a narrow `peek.hover.set` bridge action. The compact Peek frame is now 76px tall when idle and 176px while hovered; CSS only handles the visible slide/fade of the history tray. This avoids permanently reserving an invisible native webview hitbox below the compact card.
- Decision: Phase J Peek hover fix uses bubbling `mouseover` / `mouseout` with `relatedTarget` guards instead of document-level `mouseenter` / `mouseleave`. The root cause of the first hover-frame experiment doing nothing in runtime was that `mouseenter` / `mouseleave` do not bubble, and Hammerspoon's WebKit did not reliably deliver those events to the document listener, so no `peek.hover.set` bridge action reached Lua.
- Decision: Phase K makes Peek the primary non-expanded mode. `webview/state.lua` now defaults to `viewMode = "peek"` even when there are no active rows or events; the old simplest header remains available as explicit `viewMode = "compact"` instead of being activity-derived.
- Decision: Phase K keeps mini/Peek switching separate from full details expansion. A narrow `compact.mode.set` bridge action persists `claudeStatus.compactMode` as either `peek` or `compact`; Peek hover reveals a shrink button, and mini hover reveals an enlarge button. Full expanded details still use `expand.toggle`.
- Decision: Phase K native hover tracking only controls Peek's hover history frame when `viewMode == "peek"`, so the mini header does not accidentally reserve the larger Peek hover frame.
- Decision: Phase K click follow-up removes whole-component expansion from the mini header. `requestExpand()` now returns false in compact mode, and the native Hammerspoon collapsed-frame click tap logs and skips expansion when `viewMode == "compact"`. The mini header can only return to Peek through the explicit `compact.mode.set` enlarge control.
- Decision: Phase K idle Peek follow-up renders an explicit all-clear card instead of an empty Peek card. When no rows or events are active, `webview/state.lua` emits an `idle` Peek item with `All clear` plus latest recent completion context when available. The renderer suppresses the useless active `0` pill and keeps the completed pill when there is recent finished work.
- Decision: Phase K idle layout follow-up gives the idle Peek card its own two-column layout and hides the right stat cluster when there is no active work. This prevents short idle text such as `All clear` and latest-finish context from being squeezed by empty badge/meta columns.
- Decision: Phase K Peek action placement follow-up moves Peek view-mode controls out of the header and into the hover history bottom action row. Shrink-to-mini and expand-to-details now use local `minimize-2` / `maximize-2` window-style icons, keeping item content separate from widget-level actions.
- Decision: Phase K Peek dynamic-history follow-up removes fixed hover sizing from the Peek history tray. Lua now derives hovered frame height from the number of history rows, while CSS allows up to eight visible history rows and scrolls the list after that. This keeps dynamic recent-finished content and the bottom action row visible instead of clipping when more rows arrive.
- Decision: Phase K Peek click-isolation follow-up removes whole-header/full-frame expansion from compact and Peek modes. Full details now open only through explicit `expand.toggle` controls; Peek card/history clicks focus sessions, and Peek shrink controls switch to mini without the native Hammerspoon click fallback also expanding details.
- Decision: Phase K Peek button reliability follow-up disables native Hammerspoon mousedown drag tracking for compact and Peek modes. DOM mousedown already excludes buttons, but native eventtap cannot see DOM targets, so it could start drag tracking under the minimize button and make clicks feel delayed or intermittent. Compact/Peek dragging now relies on the DOM bridge path.
- Decision: Phase L component isolation splits Mini, Peek, and Detail into source-level view modules while preserving one root webview shell, one bridge/event dispatcher, one placement system, one Lua frame-sizing path, and centralized CSS/animation policy. This deliberately avoids separate runtime webviews or per-view frame sizing.
- Decision: Webview should remain default only after the manual Phase F smoke checklist passes; canvas fallback remains available.
- Risk: `hs.webview` click/focus behavior may differ from canvas and needs real Hammerspoon testing.
- Risk: fullscreen/Spaces behavior may need tuning after the first production implementation.
- Risk: JS-to-Lua callback path must stay narrow so arbitrary web content cannot trigger random local actions.
- Risk: Manual Phase F Hammerspoon smoke testing has not been performed by the executor because Hammerspoon IPC is unavailable in this environment.
- Risk: Row click focus is source/build verified but still needs manual Hammerspoon/Zellij validation. Focus attempts are logged to `/tmp/claude-status-webview-focus.log`. Exact pane focus requires the running Zellij session to have loaded the updated `claude-tab-status.wasm`; existing sessions may need restart/reload if they still run the older plugin in memory.
- Risk: Phase G is source/build verified but still needs manual Hammerspoon visual smoke testing. Confirm the LDRS custom elements register correctly in Hammerspoon WebKit and that the 18px loader does not visually overpower the header.
- Risk: Phase H is source/build verified but still needs manual visual smoke testing for popover placement, WebKit click behavior, and event expiry timing.
- Risk: Phase I is source/build verified but still needs manual Hammerspoon visual smoke testing for tier grouping, older-tier toggling, and height changes.
- Risk: Phase J is source/build verified but still needs manual Hammerspoon visual smoke testing for ticker cycling, waiting pinning, right-edge placement, hover expansion interaction, native frame resize feel, and final card proportions in Hammerspoon WebKit.
- Risk: Phase K is source/build verified but still needs manual Hammerspoon smoke testing for persisted mini/Peek mode after reload, hover visibility of shrink/enlarge buttons, and interaction with right-edge placement.
- Risk: Phase L is source/build verified only. Runtime behavior should be unchanged because the refactor moved static shell fragments only, but Hammerspoon reload/manual smoke should still confirm Mini, Peek, Detail, hover history, and Detail collapse controls render exactly as before.
- Risk: Notification enable/disable is source/build verified only. Manual Hammerspoon smoke should confirm the new `Show notifications` setting appears in the settings sidecar, persists across reload, suppresses collapsed event popovers when off, and resumes them when on.
- Risk: Options sidecar clipping fix is source/build verified only. Manual Hammerspoon smoke should confirm all five rows are visible and the sidecar still places correctly near screen edges.
- Risk: Options sidecar pin removal and Peek Options entry point are source/build verified only. Manual Hammerspoon smoke should confirm the sidecar header no longer shows a pin and the Peek ellipsis opens Options without breaking Peek pin/minimize/expand controls.
- Risk: Options cog icon swap is source/build verified only. Manual Hammerspoon smoke should confirm both Detail and Peek Options buttons render as the cog and still open the sidecar reliably.
- Risk: Very long session lists can still hit the 700px clamp; scrolling or screen-relative max height may be needed later.

## Executor Prompt

Copy this prompt into the executor agent:

```text
You are the Executor agent for the Hammerspoon webview port in `/Users/cr1g/Projects/own/pixel-agents-standalone`.

Read and follow `docs/plans/2026-05-01-hammerspoon-webview-port-status.md` as the source of truth. Your job is implementation only; keep the plan/status document updated as you complete work.

Hard requirements:
- Do not rewrite the Rust/Zellij plugin unless the audit proves the JSON contract is insufficient.
- Keep `/tmp/claude-tab-status/*.json` as the data contract.
- Do not destructively replace the live canvas widget at first.
- Treat `claude-tab-status/hammerspoon/webview-demo.lua` as visual reference only. Do not evolve it into production code.
- Create production code separately, starting with `claude-tab-status/hammerspoon/claude-status-webview.lua`.
- Preserve Hammerspoon ownership of data loading, settings, sounds, reminders, transition detection, denylist, timers, and macOS window lifecycle.
- Let HTML/CSS/JS own layout, settings controls, pulse animation, and finish flash visuals.
- Use TDD: write or update a failing test first, run it and confirm it fails, implement, then rerun and confirm it passes.
- Use `apply_patch` for manual edits.
- Do not revert unrelated dirty worktree changes.
- Update `docs/plans/2026-05-01-hammerspoon-webview-port-status.md` after every completed phase or whenever the audit discovers missing behavior.

Start with Phase 1:
1. Audit `claude-tab-status/hammerspoon/claude-status.lua`.
2. Confirm every behavior listed in the status document is complete.
3. Add any missing behavior to the audit section.
4. Then begin Phase 2 by creating source-level tests for `claude-status-webview.lua`.

Verification commands:
- `node --test claude-tab-status/hammerspoon/*.test.mjs`
- `cd claude-tab-status && cargo build`
- `cd claude-tab-status && cargo test --no-run`

When reporting back, include:
- phases completed,
- files changed,
- verification output summary,
- status document updates,
- any remaining risks or blocked items.
```

## Verification Log

- 2026-05-01: Status document created by Planner. Implementation not started.
- 2026-05-02: Row click focus added. RED confirmed with `row_focus.test.mjs` and `focus_pane.test.mjs`; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 89/89, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Focus debugging/fallback added after manual report that row click did nothing. Hammerspoon now writes `/tmp/claude-status-webview-focus.log`, activates Ghostty before focusing, includes `tab_num` in `row.focus`, and runs a `go-to-tab` fallback before piping `Focus`. Release WASM rebuilt and copied to `~/.config/zellij/plugins/claude-tab-status.wasm`.
- 2026-05-02: Phase G LDRS header loader added. RED confirmed with `phase_g_ldrs_loaders.test.mjs`; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 96/96, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase H collapsed event notifications added. RED confirmed with `phase_h_event_notifications.test.mjs`; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 103/103, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase I older-tier bottom action polish added. RED confirmed with `phase_g_attention_tiers.test.mjs` on missing bottom action row/options placement/frame allowance; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 107/107, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase I bottom-border follow-up fixed after runtime screenshot showed clipping with active + recent + older tiers. RED confirmed with `phase_g_attention_tiers.test.mjs` on missing bottom action row-gap/border safety; verification rerun after implementation.
- 2026-05-02: Phase I top-right collapse control added after runtime screenshot request. RED confirmed with `phase_f_placement.test.mjs` on missing collapse button/hide rule/drag exclusion; verification rerun after implementation.
- 2026-05-02: Phase J Peek mode added. RED confirmed with `phase_i_peek_mode.test.mjs` on missing peek state/ticker/shell/styles; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 116/116, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase J Peek visual polish added after runtime screenshot showed the first version felt underwhelming. RED confirmed with `phase_i_peek_mode.test.mjs` on missing row-native card markup/styles; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 117/117, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase J Peek clipping regression fixed after runtime screenshot showed the card out of view. RED confirmed with `phase_i_peek_mode.test.mjs` on missing `grid-row: 1` placement for loader/ticker/counts; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 118/118, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase J standalone Peek fix removed the duplicated loader/count presentation after runtime screenshots showed two status icons and split responsibility. RED confirmed with `phase_i_peek_mode.test.mjs` on missing standalone Peek assertions; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 118/118, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase J Peek semantic polish moved running animation into the left marker, moved global active/done metadata to the far right, and stopped duplicating the tab number in the title. RED confirmed with `phase_i_peek_mode.test.mjs`; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 120/120, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase J Peek count polish replaced monotone `active / done` text with two colored stat pills. RED confirmed with `phase_i_peek_mode.test.mjs`; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 121/121, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase J Peek loader reset fixed. Root cause was `renderPeekKind()` clearing and recreating the LDRS custom element during every one-second `renderStatus` pass. RED confirmed with `phase_i_peek_mode.test.mjs`; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 123/123, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase J Peek hover history added. RED confirmed with `phase_i_peek_mode.test.mjs` on missing history state/rendering and non-expanding hover contract; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 125/125, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: LDRS cycle pool changed to `square`, `dot-spinner`, `quantum`, `cardio`, `miyagi`, `mirage`, `trio`, and `grid`. RED confirmed with `phase_g_ldrs_loaders.test.mjs`; local `webview/ldrs.lua` bundle regenerated from `webview/ldrs-entry.js`; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 120/120, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: LDRS cycle pool changed again: removed `square`, `mirage`, and kept `trefoil` / `helix` out of the pool; added `chaotic-orbit`, `hourglass`, `hatch`, and `bouncy`. Current cycle is `dot-spinner`, `quantum`, `cardio`, `miyagi`, `trio`, `grid`, `chaotic-orbit`, `hourglass`, `hatch`, and `bouncy`. RED confirmed with `phase_g_ldrs_loaders.test.mjs`; local `webview/ldrs.lua` bundle regenerated from `webview/ldrs-entry.js`; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 140/140, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Mini idle indicator changed from the active blue dot fallback to a muted local inline SVG coffee icon, while active work still renders the LDRS animation in the same loader slot. RED/GREEN confirmed with `phase_j_primary_peek.test.mjs`.
- 2026-05-02: Mini visual polish nudged the coffee idle icon down and reduced it to `13px`; the mini expand control now uses a transparent, muted default state with the blue bordered treatment reserved for hover. RED/GREEN confirmed with `phase_j_primary_peek.test.mjs`.
- 2026-05-02: Mini icon centering fix scoped nested SVG sizes for the coffee idle icon and mini expand icon. Root cause was wrapper sizes (`13px` / `14px`) still containing globally sized `16px` SVGs. RED/GREEN confirmed with `phase_j_primary_peek.test.mjs`.
- 2026-05-02: Mini edge icon calibration increased coffee to `14px` with a `0.5px` optical nudge and increased mini expand to `15px` with slightly stronger muted color/opacity, still no default button fill. RED/GREEN confirmed with `phase_j_primary_peek.test.mjs`.
- 2026-05-02: Idle Peek personality polish changed the empty/all-clear card to a `Coffee break` resting state with `All tabs quiet` context and reused the local coffee SVG instead of the generic bullet marker. RED/GREEN confirmed with `phase_j_primary_peek.test.mjs`; full verification rerun after implementation.
- 2026-05-02: Peek/notification separation fixed after runtime screenshot showed the same finished tab in the main Peek card, hover history, completed row, and event popover. Root cause: `webview/state.lua` inserted `input.events` into both primary Peek items and Peek hover history while completed JSON rows rendered the same finished tab. New rule: primary Peek is live work only, event popovers own just-finished notifications, and hover history suppresses rows represented by active notification events. RED/GREEN confirmed with `phase_j_primary_peek.test.mjs`; full verification rerun after implementation.
- 2026-05-02: Idle Peek layout regression fixed after runtime screenshot showed an empty badge block and the `Coffee break` copy pushed below the card. Root cause: idle layout still depended on `.peek-badge:empty` and CSS Grid auto-placement, which is brittle in Hammerspoon WebKit. Idle Peek now hides the badge unconditionally and pins the coffee marker/copy to the first grid row. RED/GREEN confirmed with `phase_j_primary_peek.test.mjs`; full verification rerun after implementation.
- 2026-05-02: Peek hover polish added an explicit dynamic bottom-border safety allowance and a Peek-specific pin action. The border fix adds `PEEK_HOVER_BORDER_SAFETY` to hover frame sizing so dynamic history/action rows do not clip the rounded bottom border. The new `peek.pin.toggle` bridge action keeps the Peek hover/history panel open persistently without using the full expanded renderer pin; the bottom action-row pin button reflects state with an active style and `aria-pressed`. RED/GREEN confirmed with `phase_j_primary_peek.test.mjs`; full verification rerun after implementation.
- 2026-05-02: Phase J Peek hover frame experiment added. RED confirmed with `phase_i_peek_mode.test.mjs` on missing idle/hover frame split, missing `peek.hover.set`, and CSS-only hover reveal. GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 125/125, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual acceptance is pending.
- 2026-05-02: Phase J Peek hover runtime fix added after manual report that hovering did nothing. Root cause: the JS bridge listened for non-bubbling `mouseenter` / `mouseleave` on `document`; Hammerspoon WebKit did not trigger that path, so Lua never received `peek.hover.set`. RED confirmed with `phase_i_peek_mode.test.mjs`; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 125/125, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase K primary Peek mode added. RED confirmed with new `phase_j_primary_peek.test.mjs` on missing default Peek mode, missing `compact.mode.set`, missing shrink/enlarge controls, and native-hover scoping. GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 130/130, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase K mini-click follow-up fixed after runtime report that clicking the simple header still opened full details. Root cause: the simple header still had two whole-component expansion paths: JS `.header` click through `requestExpand()` and Lua native collapsed-frame click through the interaction tap. RED confirmed with `phase_j_primary_peek.test.mjs`; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 134/134, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase K idle Peek card added after runtime screenshot showed an empty-looking Peek view when no workers were active. RED confirmed with `phase_j_primary_peek.test.mjs`; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 135/135, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase K idle Peek clipping fixed after runtime screenshot showed `All clear` clipped to `All ...`. Root cause: idle reused the normal four-column Peek grid, reserving empty badge and meta columns. RED confirmed with `phase_j_primary_peek.test.mjs`; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 135/135, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase K Peek action placement changed after UX review of the top-right shrink chevron. RED confirmed with `phase_j_primary_peek.test.mjs`; implementation moved shrink/expand into a bottom Peek action row and added window-style local icons. GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 136/136, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase K Peek action-row clipping fixed after runtime screenshot showed the bottom shrink/expand controls were still not visible. Root cause: the controls existed after the history list, but the hovered native frame and CSS history reveal height still matched the older text-button layout. RED confirmed with `phase_j_primary_peek.test.mjs`; implementation increased `PEEK_HOVER_FRAME_HEIGHT` from 148 to 176 and `.peek-history` hover `max-height` from 72 to 104. GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 136/136, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase K Peek dynamic-history sizing fixed after runtime screenshot still showed clipped hover content with multiple recent rows. Root cause: Peek history still had two fixed caps: Lua used one hover frame height, and JS/CSS were built around a three-row/104px reveal. RED confirmed with `phase_i_peek_mode.test.mjs` and `phase_j_primary_peek.test.mjs`; implementation added `peekHoverFrameHeight(sections)`, expanded history collection beyond three items, rendered the full history list, and made `.peek-history-list` scroll after eight visible rows. GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 136/136, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase K Peek click isolation fixed after runtime report that every Peek button opened full details. Root cause: the JS generic header click path and Lua native collapsed-frame click fallback both treated non-expanded Peek clicks as expansion. RED confirmed with `phase_i_peek_mode.test.mjs`, `phase_f_placement.test.mjs`, `phase_d_runtime_smoke.test.mjs`, and `phase_j_primary_peek.test.mjs`; implementation removed the generic header click expansion, made `requestExpand()` return false in Peek, and made the native click fallback ignore compact/Peek modes. GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 136/136, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase K Peek minimize reliability fixed after runtime report that the minimize button sometimes took many clicks. Root cause: native Hammerspoon mousedown handling still started drag tracking anywhere inside the non-expanded Peek frame, including DOM buttons; the DOM handler skipped buttons, but the native eventtap cannot know the DOM target. RED confirmed with `phase_f_placement.test.mjs` and `phase_j_primary_peek.test.mjs`; implementation ignores native mousedown in compact/Peek modes and leaves button clicks to the webview DOM bridge. GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 136/136, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase L component isolation refactor completed. RED confirmed first with new `phase_l_component_isolation.test.mjs` because `webview/views/{shared,mini,peek,detail}.lua` did not exist and `html.lua` did not delegate. Implementation extracted static Mini, Peek, Detail, and shared icon-template fragments into source modules while keeping one root shell, one JS dispatcher, one bridge, one placement system, and centralized sizing/overflow behavior. Existing source assertions were updated to include the delegated view modules. GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 139/139, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase L Mini polish follow-up fixed inconsistent Mini enlarge control visibility and aligned Mini counters with Peek count pills. Root cause: Mini had duplicated CSS control rules, and the later duplicate still hid `.mini-enlarge-toggle` until hover while compact counters kept the older plain `dot + value` treatment. RED confirmed with `phase_j_primary_peek.test.mjs` and `phase_c_visual_parity.test.mjs`; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 140/140, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase L Peek closed-height follow-up fixed visible dead space below the idle Peek card. Root cause: the non-hover Peek frame and `.widget.peek` min-height stayed at `76px` while the closed Peek header/card layout is `64px`, so the closed view reserved an extra bottom band even with history hidden. RED confirmed with `phase_i_peek_mode.test.mjs` and `phase_j_primary_peek.test.mjs`; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 141/141, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase L Peek border clipping follow-up fixed the bottom rounded border being clipped after the closed-height fix. Root cause: the native frame height and CSS visible height were both `64px`; WebKit clips the anti-aliased border when the rounded rectangle sits exactly on the webview edge. Implementation split `PEEK_VISIBLE_HEIGHT = 64` from `PEEK_FRAME_HEIGHT = PEEK_VISIBLE_HEIGHT + BORDER_SHADOW_SAFETY`, preserving the tight visible card while reserving transparent native-frame safety. RED confirmed with `phase_i_peek_mode.test.mjs`; GREEN confirmed with `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 141/141, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase L Peek reduce reliability follow-up fixed missed clicks on the Peek shrink button. Root cause: `renderStatus()` runs frequently and `renderPeekActions()` destroyed/recreated the action buttons on every pass with `innerHTML = ""`; if a refresh landed between mouse down and mouse up, WebKit lost the original button node and never emitted the click. RED confirmed with `phase_j_primary_peek.test.mjs`; implementation made Peek action rendering idempotent with stable button nodes. Full verification rerun after implementation.
- 2026-05-02: Phase L Mini control polish aligned the Mini enlarge control with the Peek window-style control language and reduced the crowded feel. RED confirmed with `phase_j_primary_peek.test.mjs`, `phase_b_rendering.test.mjs`, `phase_g_ldrs_loaders.test.mjs`, and `phase_f_placement.test.mjs`; implementation widened Mini from `148px` to `168px`, switched the Mini enlarge icon from chevron to `maximize-2`, and made the Mini control participate in the compact header grid with clearer gaps/padding.
- 2026-05-02: Phase L Peek pin action follow-up fixed the bottom action-row pin button after runtime report that the icon looked wrong and clicking it closed the panel. Root cause: the button rendered `data-action="peek.pin.toggle"` and the bridge allowlist accepted it, but the DOM click dispatcher had no `peek.pin.toggle` branch, so clicks fell through to Peek row/focus handling. RED confirmed with `phase_j_primary_peek.test.mjs`; implementation added the missing click dispatch, added targeted `peek pin toggle before/after` debug logging, and replaced the diagonal pushpin SVG with a quieter vertical Lucide-style pin. GREEN confirmed with `node --test claude-tab-status/hammerspoon/phase_j_primary_peek.test.mjs`; full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 144/144, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual verification is still pending.
- 2026-05-02: Phase L LDRS loader cycle updated by request. Removed `miyagi`, `hatch`, and `bouncy`; added `treadmill`, `metronome`, `jelly`, and `pulsar`. Current cycle is `dot-spinner`, `quantum`, `cardio`, `trio`, `grid`, `chaotic-orbit`, `hourglass`, `treadmill`, `metronome`, `jelly`, and `pulsar`. RED confirmed with `phase_g_ldrs_loaders.test.mjs`; `webview/ldrs.lua` was regenerated from local `webview/ldrs-entry.js` using the pinned `ldrs` package. GREEN confirmed with `node --test claude-tab-status/hammerspoon/phase_g_ldrs_loaders.test.mjs`; full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 144/144, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Phase L LDRS loader cycle follow-up replaced `pulsar` with `ripples`. Current cycle is `dot-spinner`, `quantum`, `cardio`, `trio`, `grid`, `chaotic-orbit`, `hourglass`, `treadmill`, `metronome`, `jelly`, and `ripples`. RED confirmed with `phase_g_ldrs_loaders.test.mjs`; `webview/ldrs.lua` was regenerated from local `webview/ldrs-entry.js`. GREEN confirmed with `node --test claude-tab-status/hammerspoon/phase_g_ldrs_loaders.test.mjs`; full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 144/144, `cargo build` passing, and `cargo test --no-run` passing. Runtime note: `jelly` is likely visually fragile in the tiny fixed loader slot because its LDRS implementation uses a filtered half-height SVG blob with `overflow: visible` and rotating/translated dots.
- 2026-05-02: Phase L LDRS loader cycle follow-up removed `jelly`, `treadmill`, and `ripples`, then added `reuleaux`. Current cycle is `dot-spinner`, `quantum`, `cardio`, `trio`, `grid`, `chaotic-orbit`, `hourglass`, `metronome`, and `reuleaux`. RED confirmed with `phase_g_ldrs_loaders.test.mjs`; `webview/ldrs.lua` was regenerated from local `webview/ldrs-entry.js`. GREEN confirmed with `node --test claude-tab-status/hammerspoon/phase_g_ldrs_loaders.test.mjs`; full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 144/144, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-02: Notification setting added to the webview settings sidecar. `notificationsEnabled` defaults to true, is persisted under the existing `claudeStatus.settings` key, is allowed through the controlled settings bridge, is exposed through Lua-owned view state, and gates the collapsed event notification queue/popover without changing sounds or status JSON loading. Follow-up tightened the UX to a single binary `Show notifications` switch and added a regression assertion against notification modes/levels/tiers. RED confirmed with `phase_h_event_notifications.test.mjs`; GREEN confirmed with focused tests passing 8/8. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 145/145, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon smoke testing was not performed by the executor.
- 2026-05-02: Options sidecar clipping fixed after runtime screenshot showed the panel cut off below `Finish flash`. Root cause: `SETTINGS_SIZE.height = 178` was a fixed four-row frame; adding `Show notifications` created a fifth 28px row without increasing the native webview height. Implementation replaced the fixed height with `settingsSize()` derived from `#SETTINGS_ITEMS`, row height, row gap, header height, vertical padding, and border safety; the static settings shell also includes the `Show notifications` fallback row. RED confirmed with `phase_h_event_notifications.test.mjs`; GREEN confirmed with focused tests passing 29/29. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 146/146, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon smoke testing was not performed by the executor.
- 2026-05-02: Options sidecar pin removed and Peek Options entry point added. The sidecar header now only contains the `Options` title; the obsolete sidecar `pin.toggle` button, styles, and sidecar JS handler were removed. Peek actions now include a low-emphasis ellipsis button wired to the existing controlled `settings.toggle` bridge so Options can be opened from Peek as well as Detail. RED confirmed with `phase_f_placement.test.mjs` and `phase_j_primary_peek.test.mjs`; GREEN confirmed with focused tests passing 56/56. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 146/146, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon smoke testing was not performed by the executor.
- 2026-05-02: Options button icon changed from ellipsis to cog/settings. The shared Options button and Peek Options action now use the local inline SVG `settings` icon through `settings-icon-template`; the old ellipsis icon is no longer instantiated for Options. RED confirmed with `phase_j_primary_peek.test.mjs`, `webview_port.test.mjs`, and `phase_l_component_isolation.test.mjs`; GREEN confirmed with focused tests passing 39/39. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 146/146, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon smoke testing was not performed by the executor.
- 2026-05-03: Processing neon polish added for active work. Active rows whose activity is `Thinking` or `Tool` now receive a declarative `processing-neon` class, and the primary Peek card receives a `working` class only for running agents. CSS adds a subtle blue neon border/glow animation around the inner processing card/row with reduced-motion handling; waiting, finished, and idle states keep their existing visual paths. RED confirmed with new `phase_neon_processing.test.mjs`; GREEN confirmed with focused tests passing 3/3. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 149/149, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Processing neon follow-up strengthened the effect after UX feedback that the first version was too timid. The old clipped one-pixel border was replaced with a masked conic-gradient strip and separate blurred aura so active work reads more like a moving neon light tracing the card edge. RED confirmed by tightening `phase_neon_processing.test.mjs` to require the aura, conic strip, mask, and orbit animation; GREEN confirmed with focused tests passing 3/3. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 149/149, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Processing neon geometry fixed after runtime screenshot showed the conic-gradient glow spinning around the card center like a spotlight instead of tracing the rounded rectangle edge. Root cause: `conic-gradient` plus `transform: rotate()` is circle-native and visually wrong on a wide rounded rectangle. Implementation replaced the center-spinning pseudo-elements with four explicit DOM edge strips (`top`, `right`, `bottom`, `left`) that animate sequentially around the row/card perimeter. RED confirmed by updating `phase_neon_processing.test.mjs` to reject `conic-gradient`/`processingNeonOrbit` and require edge elements/keyframes; GREEN confirmed with focused tests passing 4/4. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 150/150, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Processing neon restart fixed after runtime report that the strip repeatedly restarted from the top-left. Root cause: the production webview refreshes every second through `hs.timer.doEvery(1, refreshWebview)`, and `renderStatus()` clears/rebuilds rows with `rows.innerHTML = ""`; Peek also removed and re-added neon edges during each render. Recreated CSS animation nodes restarted from zero each second. Implementation keeps the current render architecture but assigns neon edge `animation-delay` from `Date.now() % NEON_TRACE_DURATION_MS`, so recreated edge elements resume the wall-clock animation phase instead of restarting. RED confirmed with `phase_neon_processing.test.mjs`; GREEN confirmed with focused tests passing 5/5. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 151/151, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Processing neon visual tuning reduced the static glow and thinned the hot edge line after runtime screenshot feedback that the effect was in the right family but still too boxy/loud. CSS now keeps the edge-native trace while using a 1px hot line, softer cyan bloom, reduced white core opacity, and quieter pulse shadow so active work reads as a moving charge instead of a selected input frame. RED confirmed by tightening `phase_neon_processing.test.mjs`; GREEN confirmed with focused tests passing 5/5. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 151/151, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Processing neon motion path changed to a symmetric center-out trace after UX feedback requesting a top-center start, left/right split, bottom-center meet, short hold, and return motion. Implementation replaced the four one-direction strips with six perimeter segments (`top-left`, `top-right`, `left`, `right`, `bottom-left`, `bottom-right`) and an alternate 5.2s leg / 10.4s full-cycle delay so refresh-safe animation phase tracking preserves both forward and reverse halves. RED confirmed with `phase_neon_processing.test.mjs`; GREEN confirmed with focused tests passing 5/5. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 151/151, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Processing neon corner geometry fixed by replacing segmented CSS strips with an inline SVG rounded-rectangle path. Root cause: straight DOM strips cannot continuously travel around rounded corners, so every corner produced a visible handoff. Implementation now renders two SVG paths starting at top center, one around each side of the rounded card, meeting at bottom center and alternating back; CSS animates `stroke-dashoffset` on the true rounded path while preserving wall-clock phase delay across one-second refreshes. RED confirmed with `phase_neon_processing.test.mjs`; GREEN confirmed with focused tests passing 5/5. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 151/151, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Processing neon SVG follow-up changed the path animation from progressive draw-on to a moving dash window after runtime feedback that the top/sides and bottom appeared as separate phases. Root cause: `stroke-dasharray: 100` with `stroke-dashoffset: 100 -> 0` draws and leaves the whole half-path behind, so bottom motion reads late/separate. CSS now uses `stroke-dasharray: 18 100` and animates `stroke-dashoffset: 18 -> -100`, making one lit segment travel the rounded path instead of progressively filling it. RED confirmed with `phase_neon_processing.test.mjs`; GREEN confirmed with focused tests passing 5/5. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 151/151, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Processing neon renderer switched from SVG stroke animation to a local canvas overlay after runtime feedback showed SVG dash rendering was still unreliable in Hammerspoon WebKit. Root cause: even with a correct rounded SVG path, dash animation timing/rendering made the bottom segment read separately. Implementation now inserts a transparent `canvas.neon-trace-canvas`, drives it with `requestAnimationFrame`, samples the rounded-rectangle perimeter in JavaScript, and draws the moving neon segment directly with Canvas 2D. This removes SVG dash animation, CDN/library dependency, and CSS corner handoff behavior while preserving active-only declarative `processing-neon` / Peek `working` state. RED confirmed with `phase_neon_processing.test.mjs`; GREEN confirmed with focused tests passing 5/5. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 151/151, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Processing neon canvas motion changed from independent moving dash segments to a connected circuit fill/drain cycle. Runtime feedback requested one connected light that starts at top center, spreads down both sides, meets at bottom center, holds, drains from top toward bottom, then returns upward. Implementation added `neonCircuitWindow()` to produce continuous `[start, end]` distance ranges over the rounded-rectangle half-path and samples that window for both mirrored sides instead of drawing a short segment head. RED confirmed by tightening `phase_neon_processing.test.mjs` against `segmentLength`/`head` and requiring fill/drain phase constants; GREEN confirmed with focused tests passing 5/5. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 151/151, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Processing neon connected-trace brightness increased after runtime feedback that the connected circuit became barely visible. Root cause: the previous bright moving dash concentrated glow into a short segment, while the connected fill/drain spreads the same low-alpha paint over a much longer path. Implementation increased the outer cyan glow alpha/width/blur, added a middle cyan tube layer, and widened/brightened the white core while leaving `neonCircuitWindow()` timing unchanged. RED confirmed by tightening `phase_neon_processing.test.mjs` around the canvas paint values; GREEN confirmed with focused tests passing 5/5. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 151/151, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Processing neon reverted from the connected fill/drain experiment back to the earlier clear canvas moving-line version after runtime feedback that the connected version remained too faint. Implementation removed `neonCircuitWindow()`, restored the short moving segment `segmentLength`/`head` math, restored the original two-layer canvas paint (`0.32` cyan glow at `7px`, `0.84` white core at `1.1px`), and updated the source test to lock the reverted behavior. RED confirmed with `phase_neon_processing.test.mjs`; GREEN confirmed with focused tests passing 5/5. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 151/151, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Processing neon option 3 implemented as a faint persistent rail plus the restored clear moving pulse. The canvas renderer now samples the full rounded-rectangle half-path into `railRightPoints`/`railLeftPoints`, draws a low-alpha connected cyan rail first, then draws the existing bright pulse over it. This keeps the visible moving line while giving the card a continuously connected route. RED confirmed by extending `phase_neon_processing.test.mjs` to require the rail pass and draw order; GREEN confirmed with focused tests passing 5/5. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 151/151, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Processing neon path root cause fixed after runtime screenshot showed two separate moving lines. Root cause: the canvas renderer only sampled a top-center-to-bottom-center half-path and mirrored it into separate `rightPoints`/`leftPoints`, so the bright pulse was never one continuous perimeter trace. Implementation replaced the mirrored half-path with one full rounded-rectangle sampler and draws a single `railPoints` / `pulsePoints` path around the full card. RED confirmed by tightening `phase_neon_processing.test.mjs` to reject mirrored point arrays and require `perimeterLength`; focused GREEN confirmed with `node --test claude-tab-status/hammerspoon/phase_neon_processing.test.mjs` passing 5/5. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 151/151, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Processing neon option A retried as a connected travelling charge after UX clarification. The full-perimeter single pulse was replaced with a symmetric half-path window: the lit range starts at top center, travels down both sides toward bottom center while its tail clears behind it, then reverses back upward. RED confirmed by tightening `phase_neon_processing.test.mjs` to require `neonTravelWindow()`, `tailLength`, mirrored half-path rails, and no full-perimeter `pulsePoints`; focused GREEN confirmed with `node --test claude-tab-status/hammerspoon/phase_neon_processing.test.mjs` passing 5/5. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 151/151, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Processing neon battery optimization added after runtime report that Hammerspoon showed significant energy use. Root causes/risk factors: per-canvas `requestAnimationFrame` was drawing every frame, CSS `drop-shadow` filters and `processingNeonGlow` added compositor work, hidden row DOM could still attach canvases outside expanded mode, and multiple processing rows could create multiple canvas loops. Implementation caps neon drawing at 24 FPS, skips drawing while document is hidden or reduced-motion is enabled, removes the CSS filter and CSS glow animation, attaches row neon only in expanded mode, attaches Peek neon only in Peek mode, limits row neon to the first processing row per render, and adds a persisted `Processing neon` setting under `claudeStatus.settings`. RED confirmed with `phase_neon_processing.test.mjs`; GREEN confirmed with focused tests passing 6/6. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 152/152, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon energy/runtime validation was not performed by the executor.
- 2026-05-03: Processing neon visual length increased after runtime screenshot showed the top bars reading as disconnected because the lit travel window was too short. Tail/window length changed from `max(30, min(92, halfLength * 0.48))` to `max(48, min(140, halfLength * 0.68))` while keeping the 24 FPS cap and persisted `Processing neon` toggle. RED confirmed with `phase_neon_processing.test.mjs`; GREEN confirmed with focused tests passing 6/6. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 152/152, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Processing neon animation removed after runtime screenshot showed the perimeter animation still looked laggy and clipped/awkward at the bottom-center handoff. Decision: the Hammerspoon WebKit surface is not a good fit for polished moving perimeter choreography. Implementation keeps the `Processing neon` setting but changes it to a static low-cost active treatment: confident cyan border/glow on active processing row/Peek card plus existing LDRS loader motion. Removed the neon canvas, `requestAnimationFrame` draw loop, wall-clock phase math, and `neon-trace-canvas` CSS. RED confirmed by changing `phase_neon_processing.test.mjs` to reject animated trace nodes; GREEN confirmed with focused tests passing 6/6. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 152/152, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual/energy validation was not performed by the executor.
- 2026-05-03: Peek active queue visibility added after UX review asked for better visibility into multiple active tasks without opening full details. The Peek state now exposes active queue metadata, the hovered/pinned Peek view renders up to three compact active stack rows under the primary card plus an overflow count, and the primary active item rotates every five seconds with a transform/opacity transition while keeping row focus actions controlled through the existing bridge. RED confirmed with new `phase_k_peek_active_queue.test.mjs`; GREEN confirmed with focused tests passing 4/4. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 156/156, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor; runtime review should check the hover frame height, stack row readability, and whether pausing rotation while hovered feels right.
- 2026-05-03: Peek active queue visual polish added after UX review of the first stack rendering. Queue rows now get depth classes with progressively quieter opacity/scale, and the Peek hover view uses one subtle dashed divider between the active queue and finished history instead of per-row separators. Lua hover-frame sizing accounts for the new divider so the bottom actions/history should not clip. RED confirmed with `phase_k_peek_active_queue.test.mjs`; GREEN confirmed with focused tests passing 5/5. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 157/157, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Peek active queue divider/timing follow-up fixed after runtime screenshot showed the dashed queue divider visible in the closed Peek card. CSS now fully hides the divider border outside hover/focus, the primary rotation cadence changed from 5s to 10s, and the transition changed from a sharper 240ms/8px movement to a smoother 420ms/5px movement. RED confirmed with `phase_k_peek_active_queue.test.mjs`; GREEN confirmed with focused tests passing 5/5. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 157/157, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Closed Peek vertical-centering follow-up fixed after runtime screenshot showed the non-hover card sitting high with extra bottom padding. Root cause: reveal-only Peek sections (`.peek-active-stack`, `.peek-queue-divider`, and `.peek-history`) remained in the closed grid flow with zero/transparent styling, so the closed header had hidden layout participants below the primary card. CSS now centers the closed Peek header and removes those reveal-only sections from layout until hover/focus opens the Peek view. RED confirmed with `phase_k_peek_active_queue.test.mjs`; GREEN confirmed with focused tests passing 6/6. Verification: `cargo build` passed and `cargo test --no-run` passed. Full Hammerspoon source verification currently has two unrelated sound expectation failures (`completion_flash.test.mjs` and `webview_sound.test.mjs`) expecting file-based sound constants while the dirty worktree defines system sounds (`Glass`/`Ping`) in canvas/webview; manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Peek loader spacing polish fixed after runtime screenshots showed the animated LDRS icon looking cramped beside the tab badge. The Peek primary card now gives the loader a 24px slot, a 12px gap before the tab badge, and a 20px max render box for loader custom elements so rotating variants have breathing room without changing frame height, counts, hover behavior, or the active queue. RED confirmed with `phase_k_peek_active_queue.test.mjs`; GREEN confirmed with focused Peek tests passing 21/21. Verification: `cargo build` passed and `cargo test --no-run` passed. Full Hammerspoon source verification still has unrelated dirty-tree source assertion failures around dormant detail/settings expectations; manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Peek loader spacing balance follow-up fixed after runtime screenshot showed the previous loader spacing overcorrected: the left inset stayed too tight while the internal loader/badge/title gaps became too wide. The Peek card keeps the 24px loader slot and 20px loader cap, but shifts the rhythm to `padding-left: 10px` with a calmer `10px` column gap. RED confirmed with `phase_k_peek_active_queue.test.mjs`; GREEN confirmed with focused Peek tests passing 21/21. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 163/163, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Peek badge-to-title spacing tightened after runtime screenshot showed the tab badge floating too far from the title/action text. The card keeps the balanced loader slot/left inset, and the badge now uses a small negative right margin so the badge/title relationship is tighter than the loader/badge relationship. RED confirmed with `phase_k_peek_active_queue.test.mjs`; GREEN confirmed with focused Peek tests passing 22/22. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 164/164, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Finished notification sound changed from the system `Glass` sound to `hammerspoon/sounds/mixkit-correct-answer-tone-2870.wav`, copied from `~/Downloads/mixkit-correct-answer-tone-2870.wav`. Both the webview renderer and canvas fallback resolve the sound relative to their source directory so the existing `~/.hammerspoon` symlinks keep working. Waiting/input sounds still use `Ping`. RED confirmed with focused sound tests expecting the new file-backed done sound; GREEN confirmed with focused sound tests passing 17/17. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 161/161, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-03: Finished notification sound changed from Mixkit to `hammerspoon/sounds/Glass.wav`, copied from `/Users/cr1g/Downloads/Notifications-master/WAV/Glass.wav`. Both the webview renderer and canvas fallback resolve the sound relative to their source directory so the existing `~/.hammerspoon` symlinks keep working. Waiting/input sounds still use `Ping`. RED confirmed with focused sound tests expecting the new file-backed done sound; GREEN confirmed with focused sound tests passing 17/17.
- 2026-05-03: Detail view disconnected but not deleted. `DETAIL_VIEW_ENABLED` now defaults to false, and normal UI/bridge paths (`expand.toggle`, `expand.set`, `pin.toggle`, native collapsed clicks, and the Peek action row) can no longer enter the full Detail pane. The archived `webview/views/detail.lua` module and Detail shell markup remain in place for a future re-enable. Peek still owns focus/history, Mini still enlarges only to Peek, and Options now opens as an independent sidecar without forcing Detail open. RED confirmed with new `phase_m_detail_disconnect.test.mjs`; full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 166/166, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-03: Idle compact rerender fixed after runtime screenshot showed the widget briefly rendering correctly with the coffee icon, then refreshing into a broken closed Peek layout without the enlarge control. Root cause: `DEFAULT_COMPACT_MODE` and the persisted `claudeStatus.compactMode` could both select `peek` even when there were no active/waiting rows, so idle state used the closed Peek card instead of the Mini coffee pill. `compactViewMode(input, activeTotal)` now falls back to `compact` when `activeTotal <= 0`, preserving Peek for live work. RED confirmed with `phase_i_peek_mode.test.mjs` and `phase_j_primary_peek.test.mjs`; focused GREEN passed 30/30. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 164/164, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Active Mini layout fixed after runtime screenshot showed live-work Mini rendering the left LDRS loader and centered counts but losing the right expand button. Root cause: the Mini renderer did have the same three conceptual parts as idle/waiting, but the `168px` frame and flexible center column let the two count pills overflow into the right control lane. The Mini pill is now `188px`, with explicit compact grid columns for loader, centered counts, and the expand control; the count lane is contained so it cannot cover the button. RED confirmed with `phase_j_primary_peek.test.mjs`; focused GREEN passed 16/16. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing 164/164, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Phase N row edit mode added. Peek now has an explicit edit toggle beside options in the bottom action row. When edit mode is on, the primary Peek card, active queue rows, Peek history rows, and expanded rows expose row-level controls: finished/idle rows use the existing dismiss/disconnect denylist path, while active/waiting rows use a new `row.interrupt` bridge action that quietly marks the local JSON row as `Done` with `0s ago · cancelled` and suppresses fake done sound/notification transitions by updating `prevActivities`. RED confirmed with new `phase_n_edit_mode.test.mjs`; full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 173/173, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed.
- 2026-05-03: Options cleanup removed the webview `Finish flash` and `Processing neon` toggles and their webview visual effects after runtime request to simplify settings. The webview no longer builds flash state, widget flash overlays, completion-highlight classes, or processing-neon row/Peek styling; waiting pulse, sounds, and notifications remain Lua-owned and available. RED confirmed with new `phase_l_remove_visual_effect_toggles.test.mjs`; focused GREEN passed 37/37 for the affected webview tests. Full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs` passing, `cargo build` passing, and `cargo test --no-run` passing. Manual Hammerspoon visual smoke testing was not performed by the executor.
- 2026-05-03: Phase N interrupt resurrection bug fixed after runtime report that interrupted active rows came back and kept receiving events. Root cause: `row.interrupt` rewrote the current JSON row as `Done`, but did not add the pane to the denylist or send the existing `Dismiss` pipe, so the next hook/file update could rehydrate the same live pane. Interrupt now also uses `addToDenylist(zj_session, pane_id)` and sends the same `{"hook_event":"Dismiss","pane_id":...}` pipe used by row dismiss while still suppressing fake done sounds/notifications. RED confirmed with `phase_n_edit_mode.test.mjs`; full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 174/174, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-03: Phase O run-scoped interrupt contract added after UX review found pane-scoped interrupt too broad. Rust `SessionInfo` now owns a `run_id`, `PluginState` owns a monotonic `run_seq`, `UserPromptSubmit` starts a fresh run id, and `status_writer.rs` emits `run_id` into `/tmp/claude-tab-status/*.json`. The webview carries `run_id` through row DOM identity and state. `row.interrupt` now blocks only the current run id in `~/.hammerspoon/claude-status-interrupted-runs.json` and coerces stale writes for that run to local `Done / cancelled`; a new user prompt produces a new `run_id` and becomes visible immediately. Finished-row dismiss uses a separate hidden-run store when `run_id` exists, while legacy rows without `run_id` still fall back to the old pane denylist and Zellij `Dismiss` pipe. RED confirmed with new `phase_o_run_scoped_interrupt.test.mjs`; full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 177/177, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-03: Peek hover bottom clipping root cause fixed after runtime screenshot showed the lower border/action area missing when active stack plus history rows were visible. Root cause: the Peek hover native frame is capped while the history list could still consume too much of the capped surface, so the action strip and rounded border had no guaranteed space. The fix adds a `peek-has-active-stack` root class and lowers the scrollable history-list max height only when active stack rows are present, keeping the shell/bottom actions inside the capped frame. RED confirmed with `phase_i_peek_mode.test.mjs`; full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 179/179, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-03: Event notification padding fixed after runtime screenshot showed a single notification with a large transparent hover frame. Root cause: the notification is a separate Hammerspoon webview with a fixed `244x108` frame sized for multiple rows, while a single event card only needs about one row of height. `eventPopoverSize()` now derives height from the visible event count, row height, row gap, panel padding, and frame safety, while preserving the existing three-row cap. RED confirmed with `phase_h_event_notifications.test.mjs`; full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 180/180, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-03: Peek/event placement mismatch fixed after runtime screenshot still showed the notification too far from the hovered Peek panel. Root cause: CSS capped `.peek-history-list` at `150px` when active stack rows are present, but Lua frame sizing still reserved the old uncapped history height, leaving transparent native webview space below the visible Peek panel. `peekHistoryListHeight(historyCount, hasActiveStack)` now applies the same `150px` active-stack cap used by CSS, so popovers anchor to the actual visible Peek surface. RED confirmed with `phase_i_peek_mode.test.mjs`; full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 180/180, `cargo build` passing, and `cargo test --no-run` passing.
- 2026-05-03: Runtime placement instrumentation added after the Peek/event spacing issue persisted in a screenshot. This is diagnostic only, not another visual fix. The webview now logs the applied native main frame, event popover frame, requested event size, and event DOM geometry (`.event-panel` / `.event-row`) to `/tmp/claude-status-webview-debug.log` when `claudeStatus.debug` is enabled. RED confirmed with `phase_h_event_notifications.test.mjs`; focused and full source verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 182/182, `cargo build` passing, and `cargo test --no-run` passing. Manual reproduction with a visible event popover is still needed to identify whether the remaining mismatch is in Lua frame sizing, popover placement, or WebKit DOM layout.
- 2026-05-03: Peek popover anchor root cause fixed after runtime logs proved event placement was using the full native Peek frame. Root cause: the native frame intentionally includes transparent WebKit safety space (`PEEK_HOVER_FRAME_SAFETY` and `PEEK_HOVER_BORDER_SAFETY`) to prevent clipped borders/actions, but event/settings popovers should attach to the visible card surface, not that safety-padded frame. `webview/state.lua` now emits `frame.anchorHeight`, and `claude-status-webview.lua` uses `popoverAnchorFrame(mainFrame, viewState.frame)` for event and settings sidecars while keeping the native frame unchanged. RED confirmed with `phase_h_event_notifications.test.mjs`; full verification confirmed `node --test claude-tab-status/hammerspoon/*.test.mjs claude-tab-status/src/*.test.mjs` passing 183/183, `cargo build` passing, and `cargo test --no-run` passing. Hammerspoon was reloaded; runtime visual acceptance is pending.

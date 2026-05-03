import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const state = readFileSync(new URL("./webview/state.lua", import.meta.url), "utf8");
const styles = readFileSync(new URL("./webview/styles.lua", import.meta.url), "utf8");
const html = readFileSync(new URL("./webview/html.lua", import.meta.url), "utf8");
const webview = readFileSync(
  new URL("./claude-status-webview.lua", import.meta.url),
  "utf8",
);

test("state helper emits canvas-parity render sections", () => {
  assert.match(state, /header = \{/);
  assert.match(state, /activeCount = counts\.active/);
  assert.match(state, /completedCount = #recentCompletedRows/);
  assert.match(state, /totalCompletedCount = counts\.done/);
  assert.match(state, /activeRows = activeRows/);
  assert.match(state, /completedRows = completedRows/);
  assert.match(state, /showDivider = showDivider/);
  assert.match(state, /settings = \{[\s\S]*items = input\.settingsItems[\s\S]*values = input\.settings[\s\S]*open = input\.settingsOpen == true/);
  assert.match(state, /effects = \{[\s\S]*flash = input\.flash[\s\S]*waitingPulse = input\.settings and input\.settings\.waitingPulse[\s\S]*completionFlash = input\.settings and input\.settings\.completionFlash/);
});

test("state helper computes dynamic canvas-anchored frame size", () => {
  assert.match(state, /local WIDTH = 300/);
  assert.match(state, /local PILL_WIDTH = 188/);
  assert.match(state, /local HEADER_HEIGHT = 30/);
  assert.match(state, /local ACTIVE_ROW_HEIGHT = 28/);
  assert.match(state, /local COMPLETED_ROW_HEIGHT = 24/);
  assert.match(state, /local ROW_GAP = 3/);
  assert.match(state, /local DIVIDER_HEIGHT = 16/);
  assert.match(state, /local MAX_FRAME_HEIGHT = 700/);
  assert.match(state, /function M\.frameForSections\(sections\)/);
  assert.match(state, /height = height \+ HEADER_HEIGHT/);
  assert.match(state, /height = height \+ \(\#sections\.activeRows \* \(ACTIVE_ROW_HEIGHT \+ ROW_GAP\)\)/);
  assert.match(state, /height = height \+ \(\#sections\.completedRows \* \(COMPLETED_ROW_HEIGHT \+ ROW_GAP\)\)/);
  assert.match(state, /if sections\.showDivider then[\s\S]*height = height \+ DIVIDER_HEIGHT/);
  assert.doesNotMatch(state, /if sections\.settings and sections\.settings\.open then/);
  assert.match(state, /height = math\.min\(height, MAX_FRAME_HEIGHT\)/);
  assert.match(state, /width = sections\.expanded and WIDTH or PILL_WIDTH/);
});

test("styles expose canvas-parity sections and row treatments", () => {
  assert.match(styles, /\/\* Header \*\//);
  assert.match(styles, /\.header/);
  assert.match(styles, /\.header-counts/);
  assert.match(styles, /\.header-icon-button/);
  assert.match(styles, /\/\* Rows \*\//);
  assert.match(styles, /\.tab-badge/);
  assert.match(styles, /\.row\.active-row/);
  assert.match(styles, /\.row\.waiting-row/);
  assert.match(styles, /\.row\.completed-row/);
  assert.match(styles, /\.divider/);
  assert.match(styles, /\.row\.completion-highlight/);
  assert.match(styles, /\.waiting-pulse-enabled \.row\.waiting-row/);
  assert.match(styles, /\/\* Settings \*\//);
  assert.match(styles, /\.settings/);
});

test("HTML renderer consumes render sections without moving bridge behavior", () => {
  assert.match(html, /renderHeader\(state\.header \|\| \{\}\)/);
  assert.match(html, /var active = renderRows\(state\.activeRows \|\| state\.activeSessions \|\| \[\], "active-row"\)/);
  assert.match(html, /var completed = renderRows\(state\.recentCompletedRows \|\| state\.completedRows \|\| \[\], "completed-row"\)/);
  assert.match(html, /if \(state\.showDivider\) \{/);
  assert.match(html, /var effects = state\.effects \|\| \{\}/);
  assert.match(html, /"row\.dismiss": true/);
  assert.doesNotMatch(html, /postAction\(\{ type: "row\.dismiss"/);
});

test("production webview applies dynamic frame sizing from state helper", () => {
  assert.match(webview, /local currentFrameSize = \{ width = PILL_WIDTH, height = HEADER_HEIGHT \}/);
  assert.match(webview, /local function frameForSize\(size\)/);
  assert.match(webview, /local viewState = buildViewState\(\)/);
  assert.match(webview, /currentFrameSize = viewState\.frame/);
  assert.match(webview, /mainFrame = frameForSize\(currentFrameSize\)[\s\S]*webview:frame\(mainFrame\)/);
  assert.match(webview, /local payload = hs\.json\.encode\(viewState\)/);
});

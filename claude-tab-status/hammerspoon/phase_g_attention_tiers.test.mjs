import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const state = readFileSync(new URL("./webview/state.lua", import.meta.url), "utf8");
const html = readFileSync(new URL("./webview/html.lua", import.meta.url), "utf8");
const styles = readFileSync(new URL("./webview/styles.lua", import.meta.url), "utf8");
const bridge = readFileSync(new URL("./webview/bridge.lua", import.meta.url), "utf8");
const webview = readFileSync(
  new URL("./claude-status-webview.lua", import.meta.url),
  "utf8",
);

test("state helper derives running, recent finished, and older finished tiers", () => {
  assert.match(state, /local RECENT_FINISHED_WINDOW_SECONDS = 3600/);
  assert.match(state, /local function parseElapsedSeconds\(detail\)/);
  assert.match(state, /local function splitFinishedRows\(rows\)/);
  assert.match(state, /if elapsed <= RECENT_FINISHED_WINDOW_SECONDS then[\s\S]*table\.insert\(recentRows, row\)/);
  assert.match(state, /else[\s\S]*table\.insert\(olderRows, row\)/);
  assert.match(state, /recentCompletedRows = recentCompletedRows/);
  assert.match(state, /olderCompletedRows = olderCompletedRows/);
  assert.match(state, /olderFinished = \{[\s\S]*count = #olderCompletedRows[\s\S]*expanded = olderExpanded/);
});

test("frame sizing counts older finished rows only when that tier is expanded", () => {
  assert.match(state, /local BOTTOM_ACTION_HEIGHT = 26/);
  assert.match(state, /local BOTTOM_ACTION_BORDER_SAFETY = 8/);
  assert.match(state, /local EXPANDED_BORDER_SAFETY = 12/);
  assert.match(state, /local olderRowsVisible = sections\.olderFinished and sections\.olderFinished\.expanded == true/);
  assert.match(state, /if olderRowsVisible then[\s\S]*height = height \+ \(#sections\.olderCompletedRows \* \(COMPLETED_ROW_HEIGHT \+ ROW_GAP\)\)/);
  assert.doesNotMatch(state, /local OLDER_CONTROL_HEIGHT/);
  assert.match(state, /if sections\.showBottomActions then[\s\S]*height = height \+ BOTTOM_ACTION_HEIGHT \+ ROW_GAP \+ BOTTOM_ACTION_BORDER_SAFETY/);
  assert.match(state, /if sections\.showOlderFinishedDivider then[\s\S]*height = height \+ DIVIDER_HEIGHT/);
  assert.match(state, /if olderRowsVisible then[\s\S]*height = height \+ EXPANDED_BORDER_SAFETY/);
});

test("HTML renders a collapsed older-finished tier with a controlled toggle action", () => {
  assert.match(html, /"older\.toggle": true/);
  assert.match(html, /function renderOlderFinishedControl\(state\)/);
  assert.match(html, /data-action", "older\.toggle"/);
  assert.match(html, /Show all/);
  assert.match(html, /Collapse/);
  assert.match(html, /Older finished/);
  assert.match(html, /olderDivider\.className = "divider older-finished-divider"/);
  assert.match(html, /if \(state\.showOlderFinishedDivider\)/);
  assert.match(html, /renderRows\(state\.recentCompletedRows \|\| state\.completedRows \|\| \[\], "completed-row", state\.editMode\)/);
  assert.match(html, /renderRows\(state\.olderCompletedRows \|\| \[\], "completed-row older-finished-row", state\.editMode\)/);
  assert.match(html, /postAction\(\{ type: "older\.toggle" \}\)/);
});

test("bottom action bar owns older tier toggle and options placement", () => {
  assert.doesNotMatch(html, /<button class="header-icon-button more-toggle"[^>]*data-action="settings\.toggle"/);
  assert.match(html, /function renderBottomActions\(state\)/);
  assert.match(html, /bottomActions\.className = "bottom-actions"/);
  assert.match(html, /options\.className = "header-icon-button more-toggle bottom-options-toggle"/);
  assert.match(html, /older\.forEach\(function\(row\) \{ rows\.appendChild\(row\); \}\);[\s\S]*var bottomActions = renderBottomActions\(state\)/);
  assert.match(html, /rows\.appendChild\(bottomActions\)/);
});

test("older-finished toggle click is robust in older WebKit and does not start dragging", () => {
  assert.match(html, /function closestTarget\(target, selector\)/);
  assert.match(html, /target = target\.parentElement \|\| target\.parentNode/);
  assert.match(html, /var control = closestTarget\(event\.target, "\[data-action\]"\)/);
  assert.match(html, /if \(closestTarget\(event\.target, "\.bottom-actions"\)\) return/);
});

test("peek hover refreshes are idempotent so action clicks are not re-rendered away", () => {
  assert.match(html, /var lastPostedPeekHover = null/);
  assert.match(html, /if \(lastPostedPeekHover === hovering\) return/);
  assert.match(html, /lastPostedPeekHover = hovering/);
  assert.match(webview, /local nextPeekHover = body\.hovering == true/);
  assert.match(webview, /if peekHover ~= nextPeekHover then[\s\S]*peekHover = nextPeekHover[\s\S]*if refreshWebview then refreshWebview\(\) end/);
});

test("bridge and Lua own the older-finished expanded state", () => {
  assert.match(bridge, /\["older\.toggle"\] = true/);
  assert.match(webview, /local olderFinishedExpanded = false/);
  assert.match(webview, /elseif body\.type == "older\.toggle" then[\s\S]*if expanded or viewMode == "peek" then[\s\S]*olderFinishedExpanded = not olderFinishedExpanded/);
  assert.match(webview, /olderFinishedExpanded = olderFinishedExpanded/);
});

test("styles distinguish recent finished rows from the older-finished control", () => {
  assert.match(styles, /\.older-finished-divider/);
  assert.match(styles, /\.older-finished-toggle/);
  assert.match(styles, /\.older-finished-toggle\[aria-expanded="true"\]/);
  assert.match(styles, /\.older-finished-toggle-shell/);
  assert.match(styles, /\.bottom-actions/);
  assert.match(styles, /\.bottom-options-toggle/);
  assert.match(styles, /justify-items: center/);
  assert.match(styles, /width: 150px/);
  assert.match(styles, /grid-template-columns: auto auto/);
  assert.match(styles, /\.rows[\s\S]*padding: 0 8px 10px/);
  assert.match(styles, /\.older-finished-row/);
});

test("peek action row anchors options left and pin/minimize right", () => {
  assert.match(html, /ensurePeekActionButton\(peekActions, "peek-options-toggle", "settings\.toggle"/);
  assert.match(html, /ensurePeekActionButton\(peekActions, "peek-edit-toggle", "edit\.toggle"/);
  assert.match(html, /ensurePeekActionButton\(peekActions, "peek-pin-toggle", "peek\.pin\.toggle"/);
  assert.match(html, /ensurePeekActionButton\(peekActions, "peek-minimize-toggle", "compact\.mode\.set"/);
  assert.match(styles, /\.peek-actions\s*\{[\s\S]*display: grid;[\s\S]*grid-template-columns: 28px 28px minmax\(0, 1fr\) 28px 28px;/);
  assert.match(styles, /\.peek-options-toggle\s*\{[^}]*grid-column: 1;/);
  assert.match(styles, /\.peek-edit-toggle\s*\{[^}]*grid-column: 2;/);
  assert.match(styles, /\.peek-pin-toggle\s*\{[^}]*grid-column: 4;/);
  assert.match(styles, /\.peek-minimize-toggle\s*\{[^}]*grid-column: 5;/);
});

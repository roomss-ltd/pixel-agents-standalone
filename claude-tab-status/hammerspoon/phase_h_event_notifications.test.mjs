import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const webview = readFileSync(new URL("./claude-status-webview.lua", import.meta.url), "utf8");
const html = readFileSync(new URL("./webview/html.lua", import.meta.url), "utf8");
const styles = readFileSync(new URL("./webview/styles.lua", import.meta.url), "utf8");
const state = readFileSync(new URL("./webview/state.lua", import.meta.url), "utf8");
const bridge = readFileSync(new URL("./webview/bridge.lua", import.meta.url), "utf8");
const placement = readFileSync(new URL("./webview/placement.lua", import.meta.url), "utf8");

test("collapsed status events are Lua-owned with expiring finished events and sticky waiting events", () => {
  assert.match(webview, /local EVENT_TTL = 15\.0/);
  assert.match(webview, /local MAX_EVENT_ROWS = 3/);
  assert.match(webview, /local EVENT_POPOVER_SIZE = \{ width = 244, height = 118 \}/);
  assert.match(webview, /local eventWebview = nil/);
  assert.match(webview, /local eventQueue = \{\}/);
  assert.match(webview, /local function enqueueStatusEvent\(kind, session, now\)/);
  assert.match(webview, /expires = kind == "finished" and \(now \+ EVENT_TTL\) or nil/);
  assert.match(webview, /sticky = kind == "waiting"/);
  assert.match(webview, /local function cleanupExpiredEvents\(\)/);
  assert.match(webview, /if event\.kind == "waiting" then/);
});

test("activity transitions enqueue collapsed notifications without replacing the existing flash and sound path", () => {
  assert.match(webview, /detectActivityTransitions\(\)[\s\S]*enqueueStatusEvent\("finished", s, now2\)/);
  assert.match(webview, /detectActivityTransitions\(\)[\s\S]*enqueueStatusEvent\("waiting", s, now2\)/);
  assert.match(webview, /flashState\[id\] = \{/);
  assert.match(webview, /playStatusSound\("done"\)/);
  assert.match(webview, /playStatusSound\("waiting"\)/);
});

test("event popover is a separate collapsed-only webview placed through the shared popover helper", () => {
  assert.match(webview, /local function buildEventsHtml\(\)/);
  assert.match(webview, /webviewHtml\.buildEvents\(\{/);
  assert.match(webview, /local function buildEventViewState\(\)/);
  assert.match(webview, /eventWebview = hs\.webview\.new\(eventFrame\)/);
  assert.match(webview, /eventWebview:html\(buildEventsHtml\(\)\)/);
  assert.match(webview, /webviewPlacement\.placePopover\(screenFrame\(\), mainFrame, EVENT_POPOVER_SIZE/);
  assert.match(webview, /local showEvents = shouldShow and settings\.notificationsEnabled ~= false and not expanded and #eventQueue > 0/);
  assert.match(webview, /window\.renderEvents\(/);
  assert.match(webview, /if eventWebview then eventWebview:delete\(\) end/);
});

test("event popover prefers bottom then top before side fallbacks", () => {
  assert.match(placement, /local order = options\.order or \{ "right", "left", "below", "above" \}/);
  assert.match(placement, /local function candidateFrame\(name, anchorFrame, width, height, screenFrame, padding, gap, clampCrossAxis\)/);
  assert.match(placement, /if clampCrossAxis and \(name == "below" or name == "above"\) then/);
  assert.match(placement, /for _, name in ipairs\(order\) do[\s\S]*local candidate = \{ name = name, frame = candidateFrame/);
  assert.match(webview, /order = \{ "below", "above", "left", "right" \}/);
  assert.match(webview, /clampCrossAxis = true/);
});

test("event popover renders compact cards with focus and dismiss bridge actions", () => {
  assert.match(html, /function M\.eventsScript\(bridgeScheme\)/);
  assert.match(html, /function M\.buildEvents\(options\)/);
  assert.match(html, /window\.renderEvents = function\(state\)/);
  assert.match(html, /className = "event-row " \+ String\(event\.kind \|\| "finished"\)/);
  assert.match(html, /data-action="event\.dismiss"/);
  assert.match(html, /postAction\(\{\s*type: "event\.focus"/);
  assert.match(html, /postAction\(\{\s*type: "event\.dismiss"/);
  assert.match(styles, /\.event-panel/);
  assert.match(styles, /\.event-row\.finished/);
  assert.match(styles, /\.event-row\.waiting/);
  assert.match(styles, /\.event-overflow/);
});

test("event notification polish uses row-native badge layout and quiet dismiss", () => {
  assert.match(webview, /local EVENT_POPOVER_SIZE = \{ width = 244, height = 118 \}/);
  assert.match(webview, /return tostring\(name\) \.\. " needs input"/);
  assert.match(webview, /return tostring\(name\) \.\. " finished"/);
  assert.match(webview, /event\.detail = kind == "waiting" and tostring\(event\.display_label\) \.\. " · Waiting for approval" or tostring\(event\.display_label\) \.\. " · Click to focus"/);
  assert.match(html, /badge\.className = "event-badge"/);
  assert.match(html, /status\.className = "event-status"/);
  assert.match(html, /status\.textContent = eventIcon\(event\.kind\)/);
  assert.match(styles, /\.event-panel\s*\{[\s\S]*width: 244px;/);
  assert.match(styles, /\.event-row\s*\{[\s\S]*grid-template-columns: 34px minmax\(0, 1fr\) 20px 18px;/);
  assert.match(styles, /\.event-row::before/);
  assert.match(styles, /\.event-dismiss\s*\{[\s\S]*background: transparent;[\s\S]*opacity: 0\.34;/);
  assert.match(styles, /\.event-row:hover \.event-dismiss/);
});

test("event bridge actions are explicitly allowlisted and reuse row focus identity", () => {
  assert.match(bridge, /\["event\.focus"\] = true/);
  assert.match(bridge, /\["event\.dismiss"\] = true/);
  assert.match(webview, /elseif body\.type == "event\.focus" then\s*focusSession\(body\._zj_session, body\.pane_id, body\.tab_num\)/);
  assert.match(webview, /elseif body\.type == "event\.dismiss" then\s*dismissEvent\(body\.id\)/);
  assert.match(state, /notifications = \{/);
});

test("collapsed event notifications are controlled by a persisted settings toggle", () => {
  assert.match(webview, /notificationsEnabled = true/);
  assert.match(webview, /\{ key = "notificationsEnabled", label = "Show notifications" \}/);
  assert.match(html, /data-setting="notificationsEnabled"/);
  assert.match(html, /notificationsEnabled: true/);
  assert.match(html, /row\.setAttribute\("data-setting", item\.key\)/);
  assert.match(state, /notificationsEnabled = input\.settings and input\.settings\.notificationsEnabled/);
  assert.match(webview, /local function enqueueStatusEvent\(kind, session, now\)[\s\S]*if settings\.notificationsEnabled == false then return end/);
  assert.match(webview, /local function buildEventViewState\(\)[\s\S]*if settings\.notificationsEnabled == false then[\s\S]*return \{ events = \{\}, overflow = 0 \}/);
  assert.match(webview, /local showEvents = shouldShow and settings\.notificationsEnabled ~= false and not expanded and #eventQueue > 0/);
  assert.match(webview, /if body\.key == "notificationsEnabled" and settings\.notificationsEnabled == false then[\s\S]*eventQueue = \{\}/);
  assert.doesNotMatch(webview + html + state, /notificationMode|notificationLevel|notificationTier/);
});

test("settings sidecar height is derived from all settings rows instead of the old four-row frame", () => {
  assert.match(webview, /local SETTINGS_ROW_HEIGHT = 28/);
  assert.match(webview, /local SETTINGS_ROW_GAP = 6/);
  assert.match(webview, /local function settingsSize\(\)[\s\S]*#SETTINGS_ITEMS \* SETTINGS_ROW_HEIGHT[\s\S]*math\.max\(#SETTINGS_ITEMS - 1, 0\) \* SETTINGS_ROW_GAP/);
  assert.match(webview, /webviewPlacement\.placePopover\(screenFrame\(\), mainFrame, settingsSize\(\)/);
  assert.doesNotMatch(webview, /local SETTINGS_SIZE = \{ width = 220, height = 178 \}/);
});

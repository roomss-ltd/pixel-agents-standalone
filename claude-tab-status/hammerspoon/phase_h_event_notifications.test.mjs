import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const webview = readFileSync(new URL("./claude-status-webview.lua", import.meta.url), "utf8");
const html = readFileSync(new URL("./webview/html.lua", import.meta.url), "utf8");
const styles = readFileSync(new URL("./webview/styles.lua", import.meta.url), "utf8");
const state = readFileSync(new URL("./webview/state.lua", import.meta.url), "utf8");
const bridge = readFileSync(new URL("./webview/bridge.lua", import.meta.url), "utf8");
const placement = readFileSync(new URL("./webview/placement.lua", import.meta.url), "utf8");
const icons = readFileSync(new URL("./webview/icons.lua", import.meta.url), "utf8");

test("collapsed status events are Lua-owned with expiring finished and waiting event pings", () => {
  assert.match(webview, /local EVENT_TTL = 15\.0/);
  assert.match(webview, /local MAX_EVENT_ROWS = 3/);
  assert.match(webview, /local EVENT_POPOVER_WIDTH = 244/);
  assert.match(webview, /local function eventPopoverSize\(\)/);
  assert.match(webview, /local eventWebview = nil/);
  assert.match(webview, /local eventQueue = \{\}/);
  assert.match(webview, /local function enqueueStatusEvent\(kind, session, now\)/);
  assert.match(webview, /expires = now \+ EVENT_TTL/);
  assert.doesNotMatch(webview, /sticky = kind == "waiting"/);
  assert.doesNotMatch(webview, /if event\.kind == "waiting" then/);
  assert.match(webview, /local function cleanupExpiredEvents\(\)/);
  assert.match(webview, /if not event\.expires or now <= event\.expires then/);
});

test("activity transitions enqueue collapsed notifications while sounds stay Lua-owned", () => {
  assert.match(webview, /detectActivityTransitions\(\)[\s\S]*enqueueStatusEvent\("finished", s, now2\)/);
  assert.match(webview, /detectActivityTransitions\(\)[\s\S]*enqueueStatusEvent\("waiting", s, now2\)/);
  assert.doesNotMatch(webview, /flashState\[id\] = \{/);
  assert.match(webview, /playStatusSound\("done"\)/);
  assert.match(webview, /playStatusSound\("waiting"\)/);
});

test("event popover is a separate collapsed-only webview placed through the shared popover helper", () => {
  assert.match(webview, /local function buildEventsHtml\(\)/);
  assert.match(webview, /webviewHtml\.buildEvents\(\{/);
  assert.match(webview, /local function buildEventViewState\(\)/);
  assert.match(webview, /eventWebview = hs\.webview\.new\(eventFrame\)/);
  assert.match(webview, /eventWebview:html\(buildEventsHtml\(\)\)/);
  assert.match(webview, /local popoverAnchor = popoverAnchorFrame\(mainFrame, viewState\.frame\)/);
  assert.match(webview, /local eventSize = eventPopoverSize\(\)/);
  assert.match(webview, /webviewPlacement\.placePopover\(screenFrame\(\), popoverAnchor, eventSize/);
  assert.match(webview, /gap = EVENT_POPOVER_GAP/);
  assert.match(webview, /local showEvents = shouldShow and settings\.notificationsEnabled ~= false and not expanded and #eventQueue > 0/);
  assert.match(webview, /window\.renderEvents\(/);
  assert.match(webview, /if eventWebview then eventWebview:delete\(\) end/);
});

test("event popover anchors to visible widget height instead of transparent frame safety", () => {
  assert.match(state, /anchorHeight = height - \(PEEK_HOVER_FRAME_SAFETY \+ PEEK_HOVER_BORDER_SAFETY\)/);
  assert.match(webview, /local function popoverAnchorFrame\(frame, size\)/);
  assert.match(webview, /local anchorHeight = tonumber\(size and size\.anchorHeight\)/);
  assert.match(webview, /h = anchorHeight or frame\.h/);
  assert.match(webview, /debugLog\("event frame main=.*anchor="/);
});

test("event popover debug logs native frame and DOM geometry", () => {
  assert.match(webview, /local function eventLayoutDebugScript\(\)/);
  assert.match(webview, /debugLog\("event frame main=/);
  assert.match(webview, /eventWebview:evaluateJavaScript\(eventLayoutDebugScript\(\), function\(layout\)/);
  assert.match(webview, /debugLog\("event layout " \.\. tostring\(layout\)\)/);
  assert.match(webview, /document\.querySelector\("\.event-panel"\)/);
  assert.match(webview, /document\.querySelector\("\.event-row"\)/);
});

test("main widget debug logs applied native frame after resize", () => {
  assert.match(webview, /debugLog\("main frame applied viewMode="/);
  assert.match(webview, /tostring\(viewState\.viewMode\)/);
  assert.match(webview, /tostring\(viewState\.frame\.width\)/);
  assert.match(webview, /tostring\(mainFrame\.w\)/);
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
  assert.match(webview, /local EVENT_POPOVER_WIDTH = 244/);
  assert.match(webview, /local EVENT_POPOVER_GAP = 5/);
  assert.match(webview, /return tostring\(name\) \.\. " needs input"/);
  assert.match(webview, /return tostring\(name\) \.\. " finished"/);
  assert.match(webview, /event\.detail = kind == "waiting" and tostring\(event\.display_label\) \.\. " · Waiting for approval" or tostring\(event\.display_label\) \.\. " · Click to focus"/);
  assert.match(icons, /\["triangle-alert"\]/);
  assert.match(html, /badge\.className = "event-badge"/);
  assert.match(html, /status\.className = "event-status"/);
  assert.match(html, /var WAITING_EVENT_ICON = /);
  assert.match(html, /status\.innerHTML = eventIcon\(event\.kind\)/);
  assert.doesNotMatch(html, /kind === "waiting" \? "!"/);
  assert.match(html, /dismiss\.setAttribute\("title", "Dismiss"\)/);
  assert.match(styles, /\.event-panel\s*\{[\s\S]*width: 244px;/);
  assert.match(styles, /\.event-panel\s*\{[\s\S]*gap: 3px;[\s\S]*padding: 4px;/);
  assert.match(styles, /\.event-row\s*\{[\s\S]*min-height: 32px;[\s\S]*grid-template-columns: 30px minmax\(0, 1fr\) 18px 22px;/);
  assert.doesNotMatch(styles, /\.event-row::before/);
  assert.match(styles, /\.event-title\s*\{[^}]*font-weight: 500;/);
  assert.match(styles, /\.event-detail\s*\{[^}]*font-size: 9\.5px;/);
  assert.match(styles, /\.event-dismiss\s*\{[\s\S]*border: 0\.5px solid rgba\(255, 255, 255, 0\.16\);[\s\S]*background: rgba\(255, 255, 255, 0\.075\);[\s\S]*opacity: 0\.9;/);
  assert.match(styles, /\.event-row:hover \.event-dismiss\s*\{[\s\S]*opacity: 1;/);
});

test("event popover height is derived from visible rows instead of one fixed padded frame", () => {
  assert.match(webview, /local EVENT_ROW_HEIGHT = 42/);
  assert.match(webview, /local EVENT_PANEL_PADDING_Y = 8/);
  assert.match(webview, /local EVENT_ROW_GAP = 3/);
  assert.match(webview, /local EVENT_FRAME_SAFETY = 8/);
  assert.match(webview, /local function eventPopoverSize\(\)[\s\S]*local visibleRows = math\.min\(#eventQueue, MAX_EVENT_ROWS\)/);
  assert.match(webview, /height = EVENT_PANEL_PADDING_Y \+ EVENT_FRAME_SAFETY/);
  assert.match(webview, /height = height \+ \(visibleRows \* EVENT_ROW_HEIGHT\)/);
  assert.match(webview, /height = height \+ \(math\.max\(visibleRows - 1, 0\) \* EVENT_ROW_GAP\)/);
  assert.match(webview, /return \{ width = EVENT_POPOVER_WIDTH, height = height \}/);
  assert.doesNotMatch(webview, /EVENT_POPOVER_SIZE = \{ width = 244, height = 108 \}/);
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
  assert.match(webview, /webviewPlacement\.placePopover\(screenFrame\(\), popoverAnchor, settingsSize\(\)/);
  assert.doesNotMatch(webview, /local SETTINGS_SIZE = \{ width = 220, height = 178 \}/);
});

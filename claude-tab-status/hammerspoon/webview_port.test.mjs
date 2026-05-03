import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const sourceFiles = [
  "./claude-status-webview.lua",
  "./webview/html.lua",
  "./webview/styles.lua",
  "./webview/state.lua",
  "./webview/bridge.lua",
  "./webview/views/shared.lua",
  "./webview/views/mini.lua",
  "./webview/views/peek.lua",
  "./webview/views/detail.lua",
];
const source = sourceFiles
  .map((file) => readFileSync(new URL(file, import.meta.url), "utf8"))
  .join("\n");
const styles = readFileSync(new URL("./webview/styles.lua", import.meta.url), "utf8");

test("production webview module is separate from the demo and owns only renderer lifecycle", () => {
  assert.match(source, /local M = \{\}/);
  assert.match(source, /local STATUS_DIR = "\/tmp\/claude-tab-status"/);
  assert.match(source, /local function buildHtml\(\)/);
  assert.match(source, /hs\.webview\.new/);
  assert.doesNotMatch(source, /webview-demo/);
  assert.doesNotMatch(source, /Tab #16/);
  assert.doesNotMatch(source, /26m ago/);
});

test("webview lifecycle is reload-safe and leaves canvas widget untouched", () => {
  assert.match(source, /function M\.start\(\)[\s\S]*M\.stop\(\)/);
  assert.match(source, /function M\.stop\(\)/);
  assert.match(source, /if webview then webview:delete\(\) end/);
  assert.match(source, /if pathwatcher then pathwatcher:stop\(\) end/);
  assert.match(source, /if updateTimer then updateTimer:stop\(\) end/);
  assert.match(source, /if hotkey then hotkey:delete\(\) end/);
  assert.match(source, /if hotkeyReset then hotkeyReset:delete\(\) end/);
  assert.match(source, /function M\.toggle\(\)/);
  assert.doesNotMatch(source, /hs\.canvas\.new/);
});

test("static shell preserves the widget structure expected by later real-data rendering", () => {
  assert.match(source, /<main class="widget"/);
  assert.match(source, /<header class="header"/);
  assert.doesNotMatch(source, /<button class="header-icon-button more-toggle" data-action="settings\.toggle"/);
  assert.match(source, /function renderBottomActions\(state\)/);
  assert.match(source, /options\.className = "header-icon-button more-toggle bottom-options-toggle"/);
  assert.match(source, /options\.setAttribute\("data-action", "settings\.toggle"\)/);
  assert.doesNotMatch(source, /<button class="header-icon-button expand-toggle"/);
  assert.doesNotMatch(source, /<button class="header-icon-button settings-toggle"/);
  assert.doesNotMatch(source, /<button class="header-icon-button pin-toggle"/);
  assert.match(source, /<section class="rows" id="rows"/);
  assert.match(source, /sharedView\.iconTemplate\("settings-icon-template", settingsIcon\)/);
  assert.match(source, /<main class="settings-panel"/);
  assert.match(source, /data-setting="soundsEnabled"/);
  assert.match(source, /data-setting="waitingReminderSound"/);
  assert.match(source, /data-setting="waitingPulse"/);
  assert.match(source, /data-setting="notificationsEnabled"/);
  assert.doesNotMatch(source, /data-setting="completionFlash"|data-setting="processingNeon"/);
});

test("webview module loads real status JSON using the existing contract", () => {
  assert.match(source, /local STATUS_DIR = "\/tmp\/claude-tab-status"/);
  assert.match(source, /local STALE_THRESHOLD = 120/);
  assert.match(source, /local function loadSessions\(\)/);
  assert.match(source, /pcall\(require\("hs\.fs"\)\.dir, STATUS_DIR\)/);
  assert.match(source, /hs\.json\.read\(path\)/);
  assert.match(source, /file:gsub\("%\.json\$"\s*,\s*""\)/);
  assert.match(source, /s\._zj_session = zj_session/);
  assert.match(source, /s\.pane_id/);
  assert.match(source, /s\.tab_num/);
  assert.match(source, /s\.tab_name/);
  assert.match(source, /s\.activity/);
  assert.match(source, /s\.icon/);
  assert.match(source, /s\.detail/);
});

test("webview view state matches canvas counting and partitioning rules", () => {
  assert.match(source, /local function partitionSessions\(\)/);
  assert.match(source, /a == "Thinking" or a == "Tool"/);
  assert.match(source, /a == "Waiting"/);
  assert.match(source, /a == "Done" or a == "Idle" or a == "Init"/);
  assert.match(source, /local function buildViewState\(\)/);
  assert.match(source, /local activeSessions, inactiveSessions = partitionSessions\(\)/);
  assert.match(source, /counts = counts/);
  assert.match(source, /activeSessions = activeSessions/);
  assert.match(source, /inactiveSessions = inactiveSessions/);
  assert.match(source, /sessions = sessions/);
});

test("webview pushes serialized Lua state into JavaScript rendering", () => {
  assert.match(source, /window\.renderStatus = function\(state\)/);
  assert.match(source, /function renderRows\(rows, className\)/);
  assert.match(source, /dataset\.paneId = String\(row\.pane_id \?\? ""\)/);
  assert.match(source, /dataset\.zjSession = row\._zj_session \|\| ""/);
  assert.match(source, /escapeHtml\(row\.tab_name \|\| ""\)/);
  assert.match(source, /escapeHtml\(row\.activity \|\| "Init"\)/);
  assert.match(source, /escapeHtml\(row\.icon \|\| ""\)/);
  assert.match(source, /escapeHtml\(row\.detail \|\| ""\)/);
  assert.match(source, /webview:evaluateJavaScript\(script, function\(result\)/);
  assert.match(source, /local viewState = buildViewState\(\)/);
  assert.match(source, /hs\.json\.encode\(viewState\)/);
  assert.match(source, /if visible and #sessions > 0 then/);
});

test("webview script builders do not format large JavaScript blobs", () => {
  assert.doesNotMatch(source, /\]\]\):format\(bridgeScheme or "claude-status"\)/);
  assert.match(source, /:gsub\("__BRIDGE_SCHEME__"/);
});

test("webview settings are Lua-owned and persisted with the canvas settings key", () => {
  assert.match(source, /local SETTINGS_KEY = "claudeStatus\.settings"/);
  assert.match(source, /local DEFAULT_SETTINGS = \{[\s\S]*soundsEnabled = true,[\s\S]*waitingReminderSound = true,[\s\S]*waitingPulse = true,[\s\S]*notificationsEnabled = true,[\s\S]*\}/);
  assert.match(source, /local SETTINGS_ITEMS = \{[\s\S]*\{ key = "soundsEnabled", label = "Sounds" \}[\s\S]*\{ key = "waitingReminderSound", label = "Waiting reminders" \}[\s\S]*\{ key = "waitingPulse", label = "Waiting pulse" \}[\s\S]*\{ key = "notificationsEnabled", label = "Show notifications" \}[\s\S]*\}/);
  assert.doesNotMatch(source, /completionFlash|processingNeon|Finish flash|Processing neon/);
  assert.match(source, /local function loadSettings\(\)[\s\S]*hs\.settings\.get\(SETTINGS_KEY\)/);
  assert.match(source, /local function saveSettings\(\)[\s\S]*hs\.settings\.set\(SETTINGS_KEY, settings\)/);
  assert.match(source, /settings = settings/);
  assert.match(source, /settingsItems = SETTINGS_ITEMS/);
});

test("webview renders settings toggles from state and posts only controlled toggle actions", () => {
  assert.match(source, /function renderSettings\(settings, settingsItems\)/);
  assert.match(source, /input\.checked = !!settings\[item\.key\]/);
  assert.match(source, /row\.dataset\.setting = item\.key/);
  assert.match(source, /var VALID_SETTING_KEYS = \{ soundsEnabled: true, waitingReminderSound: true, waitingPulse: true, notificationsEnabled: true \}/);
  assert.match(source, /function postAction\(message\)/);
  assert.match(source, /if \(!message \|\| message\.type !== "setting\.toggle"\) return/);
  assert.match(source, /if \(!VALID_SETTING_KEYS\[message\.key\]\) return/);
  assert.match(source, /window\.location\.href = BRIDGE_SCHEME \+ ":\/\/action\?payload=" \+ encodeURIComponent\(JSON\.stringify\(message\)\)/);
  assert.doesNotMatch(source, /eval\(/);
});

test("Lua bridge toggles only known settings and refreshes settings-dependent rendering", () => {
  assert.match(source, /local CALLBACK_NAME = "claudeStatus"/);
  assert.match(source, /local function isKnownSettingKey\(key\)/);
  assert.match(source, /if item\.key == key then return true end/);
  assert.match(source, /local function handleBridgeMessage\(message\)/);
  assert.match(source, /if body\.type == "setting\.toggle" then/);
  assert.match(source, /if not isKnownSettingKey\(body\.key\) then return end/);
  assert.match(source, /settings\[body\.key\] = not settings\[body\.key\]/);
  assert.match(source, /saveSettings\(\)/);
  assert.match(source, /refreshWebview\(\)/);
  assert.match(source, /local BRIDGE_SCHEME = "claude-status"/);
  assert.match(source, /local function handlePolicyAction\(action, _, request\)/);
  assert.match(source, /webview:policyCallback\(handlePolicyAction\)/);
  assert.doesNotMatch(source, /userContentController/);
  assert.doesNotMatch(source, /hs\.webview\.usercontent\.new/);
});

test("waiting pulse rendering is controlled by Lua settings state", () => {
  assert.match(source, /setClass\(document\.body, "waiting-pulse-enabled", !!settings\.waitingPulse\)/);
  assert.match(source, /\.waiting-pulse-enabled \.row\.waiting/);
});

test("webview tracks active-to-complete transitions for sounds and notifications only", () => {
  assert.doesNotMatch(source, /local FLASH_DURATION = 1\.5/);
  assert.doesNotMatch(source, /local COMPLETION_HIGHLIGHT_DURATION = 10\.0/);
  assert.doesNotMatch(source, /local flashState = \{\}/);
  assert.match(source, /local prevActivities = \{\}/);
  assert.doesNotMatch(source, /local function cleanupExpiredFlashes\(\)/);
  assert.match(source, /local function detectActivityTransitions\(\)/);
  assert.match(source, /local prev = prevActivities\[id\]/);
  assert.match(source, /if \(activity == "Done" or activity == "Idle"\) and \(prev == "Thinking" or prev == "Tool" or prev == "Waiting"\) then/);
  assert.match(source, /enqueueStatusEvent\("finished", s, now2\)/);
  assert.match(source, /playStatusSound\("done"\)/);
  assert.doesNotMatch(source, /settings\.completionFlash|flashState\[id\]/);
  assert.match(source, /prevActivities = newActivities/);
});

test("buildViewState keeps sound ownership in Lua without flash metadata", () => {
  assert.doesNotMatch(source, /local function buildFlashViewState\(\)/);
  assert.doesNotMatch(source, /flashRows\[id\]/);
  assert.doesNotMatch(source, /flash = buildFlashViewState\(\)/);
  assert.doesNotMatch(source, /cleanupExpiredFlashes\(\)/);
  assert.doesNotMatch(source, /new Audio\(/);
  assert.doesNotMatch(source, /AudioContext/);
  assert.match(source, /local function playStatusSound\(kind\)/);
  assert.match(source, /hs\.sound\.getByName\(config\.name\)/);
});

test("HTML and CSS keep waiting pulse but remove completion flash visuals", () => {
  assert.doesNotMatch(source, /<div class="widget-flash" id="widget-flash"><\/div>/);
  assert.match(source, /@keyframes waitingPulse/);
  assert.match(source, /\.waiting-pulse-enabled \.row\.waiting[\s\S]*animation: waitingPulse/);
  assert.doesNotMatch(source, /\.row\.completion-highlight/);
  assert.doesNotMatch(source, /@keyframes widgetFlash/);
  assert.doesNotMatch(source, /\.widget\.widget-flashing/);
});

test("completion highlight styles are removed from the webview", () => {
  assert.doesNotMatch(styles, /\.row\.completion-highlight/);
});

test("JS applies waiting pulse without flash or neon settings", () => {
  assert.doesNotMatch(source, /var flash = state\.flash \|\| \{\}/);
  assert.doesNotMatch(source, /flashRows|flashInfo|completion-highlight|widget-flashing|processingNeon/);
  assert.match(source, /setClass\(document\.body, "waiting-pulse-enabled", !!settings\.waitingPulse\)/);
});

test("webview interaction state preserves expand pin and custom position in Lua", () => {
  assert.match(source, /local expanded = false/);
  assert.match(source, /local pinned = false/);
  assert.match(source, /local placementState = \{ kind = "top-right" \}/);
  assert.match(source, /local dragState = nil/);
  assert.match(source, /expanded = expanded/);
  assert.match(source, /pinned = pinned/);
  assert.match(source, /placementState = placementState/);
  assert.match(source, /body\.type == "pin\.toggle"/);
  assert.match(source, /pinned = not pinned/);
  assert.match(source, /expanded = pinned/);
});

test("webview keeps dismiss as a controlled bridge action without a visible row button", () => {
  assert.match(source, /var VALID_ACTION_TYPES = \{/);
  assert.match(source, /"setting\.toggle": true/);
  assert.match(source, /"pin\.toggle": true/);
  assert.match(source, /"row\.dismiss": true/);
  assert.match(source, /"drag\.start": true/);
  assert.match(source, /"drag\.move": true/);
  assert.match(source, /"drag\.end": true/);
  assert.match(source, /"expand\.toggle": true/);
  assert.match(source, /"expand\.set": true/);
  assert.doesNotMatch(source, /button class="settings-pin-toggle" data-action="pin\.toggle"/);
  assert.doesNotMatch(source, /class="dismiss-button"/);
  assert.match(source, /postAction\(\{ type: "pin\.toggle" \}\)/);
  assert.match(source, /postAction\(\{ type: "drag\.start"/);
  assert.match(source, /postAction\(\{ type: "drag\.move"/);
  assert.match(source, /postAction\(\{ type: "drag\.end"/);
  assert.match(source, /postAction\(\{ type: "expand\.set", expanded: true \}\)/);
  assert.match(source, /postAction\(\{ type: "expand\.set", expanded: false \}\)/);
  assert.doesNotMatch(source, /longPressTimer/);
});

test("Lua dismiss action mirrors canvas denylist zellij pipe and local JSON cleanup", () => {
  assert.match(source, /local function saveDenylist\(deny\)/);
  assert.match(source, /local function addToDenylist\(zj_session, pane_id\)/);
  assert.match(source, /function dismissSession\(zj_session, pane_id, run_id\)/);
  assert.match(source, /if run_id and run_id ~= "" then\s+addHiddenRun\(run_id\)/);
  assert.match(source, /else\s+addToDenylist\(zj_session, pane_id\)/);
  assert.match(source, /hook_event":"Dismiss"/);
  assert.match(source, /zellij -s %q pipe --name "claude-tab-status"/);
  assert.match(source, /hs\.execute\(cmd, true\)/);
  assert.match(source, /data\.sessions = kept/);
  assert.match(source, /data\.counts = recountSessions\(kept\)/);
  assert.match(source, /os\.remove\(path\)/);
  assert.match(source, /body\.type == "row\.dismiss"/);
});

test("webview hotkeys reset sessions and lifecycle cleanup prevents duplicates", () => {
  assert.match(source, /local function resetSessions\(\)/);
  assert.match(source, /os\.remove\(STATUS_DIR \.\. "\/" \.\. file\)/);
  assert.match(source, /hotkey = hs\.hotkey\.bind\(\{ "ctrl", "alt" \}, "c", M\.toggle\)/);
  assert.match(source, /hotkeyReset = hs\.hotkey\.bind\(\{ "ctrl", "alt" \}, "r", resetSessions\)/);
  assert.match(source, /function M\.start\(\)[\s\S]*M\.stop\(\)/);
  assert.match(source, /function M\.stop\(\)[\s\S]*if updateTimer then updateTimer:stop\(\) end[\s\S]*if dragTap then dragTap:stop\(\) end[\s\S]*if hotkey then hotkey:delete\(\) end[\s\S]*if hotkeyReset then hotkeyReset:delete\(\) end[\s\S]*if pathwatcher then pathwatcher:stop\(\) end[\s\S]*if webview then webview:delete\(\) end/);
});

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const webview = readFileSync(new URL("./claude-status-webview.lua", import.meta.url), "utf8");
const state = readFileSync(new URL("./webview/state.lua", import.meta.url), "utf8");
const html = [
  "./webview/html.lua",
  "./webview/views/shared.lua",
  "./webview/views/mini.lua",
  "./webview/views/peek.lua",
  "./webview/views/detail.lua",
].map((file) => readFileSync(new URL(file, import.meta.url), "utf8")).join("\n");
const styles = readFileSync(new URL("./webview/styles.lua", import.meta.url), "utf8");
const bridge = readFileSync(new URL("./webview/bridge.lua", import.meta.url), "utf8");
const icons = readFileSync(new URL("./webview/icons.lua", import.meta.url), "utf8");

test("idle non-expanded state falls back to coffee mini while active work uses peek", () => {
  assert.match(state, /local DEFAULT_COMPACT_MODE = "peek"/);
  assert.match(state, /local function compactViewMode\(input, activeTotal\)/);
  assert.match(state, /if input\.viewMode == "compact" then return "compact" end/);
  assert.match(state, /if input\.viewMode == "peek" and \(activeTotal > 0 or input\.idlePeekRequested == true\) then return "peek" end/);
  assert.match(state, /if activeTotal <= 0 then return "compact" end/);
  assert.match(state, /return DEFAULT_COMPACT_MODE/);
  assert.match(state, /local viewMode = input\.expanded == true and "expanded" or compactViewMode\(input, activeTotal\)/);
  assert.doesNotMatch(state, /shouldUsePeekMode/);
  assert.match(html, /widget\.classList\.contains\("compact"\)/);
  assert.match(html, /coffee-idle-icon-template/);
  assert.match(html, /class="header-icon-button compact-mode-toggle mini-enlarge-toggle"/);
});

test("mini and peek are controlled by a dedicated compact mode bridge action", () => {
  assert.match(bridge, /\["compact\.mode\.set"\] = true/);
  assert.match(html, /"compact\.mode\.set": true/);
  assert.match(html, /if \(action === "compact\.mode\.set"\) \{/);
  assert.match(html, /postAction\(\{ type: "compact\.mode\.set", mode: control\.getAttribute\("data-mode"\) \}\)/);
  assert.match(webview, /local COMPACT_MODE_KEY = "claudeStatus\.compactMode"/);
  assert.match(webview, /local viewMode = "peek"/);
  assert.match(webview, /local function loadCompactMode\(\)/);
  assert.match(webview, /local function saveCompactMode\(\)/);
  assert.match(webview, /body\.type == "compact\.mode\.set"/);
  assert.match(webview, /if body\.mode == "peek" or body\.mode == "compact" then/);
  assert.match(webview, /idlePeekRequested = body\.mode == "peek"/);
  assert.match(webview, /idlePeekRequested = idlePeekRequested,/);
});

test("mini hover does not auto-expand into the detailed pane", () => {
  assert.match(html, /if \(widget\.classList\.contains\("compact"\)\) return;/);
  assert.doesNotMatch(html, /postAction\(\{ type: "expand\.set", expanded: hovering \}\);/);
  assert.match(webview, /elseif body\.type == "expand\.set" then[\s\S]*if \(viewMode == "compact" or viewMode == "peek"\) and body\.expanded == true then[\s\S]*return[\s\S]*end/);
});

test("mini and peek clicks do not use whole-header or native-frame expansion", () => {
  assert.match(html, /function requestExpand\(\) \{[\s\S]*if \(widget && widget\.classList\.contains\("compact"\)\) return false;/);
  assert.match(html, /function requestExpand\(\) \{[\s\S]*if \(widget && widget\.classList\.contains\("peek"\)\) return false;/);
  assert.doesNotMatch(html, /var header = closestTarget\(event\.target, "\.header"\)/);
  assert.match(webview, /if not expanded and \(viewMode == "compact" or viewMode == "peek"\) then[\s\S]*debugLog\("native compact\/peek mouse down ignored"\)[\s\S]*return false/);
  assert.match(webview, /if not pointerState\.moved then[\s\S]*if viewMode == "compact" or viewMode == "peek" then[\s\S]*debugLog\("ignored compact\/peek native click expand"\)[\s\S]*elseif canOpenDetailView\(\) then[\s\S]*expanded = true/);
});

test("peek can shrink to mini and mini can enlarge back to peek without expanding details", () => {
  assert.doesNotMatch(html, /<button class="header-icon-button compact-mode-toggle peek-minimize-toggle"/);
  assert.match(html, /className = "peek-action-button " \+ className/);
  assert.match(html, /button\.setAttribute\("data-action", action\)/);
  assert.match(html, /if \(mode\) button\.setAttribute\("data-mode", mode\)/);
  assert.match(html, /ensurePeekActionButton\(peekActions, "peek-minimize-toggle", "compact\.mode\.set", "Shrink to mini status"/);
  assert.match(html, /class="header-icon-button compact-mode-toggle mini-enlarge-toggle"/);
  assert.match(html, /data-action="compact\.mode\.set" data-mode="peek"/);
  assert.match(html, /aria-label="Enlarge to peek status"/);
  assert.match(html, /local enlargeIcon = maximizeIcon/);
  assert.match(styles, /\.widget\.peek \.peek-minimize-toggle\s*\{[\s\S]*display: grid;/);
  assert.match(styles, /\.widget\.peek:not\(\.peek-hovering\) \.peek-minimize-toggle\s*\{[\s\S]*opacity: 0;/);
  assert.match(styles, /\.widget:not\(\.peek\):not\(\.expanded\) \.mini-enlarge-toggle\s*\{[\s\S]*display: grid;/);
  assert.doesNotMatch(styles, /\.widget:not\(\.peek\):not\(\.expanded\):not\(:hover\) \.mini-enlarge-toggle/);
  assert.match(styles, /\.widget\.compact \.mini-enlarge-toggle\s*\{[\s\S]*position: static;[\s\S]*grid-column: 3;[\s\S]*opacity: 0\.78;[\s\S]*pointer-events: auto;/);
});

test("mini layout gives loader counts and enlarge control distinct spacing", () => {
  assert.match(state, /local PILL_WIDTH = 188/);
  assert.match(styles, /\.widget:not\(\.expanded\) \{ width: 188px; \}/);
  assert.match(styles, /\.widget\.compact \.header\s*\{[\s\S]*grid-template-columns: 24px 1fr 28px;[\s\S]*padding: 0 10px;[\s\S]*column-gap: 8px;/);
  assert.match(styles, /\.widget\.compact \.loader-slot\s*\{[\s\S]*grid-column: 1;/);
  assert.match(styles, /\.widget\.compact \.header-counts\s*\{[\s\S]*grid-column: 2;[\s\S]*justify-self: center;[\s\S]*gap: 8px;[\s\S]*max-width: 100%;[\s\S]*overflow: hidden;/);
  assert.match(styles, /\.widget:not\(\.peek\) \.peek-ticker,\s*\.widget:not\(\.peek\) \.peek-active-stack,\s*\.widget:not\(\.peek\) \.peek-queue-divider\s*\{[\s\S]*display: none;/);
  assert.match(styles, /\.widget\.compact \.mini-enlarge-toggle\s*\{[\s\S]*position: static;[\s\S]*inset: auto;[\s\S]*grid-row: 1;[\s\S]*grid-column: 3;[\s\S]*align-self: center;[\s\S]*width: 26px;[\s\S]*height: 26px;[\s\S]*border: 0\.5px solid transparent;[\s\S]*background: transparent;[\s\S]*color: rgba\(255, 255, 255, 0\.62\);[\s\S]*opacity: 0\.78;/);
  assert.match(styles, /\.widget\.compact \.mini-enlarge-toggle\s*\{[\s\S]*min-width: 26px;[\s\S]*min-height: 26px;[\s\S]*box-sizing: border-box;/);
  assert.match(styles, /\.header-icon-button\.compact-mode-toggle\s*\{[\s\S]*width: 26px;[\s\S]*height: 26px;[\s\S]*min-width: 26px;[\s\S]*min-height: 26px;/);
  assert.doesNotMatch(styles, /\.compact-mode-toggle\s*\{[^}]*position: absolute;/);
  assert.doesNotMatch(styles, /\.header-icon-button\.compact-mode-toggle\s*\{[^}]*position: absolute;/);
  assert.doesNotMatch(styles, /\.widget:not\(\.peek\):not\(\.expanded\) \.mini-enlarge-toggle\s*\{[^}]*top:/);
  assert.match(styles, /\.widget\.compact \.mini-enlarge-toggle:hover\s*\{[\s\S]*border-color: rgba\(115, 166, 255, 0\.20\);[\s\S]*background: rgba\(115, 166, 255, 0\.08\);[\s\S]*color: rgba\(255, 255, 255, 0\.78\);/);
  assert.match(styles, /\.widget\.compact \.mini-enlarge-toggle \.maximize-icon\s*\{[\s\S]*width: 15px;[\s\S]*height: 15px;/);
  assert.match(styles, /\.widget\.compact \.mini-enlarge-toggle \.maximize-icon svg\s*\{[\s\S]*width: 15px;[\s\S]*height: 15px;/);
});

test("mini idle loader slot renders a muted coffee icon instead of the active blue dot", () => {
  assert.match(icons, /\["coffee"\]/);
  assert.match(icons, /coffee-smoke coffee-smoke-1/);
  assert.match(icons, /coffee-smoke coffee-smoke-2/);
  assert.match(icons, /coffee-smoke coffee-smoke-3/);
  assert.match(icons, /coffee-smoke coffee-smoke-1" d="M7\.1 7\.1C4\.2 5\.2 10\.1 3\.8 7\.4 1\.6/);
  assert.match(icons, /coffee-smoke coffee-smoke-2" d="M11 7\.1C8\.1 5\.1 14 3\.9 11\.2 1\.3/);
  assert.match(icons, /coffee-smoke coffee-smoke-3" d="M14\.9 7\.1C12 5\.2 17\.8 3\.8 15 1\.5/);
  assert.match(html, /local coffeeIcon = icons\.svg\("coffee", "control-icon coffee-idle-icon"\)/);
  assert.match(html, /sharedView\.iconTemplate\("coffee-idle-icon-template", coffeeIcon\)/);
  assert.match(html, /function renderCoffeeSteamInto\(container\)/);
  assert.match(html, /existing && existing\.getAttribute\("data-coffee-steam"\) === "true"/);
  assert.match(html, /var template = document\.getElementById\("coffee-idle-icon-template"\);/);
  assert.match(html, /element\.setAttribute\("data-coffee-steam", "true"\)/);
  assert.match(html, /if \(!loader\.active && widget && widget\.classList\.contains\("compact"\)\) \{[\s\S]*renderCoffeeSteamInto\(slot\);/);
  assert.doesNotMatch(html, /slot\.innerHTML = idleIcon \? idleIcon\.innerHTML : "";/);
  assert.match(styles, /\.widget\.compact \.loader-slot:not\(\.is-active\) \.coffee-idle-icon\s*\{[^}]*width: 14px;[^}]*height: 14px;[^}]*color: rgba\(190, 198, 214, 0\.62\);[^}]*transform: translateY\(0\.5px\);/);
  assert.match(styles, /\.widget\.compact \.loader-slot:not\(\.is-active\) \.coffee-idle-icon svg\s*\{[^}]*width: 14px;[^}]*height: 14px;/);
  assert.match(styles, /\.widget\.compact \.loader-slot:not\(\.is-active\) \.coffee-smoke\s*\{[^}]*animation: coffeeSteam/);
  assert.match(styles, /\.widget\.compact \.loader-slot:not\(\.is-active\) \.coffee-smoke\s*\{[^}]*stroke-width: 1\.65px;/);
  assert.match(styles, /stroke-dasharray: 9;/);
  assert.match(styles, /stroke-dashoffset: 9;/);
  assert.match(styles, /animation-delay: -1\.1s;/);
  assert.match(styles, /animation-delay: -2\.2s;/);
  assert.match(styles, /@keyframes coffeeSteam/);
  assert.match(styles, /18%\s*\{[\s\S]*opacity: 0;/);
  assert.match(styles, /42%\s*\{[\s\S]*opacity: 0\.72;[\s\S]*stroke-dashoffset: 2\.8;/);
  assert.match(styles, /72%\s*\{[\s\S]*opacity: 0\.45;[\s\S]*stroke-dashoffset: 0;/);
  assert.match(styles, /100%\s*\{[\s\S]*opacity: 0;[\s\S]*stroke-dashoffset: 0;/);
  assert.doesNotMatch(styles, /\.widget\.compact \.loader-slot:not\(\.is-active\)::before/);
});

test("peek view mode controls live in a bottom action row with window icons", () => {
  assert.match(icons, /\["minimize-2"\]/);
  assert.match(icons, /\["maximize-2"\]/);
  assert.match(icons, /\["pin"\]/);
  assert.match(icons, /\["pin"\] = \[\[<path d="M12 17v5"\/>/);
  assert.doesNotMatch(icons, /M18\.5 5\.5 13 11/);
  assert.match(state, /local PEEK_HISTORY_MAX_VISIBLE_ROWS = 8/);
  assert.match(state, /local PEEK_MAX_HOVER_FRAME_HEIGHT = 520/);
  assert.match(state, /local PEEK_HOVER_BORDER_SAFETY = BORDER_SHADOW_SAFETY \+ \d+/);
  assert.match(state, /local function peekHoverFrameHeight\(sections\)/);
  assert.match(state, /math\.min\(historyCount, PEEK_HISTORY_MAX_VISIBLE_ROWS\)/);
  assert.match(state, /height = height \+ PEEK_HOVER_BORDER_SAFETY/);
  assert.match(html, /icons\.svg\("minimize-2", "control-icon minimize-icon"\)/);
  assert.match(html, /icons\.svg\("maximize-2", "control-icon maximize-icon"\)/);
  assert.match(html, /icons\.svg\("pin", "control-icon pin-icon"\)/);
  assert.match(html, /sharedView\.iconTemplate\("pin-icon-template", pinIcon\)/);
  assert.match(html, /function createPeekActionButton\(className, action, label, title, templateId, mode\)/);
  assert.match(html, /peekActions\.className = "peek-actions"/);
  assert.match(html, /ensurePeekActionButton\(peekActions, "peek-minimize-toggle", "compact\.mode\.set", "Shrink to mini status", "Shrink to mini", "minimize-icon-template", "compact"\)/);
  assert.match(html, /ensurePeekActionButton\(peekActions, "peek-pin-toggle", "peek\.pin\.toggle", "Pin peek open", "Pin peek open", "pin-icon-template"\)/);
  assert.match(html, /ensurePeekActionButton\(peekActions, "peek-options-toggle", "settings\.toggle", "Open options", "Options", "settings-icon-template"\)/);
  assert.match(html, /ensurePeekActionButton\(peekActions, "peek-edit-toggle", "edit\.toggle", "Edit rows", "Edit rows", "pencil-icon-template"\)/);
  assert.doesNotMatch(html, /peek-expand-button/);
  assert.doesNotMatch(html, /"Expand full status"/);
  assert.match(styles, /\.widget\.peek\.peek-hovering\s*\{[\s\S]*min-height: 64px;/);
  assert.match(styles, /\.widget\.peek\.peek-hovering \.peek-history,\s*\.widget\.peek:focus-within \.peek-history\s*\{[\s\S]*max-height: 320px;/);
  assert.match(styles, /\.peek-history-list\s*\{[\s\S]*max-height: 244px;[\s\S]*overflow-y: auto;/);
  assert.match(styles, /\.peek-actions\s*\{[\s\S]*display: grid;[\s\S]*grid-template-columns: 28px 28px minmax\(0, 1fr\) 28px 28px;[\s\S]*align-items: center;/);
  assert.match(styles, /\.peek-actions\.has-older-toggle\s*\{[\s\S]*grid-template-rows: 24px 24px;[\s\S]*min-height: 54px;/);
  assert.match(styles, /\.peek-options-toggle\s*\{[^}]*grid-column: 1;[^}]*grid-row: 1;/);
  assert.match(styles, /\.peek-edit-toggle\s*\{[^}]*grid-column: 2;[^}]*grid-row: 1;/);
  assert.match(styles, /\.peek-history-older-toggle-shell\s*\{[\s\S]*grid-column: 1 \/ -1;[\s\S]*grid-row: 1;[\s\S]*justify-self: center;/);
  assert.match(styles, /\.peek-actions\.has-older-toggle \.peek-options-toggle,\s*\.peek-actions\.has-older-toggle \.peek-edit-toggle,\s*\.peek-actions\.has-older-toggle \.peek-pin-toggle,\s*\.peek-actions\.has-older-toggle \.peek-minimize-toggle\s*\{[\s\S]*grid-row: 2;/);
  assert.match(styles, /\.peek-pin-toggle\s*\{[^}]*grid-column: 4;[^}]*grid-row: 1;/);
  assert.match(styles, /\.peek-minimize-toggle\s*\{[^}]*grid-column: 5;[^}]*grid-row: 1;/);
  assert.match(styles, /\.peek-action-button\s*\{[\s\S]*width: 24px;[\s\S]*height: 22px;/);
  assert.match(styles, /\.peek-action-button\.is-pinned\s*\{[\s\S]*color: var\(--active-blue\);/);
});

test("peek action controls preserve DOM nodes across one-second status refreshes", () => {
  assert.match(html, /function ensurePeekActionButton\(peekActions, className, action, label, title, templateId, mode\)/);
  assert.match(html, /var button = peekActions\.querySelector\("\." \+ className\);/);
  assert.match(html, /if \(!button\) \{/);
  assert.match(html, /peekActions\.appendChild\(button\);/);
  assert.doesNotMatch(html, /function renderPeekActions\(\) \{[\s\S]{0,220}peekActions\.innerHTML = "";/);
});

test("peek pin keeps hover history open without using full expanded pin state", () => {
  assert.match(bridge, /\["peek\.pin\.toggle"\] = true/);
  assert.match(html, /"peek\.pin\.toggle": true/);
  assert.match(html, /var pin = ensurePeekActionButton\(peekActions, "peek-pin-toggle", "peek\.pin\.toggle"/);
  assert.match(html, /else if \(action === "peek\.pin\.toggle"\) \{[\s\S]*event\.stopPropagation\(\);[\s\S]*postAction\(\{ type: "peek\.pin\.toggle" \}\);[\s\S]*\} else if \(action === "pin\.toggle"\)/);
  assert.match(html, /setClass\(pin, "is-pinned", !!\(peek && peek\.hoverPinned\)\)/);
  assert.match(html, /pin\.setAttribute\("aria-pressed", peek && peek\.hoverPinned \? "true" : "false"\)/);
  assert.match(webview, /local peekPinned = false/);
  assert.match(webview, /debugLog\("peek pin toggle before pinned="/);
  assert.match(webview, /elseif body\.type == "peek\.pin\.toggle" then[\s\S]*peekPinned = not peekPinned[\s\S]*peekHover = peekPinned/);
  assert.match(webview, /debugLog\("peek pin toggle after pinned="/);
  assert.match(webview, /local nextPeekHover = not expanded and not peekPinned and viewMode == "peek" and pointInFrame\(pos, webview:frame\(\)\)/);
  assert.match(webview, /peekPinned = peekPinned,/);
  assert.match(state, /local peekHover = \(input\.peekHover == true or input\.peekPinned == true\) and viewMode == "peek"/);
  assert.match(state, /hoverPinned = input\.peekPinned == true/);
});

test("compact mode controls stay hidden by default despite generic header button styles", () => {
  assert.match(styles, /\.header-icon-button\.compact-mode-toggle\s*\{[\s\S]*display: none;[\s\S]*position: absolute;/);
  assert.match(styles, /\.widget\.expanded \.compact-mode-toggle\s*\{[\s\S]*display: none;/);
  assert.match(styles, /\.widget\.expanded \.collapse-toggle\s*\{[\s\S]*display: grid;/);
});

test("full-details collapse control is hidden outside expanded mode", () => {
  assert.match(styles, /\.header-icon-button\.collapse-toggle\s*\{[\s\S]*display: none;/);
  assert.match(styles, /\.widget\.expanded \.collapse-toggle\s*\{[\s\S]*display: grid;/);
  assert.match(styles, /\.widget:not\(\.expanded\) \.collapse-toggle\s*\{[\s\S]*display: none;/);
});

test("native hover only enlarges the peek hover frame while in peek mode", () => {
  assert.match(webview, /local nextPeekHover = not expanded and not peekPinned and viewMode == "peek" and pointInFrame\(pos, webview:frame\(\)\)/);
  assert.match(webview, /elseif body\.type == "compact\.mode\.set" then[\s\S]*peekHover = false[\s\S]*settingsOpen = false[\s\S]*saveCompactMode\(\)[\s\S]*refreshWebview\(\)/);
});

test("idle peek renders useful all-clear context instead of an empty card", () => {
  assert.match(state, /local function buildIdlePeekItem\(recentCompletedRows\)/);
  assert.match(state, /kind = "idle"/);
  assert.match(state, /title = "Coffee break"/);
  assert.match(state, /detail = "All tabs quiet · last finish " \.\. latest\.detail/);
  assert.match(state, /detail = "All tabs quiet"/);
  assert.match(state, /if #peekItems == 0 then[\s\S]*table\.insert\(peekItems, buildIdlePeekItem\(recentCompletedRows\)\)/);
  assert.match(html, /var isIdle = !!item && item\.kind === "idle";/);
  assert.doesNotMatch(html, /if \(kind === "idle"\) return "•";/);
  assert.match(html, /if \(item && item\.kind === "idle"\) \{[\s\S]*renderCoffeeSteamInto\(kind\);/);
  assert.doesNotMatch(html, /kind\.innerHTML = idleIcon \? idleIcon\.innerHTML : "";/);
  assert.match(html, /setClass\(ticker, "idle", isIdle\);/);
  assert.match(html, /renderPeekMeta\(meta, header, isIdle\);/);
  assert.match(html, /if \(compact && activeTotal < 1\) \{[\s\S]*meta\.innerHTML = "";/);
  assert.match(html, /if \(activeTotal > 0\) \{[\s\S]*peek-stat-active/);
  assert.match(styles, /\.peek-ticker\.idle \.peek-card\s*\{[\s\S]*grid-template-columns: 18px minmax\(0, 1fr\);/);
  assert.match(styles, /\.peek-ticker\.idle \.peek-copy\s*\{[\s\S]*grid-column: 2;[\s\S]*grid-row: 1;/);
  assert.match(html, /if \(item && item\.kind === "idle"\) \{[\s\S]*setClass\(kind, "is-loader", false\);[\s\S]*kind\.setAttribute\("data-peek-kind-mode", "idle"\);[\s\S]*renderCoffeeSteamInto\(kind\);/);
  assert.doesNotMatch(html, /clearPeekKind\(kind\);\s*if \(item && item\.kind === "idle"\)/);
  assert.match(styles, /\.peek-ticker\.idle \.peek-kind\s*\{[\s\S]*grid-column: 1;[\s\S]*grid-row: 1;[\s\S]*color: rgba\(115, 166, 255, 0\.7\);[\s\S]*background: rgba\(115, 166, 255, 0\.08\);[\s\S]*box-shadow: 0 0 14px rgba\(115, 166, 255, 0\.12\);/);
  assert.match(styles, /\.peek-ticker\.idle \.coffee-idle-icon\s*\{[^}]*width: 17px;[^}]*height: 17px;[^}]*color: rgba\(115, 166, 255, 0\.82\);/);
  assert.match(styles, /\.peek-ticker\.idle \.coffee-idle-icon svg\s*\{[^}]*width: 17px;[^}]*height: 17px;/);
  assert.match(styles, /\.peek-ticker\.idle \.coffee-smoke\s*\{[^}]*animation: coffeeSteam 3\.6s ease-in-out infinite;/);
  assert.doesNotMatch(styles, /\.peek-ticker\.idle \.coffee-smoke-1\s*\{[^}]*display: none;/);
  assert.doesNotMatch(styles, /@keyframes peekCoffeeSteam/);
  assert.match(styles, /\.peek-ticker\.idle \.peek-badge\s*\{[\s\S]*display: none;/);
  assert.doesNotMatch(styles, /\.peek-ticker\.idle \.peek-badge:empty/);
});

test("peek primary ticker is reserved for live work while finished events stay notifications", () => {
  assert.match(state, /local function buildPeekItems\(activeRows\)/);
  assert.doesNotMatch(state, /local function buildPeekItems\(activeRows, events\)/);
  assert.doesNotMatch(state, /local waitingItems, runningItems, eventItems =/);
  assert.doesNotMatch(state, /buildPeekItems\(activeRows, input\.events\)/);
  assert.match(state, /local peekItems, peekPinned = buildPeekItems\(activeRows\)/);
  assert.match(state, /events = input\.events or \{\}/);
});

test("peek hover history suppresses rows already represented by active notification events", () => {
  assert.match(state, /local function rowKey\(row\)/);
  assert.match(state, /local function eventKeySet\(events\)/);
  assert.match(state, /local function buildPeekHistory\(completedRows, events, tier\)/);
  assert.match(state, /local suppressed = eventKeySet\(events\)/);
  assert.match(state, /local key = rowKey\(row\)/);
  assert.match(state, /if not suppressed\[key\] then[\s\S]*table\.insert\(history, peekItemFromCompletedRow\(row, tier\)\)/);
  assert.doesNotMatch(state, /table\.insert\(history, peekItemFromEvent\(event\)\)/);
});

test("compact debug bridge reports computed mini layout geometry", () => {
  assert.match(html, /"debug\.layout": true/);
  assert.match(bridge, /\["debug\.layout"\] = true/);
  assert.match(html, /function reportCompactLayout\(state\)/);
  assert.match(html, /miniButton: compactLayoutNode\("\.mini-enlarge-toggle"\)/);
  assert.match(html, /window\.getComputedStyle\(element\)/);
  assert.match(html, /postAction\(\{ type: "debug\.layout", layout: payload \}\)/);
  assert.match(webview, /local function debugEnabled\(\)/);
  assert.match(webview, /return value == true or value == "true" or value == 1 or value == "1"/);
  assert.match(webview, /debug = debugEnabled\(\)/);
  assert.match(webview, /local function compactLayoutDebugScript\(\)/);
  assert.match(webview, /miniButton: node\("\.mini-enlarge-toggle"\)/);
  assert.match(webview, /return JSON\.stringify\(payload\);/);
  assert.match(webview, /if debugEnabled\(\) and viewState\.viewMode == "compact" then[\s\S]*webview:evaluateJavaScript\(compactLayoutDebugScript\(\), function\(layout\)/);
  assert.match(webview, /elseif body\.type == "debug\.layout" then[\s\S]*debugLog\("layout " \.\. hs\.inspect\(body\.layout\)\)/);
});

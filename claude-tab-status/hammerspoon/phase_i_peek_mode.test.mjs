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

test("state exposes explicit peek mode between mini and expanded", () => {
  assert.match(state, /local PEEK_WIDTH = 326/);
  assert.match(state, /local PEEK_VISIBLE_HEIGHT = 64/);
  assert.match(state, /local PEEK_FRAME_HEIGHT = PEEK_VISIBLE_HEIGHT \+ BORDER_SHADOW_SAFETY/);
  assert.match(state, /local PEEK_HISTORY_MAX_VISIBLE_ROWS = 8/);
  assert.match(state, /local function peekHoverFrameHeight\(sections\)/);
  assert.match(state, /local DEFAULT_COMPACT_MODE = "peek"/);
  assert.match(state, /local function compactViewMode\(input, activeTotal\)/);
  assert.match(state, /if activeTotal <= 0 then return "compact" end/);
  assert.match(state, /local viewMode = input\.expanded == true and "expanded" or compactViewMode\(input, activeTotal\)/);
  assert.match(state, /viewMode = viewMode,/);
  assert.match(state, /if sections\.viewMode == "peek" then[\s\S]*height = sections\.peekHover and peekHoverFrameHeight\(sections\) or PEEK_FRAME_HEIGHT/);
  assert.match(webview, /viewMode = viewMode,/);
});

test("non-hover peek keeps closed visible height but reserves transparent border safety", () => {
  assert.match(state, /local PEEK_VISIBLE_HEIGHT = 64/);
  assert.match(state, /local PEEK_FRAME_HEIGHT = PEEK_VISIBLE_HEIGHT \+ BORDER_SHADOW_SAFETY/);
  assert.match(styles, /\.widget\.peek\s*\{[\s\S]*min-height: 64px;/);
  assert.match(styles, /\.widget\.peek \.header\s*\{[\s\S]*height: 64px;/);
  assert.doesNotMatch(styles, /\.widget\.peek\s*\{[\s\S]*min-height: 76px;/);
});

test("peek ticker prioritizes waiting sessions, then live sessions", () => {
  assert.match(state, /local function buildPeekItems\(activeRows\)/);
  assert.match(state, /if tostring\(row\.activity or ""\):lower\(\) == "waiting" then/);
  assert.match(state, /table\.insert\(waitingItems, peekItemFromSession\(row, "waiting"\)\)/);
  assert.match(state, /table\.insert\(runningItems, peekItemFromSession\(row, "running"\)\)/);
  assert.match(state, /appendAll\(items, waitingItems\)/);
  assert.match(state, /appendAll\(items, runningItems\)/);
  assert.doesNotMatch(state, /appendAll\(items, eventItems\)/);
  assert.match(state, /return items, #waitingItems > 0/);
});

test("main shell renders a dedicated peek ticker while keeping counts stable", () => {
  assert.match(html, /var PEEK_ROTATE_INTERVAL_MS = 10000/);
  assert.match(html, /var peekItems = \[\]/);
  assert.match(html, /function renderPeek\(header\)/);
  assert.match(html, /setClass\(widget, "peek", state\.viewMode === "peek"\)/);
  assert.match(html, /<div class="peek-ticker" data-peek-ticker/);
  assert.match(html, /<span class="peek-title" data-peek-title><\/span>/);
  assert.match(html, /<span class="peek-detail" data-peek-detail><\/span>/);
});

test("peek mode has its own density and visual rhythm", () => {
  assert.match(styles, /\.widget\.peek\s*\{[^\}]*width: 326px;/);
  assert.match(styles, /\.widget\.peek \.header\s*\{[\s\S]*height: 64px;[\s\S]*grid-template-columns: minmax\(0, 1fr\);/);
  assert.match(styles, /\.peek-ticker\s*\{[\s\S]*display: none;/);
  assert.match(styles, /\.widget\.peek \.peek-ticker\s*\{[\s\S]*display: grid;/);
  assert.match(styles, /\.peek-title\s*\{[\s\S]*text-overflow: ellipsis;/);
  assert.match(styles, /\.peek-detail\s*\{[\s\S]*text-overflow: ellipsis;/);
  assert.match(styles, /\.peek-ticker\.waiting\s*\{/);
});

test("peek mode renders as an independent compact row-native card instead of a stretched header", () => {
  assert.match(html, /<div class="peek-card" data-peek-card>/);
  assert.match(html, /<span class="peek-kind" data-peek-kind><\/span>/);
  assert.match(html, /<span class="peek-badge" data-peek-badge><\/span>/);
  assert.match(html, /<span class="peek-meta peek-stats" data-peek-meta><\/span>/);
  assert.match(html, /function peekKindLabel\(kind\)/);
  assert.match(html, /kind\.textContent = item \? peekKindLabel\(item\.kind\) : ""/);
  assert.match(html, /badge\.textContent = item \? \(item\.display_label \|\| ""\) : ""/);
  assert.match(html, /renderPeekMeta\(meta, header\)/);
  assert.match(styles, /\.widget\.peek \.header\s*\{[\s\S]*height: 64px;[\s\S]*grid-template-columns: minmax\(0, 1fr\);/);
  assert.match(styles, /\.widget\.peek \.loader-slot,\s*\.widget\.peek \.header-counts\s*\{[\s\S]*display: none;/);
  assert.match(styles, /\.peek-card\s*\{[\s\S]*grid-template-columns: 24px 34px minmax\(0, 1fr\) auto;[\s\S]*column-gap: 10px;[\s\S]*row-gap: 7px;/);
  assert.match(styles, /\.peek-kind\s*\{[\s\S]*border-radius: 999px;/);
  assert.match(styles, /\.peek-badge\s*\{[\s\S]*background: var\(--badge-active-bg\);/);
  assert.match(styles, /\.peek-ticker\.finished \.peek-kind/);
});

test("peek header is a standalone component with no borrowed count cluster", () => {
  assert.match(styles, /\.widget\.peek \.peek-ticker\s*\{[\s\S]*grid-row: 1;/);
  assert.match(styles, /\.widget\.peek \.peek-ticker\s*\{[\s\S]*grid-column: 1;/);
  assert.doesNotMatch(styles, /\.widget\.peek \.header-counts\s*\{[\s\S]{0,120}grid-column: 3;/);
  assert.doesNotMatch(styles, /\.widget\.peek \.loader-slot\s*\{[\s\S]{0,120}grid-column: 1;/);
});

test("peek card keeps local identity separate from global counts", () => {
  assert.match(state, /local function peekTitle\(name\)/);
  assert.match(state, /title = peekTitle\(name\),/);
  assert.doesNotMatch(state, /label \.\. " " \.\. name/);
  assert.match(html, /<span class="peek-copy">[\s\S]*<span class="peek-title" data-peek-title><\/span>[\s\S]*<span class="peek-detail" data-peek-detail><\/span>[\s\S]*<\/span>\s*<span class="peek-meta peek-stats" data-peek-meta><\/span>/);
  assert.match(styles, /\.peek-card\s*\{[\s\S]*grid-template-columns: 24px 34px minmax\(0, 1fr\) auto;[\s\S]*column-gap: 10px;[\s\S]*row-gap: 7px;/);
  assert.match(styles, /\.peek-meta\s*\{[\s\S]*justify-self: end;/);
});

test("peek global counts render as colored stat pills instead of monotone text", () => {
  assert.match(html, /function renderPeekMeta\(meta, header\)/);
  assert.match(html, /var activeTotal = \(header\.activeCount \|\| 0\) \+ \(header\.waitingCount \|\| 0\);/);
  assert.match(html, /meta\.setAttribute\("title", String\(activeTotal\) \+ " active, " \+ String\(doneTotal\) \+ " done"\)/);
  assert.match(html, /class="peek-stat peek-stat-active"/);
  assert.match(html, /class="peek-stat peek-stat-done"/);
  assert.match(html, /class="peek-stat-icon" aria-hidden="true">&#9679;<\/span>/);
  assert.match(html, /class="peek-stat-icon" aria-hidden="true">&#10003;<\/span>/);
  assert.match(styles, /\.peek-stats\s*\{[\s\S]*display: inline-flex;/);
  assert.match(styles, /\.peek-stat\s*\{[\s\S]*border-radius: 999px;/);
  assert.match(styles, /\.peek-stat-active\s*\{[\s\S]*color: var\(--active-blue\);/);
  assert.match(styles, /\.peek-stat-done\s*\{[\s\S]*color: var\(--completed-green\);/);
});

test("peek running marker uses the same cycling loader animation as active work", () => {
  assert.match(html, /function renderLoaderInto\(slot, loader\)/);
  assert.match(html, /function renderPeekKind\(kind, item, header\)/);
  assert.match(html, /if \(item && item\.kind === "running"\) \{/);
  assert.match(html, /renderLoaderInto\(kind, peekLoader\)/);
  assert.match(html, /setClass\(kind, "is-loader", true\)/);
  assert.match(html, /applyPeekItem\(currentPeekItem\(lastPeekHeader\), lastPeekHeader\)/);
  assert.match(styles, /\.peek-kind\.is-loader\s*\{[\s\S]*background: transparent;/);
  assert.match(styles, /\.peek-kind\.is-loader > \*\s*\{[\s\S]*filter: drop-shadow/);
});

test("peek running marker preserves loader DOM across one-second state refreshes", () => {
  assert.match(html, /function clearPeekKind\(kind\)/);
  assert.match(html, /function renderPeekLoader\(kind, header\)/);
  assert.match(html, /if \(kind\.getAttribute\("data-peek-kind-mode"\) !== "running"\) \{/);
  assert.match(html, /kind\.setAttribute\("data-peek-kind-mode", "running"\)/);
  assert.match(html, /renderLoaderInto\(kind, peekLoader\)/);
  assert.doesNotMatch(html, /function renderPeekKind\(kind, item, header\) \{[\s\S]{0,220}kind\.innerHTML = "";/);
  assert.doesNotMatch(html, /function renderPeekKind\(kind, item, header\) \{[\s\S]{0,260}kind\.removeAttribute\("data-loader-variant"\);/);
});

test("peek hover reveals recent finished history without auto-expanding", () => {
  assert.match(state, /local function buildPeekHistory\(completedRows, events\)/);
  assert.match(state, /if #history >= PEEK_HISTORY_MAX_ITEMS then break end/);
  assert.match(state, /history = buildPeekHistory\(recentCompletedRows, input\.events\),/);
  assert.match(state, /local peekHover = \(input\.peekHover == true or input\.peekPinned == true\) and viewMode == "peek"/);
  assert.match(state, /peekHover = peekHover,/);
  assert.match(html, /function renderPeekHistory\(header\)/);
  assert.match(html, /<section class="peek-history" data-peek-history/);
  assert.match(html, /<div class="peek-history-list" data-peek-history-list><\/div>/);
  assert.match(html, /<div class="peek-actions" data-peek-actions><\/div>/);
  assert.doesNotMatch(html, /peek-expand-button/);
  assert.doesNotMatch(html, /"Expand full status"/);
  assert.match(html, /history\.forEach\(function\(item\)/);
  assert.doesNotMatch(html, /history\.slice\(0, 3\)/);
  assert.match(styles, /\.peek-history\s*\{[\s\S]*display: grid;[\s\S]*opacity: 0;[\s\S]*transform: translateY\(-6px\);[\s\S]*pointer-events: none;/);
  assert.match(styles, /\.widget\.peek\.peek-hovering \.peek-history,\s*\.widget\.peek:focus-within \.peek-history\s*\{[\s\S]*opacity: 1;[\s\S]*transform: translateY\(0\);[\s\S]*pointer-events: auto;/);
  assert.match(styles, /\.peek-history-list\s*\{[\s\S]*max-height: 244px;[\s\S]*overflow-y: auto;/);
  assert.match(styles, /@media \(prefers-reduced-motion: reduce\)[\s\S]*\.peek-history[\s\S]*transition: none;/);
});

test("peek primary click focuses zellij without opening the dormant detail view", () => {
  assert.match(html, /var peekTarget = closestTarget\(event\.target, "\.peek-ticker"\);/);
  assert.match(html, /type: eventId \? "event\.focus" : "row\.focus"/);
  assert.match(html, /if \(widget && widget\.classList\.contains\("peek"\)\) return false;/);
  assert.doesNotMatch(html, /var header = closestTarget\(event\.target, "\.header"\);[\s\S]{0,120}requestExpand\(\)/);
  assert.match(html, /function handleWidgetHover\(hovering, event\)/);
  assert.match(html, /document\.addEventListener\("mouseover", function\(event\)/);
  assert.match(html, /document\.addEventListener\("mouseout", function\(event\)/);
  assert.match(html, /var related = event && event\.relatedTarget;/);
  assert.match(html, /if \(widget && related && widget\.contains\(related\)\) return;/);
  assert.match(html, /postAction\(\{ type: "peek\.hover\.set", hovering: hovering \}\);/);
  assert.match(html, /handleWidgetHover\(true, event\);/);
  assert.match(html, /handleWidgetHover\(false, event\);/);
  assert.match(html, /button\.setAttribute\("data-action", action\)/);
  assert.match(html, /button\.setAttribute\("aria-label", label\)/);
  assert.doesNotMatch(html, /ensurePeekActionButton\(peekActions, "peek-expand-button"/);
  assert.match(webview, /local peekHover = false/);
  assert.match(webview, /body\.type == "peek\.hover\.set"/);
  assert.match(webview, /peekHover = body\.hovering == true/);
  assert.match(webview, /peekHover = false/);
  assert.match(webview, /peekHover = peekHover,/);
  assert.match(webview, /refreshWebview\(\)/);
  assert.match(webview, /if viewMode == "compact" or viewMode == "peek" then[\s\S]*debugLog\("ignored compact\/peek native click expand"\)/);
  assert.match(readFileSync(new URL("./webview/bridge.lua", import.meta.url), "utf8"), /\["peek\.hover\.set"\] = true/);
});

test("peek hover is also tracked by native Hammerspoon mouse movement", () => {
  assert.match(webview, /local function updateNativeHover\(pos\)/);
  assert.match(webview, /event\.types\.mouseMoved/);
  assert.match(webview, /local nextPeekHover = not expanded and not peekPinned and viewMode == "peek" and pointInFrame\(pos, webview:frame\(\)\)/);
  assert.match(webview, /if nextPeekHover ~= peekHover then/);
  assert.match(webview, /debugLog\("native peek hover="/);
  assert.match(webview, /if refreshWebview then refreshWebview\(\) end/);
});

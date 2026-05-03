import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const state = readFileSync(new URL("./webview/state.lua", import.meta.url), "utf8");
const html = [
  "./webview/html.lua",
  "./webview/views/shared.lua",
  "./webview/views/mini.lua",
  "./webview/views/peek.lua",
  "./webview/views/detail.lua",
].map((file) => readFileSync(new URL(file, import.meta.url), "utf8")).join("\n");
const styles = readFileSync(new URL("./webview/styles.lua", import.meta.url), "utf8");

test("peek state exposes active queue metadata for primary plus compact stack", () => {
  assert.match(state, /local PEEK_ACTIVE_STACK_MAX_ITEMS = 3/);
  assert.match(state, /local function buildPeekActiveQueue\(peekItems\)/);
  assert.match(state, /primary = peekItems\[1\]/);
  assert.match(state, /table\.insert\(stack, peekItems\[i\]\)/);
  assert.match(state, /overflow = math\.max\(#peekItems - 1 - PEEK_ACTIVE_STACK_MAX_ITEMS, 0\)/);
  assert.match(state, /activeQueue = buildPeekActiveQueue\(peekItems\),/);
});

test("peek markup has a dedicated active stack under the primary ticker", () => {
  assert.match(html, /<div class="peek-active-stack" data-peek-active-stack><\/div>/);
  assert.match(html, /function renderPeekActiveStack\(header, primaryItem\)/);
  assert.match(html, /row\.className = "peek-active-stack-row depth-" \+ String\(index \+ 1\) \+ " "/);
  assert.match(html, /data-peek-active-stack-overflow/);
  assert.match(html, /var activeStackTarget = closestTarget\(event\.target, "\.peek-active-stack-row"\)/);
});

test("peek rotation animates primary changes and reorders the visible active stack", () => {
  assert.match(html, /var PEEK_ROTATE_INTERVAL_MS = 10000/);
  assert.match(html, /var PEEK_PRIMARY_TRANSITION_MS = 420/);
  assert.match(html, /function rotatePeekPrimary\(\)/);
  assert.match(html, /setClass\(ticker, "is-rotating-out", true\)/);
  assert.match(html, /window\.setTimeout\(function\(\) \{[\s\S]*applyPeekItem\(currentPeekItem\(lastPeekHeader\), lastPeekHeader\)[\s\S]*setClass\(ticker, "is-rotating-in", true\)/);
  assert.match(html, /if \(peek\.hovering \|\| peek\.hoverPinned\) return;/);
  assert.match(html, /renderPeekActiveStack\(header, item\)/);
});

test("peek active stack uses transform-only animation and compact queue styling", () => {
  assert.match(styles, /\.peek-active-stack\s*\{[\s\S]*display: grid;[\s\S]*gap: 4px;/);
  assert.match(styles, /\.peek-active-stack-row\s*\{[\s\S]*min-height: 25px;[\s\S]*grid-template-columns: 30px minmax\(0, 1fr\) auto;/);
  assert.match(html, /row\.className = "peek-active-stack-row depth-" \+ String\(index \+ 1\) \+ " "/);
  assert.match(styles, /\.peek-active-stack-row\.depth-2\s*\{[\s\S]*opacity: 0\.92;/);
  assert.match(styles, /\.peek-active-stack-row\.depth-3\s*\{[\s\S]*opacity: 0\.82;/);
  assert.match(styles, /\.peek-active-stack-overflow\s*\{[\s\S]*justify-self: center;/);
  assert.match(styles, /\.peek-ticker\.is-rotating-out \.peek-card\s*\{[\s\S]*transform: translateY\(-5px\);[\s\S]*opacity: 0;/);
  assert.match(styles, /\.peek-ticker\.is-rotating-in \.peek-card\s*\{[\s\S]*animation: peekPrimaryIn 420ms/);
  assert.match(styles, /@keyframes peekPrimaryIn[\s\S]*translateY\(5px\)[\s\S]*translateY\(0\)/);
  assert.match(styles, /@media \(prefers-reduced-motion: reduce\)[\s\S]*\.peek-ticker\.is-rotating-in \.peek-card[\s\S]*animation: none;/);
});

test("peek active queue uses one subtle divider before finished history", () => {
  assert.match(html, /<div class="peek-queue-divider" data-peek-queue-divider><span class="peek-section-label">Recently active<\/span><\/div>/);
  assert.match(html, /function renderPeekQueueDivider\(header\)/);
  assert.match(html, /var hasActive = activePeekItems\(header\)\.length > 0;/);
  assert.match(html, /setClass\(divider, "visible", hasActive && hasHistory\)/);
  assert.match(html, new RegExp("divider\\.innerHTML = '<span class=\"peek-section-label\">Older finished</span>';"));
  assert.match(styles, /\.peek-queue-divider\s*\{[\s\S]*height: 14px;[\s\S]*display: flex;[\s\S]*align-items: center;[\s\S]*border-top: 0;/);
  assert.match(styles, /\.peek-queue-divider::before,\s*\.peek-queue-divider::after\s*\{[\s\S]*border-top: 1px dashed rgba\(255, 255, 255, 0\.18\);/);
  assert.match(styles, /\.peek-section-label\s*\{[^}]*font-size: 8\.5px;[^}]*line-height: 10px;/);
  assert.match(styles, /\.peek-queue-divider\.visible\s*\{[\s\S]*opacity: 1;/);
  assert.match(styles, /\.widget\.peek:not\(\.peek-hovering\):not\(:focus-within\) \.peek-queue-divider::before,\s*\.widget\.peek:not\(\.peek-hovering\):not\(:focus-within\) \.peek-queue-divider::after\s*\{[\s\S]*border-top-color: transparent;/);
});

test("peek history owns recent and older finished tiers behind the older toggle", () => {
  assert.match(state, /local RECENT_FINISHED_WINDOW_SECONDS = 3600/);
  assert.match(state, /local olderExpanded = input\.olderFinishedExpanded == true and \(input\.expanded == true or viewMode == "peek"\)/);
  assert.match(state, /history = buildPeekHistory\(recentCompletedRows, input\.events, "recent-finished"\)/);
  assert.match(state, /olderHistory = buildPeekHistory\(olderCompletedRows, input\.events, "older-finished"\)/);
  assert.match(state, /olderFinished = \{[^\}]*count = #olderCompletedRows[\s\S]*expanded = olderExpanded[\s\S]*label = "Older finished"/);
  assert.match(html, /function renderPeekOlderFinishedControl\(peek\)/);
  assert.match(html, /data-peek-older-finished/);
  assert.match(html, /setClass\(peekActions, "has-older-toggle", !!olderControl\)/);
  assert.match(html, /function renderPeekActions\(state\)[\s\S]*var olderControl = renderPeekOlderFinishedControl\(peek\);[\s\S]*if \(olderControl\) peekActions\.appendChild\(olderControl\);/);
  assert.doesNotMatch(html, /renderPeekHistory\(header\)[\s\S]*var olderControl = renderPeekOlderFinishedControl\(peek\);[\s\S]*list\.appendChild\(olderControl\);/);
  assert.match(html, /renderPeekHistoryRow\(item, !!peek\.editMode\)/);
  assert.match(html, /function renderPeekHistoryRow\(item, editMode\)[\s\S]*peek-history-status/);
  assert.match(html, /if \(peek\.olderFinished && peek\.olderFinished\.expanded\) \{[\s\S]*olderHistory\.forEach/);
  assert.match(styles, /\.peek-history-row\s*\{[\s\S]*grid-template-columns: 30px minmax\(0, 1fr\) max-content;/);
  assert.match(styles, /\.peek-history-row\.edit-mode\s*\{[\s\S]*grid-template-columns: 34px minmax\(0, 1fr\) auto 24px;/);
  assert.match(styles, /\.peek-history-status\s*\{[\s\S]*justify-self: end;[\s\S]*font-variant-numeric: tabular-nums;/);
  assert.match(styles, /\.peek-history-row\.older-finished\s*\{[\s\S]*opacity: 0\.78;/);
  assert.match(state, /local PEEK_ACTION_WITH_OLDER_TOGGLE_HEIGHT = 54/);
  assert.match(state, /local actionHeight = PEEK_ACTION_HEIGHT[\s\S]*if olderFinished\.count and olderFinished\.count > 0 then[\s\S]*actionHeight = PEEK_ACTION_WITH_OLDER_TOGGLE_HEIGHT/);
  assert.match(state, /height = height \+ PEEK_HISTORY_SECTION_GAP \+ actionHeight/);
});

test("closed peek removes reveal-only sections from layout so the primary card stays vertically centered", () => {
  assert.match(styles, /\.widget\.peek \.header\s*\{[\s\S]*height: 64px;[\s\S]*align-content: center;/);
  assert.match(styles, /\.widget\.peek\.peek-hovering \.header,\s*\.widget\.peek:focus-within \.header\s*\{[\s\S]*align-content: start;/);
  assert.match(styles, /\.widget\.peek:not\(\.peek-hovering\):not\(:focus-within\) \.peek-active-stack,\s*\.widget\.peek:not\(\.peek-hovering\):not\(:focus-within\) \.peek-queue-divider,\s*\.widget\.peek:not\(\.peek-hovering\):not\(:focus-within\) \.peek-history\s*\{[\s\S]*display: none;/);
});

test("peek primary loader has enough spacing to breathe beside the tab badge", () => {
  assert.match(styles, /\.peek-card\s*\{[\s\S]*grid-template-columns: 24px 34px minmax\(0, 1fr\) auto;[\s\S]*column-gap: 10px;[\s\S]*padding: 5px 8px 5px 10px;/);
  assert.match(styles, /\.peek-kind\s*\{[\s\S]*width: 24px;[\s\S]*height: 24px;[\s\S]*line-height: 24px;/);
  assert.match(styles, /\.peek-kind\.is-loader > \*\s*\{[\s\S]*max-width: 20px;[\s\S]*max-height: 20px;/);
});

test("peek keeps the badge-to-title gap tighter than the loader-to-badge gap", () => {
  assert.match(styles, /\.peek-card\s*\{[\s\S]*grid-template-columns: 24px 34px minmax\(0, 1fr\) auto;[\s\S]*column-gap: 10px;/);
  assert.match(styles, /\.peek-badge\s*\{[\s\S]*margin-right: -6px;/);
});

test("peek finished rows are visually secondary to the active primary row", () => {
  assert.match(styles, /\.peek-title\s*\{[^}]*font-weight: 700;/);
  assert.match(styles, /\.peek-history-title\s*\{[^}]*font-weight: 500;/);
  assert.match(styles, /\.peek-history-status\s*\{[^}]*font-weight: 600;/);
});

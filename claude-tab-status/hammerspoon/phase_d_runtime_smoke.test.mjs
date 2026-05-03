import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const webview = readFileSync(
  new URL("./claude-status-webview.lua", import.meta.url),
  "utf8",
);
const html = readFileSync(new URL("./webview/html.lua", import.meta.url), "utf8");
const state = readFileSync(new URL("./webview/state.lua", import.meta.url), "utf8");
const styles = readFileSync(new URL("./webview/styles.lua", import.meta.url), "utf8");

function cssBlock(selector) {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = styles.match(new RegExp(`\\n    ${escaped} \\{([\\s\\S]*?)\\n    \\}`));
  assert.ok(match, `missing CSS block for ${selector}`);
  return match[1];
}

test("webview module bootstraps helper package path before requiring helpers", () => {
  const bootstrapIndex = webview.indexOf("bootstrapHelperPackagePath()");
  const helperRequireIndex = webview.indexOf('require("webview.html")');

  assert.notEqual(bootstrapIndex, -1);
  assert.notEqual(helperRequireIndex, -1);
  assert.ok(bootstrapIndex < helperRequireIndex);
  assert.match(webview, /debug\.getinfo\(1, "S"\)\.source/);
  assert.match(webview, /hs\.fs\.symlinkAttributes\(sourcePath\)/);
  assert.match(webview, /attrs and attrs\.target/);
  assert.ok(
    webview.includes(
      'package.path = helperRoot .. "/?.lua;" .. helperRoot .. "/?/init.lua;" .. package.path',
    ),
  );
});

test("policy callback intercepts bridge URLs before macOS handles the custom scheme", () => {
  assert.match(webview, /action ~= "navigationAction" and action ~= "newWindow"/);
  assert.match(webview, /local function requestUrlFromPolicyRequest\(request\)/);
  assert.match(webview, /local function findRequestUrl\(value, depth\)/);
  assert.match(webview, /return findRequestUrl\(request, 0\)/);
  assert.match(webview, /local url = requestUrlFromPolicyRequest\(request\)/);
  assert.match(webview, /local payload = bridgePayloadFromUrl\(url\)/);
  assert.match(webview, /return false/);
});

test("collapsed generic header clicks are disabled while explicit controls stay controlled", () => {
  assert.match(html, /function requestExpand\(\)/);
  assert.doesNotMatch(html, /postAction\(\{ type: "expand\.set", expanded: true \}\)/);
  assert.match(html, /if \(action === "expand\.toggle"\) \{[\s\S]*postAction\(\{ type: "expand\.toggle" \}\)/);
  assert.match(html, /else if \(action === "settings\.toggle"\) \{[\s\S]*postAction\(\{ type: "settings\.toggle" \}\)/);
  assert.match(html, /if \(widget && widget\.classList\.contains\("compact"\)\) return false;/);
  assert.match(html, /if \(widget && widget\.classList\.contains\("peek"\)\) return false;/);
  assert.doesNotMatch(html, /var header = closestTarget\(event\.target, "\.header"\)/);
  assert.doesNotMatch(html, /if \(header && requestExpand\(\)\) return;/);
});

test("dynamic frame height includes rendered panel spacing instead of clipping rows", () => {
  assert.match(state, /local PANEL_TOP_PADDING = \d+/);
  assert.match(state, /local PANEL_BOTTOM_PADDING = \d+/);
  assert.match(state, /local ROW_GAP = 3/);
  assert.match(state, /local ACTIVE_ROW_HEIGHT = 28/);
  assert.match(state, /local COMPLETED_ROW_HEIGHT = 24/);
  assert.match(state, /local DIVIDER_HEIGHT = 16/);
  assert.match(state, /local BORDER_SHADOW_SAFETY = \d+/);
  assert.match(state, /local MAX_FRAME_HEIGHT = \d+/);
  assert.match(state, /height = height \+ PANEL_TOP_PADDING \+ PANEL_BOTTOM_PADDING/);
  assert.match(state, /height = height \+ HEADER_HEIGHT/);
  assert.match(state, /height = height \+ \(\#sections\.activeRows \* \(ACTIVE_ROW_HEIGHT \+ ROW_GAP\)\)/);
  assert.match(state, /height = height \+ \(\#sections\.completedRows \* \(COMPLETED_ROW_HEIGHT \+ ROW_GAP\)\)/);
  assert.match(state, /if sections\.showDivider then[\s\S]*height = height \+ DIVIDER_HEIGHT/);
  assert.doesNotMatch(state, /if sections\.settings and sections\.settings\.open then/);
  assert.match(state, /height = height \+ BORDER_SHADOW_SAFETY/);
  assert.match(state, /height = math\.min\(height, MAX_FRAME_HEIGHT\)/);
});

test("CSS leaves content overflow to frame sizing instead of clipping rows inside the panel", () => {
  const widget = cssBlock(".widget");
  const rows = cssBlock(".rows");

  assert.doesNotMatch(widget, /overflow: hidden;/);
  assert.match(widget, /overflow: visible;/);
  assert.match(rows, /overflow: visible;/);
});

import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";

const baselineUrl = new URL(
  "./archive/claude-status-canvas-baseline-2026-05-02.lua",
  import.meta.url,
);
const webviewUrl = new URL("./claude-status-webview.lua", import.meta.url);
const helperUrls = {
  html: new URL("./webview/html.lua", import.meta.url),
  styles: new URL("./webview/styles.lua", import.meta.url),
  state: new URL("./webview/state.lua", import.meta.url),
  bridge: new URL("./webview/bridge.lua", import.meta.url),
};
const statusDocUrl = new URL(
  "../../docs/plans/2026-05-01-hammerspoon-webview-port-status.md",
  import.meta.url,
);
const designDocUrl = new URL(
  "../../docs/superpowers/specs/2026-05-02-hammerspoon-webview-parity-design.md",
  import.meta.url,
);

const webviewSource = readFileSync(webviewUrl, "utf8");
const statusDoc = readFileSync(statusDocUrl, "utf8");
const designDoc = readFileSync(designDocUrl, "utf8");

test("canvas baseline archive exists and remains documented", () => {
  assert.equal(existsSync(baselineUrl), true);
  const baseline = readFileSync(baselineUrl, "utf8");
  assert.match(baseline, /claude-status\.lua/);
  assert.match(statusDoc, /archive\/claude-status-canvas-baseline-2026-05-02\.lua/);
  assert.match(designDoc, /archive\/claude-status-canvas-baseline-2026-05-02\.lua/);
});

test("production webview delegates rendering structure to focused helper modules", () => {
  for (const url of Object.values(helperUrls)) {
    assert.equal(existsSync(url), true);
  }
  assert.match(webviewSource, /local webviewHtml = require\("webview\.html"\)/);
  assert.match(webviewSource, /local webviewStyles = require\("webview\.styles"\)/);
  assert.match(webviewSource, /local webviewState = require\("webview\.state"\)/);
  assert.match(webviewSource, /local webviewBridge = require\("webview\.bridge"\)/);
  assert.match(webviewSource, /webviewHtml\.build\(\{[\s\S]*styles = webviewStyles\.css\(\)/);
  assert.doesNotMatch(webviewSource, /local html = \[\[/);
});

test("helper module responsibilities are explicit", () => {
  const html = readFileSync(helperUrls.html, "utf8");
  const styles = readFileSync(helperUrls.styles, "utf8");
  const state = readFileSync(helperUrls.state, "utf8");
  const bridge = readFileSync(helperUrls.bridge, "utf8");

  assert.match(html, /function M\.build\(options\)/);
  assert.match(styles, /function M\.css\(\)/);
  assert.match(state, /function M\.build\(input\)/);
  assert.match(bridge, /function M\.normalizeMessage\(message, handlers\)/);
});

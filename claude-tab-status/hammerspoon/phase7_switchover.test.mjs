import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const loader = readFileSync(
  new URL("./claude-status-loader.lua", import.meta.url),
  "utf8",
);
const webview = readFileSync(
  new URL("./claude-status-webview.lua", import.meta.url),
  "utf8",
);
const canvas = readFileSync(
  new URL("./claude-status.lua", import.meta.url),
  "utf8",
);
const demo = readFileSync(new URL("./webview-demo.lua", import.meta.url), "utf8");
const statusDoc = readFileSync(
  new URL("../../docs/plans/2026-05-01-hammerspoon-webview-port-status.md", import.meta.url),
  "utf8",
);

test("loader has an explicit default renderer and selects webview by default", () => {
  assert.match(loader, /local STATUS_RENDERER = "webview"/);
  assert.match(loader, /local RENDERER_SETTINGS_KEY = "claudeStatus\.renderer"/);
  assert.match(loader, /local RENDERERS = \{[\s\S]*webview = "claude-status-webview"[\s\S]*canvas = "claude-status"[\s\S]*\}/);
  assert.match(loader, /return STATUS_RENDERER/);
});

test("loader keeps canvas fallback available without changing either renderer module", () => {
  assert.match(loader, /require\(moduleName\)/);
  assert.match(loader, /rendererName == "canvas"/);
  assert.match(loader, /function M\.start\(\)/);
  assert.match(loader, /function M\.stop\(\)/);
  assert.match(loader, /function M\.toggle\(\)/);
  assert.match(webview, /return M/);
  assert.match(canvas, /return M/);
});

test("webview demo remains clearly marked as demo-only", () => {
  assert.match(demo, /DEMO ONLY/);
  assert.match(demo, /not production code/);
});

test("status document records final switchover decisions and manual smoke checklist", () => {
  assert.match(statusDoc, /Status: Completed\. Manual Hammerspoon smoke test pending\./);
  assert.match(statusDoc, /Default UI decision: webview is the default renderer/);
  assert.match(statusDoc, /Canvas fallback: set `claudeStatus\.renderer` to `canvas`/);
  assert.match(statusDoc, /Load webview renderer in Hammerspoon/);
  assert.match(statusDoc, /Confirm behavior on at least two normal desktop Spaces/);
  assert.match(statusDoc, /Do not claim full runtime success until manual Hammerspoon smoke testing is complete/);
});

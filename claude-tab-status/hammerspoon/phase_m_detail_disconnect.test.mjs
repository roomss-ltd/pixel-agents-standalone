import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";

const webview = readFileSync(new URL("./claude-status-webview.lua", import.meta.url), "utf8");
const state = readFileSync(new URL("./webview/state.lua", import.meta.url), "utf8");
const html = readFileSync(new URL("./webview/html.lua", import.meta.url), "utf8");
const detailUrl = new URL("./webview/views/detail.lua", import.meta.url);

test("detail view remains archived but disabled by default", () => {
  assert.equal(existsSync(detailUrl), true);
  assert.match(webview, /local DETAIL_VIEW_ENABLED = false/);
  assert.match(webview, /local function canOpenDetailView\(\)/);
});

test("normal bridge actions cannot enter the dormant detail view", () => {
  assert.match(
    webview,
    /elseif body\.type == "expand\.toggle" then[\s\S]*if not canOpenDetailView\(\) then[\s\S]*return[\s\S]*end[\s\S]*expanded = not expanded/,
  );
  assert.match(
    webview,
    /elseif body\.type == "expand\.set" then[\s\S]*if body\.expanded == true and not canOpenDetailView\(\) then[\s\S]*return[\s\S]*end/,
  );
  assert.match(
    webview,
    /elseif body\.type == "pin\.toggle" then[\s\S]*if not canOpenDetailView\(\) then[\s\S]*return[\s\S]*end/,
  );
  assert.doesNotMatch(webview, /settings\.toggle" then[\s\S]{0,180}expanded = true/);
});

test("peek exposes mini options and pin actions but no detail expand action", () => {
  assert.match(
    html,
    /ensurePeekActionButton\(peekActions, "peek-minimize-toggle", "compact\.mode\.set"/,
  );
  assert.match(html, /ensurePeekActionButton\(peekActions, "peek-options-toggle", "settings\.toggle"/);
  assert.match(html, /ensurePeekActionButton\(peekActions, "peek-pin-toggle", "peek\.pin\.toggle"/);
  assert.doesNotMatch(html, /peek-expand-button/);
  assert.doesNotMatch(html, /"Expand full status"/);
});

test("options sidecar is independent from the dormant detail view", () => {
  assert.match(webview, /local showSettings = shouldShow and settingsOpen/);
  assert.match(state, /local settingsOpen = input\.settingsOpen == true/);
  assert.match(state, /open = input\.settingsOpen == true/);
  assert.doesNotMatch(state, /open = input\.settingsOpen == true and input\.expanded == true/);
});

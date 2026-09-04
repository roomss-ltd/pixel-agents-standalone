import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const html = readFileSync(new URL("./webview/html.lua", import.meta.url), "utf8");
const bridge = readFileSync(new URL("./webview/bridge.lua", import.meta.url), "utf8");
const webview = readFileSync(new URL("./claude-status-webview.lua", import.meta.url), "utf8");

test("webview rows post controlled row.focus messages with pane and session identity", () => {
  assert.match(html, /"row\.focus": true/);
  assert.match(html, /el\.setAttribute\("data-tab-num", String\(row\.tab_num != null \? row\.tab_num : ""\)\)/);
  assert.match(html, /var clickedRow = closestTarget\(event\.target, "\.row"\)/);
  assert.match(html, /postAction\(\{\s*type: "row\.focus",\s*pane_id: clickedRow\.getAttribute\("data-pane-id"\),\s*_zj_session: clickedRow\.getAttribute\("data-zj-session"\),\s*tab_num: clickedRow\.getAttribute\("data-tab-num"\)\s*\}\)/);
  assert.match(html, /closestTarget\(event\.target, "\[data-action\], label, input, button"\)/);
});

test("Lua bridge accepts row.focus and pipes Focus hook event to the target Zellij session", () => {
  assert.match(bridge, /\["row\.focus"\] = true/);
  assert.match(webview, /local FOCUS_LOG_PATH = "\/tmp\/claude-status-webview-focus\.log"/);
  assert.match(webview, /local TERMINAL_APP = "Ghostty"/);
  assert.match(webview, /function focusSession\(zj_session, pane_id, tab_num\)/);
  assert.match(webview, /focusLog\("request session=" \.\. tostring\(zj_session\)/);
  assert.match(webview, /hs\.application\.launchOrFocus\(TERMINAL_APP\)/);
  assert.match(webview, /local tabCmd = string\.format\('zellij -s %q action go-to-tab %d', zj_session, tab_num\)/);
  assert.match(webview, /local payload = string\.format\('\{"hook_event":"Focus","pane_id":%d\}', pane_id\)/);
  assert.match(webview, /zellij -s %q pipe --name "agent-tab-status-v2" -- %q/);
  assert.match(webview, /elseif body\.type == "row\.focus" then\s*focusSession\(body\._zj_session, body\.pane_id, body\.tab_num\)/);
});

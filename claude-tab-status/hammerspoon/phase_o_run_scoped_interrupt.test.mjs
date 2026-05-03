import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const webview = readFileSync(new URL("./claude-status-webview.lua", import.meta.url), "utf8");
const html = readFileSync(new URL("./webview/html.lua", import.meta.url), "utf8");
const state = readFileSync(new URL("./webview/state.lua", import.meta.url), "utf8");
const rustState = readFileSync(new URL("../src/state.rs", import.meta.url), "utf8");
const eventHandler = readFileSync(new URL("../src/event_handler.rs", import.meta.url), "utf8");
const statusWriter = readFileSync(new URL("../src/status_writer.rs", import.meta.url), "utf8");
const interruptBody = webview.match(/function interruptSession\(zj_session, pane_id, run_id\)[\s\S]*?\nend\n\nfunction focusSession/)?.[0] ?? "";

test("Rust status contract emits a stable run_id that changes on user prompt submit", () => {
  assert.match(rustState, /pub run_id: String/);
  assert.match(rustState, /pub run_seq: u64/);
  assert.match(eventHandler, /fn next_run_id\([\s\S]*state: &mut PluginState,[\s\S]*pane_id: u32,[\s\S]*session_id: Option<&str>,[\s\S]*now: u64,[\s\S]*\) -> String/);
  assert.match(eventHandler, /event == "UserPromptSubmit" \|\| !session_exists/);
  assert.match(eventHandler, /session\.run_id = run_id/);
  assert.match(statusWriter, /\\"run_id\\":\\"{}\\"/);
  assert.match(statusWriter, /escape_json_string\(&session\.run_id\)/);
});

test("webview carries run_id through row identity and render state", () => {
  assert.match(webview, /run_id = s\.run_id/);
  assert.match(state, /run_id = row\.run_id/);
  assert.match(html, /run_id: row && row\.getAttribute\("data-run-id"\)/);
  assert.match(html, /setAttribute\("data-run-id", item && item\.run_id != null \? String\(item\.run_id\) : ""\)/);
  assert.match(html, /setAttribute\("data-run-id", String\(row\.run_id != null \? row\.run_id : ""\)\)/);
});

test("interrupt blocks only the current run_id and leaves new pane runs visible", () => {
  assert.match(webview, /local INTERRUPTED_RUNS_PATH = /);
  assert.match(webview, /local function addInterruptedRun\(run_id\)/);
  assert.match(webview, /local interruptedRuns = loadInterruptedRuns\(\)/);
  assert.match(webview, /local interruptedAt = interruptedRuns\[tostring\(s\.run_id or ""\)\]/);
  assert.match(webview, /local paneDenied = deny\[key\] and run_id == ""/);
  assert.match(webview, /if interruptedAt then[\s\S]*activity = "Done"[\s\S]*manual_state = "cancelled"/);
  assert.match(interruptBody, /if run_id and run_id ~= "" then[\s\S]*addInterruptedRun\(run_id\)[\s\S]*else[\s\S]*addToDenylist\(zj_session, pane_id\)/);
});

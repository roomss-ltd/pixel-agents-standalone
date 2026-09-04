import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const state = readFileSync(new URL("./state.rs", import.meta.url), "utf8");
const eventHandler = readFileSync(new URL("./event_handler.rs", import.meta.url), "utf8");
const manualInterruptBody = eventHandler.match(/if event == "ManualInterrupt" \{[\s\S]*?\n    \}\n\n    \/\/ Drop any other hook event/)?.[0] ?? "";

test("ManualInterrupt payload is run scoped so stale widget clicks cannot clear a newer run", () => {
  assert.match(state, /pub run_id: Option<String>/);
  assert.match(manualInterruptBody, /payload\.run_id\.as_deref\(\)\.unwrap_or\(""\)/);
  assert.match(manualInterruptBody, /payload_run_id\.is_empty\(\) \|\| payload_run_id == session\.run_id/);
});

test("ManualInterrupt marks the session done without dismissing the pane or renaming the tab", () => {
  assert.match(manualInterruptBody, /session\.activity = Activity::Done/);
  assert.match(manualInterruptBody, /session\.last_event_ts = now/);
  assert.match(manualInterruptBody, /status_writer::write_status_file\(state\)/);
  assert.doesNotMatch(manualInterruptBody, /rename_tab|update_tab_name/);
  assert.doesNotMatch(manualInterruptBody, /state\.sessions\.remove/);
  assert.doesNotMatch(manualInterruptBody, /dismissed_until\.insert/);
});

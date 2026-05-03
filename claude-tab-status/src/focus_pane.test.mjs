import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const eventHandler = readFileSync(new URL("./event_handler.rs", import.meta.url), "utf8");

test("Focus hook event focuses the target terminal pane without mutating status state", () => {
  assert.match(eventHandler, /use zellij_tile::prelude::focus_terminal_pane;/);
  assert.match(eventHandler, /if event == "Focus" \{[\s\S]*focus_terminal_pane\(payload\.pane_id, false\);[\s\S]*return;[\s\S]*\}/);
  assert.match(eventHandler, /if event == "Focus" \{[\s\S]*\}[\s\S]*if event == "Dismiss"/);
});

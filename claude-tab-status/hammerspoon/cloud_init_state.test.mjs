import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const webview = readFileSync(
  new URL("./claude-status-webview.lua", import.meta.url),
  "utf8",
);
const canvas = readFileSync(new URL("./claude-status.lua", import.meta.url), "utf8");

test("Cloud Init is a finished Hammerspoon state, not active work", () => {
  for (const source of [webview, canvas]) {
    assert.doesNotMatch(source, /a == "Thinking" or a == "Tool" or a == "Init"/);
    assert.match(source, /a == "Done" or a == "Idle" or a == "Init"/);
    assert.match(source, /if a == "Done" or a == "Idle" or a == "Init" then/);
  }
});

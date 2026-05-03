import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const webview = readFileSync(new URL("./claude-status-webview.lua", import.meta.url), "utf8");
const html = readFileSync(new URL("./webview/html.lua", import.meta.url), "utf8");
const state = readFileSync(new URL("./webview/state.lua", import.meta.url), "utf8");
const styles = readFileSync(new URL("./webview/styles.lua", import.meta.url), "utf8");

test("webview options no longer expose finish flash or processing neon toggles", () => {
  for (const source of [webview, html, state]) {
    assert.doesNotMatch(source, /completionFlash/);
    assert.doesNotMatch(source, /processingNeon/);
    assert.doesNotMatch(source, /Finish flash/);
    assert.doesNotMatch(source, /Processing neon/);
  }
});

test("webview renderer no longer applies finish flash or processing neon visuals", () => {
  for (const source of [webview, html, state, styles]) {
    assert.doesNotMatch(source, /widget-flashing/);
    assert.doesNotMatch(source, /completion-highlight/);
    assert.doesNotMatch(source, /processing-neon/);
  }
  assert.doesNotMatch(webview, /flashState/);
  assert.doesNotMatch(html, /__claudeStatusFlash/);
});

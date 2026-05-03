import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = readFileSync(
  new URL("./webview-demo.lua", import.meta.url),
  "utf8",
);

test("webview demo renders HTML/CSS in a floating Hammerspoon webview", () => {
  assert.match(source, /local M = \{\}/);
  assert.match(source, /hs\.webview\.new/);
  assert.match(source, /webview:html\(html\)/);
  assert.match(source, /webview:level\(hs\.canvas\.windowLevels\.floating\)/);
  assert.match(source, /webview:behavior\(hs\.canvas\.windowBehaviors\.canJoinAllSpaces\)/);
  assert.match(source, /webview:transparent\(true\)/);
});

test("webview demo shows CSS-driven widget controls", () => {
  assert.match(source, /<style>/);
  assert.match(source, /\.widget/);
  assert.match(source, /\.row\.waiting/);
  assert.match(source, /\.switch input:checked \+ \.track/);
  assert.match(source, /<button class="header-button"/);
  assert.match(source, /<section class="settings"/);
});

test("webview demo has start stop and toggle helpers for reload safety", () => {
  assert.match(source, /function M\.start\(\)/);
  assert.match(source, /function M\.stop\(\)/);
  assert.match(source, /function M\.toggle\(\)/);
  assert.match(source, /M\.stop\(\)/);
});

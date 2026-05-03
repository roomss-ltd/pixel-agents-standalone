import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const html = readFileSync(new URL("./webview/html.lua", import.meta.url), "utf8");
const styles = readFileSync(new URL("./webview/styles.lua", import.meta.url), "utf8");

test("header renderer uses compact canvas-style counts", () => {
  assert.doesNotMatch(html, /active 0/);
  assert.doesNotMatch(html, /waiting 0/);
  assert.doesNotMatch(html, /done 0/);
  assert.doesNotMatch(html, /"active " \+/);
  assert.doesNotMatch(html, /"wait " \+/);
  assert.doesNotMatch(html, /"done " \+/);

  assert.match(html, /class="count compact-count active-count"/);
  assert.match(html, /data-count="active"/);
  assert.match(html, /class="count compact-count completed-count"/);
  assert.match(html, /data-count="completed"/);
  assert.match(html, /class="count-icon"/);
  assert.match(html, /class="count-value"/);
});

test("mini counters use the same pill treatment as peek counters", () => {
  assert.match(styles, /\.compact-count\s*\{[\s\S]*height:\s*18px;[\s\S]*min-width:\s*28px;[\s\S]*border-radius:\s*999px;/);
  assert.match(styles, /\.active-count\s*\{[\s\S]*background:\s*rgba\(115,\s*166,\s*255,\s*0\.11\);[\s\S]*border-color:\s*rgba\(115,\s*166,\s*255,\s*0\.18\);/);
  assert.match(styles, /\.completed-count\s*\{[\s\S]*background:\s*rgba\(116,\s*204,\s*139,\s*0\.10\);[\s\S]*border-color:\s*rgba\(116,\s*204,\s*139,\s*0\.16\);/);
});

test("canvas-parity style tokens exist for the panel and rows", () => {
  assert.match(styles, /--panel-bg:\s*rgba\(23,\s*23,\s*34,\s*0\.94\)/);
  assert.match(styles, /--panel-border:\s*rgba\(128,\s*128,\s*148,\s*0\.55\)/);
  assert.match(styles, /--panel-radius:\s*12px/);
  assert.match(styles, /--active-row-height:\s*28px/);
  assert.match(styles, /--completed-row-height:\s*24px/);
  assert.match(styles, /--row-gap:\s*3px/);
  assert.match(styles, /--badge-active-bg:\s*rgba\(115,\s*166,\s*255,\s*0\.15\)/);
  assert.match(styles, /--badge-completed-bg:\s*rgba\(115,\s*210,\s*128,\s*0\.15\)/);
});

test("rows and divider match the subdued canvas hierarchy without a visible dismiss control", () => {
  assert.match(styles, /\.row\s*\{[\s\S]*height:\s*var\(--active-row-height\)/);
  assert.match(styles, /\.row\.completed-row\s*\{[\s\S]*height:\s*var\(--completed-row-height\)/);
  assert.match(styles, /\.row\.active-row\s*\{[\s\S]*background:\s*rgba\(115,\s*166,\s*255,\s*0\.12\)/);
  assert.match(styles, /\.row\.completed-row\s*\{[\s\S]*background:\s*rgba\(115,\s*210,\s*128,\s*0\.06\)/);
  assert.match(styles, /\.divider\s*\{[\s\S]*border-top:\s*1px dashed rgba\(255,\s*255,\s*255,\s*0\.50\)/);
  assert.match(styles, /grid-template-columns:\s*34px minmax\(0,\s*1fr\) 102px;/);
  assert.doesNotMatch(styles, /\.dismiss-button/);
  assert.doesNotMatch(html, /dismiss-button/);
});

test("row renderer keeps tab title and right status in separate canvas-like columns", () => {
  assert.match(html, /title\.innerHTML = escapeHtml\(row\.tab_name \|\| ""\)/);
  assert.match(html, /status\.innerHTML = escapeHtml\(statusText\)/);
  assert.match(html, /var statusText = statusIcon \+ \(statusDetail \? " " \+ statusDetail : " " \+ \(row\.activity \|\| "Init"\)\)/);
});

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const html = readFileSync(new URL("./webview/html.lua", import.meta.url), "utf8");
const styles = readFileSync(new URL("./webview/styles.lua", import.meta.url), "utf8");

test("processing rows get a declarative neon class only for active work", () => {
  assert.match(html, /function isProcessingActivity\(activity\)/);
  assert.match(html, /activity === "thinking" \|\| activity === "tool"/);
  assert.match(html, /var processingClass = isProcessingActivity\(activity\) \? "processing-neon" : "";/);
  assert.match(html, /\["row", className \|\| "", waitingClass, processingClass, activity\]\.join\(" "\)/);
});

test("peek card gets working state only for running agents", () => {
  assert.match(html, /setClass\(ticker, "working", !!item && item\.kind === "running"\)/);
  assert.doesNotMatch(html, /setClass\(ticker, "working", !!item && item\.kind === "finished"\)/);
  assert.doesNotMatch(html, /setClass\(ticker, "working", !!item && item\.kind === "idle"\)/);
});

test("styles add a static low-cost neon treatment without animated traces", () => {
  assert.match(styles, /\.row\.processing-neon,\s*\.peek-ticker\.working \.peek-card\s*\{/);
  assert.match(styles, /border-color: rgba\(139, 184, 255, 0\.52\);/);
  assert.match(styles, /box-shadow:[\s\S]*0 0 18px rgba\(70, 206, 255, 0\.10\)/);
  assert.doesNotMatch(styles, /\.row\.processing-neon::before/);
  assert.doesNotMatch(styles, /\.peek-ticker\.working \.peek-card::before/);
  assert.doesNotMatch(styles, /neon-trace-canvas/);
  assert.doesNotMatch(styles, /@keyframes processingNeonGlow/);
  assert.doesNotMatch(styles, /@keyframes processingNeonCornerPulse/);
  assert.doesNotMatch(styles, /animation: processingNeonGlow/);
  assert.doesNotMatch(styles, /conic-gradient/);
  assert.doesNotMatch(styles, /processingNeonOrbit/);
  assert.doesNotMatch(styles, /stroke-dasharray/);
  assert.doesNotMatch(styles, /stroke-dashoffset/);
  assert.doesNotMatch(styles, /neonTracePath/);
  assert.match(styles, /prefers-reduced-motion: reduce[\s\S]*\.row\.processing-neon/);
  assert.match(styles, /prefers-reduced-motion: reduce[\s\S]*\.peek-ticker\.working \.peek-card/);
});

test("renderer keeps processing neon static and does not create animation loops", () => {
  assert.doesNotMatch(html, /function appendNeonEdges\(element\)/);
  assert.doesNotMatch(html, /NEON_TRACE_DURATION_MS/);
  assert.doesNotMatch(html, /NEON_FRAME_INTERVAL_MS/);
  assert.doesNotMatch(html, /document\.createElement\("canvas"\)/);
  assert.doesNotMatch(html, /neon-trace-canvas/);
  assert.doesNotMatch(html, /startNeonCanvas/);
  assert.doesNotMatch(html, /requestAnimationFrame\(drawNeonFrame\)/);
  assert.doesNotMatch(html, /function roundedRectPoint/);
  assert.doesNotMatch(html, /function drawNeonSegment/);
  assert.doesNotMatch(html, /function neonTravelWindow/);
  assert.doesNotMatch(html, /var perimeterLength =/);
  assert.doesNotMatch(html, /var pulsePoints = \[\];/);
  assert.doesNotMatch(html, /function neonCircuitWindow/);
  assert.doesNotMatch(html, /rgba\(70, 220, 255, 0\.62\)/);
  assert.doesNotMatch(html, /createElementNS\("http:\/\/www\.w3\.org\/2000\/svg"/);
  assert.match(html, /var processingNeonEnabled = settings\.processingNeon !== false && widget && widget\.classList\.contains\("peek"\);/);
  assert.match(html, /var neonAttached = false;/);
  assert.match(html, /var processingNeonEnabled = settings\.processingNeon !== false && widget && widget\.classList\.contains\("expanded"\);/);
  assert.match(html, /if \(!processingNeonEnabled\) setClass\(card, "working", false\);/);
  assert.match(html, /var processingClass = processingNeonEnabled && isProcessingActivity\(activity\) && !neonAttached \? "processing-neon" : "";/);
  assert.match(html, /if \(processingClass\) neonAttached = true;/);
});

test("processing neon is controlled by persisted settings state", () => {
  const webview = readFileSync(new URL("./claude-status-webview.lua", import.meta.url), "utf8");
  const state = readFileSync(new URL("./webview/state.lua", import.meta.url), "utf8");

  assert.match(webview, /processingNeon = true/);
  assert.match(webview, /\{ key = "processingNeon", label = "Processing neon" \}/);
  assert.match(html, /VALID_SETTING_KEYS = \{[\s\S]*processingNeon: true/);
  assert.match(html, /data-setting="processingNeon"/);
  assert.match(html, /processingNeon: true/);
  assert.match(state, /processingNeon = input\.settings and input\.settings\.processingNeon/);
});

test("static neon does not add refresh-sensitive animation nodes", () => {
  assert.match(html, /rows\.innerHTML = "";/);
  assert.doesNotMatch(html, /Date\.now\(\) % NEON_TRACE_DURATION_MS/);
  assert.doesNotMatch(html, /animationDelay = "0s"/);
});

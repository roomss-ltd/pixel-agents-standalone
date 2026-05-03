import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const styles = readFileSync(new URL("./webview/styles.lua", import.meta.url), "utf8");
const icons = readFileSync(new URL("./webview/icons.lua", import.meta.url), "utf8");

function coffeeSteamKeyframes() {
  const match = styles.match(/@keyframes coffeeSteam\s*\{([\s\S]*?)\n    \}/);
  assert.ok(match, "coffeeSteam keyframes should exist");
  return match[1];
}

test("idle coffee steam rises vertically instead of drifting sideways", () => {
  const keyframes = coffeeSteamKeyframes();

  assert.match(keyframes, /transform:\s*translateY\(3px\);/);
  assert.match(keyframes, /transform:\s*translateY\(-9px\);/);
  assert.doesNotMatch(keyframes, /translateX\(/);
});

test("idle coffee steam wisps launch together without staggered delays", () => {
  assert.doesNotMatch(styles, /coffee-smoke-[23]\s*\{[\s\S]*?animation-delay:/);
});

test("idle coffee steam uses a slower shared rise animation", () => {
  assert.match(styles, /animation:\s*coffeeSteam 4\.8s ease-in-out infinite;/);
  assert.doesNotMatch(styles, /animation:\s*coffeeSteam 3\.6s ease-in-out infinite;/);
});

test("idle coffee steam can rise past the icon box without a hard top clip", () => {
  assert.match(styles, /\.coffee-idle-icon svg\s*\{[\s\S]*?overflow: visible;/);
  assert.match(styles, /78%\s*\{[\s\S]*?opacity: 0\.08;[\s\S]*?transform: translateY\(-7px\);/);
});

test("side coffee steam wisps are shorter from the top than the center wisp", () => {
  assert.match(icons, /coffee-smoke-1" d="M7\.1 7\.1C4\.2 5\.2 10\.1 5\.6 7\.4 4\.6/);
  assert.match(icons, /coffee-smoke-2" d="M11 7\.1C8\.1 5\.1 14 3\.9 11\.2 1\.3/);
  assert.match(icons, /coffee-smoke-3" d="M14\.9 7\.1C12 5\.2 17\.8 5\.6 15 4\.6/);
});

import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";

const webview = readFileSync(
  new URL("./claude-status-webview.lua", import.meta.url),
  "utf8",
);
const html = readFileSync(new URL("./webview/html.lua", import.meta.url), "utf8");
const doneSound = new URL(
  "./sounds/mixkit-correct-answer-tone-2870.wav",
  import.meta.url,
);

test("webview keeps status sounds owned by Hammerspoon Lua", () => {
  assert.match(webview, /local SOUND_ENABLED = true/);
  assert.match(
    webview,
    /local SOUND_DONE = \{ file = SOURCE_DIR \.\. "\/sounds\/mixkit-correct-answer-tone-2870\.wav" \}/,
  );
  assert.match(webview, /local SOUND_WAITING = \{ name = "Ping" \}/);
  assert.match(webview, /local SOUND_COOLDOWN = 0\.75/);
  assert.match(webview, /local WAITING_SOUND_REMINDER_INTERVAL = 30\.0/);
  assert.match(webview, /local function playStatusSound\(kind\)/);
  assert.match(webview, /if not SOUND_ENABLED or not settings\.soundsEnabled then return end/);
  assert.match(webview, /hs\.sound\.getByFile\(config\.file\)/);
  assert.match(webview, /hs\.sound\.getByName\(config\.name\)/);
  assert.equal(existsSync(doneSound), true);
  assert.doesNotMatch(html, /new Audio|AudioContext|\.play\(\)/);
});

test("webview plays sounds on real activity transitions", () => {
  assert.match(
    webview,
    /if prev and prev ~= activity then\s+if \(activity == "Done" or activity == "Idle"\) and \(prev == "Thinking" or prev == "Tool" or prev == "Waiting"\)/,
  );
  assert.match(webview, /playStatusSound\("done"\)/);
  assert.match(webview, /elseif activity == "Waiting" then\s+playStatusSound\("waiting"\)/);
});

test("webview repeats waiting reminder sounds while input is still needed", () => {
  assert.match(webview, /local function playWaitingReminderSound\(\)/);
  assert.match(webview, /if not settings\.waitingReminderSound then return end/);
  assert.match(webview, /if a == "Waiting" then hasWaiting = true; break end/);
  assert.match(
    webview,
    /if now - lastWaitingSoundAt >= WAITING_SOUND_REMINDER_INTERVAL then\s+playStatusSound\("waiting"\)/,
  );
  assert.match(webview, /playWaitingReminderSound\(\)/);
});

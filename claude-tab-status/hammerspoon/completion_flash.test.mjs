import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";

const source = readFileSync(
  new URL("./claude-status.lua", import.meta.url),
  "utf8",
);
const doneSound = new URL(
  "./sounds/Glass.wav",
  import.meta.url,
);

test("finish attention keeps existing flash and adds high-contrast metadata", () => {
  assert.match(source, /local FLASH_DURATION = 1\.5/);
  assert.match(source, /local COMPLETION_HIGHLIGHT_DURATION = 10\.0/);
  assert.match(source, /local FLASH_CAMERA = \{ red = 1, green = 1, blue = 1, alpha = 0\.55 \}/);
  assert.match(source, /local FLASH_COMPLETE = \{ red = 1, green = 1, blue = 1, alpha = 0\.92 \}/);
  assert.match(source, /local FLASH_INVERT_TEXT = \{ red = 0\.04, green = 0\.05, blue = 0\.06, alpha = 0\.96 \}/);
  assert.match(source, /local FLASH_POP_PIXELS = 8/);
  assert.match(
    source,
    /flashState\[id\] = \{ color = FLASH_GREEN, expires = now2 \+ COMPLETION_HIGHLIGHT_DURATION, duration = COMPLETION_HIGHLIGHT_DURATION, camera_expires = now2 \+ FLASH_DURATION, camera_duration = FLASH_DURATION \}/,
  );
});

test("finish attention animates whole widget flash and row pop while flash is active", () => {
  assert.match(source, /local function flashProgress/);
  assert.match(source, /local function flashPopProgress/);
  assert.match(source, /local function flashEaseOut/);
  assert.match(source, /local function drawWidgetFlash/);
  assert.match(source, /local function drawCompletionRowFlash/);
  assert.match(source, /strokeWidth = 2\.5/);
  assert.match(source, /drawWidgetFlash\(\)/);
  assert.match(source, /drawCompletionRowFlash\(rowX, y \+ 1, rowW, ROW_HEIGHT - 1, flash\)/);
  assert.match(source, /drawCompletionRowFlash\(8, y \+ 1, w - 16, ROW_HEIGHT_COMPACT - 1, flash\)/);
});

test("finish highlight inverts row text while active", () => {
  assert.match(source, /local nameColor = flash and FLASH_INVERT_TEXT or WHITE/);
  assert.match(source, /local statusColor = flash and FLASH_INVERT_TEXT or sc/);
  assert.match(source, /local compactNameColor = flash and FLASH_INVERT_TEXT or DIM_WHITE/);
  assert.match(source, /local compactStatusColor = flash and FLASH_INVERT_TEXT or sc/);
});

test("finish flash animates even after workers stop running", () => {
  assert.match(source, /local hasMotion = next\(flashState\) ~= nil/);
  assert.match(source, /cleanupExpiredFlashes\(\)/);
});

test("completed idle sessions stay rendered and counted", () => {
  assert.match(
    source,
    /if not deny\[key\] then\s+s\._zj_session = zj_session\s+table\.insert\(sessions, s\)/,
  );
  assert.match(source, /elseif a == "Done" or a == "Idle" or a == "Init" then/);
});

test("hammerspoon owns separate done and input sounds", () => {
  assert.match(source, /local SOUND_ENABLED = true/);
  assert.match(
    source,
    /local SOUND_DONE = \{ file = SOURCE_DIR \.\. "\/sounds\/Glass\.wav" \}/,
  );
  assert.match(source, /local SOUND_WAITING = \{ name = "Ping"/);
  assert.match(source, /local function playStatusSound\(kind\)/);
  assert.match(source, /hs\.sound\.getByFile\(config\.file\)/);
  assert.match(source, /hs\.sound\.getByName\(config\.name\)/);
  assert.equal(existsSync(doneSound), true);
});

test("sounds fire only on real transitions, not reload", () => {
  assert.match(
    source,
    /if prev and prev ~= activity then\s+if \(activity == "Done" or activity == "Idle"\)/,
  );
  assert.match(source, /playStatusSound\("done"\)/);
  assert.match(source, /elseif activity == "Waiting" then\s+playStatusSound\("waiting"\)/);
});

test("waiting rows pulse using the existing waiting color", () => {
  assert.match(source, /local WAITING_PULSE_PERIOD = 1\.6/);
  assert.match(source, /local function waitingPulseAlpha\(minAlpha, maxAlpha\)/);
  assert.match(source, /rowBg\(activity, waitingPulseAlpha\(0\.12, 0\.28\)\)/);
  assert.match(source, /rowBorder\(activity, waitingPulseAlpha\(0\.25, 0\.72\)\)/);
});

test("waiting pulse keeps animation timer alive", () => {
  assert.match(source, /if a == "Thinking" or a == "Tool" or \(a == "Waiting" and \(settings\.waitingPulse or settings\.waitingReminderSound\)\) then hasMotion = true; break end/);
});

test("waiting sound repeats periodically while input is still needed", () => {
  assert.match(source, /local WAITING_SOUND_REMINDER_INTERVAL = 30\.0/);
  assert.match(source, /local function playWaitingReminderSound\(\)/);
  assert.match(source, /if a == "Waiting" then hasWaiting = true; break end/);
  assert.match(source, /if now - lastWaitingSoundAt >= WAITING_SOUND_REMINDER_INTERVAL then\s+playStatusSound\("waiting"\)/);
  assert.match(source, /playWaitingReminderSound\(\)/);
});

test("settings drawer persists toggles through hammerspoon settings", () => {
  assert.match(source, /local SETTINGS_KEY = "claudeStatus\.settings"/);
  assert.match(source, /local DEFAULT_SETTINGS = \{/);
  assert.match(source, /soundsEnabled = true/);
  assert.match(source, /waitingReminderSound = true/);
  assert.match(source, /waitingPulse = true/);
  assert.match(source, /completionFlash = true/);
  assert.match(source, /local function loadSettings\(\)/);
  assert.match(source, /hs\.settings\.get\(SETTINGS_KEY\)/);
  assert.match(source, /local function saveSettings\(\)/);
  assert.match(source, /hs\.settings\.set\(SETTINGS_KEY, settings\)/);
  assert.match(source, /loadSettings\(\)/);
});

test("settings drawer uses canvas hitboxes for header and toggle clicks", () => {
  assert.match(source, /local settingsExpanded = false/);
  assert.match(source, /local hitboxes = \{\}/);
  assert.match(source, /local function registerHitbox\(id, x, y, w, h\)/);
  assert.match(source, /registerHitbox\("settings\.toggle", w - 34, 5, 24, 20\)/);
  assert.match(source, /local function handleHitbox\(hitbox\)/);
  assert.match(source, /settingsExpanded = not settingsExpanded/);
  assert.match(source, /settings\[hitbox\.setting\] = not settings\[hitbox\.setting\]/);
  assert.match(source, /saveSettings\(\)\s+redraw\(\)\s+updateSpinnerTimer\(\)/);
});

test("settings drawer renders compact toggle rows below sessions", () => {
  assert.match(source, /local SETTINGS_ROW_HEIGHT = 28/);
  assert.match(source, /local SETTINGS_ITEMS = \{/);
  assert.match(source, /\{ key = "soundsEnabled", label = "Sounds" \}/);
  assert.match(source, /\{ key = "waitingReminderSound", label = "Waiting reminders" \}/);
  assert.match(source, /\{ key = "waitingPulse", label = "Waiting pulse" \}/);
  assert.match(source, /\{ key = "completionFlash", label = "Finish flash" \}/);
  assert.match(source, /local function drawSettingsToggle\(x, y, on\)/);
  assert.doesNotMatch(source, /type = "circle"/);
  assert.match(source, /frame = \{ x = knobX, y = y \+ 2, w = 14, h = 14 \}/);
  assert.match(source, /roundedRectRadii = \{ xRadius = 7, yRadius = 7 \}/);
  assert.match(source, /local function drawSettingsDrawer\(y, w\)/);
  assert.match(source, /drawSettingsDrawer\(y, w\)/);
});

test("attention behaviors honor persisted settings", () => {
  assert.match(source, /if not SOUND_ENABLED or not settings\.soundsEnabled then return end/);
  assert.match(source, /if not settings\.waitingReminderSound then return end/);
  assert.match(source, /if activity == "Waiting" and settings\.waitingPulse then/);
  assert.match(source, /if settings\.completionFlash then\s+flashState\[id\]/);
  assert.match(source, /if a == "Thinking" or a == "Tool" or \(a == "Waiting" and \(settings\.waitingPulse or settings\.waitingReminderSound\)\) then hasMotion = true; break end/);
});

import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";

const state = readFileSync(new URL("./webview/state.lua", import.meta.url), "utf8");
const html = readFileSync(new URL("./webview/html.lua", import.meta.url), "utf8");
const styles = readFileSync(new URL("./webview/styles.lua", import.meta.url), "utf8");
const bridge = readFileSync(new URL("./webview/bridge.lua", import.meta.url), "utf8");
const webview = readFileSync(new URL("./claude-status-webview.lua", import.meta.url), "utf8");
const iconsUrl = new URL("./webview/icons.lua", import.meta.url);
const icons = existsSync(iconsUrl) ? readFileSync(iconsUrl, "utf8") : "";

test("webview state preserves exact canvas display labels for decimal tab badges", () => {
  assert.match(state, /local function displayLabel\(row\)/);
  assert.match(state, /row\._display_num/);
  assert.match(state, /row\.display_label/);
  assert.match(state, /copy\.display_label = displayLabel\(row\)/);
  assert.match(html, /label\.textContent = escapeHtml\(row\.display_label \|\| row\._display_num \|\| row\.tab_num \|\| ""\)/);
});

test("settings sidecar open state is Lua-owned and separate from main frame sizing", () => {
  assert.match(webview, /local settingsOpen = false/);
  assert.match(webview, /elseif body\.type == "settings\.toggle" then[\s\S]*settingsOpen = not settingsOpen[\s\S]*refreshWebview\(\)/);
  assert.match(webview, /settingsOpen = false/);
  assert.match(webview, /settingsOpen = settingsOpen,/);
  assert.match(webview, /function M\.stop\(\)[\s\S]*settingsOpen = false/);
  assert.match(state, /open = input\.settingsOpen == true/);
  assert.doesNotMatch(state, /if sections\.settings and sections\.settings\.open then/);
  assert.match(html, /"settings\.toggle": true/);
  assert.match(html, /postAction\(\{ type: "settings\.toggle" \}\)/);
  assert.doesNotMatch(html, /var settingsOpen = false/);
  assert.doesNotMatch(html, /widget\.classList\.toggle\("settings-open"/);
  assert.match(bridge, /\["settings\.toggle"\] = true/);
});

test("row density tokens are slightly tighter while staying aligned with frame sizing", () => {
  assert.match(state, /local ACTIVE_ROW_HEIGHT = 28/);
  assert.match(state, /local COMPLETED_ROW_HEIGHT = 24/);
  assert.match(state, /local ROW_GAP = 3/);
  assert.match(styles, /--active-row-height: 28px;/);
  assert.match(styles, /--completed-row-height: 24px;/);
  assert.match(styles, /--row-gap: 3px;/);
});

test("bottom action row uses one quiet cog options control with controlled action and accessible labels", () => {
  assert.doesNotMatch(html, /textContent = header\.expanded \? "v" : ">"/);
  assert.doesNotMatch(html, />p<\/button>/);
  assert.doesNotMatch(html, /<button class="header-icon-button more-toggle"[^>]*data-action="settings\.toggle"/);
  assert.match(html, /options\.className = "header-icon-button more-toggle bottom-options-toggle"/);
  assert.match(html, /options\.setAttribute\("data-action", "settings\.toggle"\)/);
  assert.match(html, /options\.setAttribute\("aria-label", "Open options"\)/);
  assert.match(html, /options\.setAttribute\("title", "Options"\)/);
  assert.doesNotMatch(html, /class="header-icon-button expand-toggle"/);
  assert.doesNotMatch(html, /class="header-icon-button settings-toggle"/);
  assert.doesNotMatch(html, /class="header-icon-button pin-toggle"/);
  assert.match(html, /"expand\.toggle": true/);
  assert.match(html, /action === "expand\.toggle"[\s\S]*postAction\(\{ type: "expand\.toggle" \}\)/);
  assert.match(bridge, /\["expand\.toggle"\] = true/);
  assert.match(webview, /elseif body\.type == "expand\.toggle" then[\s\S]*if not canOpenDetailView\(\) then[\s\S]*return[\s\S]*end[\s\S]*expanded = not expanded/);
});

test("header controls render local inline SVG icons instead of CSS pseudo-icons", () => {
  assert.ok(existsSync(iconsUrl), "webview/icons.lua should exist");
  assert.match(icons, /local ICONS = \{/);
  assert.match(icons, /\["chevron-up"\]/);
  assert.match(icons, /\["chevron-down"\]/);
  assert.match(icons, /\["settings"\]/);
  assert.match(icons, /\["pin"\]/);
  assert.match(icons, /\["ellipsis"\]/);
  assert.match(icons, /<svg[^>]+stroke="currentColor"/);
  assert.match(icons, /function M\.svg\(name/);
  assert.doesNotMatch(icons, /::before|::after|content:/);
  assert.match(html, /local icons = require\("webview\.icons"\)/);
  assert.match(html, /icons\.svg\("settings", "control-icon settings-icon"\)/);
  assert.doesNotMatch(html, /icons\.svg\("ellipsis"/);
  assert.match(icons, /<span class="/);
  assert.match(icons, /<svg viewBox="0 0 24 24" fill="none" stroke="currentColor"/);
  assert.match(html, /"control-icon settings-icon"/);
});

test("expanded webview keeps one low-emphasis options control", () => {
  assert.doesNotMatch(styles, /\.widget:not\(\.expanded\) \.settings-toggle/);
  assert.doesNotMatch(styles, /\.widget:not\(\.expanded\) \.pin-toggle/);
  assert.match(styles, /\.widget:not\(\.expanded\) \.more-toggle\s*\{[\s\S]*display: none;/);
  assert.match(styles, /\.header-icon-button\s*\{[\s\S]*background: transparent;/);
  assert.match(styles, /\.control-icon svg\s*\{[\s\S]*width: 16px;[\s\S]*height: 16px;/);
  assert.match(styles, /\.more-toggle\s*\{[\s\S]*opacity: 0\.55;/);
  assert.doesNotMatch(styles, /\.header-icon-button::before/);
  assert.doesNotMatch(styles, /\.expand-toggle::before/);
  assert.doesNotMatch(styles, /\.settings-toggle::before/);
  assert.doesNotMatch(styles, /\.pin-toggle::before/);
});

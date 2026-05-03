import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";

const placementUrl = new URL("./webview/placement.lua", import.meta.url);
const placement = existsSync(placementUrl) ? readFileSync(placementUrl, "utf8") : "";
const webview = readFileSync(new URL("./claude-status-webview.lua", import.meta.url), "utf8");
const html = [
  "./webview/html.lua",
  "./webview/views/shared.lua",
  "./webview/views/mini.lua",
  "./webview/views/peek.lua",
  "./webview/views/detail.lua",
].map((file) => readFileSync(new URL(file, import.meta.url), "utf8")).join("\n");
const bridge = readFileSync(new URL("./webview/bridge.lua", import.meta.url), "utf8");
const state = readFileSync(new URL("./webview/state.lua", import.meta.url), "utf8");
const styles = readFileSync(new URL("./webview/styles.lua", import.meta.url), "utf8");

test("placement helper exists and exposes anchor-aware frame helpers", () => {
  assert.ok(existsSync(placementUrl), "webview/placement.lua should exist");
  assert.match(placement, /function M\.frameForWidget\(screenFrame, size, placementState, padding\)/);
  assert.match(placement, /function M\.inferAnchor\(frame, screenFrame, padding\)/);
  assert.match(placement, /function M\.clampFrame\(frame, screenFrame, padding\)/);
  assert.match(placement, /function M\.placePopover\(screenFrame, anchorFrame, popoverSize, options\)/);
});

test("placement helper preserves corner anchors during size changes", () => {
  assert.match(placement, /kind == "top-right"[\s\S]*x = screenFrame\.x \+ screenFrame\.w - padding - width[\s\S]*y = screenFrame\.y \+ padding/);
  assert.match(placement, /kind == "top-left"[\s\S]*x = screenFrame\.x \+ padding[\s\S]*y = screenFrame\.y \+ padding/);
  assert.match(placement, /kind == "bottom-right"[\s\S]*x = screenFrame\.x \+ screenFrame\.w - padding - width[\s\S]*y = screenFrame\.y \+ screenFrame\.h - padding - height/);
  assert.match(placement, /kind == "bottom-left"[\s\S]*x = screenFrame\.x \+ padding[\s\S]*y = screenFrame\.y \+ screenFrame\.h - padding - height/);
});

test("placement helper treats middle drags as custom positions and clamps onscreen", () => {
  assert.match(placement, /kind == "custom"/);
  assert.match(placement, /placementState\.x/);
  assert.match(placement, /placementState\.y/);
  assert.match(placement, /return M\.clampFrame\(frame, screenFrame, padding\)/);
  assert.match(placement, /local nearest = \{/);
  assert.match(placement, /return \{ kind = "custom", x = frame\.x, y = frame\.y \}/);
});

test("popover placement prefers right then left and clamps when space is constrained", () => {
  assert.match(placement, /local order = options\.order or \{ "right", "left", "below", "above" \}/);
  assert.match(placement, /for _, name in ipairs\(order\) do[\s\S]*if fits\(frame, screenFrame, padding\) then[\s\S]*return frame, candidate\.name/);
  assert.match(placement, /return M\.clampFrame\(firstCandidate\.frame, screenFrame, padding\), firstCandidate\.name/);
});

test("webview uses placement state instead of bottom-right-only customPos math", () => {
  assert.match(webview, /local webviewPlacement = require\("webview\.placement"\)/);
  assert.match(webview, /local placementState = \{ kind = "top-right" \}/);
  assert.match(webview, /webviewPlacement\.frameForWidget\(screenFrame\(\), size, placementState, WINDOW_PADDING\)/);
  assert.match(webview, /placementState = webviewPlacement\.inferAnchor\(f, screenFrame\(\), WINDOW_PADDING\)/);
  assert.doesNotMatch(webview, /local function screenBottomRight/);
  assert.doesNotMatch(webview, /customPos = \{ x = f\.x \+ f\.w, y = f\.y \+ f\.h \}/);
});

test("settings are rendered in a separate sidecar webview independent of detail mode", () => {
  assert.match(webview, /local settingsWebview = nil/);
  assert.match(webview, /settingsWebview = hs\.webview\.new\(settingsFrame\)/);
  assert.match(webview, /settingsWebview:html\(buildSettingsHtml\(\)\)/);
  assert.match(webview, /settingsWebview:evaluateJavaScript\(script, function\(result\)/);
  assert.match(webview, /webviewPlacement\.placePopover\(screenFrame\(\), popoverAnchor, settingsSize\(\)/);
  assert.match(webview, /if not expanded then settingsOpen = false end/);
  assert.match(webview, /if settingsWebview then settingsWebview:delete\(\) end/);
  assert.match(html, /function M\.buildSettings\(options\)/);
  assert.doesNotMatch(html, /settings-pin-toggle/);
  assert.doesNotMatch(html, /data-action="pin\.toggle"/);
  assert.match(state, /settings = \{[\s\S]*open = input\.settingsOpen == true/);
});

test("main header keeps counts centered and bottom actions expose one cog options control", () => {
  assert.match(html, /icons\.svg\("settings", "control-icon settings-icon"\)/);
  assert.doesNotMatch(html, /icons\.svg\("ellipsis"/);
  assert.match(html, /<div class="loader-slot" data-loader-slot aria-hidden="true"><\/div>\s*<div class="counts header-counts" id="counts">/);
  assert.match(styles, /\.header\s*\{[\s\S]*grid-template-columns: 24px minmax\(0, 1fr\) 24px;/);
  assert.match(styles, /\.loader-slot\s*\{[\s\S]*width: 24px;/);
  assert.match(styles, /\.header-counts\s*\{[\s\S]*grid-column: 2;[\s\S]*justify-self: center;/);
  assert.match(styles, /\.bottom-options-toggle\s*\{[\s\S]*grid-column: 3;/);
  assert.doesNotMatch(html, /<button class="header-icon-button more-toggle"[^>]*data-action="settings\.toggle"/);
  assert.match(html, /options\.className = "header-icon-button more-toggle bottom-options-toggle"/);
  assert.match(html, /options\.setAttribute\("data-action", "settings\.toggle"\)/);
  assert.match(html, /options\.setAttribute\("aria-label", "Open options"\)/);
  assert.match(html, /options\.setAttribute\("title", "Options"\)/);
  assert.doesNotMatch(html, /class="header-icon-button expand-toggle"/);
  assert.doesNotMatch(html, /class="header-icon-button settings-toggle"/);
  assert.doesNotMatch(html, /class="header-icon-button pin-toggle"/);
  assert.doesNotMatch(html, /data-action="pin\.toggle"[^>]*aria-label="Pin expanded widget"/);
  assert.match(bridge, /\["settings\.toggle"\] = true/);
});

test("collapsed mode hides options control so header is the only collapsed interaction", () => {
  assert.match(styles, /\.widget:not\(\.expanded\) \.more-toggle\s*\{[\s\S]*display: none;/);
  assert.match(styles, /\.header\s*\{[\s\S]*grid-template-columns: 24px minmax\(0, 1fr\) 24px;/);
});

test("expanded header exposes a quiet top-right collapse control", () => {
  assert.match(html, /icons\.svg\("chevron-up", "control-icon collapse-icon"\)/);
  assert.match(html, /class="header-icon-button collapse-toggle"[^>]*data-action="expand\.toggle"[^>]*aria-label="Collapse widget"[^>]*title="Collapse"/);
  assert.match(styles, /\.collapse-toggle\s*\{[\s\S]*grid-column: 3;[\s\S]*justify-self: end;[\s\S]*opacity: 0\.55;/);
  assert.match(styles, /\.widget:not\(\.expanded\) \.collapse-toggle\s*\{[\s\S]*display: none;/);
  assert.match(html, /if \(closestTarget\(event\.target, "\.collapse-toggle"\)\) return/);
});

test("collapsed frame is compact and does not reserve hidden row height", () => {
  assert.match(state, /local COLLAPSED_FRAME_HEIGHT = HEADER_HEIGHT \+ BORDER_SHADOW_SAFETY/);
  assert.match(state, /if not sections\.expanded then[\s\S]*width = PILL_WIDTH,[\s\S]*height = COLLAPSED_FRAME_HEIGHT,[\s\S]*end/);
  assert.match(state, /if not sections\.expanded then[\s\S]*end[\s\S]*height = height \+ \(#sections\.activeRows \* \(ACTIVE_ROW_HEIGHT \+ ROW_GAP\)\)/);
  assert.match(styles, /body\s*\{[\s\S]*place-items: start;/);
});

test("collapsed generic header clicks do not expand compact or peek views", () => {
  assert.match(html, /if \(action === "settings\.toggle"\) \{[\s\S]*if \(requestExpand\(\)\) return;[\s\S]*postAction\(\{ type: "settings\.toggle" \}\)/);
  assert.match(html, /if \(widget && widget\.classList\.contains\("compact"\)\) return false;/);
  assert.match(html, /if \(widget && widget\.classList\.contains\("peek"\)\) return false;/);
  assert.doesNotMatch(html, /var header = closestTarget\(event\.target, "\.header"\)/);
  assert.doesNotMatch(html, /if \(header && requestExpand\(\)\) return;/);
});

test("dragging starts from mouse down and Lua eventtap owns motion tracking", () => {
  assert.match(html, /document\.addEventListener\("mousedown"/);
  assert.doesNotMatch(html, /postAction\(\{ type: "drag\.move"/);
  assert.doesNotMatch(html, /postAction\(\{ type: "drag\.end"/);
  assert.match(html, /postAction\(\{ type: "drag\.start"/);
  assert.match(html, /if \(closestTarget\(event\.target, "button"\)\) return;/);
  assert.match(webview, /elseif body\.type == "drag\.start" then[\s\S]*startDrag\(body\.x, body\.y\)/);
  assert.match(webview, /hs\.eventtap\.new\(\{ hs\.eventtap\.event\.types\.leftMouseDragged, hs\.eventtap\.event\.types\.leftMouseUp \}/);
  assert.match(webview, /hs\.mouse\.absolutePosition\(\)/);
  assert.match(webview, /moveDrag\(pos\.x - dragState\.mx, pos\.y - dragState\.my\)/);
  assert.match(webview, /if event:getType\(\) == hs\.eventtap\.event\.types\.leftMouseUp then[\s\S]*endDrag\(\)/);
});

test("bottom options row does not start panel dragging and click suppression remains intact", () => {
  assert.doesNotMatch(html, /closest\("button, label, input"\)/);
  assert.match(html, /closestTarget\(event\.target, "label, input"\)/);
  assert.match(html, /if \(closestTarget\(event\.target, "\.bottom-actions"\)\) return/);
  assert.match(html, /dragClickSuppressed = false/);
  assert.match(html, /document\.addEventListener\("mousemove"[\s\S]*Math\.abs\(event\.screenX - dragOrigin\.x\) > 3/);
  assert.match(html, /dragClickSuppressed = true/);
  assert.match(html, /if \(dragClickSuppressed\) \{[\s\S]*event\.preventDefault\(\);[\s\S]*event\.stopPropagation\(\);[\s\S]*dragClickSuppressed = false;[\s\S]*return;/);
});

test("hover state does not fire while a drag is active or auto-expand mini mode", () => {
  assert.match(html, /function handleWidgetHover\(hovering, event\) \{[\s\S]*if \(dragOrigin\) return;/);
  assert.match(html, /document\.addEventListener\("mouseover", function\(event\) \{[\s\S]*handleWidgetHover\(true, event\);/);
  assert.match(html, /document\.addEventListener\("mouseout", function\(event\) \{[\s\S]*handleWidgetHover\(false, event\);/);
  assert.match(html, /if \(widget\.classList\.contains\("peek"\)\) \{[\s\S]*postAction\(\{ type: "peek\.hover\.set", hovering: hovering \}\);[\s\S]*return;/);
  assert.match(html, /if \(widget\.classList\.contains\("compact"\)\) return;/);
  assert.doesNotMatch(html, /postAction\(\{ type: "expand\.set", expanded: hovering \}\)/);
});

test("runtime debug logging can trace JS bridge policy and drag checkpoints", () => {
  assert.match(webview, /local DEBUG_KEY = "claudeStatus.debug"/);
  assert.match(webview, /local DEBUG_LOG_PATH = "\/tmp\/claude-status-webview-debug\.log"/);
  assert.match(webview, /local function debugLog\(message\)/);
  assert.match(webview, /hs\.settings\.get\(DEBUG_KEY\)/);
  assert.match(webview, /io\.open\(DEBUG_LOG_PATH, "a"\)/);
  assert.match(webview, /hs\.printf\("\[claude-status-webview\] %s", tostring\(message\)\)/);
  assert.match(webview, /debugLog\("policy action=/);
  assert.match(webview, /debugLog\("bridge action=/);
  assert.match(webview, /debugLog\("drag start"/);
  assert.match(webview, /debugLog\("drag move"/);
  assert.match(webview, /debugLog\("drag end"/);
  assert.match(html, /window\.location\.href = BRIDGE_SCHEME/);
});

test("native Lua interaction tap does not treat compact or peek button clicks as detail expansion", () => {
  assert.match(webview, /local interactionTap = nil/);
  assert.match(webview, /local pointerState = nil/);
  assert.match(webview, /local hoverCollapseSuppressedUntil = 0/);
  assert.match(webview, /local CLICK_DRAG_THRESHOLD = 8/);
  assert.match(webview, /local function pointInFrame\(point, frame\)/);
  assert.match(webview, /local function startInteractionTap\(\)/);
  assert.match(webview, /hs\.eventtap\.new\(\{ hs\.eventtap\.event\.types\.mouseMoved, hs\.eventtap\.event\.types\.leftMouseDown, hs\.eventtap\.event\.types\.leftMouseDragged, hs\.eventtap\.event\.types\.leftMouseUp \}/);
  assert.match(webview, /if eventType == hs\.eventtap\.event\.types\.mouseMoved then[\s\S]*updateNativeHover\(pos\)/);
  assert.match(webview, /if not expanded and \(viewMode == "compact" or viewMode == "peek"\) then[\s\S]*debugLog\("native compact\/peek mouse down ignored"\)[\s\S]*return false/);
  assert.match(webview, /if eventType == hs\.eventtap\.event\.types\.leftMouseDown then[\s\S]*pointInFrame\(pos, webview:frame\(\)\)/);
  assert.match(webview, /debugLog\("native mouse down inside main frame"\)/);
  assert.match(webview, /math\.abs\(pos\.x - pointerState\.x\) > CLICK_DRAG_THRESHOLD/);
  assert.match(webview, /debugLog\("native mouse up moved=" \.\. tostring\(pointerState\.moved\)\)/);
  assert.match(webview, /if viewMode == "compact" or viewMode == "peek" then[\s\S]*debugLog\("ignored compact\/peek native click expand"\)/);
  assert.match(webview, /elseif canOpenDetailView\(\) then[\s\S]*expanded = true[\s\S]*hoverCollapseSuppressedUntil = hs\.timer\.secondsSinceEpoch\(\) \+ 0\.6[\s\S]*refreshWebview\(\)/);
  assert.match(webview, /else[\s\S]*debugLog\("ignored dormant detail native click expand"\)/);
  assert.match(webview, /body\.type == "expand\.set"[\s\S]*body\.expanded ~= true[\s\S]*hs\.timer\.secondsSinceEpoch\(\) < hoverCollapseSuppressedUntil[\s\S]*debugLog\("ignored immediate hover collapse after native expand"\)/);
  assert.match(webview, /startInteractionTap\(\)/);
  assert.match(webview, /if interactionTap then interactionTap:stop\(\) end/);
});

test("debug logging traces real JSON load decisions and rendered counts", () => {
  assert.match(webview, /debugLog\("loadSessions start dir=" \.\. STATUS_DIR\)/);
  assert.match(webview, /debugLog\("loadSessions file=" \.\. file \.\. " age=" \.\. tostring\(age\) \.\. " rows=" \.\. tostring\(#data\.sessions\)\)/);
  assert.match(webview, /debugLog\("loadSessions stale file=" \.\. file \.\. " age=" \.\. tostring\(age\)\)/);
  assert.match(webview, /debugLog\("loadSessions result sessions=" \.\. tostring\(#sessions\) \.\. " active=" \.\. tostring\(counts\.active\) \.\. " waiting=" \.\. tostring\(counts\.waiting\) \.\. " done=" \.\. tostring\(counts\.done\)\)/);
  assert.match(webview, /debugLog\("refresh state expanded=" \.\. tostring\(viewState\.expanded\) \.\. " sessions=" \.\. tostring\(#sessions\) \.\. " activeRows=" \.\. tostring\(#viewState\.activeRows\) \.\. " completedRows=" \.\. tostring\(#viewState\.completedRows\) \.\. " frame=" \.\. tostring\(mainFrame\.x\) \.\. "," \.\. tostring\(mainFrame\.y\) \.\. " " \.\. tostring\(mainFrame\.w\) \.\. "x" \.\. tostring\(mainFrame\.h\)\)/);
  assert.match(webview, /typeof window\.renderStatus !== "function"[\s\S]*return "missing-renderStatus"/);
  assert.match(webview, /return "ok active=" \+ \(activeValue \? activeValue\.textContent : "missing"\) \+ " completed=" \+ \(completedValue \? completedValue\.textContent : "missing"\)/);
  assert.match(webview, /return "error:" \+ \(error && error\.name \? error\.name : "unknown"\) \+ ":" \+ \(error && error\.message \? error\.message : String\(error\)\)/);
  assert.match(webview, /webview:evaluateJavaScript\(script, function\(result\)[\s\S]*debugLog\("render eval result=" \.\. tostring\(result\)\)/);
});

test("production webview JavaScript avoids modern syntax unsupported by older Hammerspoon WebKit", () => {
  assert.doesNotMatch(html, /\?\?/);
  assert.doesNotMatch(html, /Object\.assign/);
  assert.doesNotMatch(html, /classList\.toggle\([^)]*,/);
  assert.match(html, /row\.pane_id != null \? row\.pane_id : ""/);
  assert.match(html, /function mergeSettings\(settings\)/);
  assert.match(html, /function setClass\(element, className, enabled\)/);
  assert.match(html, /setClass\(widget, "expanded", !!state\.expanded\)/);
  assert.match(html, /setClass\(document\.body, "waiting-pulse-enabled", !!settings\.waitingPulse\)/);
  assert.match(html, /window\.renderStatus = function\(state\)/);
});

test("production webview injects renderer script before state rendering when WebKit skips inline scripts", () => {
  assert.match(html, /function M\.script\(bridgeScheme\)/);
  assert.match(html, /window\.__claudeStatusRendererInstalled/);
  assert.match(webview, /local function rendererScript\(\)[\s\S]*webviewHtml\.script\(BRIDGE_SCHEME\)/);
  assert.match(webview, /local bootstrapScript = rendererScript\(\)/);
  assert.match(webview, /local script = bootstrapScript \.\. \[\[/);
  assert.match(webview, /typeof window\.renderStatus !== "function"[\s\S]*return "missing-renderStatus"/);
});

test("expanded panel does not paint an external bottom shadow outside the rounded border", () => {
  assert.match(styles, /\.widget\s*\{[\s\S]*box-shadow: inset 0 0 0 1px var\(--panel-inner-border\);/);
  assert.doesNotMatch(styles, /0 12px 34px rgba\(0,\s*0,\s*0,\s*0\.32\)/);
  assert.match(state, /local BORDER_SHADOW_SAFETY = 6/);
});

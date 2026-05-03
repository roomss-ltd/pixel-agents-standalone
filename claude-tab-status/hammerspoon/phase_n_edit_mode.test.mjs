import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const webview = readFileSync(new URL("./claude-status-webview.lua", import.meta.url), "utf8");
const state = readFileSync(new URL("./webview/state.lua", import.meta.url), "utf8");
const html = readFileSync(new URL("./webview/html.lua", import.meta.url), "utf8");
const styles = readFileSync(new URL("./webview/styles.lua", import.meta.url), "utf8");
const bridge = readFileSync(new URL("./webview/bridge.lua", import.meta.url), "utf8");
const icons = readFileSync(new URL("./webview/icons.lua", import.meta.url), "utf8");
const interruptBody = webview.match(/function interruptSession\(zj_session, pane_id, run_id\)[\s\S]*?\nend\n\nfunction focusSession/)?.[0] ?? "";

test("edit mode is a controlled peek action exposed through the bridge", () => {
  assert.match(bridge, /\["edit\.toggle"\] = true/);
  assert.match(html, /"edit\.toggle": true/);
  assert.match(webview, /local editMode = false/);
  assert.match(webview, /elseif body\.type == "edit\.toggle" then[\s\S]*viewMode == "peek"[\s\S]*editMode = not editMode[\s\S]*peekHover = true/);
  assert.match(state, /local editMode = input\.editMode == true/);
  assert.match(state, /editMode = editMode/);
  assert.match(state, /editMode = editMode,/);
  assert.match(html, /setClass\(widget, "editing", !!state\.editMode\)/);
  assert.match(html, /ensurePeekActionButton\(peekActions, "peek-edit-toggle", "edit\.toggle", "Edit rows"/);
  assert.match(html, /setClass\(edit, "is-active", !!state\.editMode\)/);
  assert.match(styles, /\.peek-edit-toggle\s*\{[^}]*grid-column: 2;/);
  assert.match(styles, /\.peek-action-button\.is-active\s*\{[\s\S]*color: var\(--active-blue\);/);
});

test("edit mode renders row-level disconnect and interrupt buttons without stealing row focus", () => {
  assert.match(icons, /\["pencil"\]/);
  assert.match(icons, /\["ban"\]/);
  assert.match(icons, /\["unlink"\]/);
  assert.match(html, /sharedView\.iconTemplate\("pencil-icon-template", pencilIcon\)/);
  assert.match(html, /sharedView\.iconTemplate\("ban-icon-template", banIcon\)/);
  assert.match(html, /sharedView\.iconTemplate\("unlink-icon-template", unlinkIcon\)/);
  assert.match(html, /function rowEditActionForActivity\(activity\)/);
  assert.match(html, /return done \? "row\.dismiss" : "row\.interrupt"/);
  assert.match(html, /function appendRowEditButton\(container, action, label, templateId\)/);
  assert.match(html, /if \(editMode\) \{[\s\S]*var action = rowEditActionForActivity\(row\.activity\);[\s\S]*appendRowEditButton\(el, action, labelText, templateId\);/);
  assert.match(html, /renderRows\(state\.activeRows \|\| state\.activeSessions \|\| \[\], "active-row", state\.editMode\)/);
  assert.match(html, /renderRows\(state\.recentCompletedRows \|\| state\.completedRows \|\| \[\], "completed-row", state\.editMode\)/);
  assert.match(html, /function rowIdentityFromNode\(node\)/);
  assert.match(html, /if \(action === "row\.dismiss" \|\| action === "row\.interrupt"\) \{/);
  assert.match(html, /event\.preventDefault\(\);[\s\S]*event\.stopPropagation\(\);[\s\S]*postAction\(rowIdentityFromNode\(control\)\)/);
  assert.match(styles, /\.widget\.editing \.row\s*\{[\s\S]*grid-template-columns: 36px minmax\(0, 1fr\) minmax\(72px, auto\) 24px;/);
  assert.match(styles, /\.row-edit-button,\s*\.peek-card-edit-button\s*\{[\s\S]*width: 22px;[\s\S]*height: 22px;/);
});

test("peek edit mode covers primary ticker active stack and history rows", () => {
  assert.match(html, /function rowEditActionForKind\(kind\)/);
  assert.match(html, /function ensurePeekCardEditButton\(card\)/);
  assert.match(html, /var editMode = !!\(header && header\.peek && header\.peek\.editMode\)/);
  assert.match(html, /setClass\(ticker, "edit-mode", editMode\)/);
  assert.match(html, /setPeekEditButton\(card, item, editMode\)/);
  assert.match(html, /renderPeekActiveStackRow\(item, index, editMode\)/);
  assert.match(html, /renderPeekHistoryRow\(item, !!peek\.editMode\)/);
  assert.match(styles, /\.peek-card-edit-button\s*\{[\s\S]*width: 22px;[\s\S]*height: 22px;/);
  assert.match(styles, /\.peek-history-row\.edit-mode\s*\{[\s\S]*grid-template-columns: 34px minmax\(0, 1fr\) auto 24px;/);
  assert.match(styles, /\.peek-active-stack-row\.edit-mode\s*\{[\s\S]*grid-template-columns: 30px minmax\(0, 1fr\) auto 24px;/);
});

test("manual interrupt quietly marks stale active or waiting rows as done", () => {
  assert.match(bridge, /\["row\.interrupt"\] = true/);
  assert.match(html, /"row\.interrupt": true/);
  assert.match(webview, /local interruptSession = nil/);
  assert.match(webview, /elseif body\.type == "row\.interrupt" then[\s\S]*interruptSession\(body\._zj_session, body\.pane_id, body\.run_id\)/);
  assert.match(webview, /function interruptSession\(zj_session, pane_id, run_id\)/);
  assert.match(webview, /existing\.activity = "Done"/);
  assert.match(webview, /existing\.detail = "0s ago · cancelled"/);
  assert.match(webview, /existing\.manual_state = "cancelled"/);
  assert.match(webview, /prevActivities\[tostring\(run_id or pane_id\)\] = "Done"/);
  assert.doesNotMatch(interruptBody, /playStatusSound\("done"\)/);
  assert.doesNotMatch(interruptBody, /enqueueStatusEvent\("finished"/);
});

test("manual interrupt disconnects the current run so later stale writes cannot resurrect it", () => {
  assert.match(interruptBody, /if run_id and run_id ~= "" then[\s\S]*addInterruptedRun\(run_id\)/);
  assert.match(interruptBody, /else[\s\S]*addToDenylist\(zj_session, pane_id\)[\s\S]*\{"hook_event":"Dismiss","pane_id":%d\}/);
});

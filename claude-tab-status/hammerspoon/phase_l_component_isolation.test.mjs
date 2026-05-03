import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";

const htmlUrl = new URL("./webview/html.lua", import.meta.url);
const viewUrls = {
  shared: new URL("./webview/views/shared.lua", import.meta.url),
  mini: new URL("./webview/views/mini.lua", import.meta.url),
  peek: new URL("./webview/views/peek.lua", import.meta.url),
  detail: new URL("./webview/views/detail.lua", import.meta.url),
};

const html = readFileSync(htmlUrl, "utf8");

test("mini, peek, and detail have source-level view modules", () => {
  for (const [name, url] of Object.entries(viewUrls)) {
    assert.equal(existsSync(url), true, `${name} view module should exist`);
  }

  const shared = readFileSync(viewUrls.shared, "utf8");
  const mini = readFileSync(viewUrls.mini, "utf8");
  const peek = readFileSync(viewUrls.peek, "utf8");
  const detail = readFileSync(viewUrls.detail, "utf8");

  assert.match(shared, /function M\.iconTemplate\(id, icon\)/);
  assert.match(mini, /function M\.headerControls\(options\)/);
  assert.match(peek, /function M\.ticker\(\)/);
  assert.match(peek, /function M\.history\(\)/);
  assert.match(detail, /function M\.headerControls\(options\)/);
});

test("html shell delegates view markup while keeping one root shell", () => {
  assert.match(html, /local sharedView = require\("webview\.views\.shared"\)/);
  assert.match(html, /local miniView = require\("webview\.views\.mini"\)/);
  assert.match(html, /local peekView = require\("webview\.views\.peek"\)/);
  assert.match(html, /local detailView = require\("webview\.views\.detail"\)/);

  assert.match(html, /miniView\.headerControls\(\{[\s\S]*enlargeIcon = enlargeIcon/);
  assert.match(html, /peekView\.ticker\(\)/);
  assert.match(html, /peekView\.history\(\)/);
  assert.match(html, /detailView\.headerControls\(\{[\s\S]*collapseIcon = collapseIcon/);
  assert.match(html, /sharedView\.iconTemplate\("settings-icon-template", settingsIcon\)/);
  assert.match(html, /<main class="widget">/);
  assert.doesNotMatch(html, /hs\.webview/);
});

test("view modules do not own global runtime mechanics", () => {
  for (const url of Object.values(viewUrls)) {
    const source = readFileSync(url, "utf8");
    assert.doesNotMatch(source, /hs\.webview/);
    assert.doesNotMatch(source, /evaluateJavaScript/);
    assert.doesNotMatch(source, /frameHeight|frame =|setFrame/);
    assert.doesNotMatch(source, /postAction\(|addEventListener/);
  }
});

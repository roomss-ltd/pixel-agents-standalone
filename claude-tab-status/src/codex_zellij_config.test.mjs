import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const wrapper = readFileSync(
  new URL("../scripts/codex-wrapper.sh", import.meta.url),
  "utf8",
);
const configSnippet = readFileSync(
  new URL("../../dotfiles/codex/config.toml.snippet", import.meta.url),
  "utf8",
);
const codexHook = readFileSync(
  new URL("../scripts/codex-zj-hook.sh", import.meta.url),
  "utf8",
);
const tabManager = readFileSync(new URL("./tab_manager.rs", import.meta.url), "utf8");
const statusWriter = readFileSync(new URL("./status_writer.rs", import.meta.url), "utf8");

test("Codex runs inline in Zellij so its output remains scrollable", () => {
  assert.match(wrapper, /--no-alt-screen/);
  assert.match(wrapper, /"\$CODEX_BIN" "\$\{CODEX_ZELLIJ_ARGS\[@\]\}" "\$@"\n/);
  assert.doesNotMatch(wrapper, /"\$CODEX_BIN" "\$\{CODEX_ZELLIJ_ARGS\[@\]\}" "\$@" &/);
  assert.doesNotMatch(wrapper, /CODEX_PID|wait "\$CODEX_PID"/);
  assert.match(configSnippet, /alternate_screen\s*=\s*"never"/);
});

test("Codex cannot overwrite framework-managed terminal titles", () => {
  assert.match(wrapper, /tui\.terminal_title=\[\]/);
  assert.match(configSnippet, /terminal_title\s*=\s*\[\]/);
});

test("the bridge identifies Codex and discovers Devin panes", () => {
  assert.match(codexHook, /agent_kind: "codex"/);
  assert.match(tabManager, /Some\("devin"\)/);
  assert.match(statusWriter, /\\"agent_kind\\"/);
  assert.match(statusWriter, /\\"agent_title\\"/);
});

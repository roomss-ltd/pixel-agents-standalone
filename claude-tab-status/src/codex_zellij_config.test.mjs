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

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const tabManagerSource = readFileSync(
  new URL("./tab_manager.rs", import.meta.url),
  "utf8",
);

test("tab status plugin uses visual tab positions with patched Zellij", () => {
  assert.match(
    tabManagerSource,
    /rename_tab\(\(tab_index \+ 1\) as u32, &new_name\)/,
  );
  assert.doesNotMatch(tabManagerSource, /tab_internal_keys/);
});

test("bootstrap probing is disabled with patched Zellij", () => {
  assert.match(
    tabManagerSource,
    /state\.bootstrap = BootstrapPhase::Complete;/,
  );
  assert.doesNotMatch(tabManagerSource, /for k in 0\.\.PROBE_MAX/);
});

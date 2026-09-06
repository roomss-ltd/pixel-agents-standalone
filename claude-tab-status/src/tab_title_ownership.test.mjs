import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import test from "node:test";

const sourceDirectory = new URL("./", import.meta.url);
const rustSource = readdirSync(sourceDirectory)
  .filter((name) => name.endsWith(".rs"))
  .map((name) => readFileSync(new URL(name, sourceDirectory), "utf8"))
  .join("\n");
const mainSource = readFileSync(new URL("./main.rs", import.meta.url), "utf8");
const claudeHook = readFileSync(new URL("../scripts/claude-zj-hook.sh", import.meta.url), "utf8");
const codexHook = readFileSync(new URL("../scripts/codex-zj-hook.sh", import.meta.url), "utf8");

test("status plugin appends only a working circle using stable tab ids", () => {
  assert.match(rustSource, /const WORKING_MARKER: &str = "●"/);
  assert.match(rustSource, /\brename_tab_with_id\s*\(/);
  assert.doesNotMatch(rustSource, /\brename_tab\s*\(/);
  assert.doesNotMatch(rustSource, /"⚡"|"⏸"|"✓"/);
});

test("v2 event channel isolates the safe plugin from legacy in-memory instances", () => {
  assert.match(mainSource, /pipe_message\.name\.as_str\(\) != "agent-tab-status-v2"/);
  assert.match(claudeHook, /--name "agent-tab-status-v2"/);
  assert.match(codexHook, /--name "agent-tab-status-v2"/);
  assert.match(claudeHook, /zellij_session_name: \$zsession/);
  assert.match(codexHook, /zellij_session_name: \$zsession/);
});

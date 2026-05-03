import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";

const packageJson = readFileSync(new URL("../../package.json", import.meta.url), "utf8");
const html = readFileSync(new URL("./webview/html.lua", import.meta.url), "utf8");
const styles = readFileSync(new URL("./webview/styles.lua", import.meta.url), "utf8");
const state = readFileSync(new URL("./webview/state.lua", import.meta.url), "utf8");
const ldrsUrl = new URL("./webview/ldrs.lua", import.meta.url);
const ldrsEntryUrl = new URL("./webview/ldrs-entry.js", import.meta.url);
const ldrs = existsSync(ldrsUrl) ? readFileSync(ldrsUrl, "utf8") : "";
const ldrsEntry = existsSync(ldrsEntryUrl) ? readFileSync(ldrsEntryUrl, "utf8") : "";

test("project pins ldrs as the local loader source package", () => {
  assert.match(packageJson, /"ldrs": "1\.1\.9"/);
  assert.ok(existsSync(ldrsEntryUrl), "ldrs bundler entry should exist");
  assert.match(ldrsEntry, /import \{ dotSpinner, quantum, cardio, trio, grid, chaoticOrbit, hourglass, metronome, reuleaux \} from "ldrs"/);
  assert.doesNotMatch(ldrsEntry, /square\.register\(\)/);
  assert.doesNotMatch(ldrsEntry, /mirage\.register\(\)/);
  assert.doesNotMatch(ldrsEntry, /trefoil\.register\(\)/);
  assert.doesNotMatch(ldrsEntry, /helix\.register\(\)/);
  assert.doesNotMatch(ldrsEntry, /miyagi\.register\(\)/);
  assert.doesNotMatch(ldrsEntry, /hatch\.register\(\)/);
  assert.doesNotMatch(ldrsEntry, /bouncy\.register\(\)/);
  assert.doesNotMatch(ldrsEntry, /pulsar\.register\(\)/);
  assert.doesNotMatch(ldrsEntry, /treadmill\.register\(\)/);
  assert.doesNotMatch(ldrsEntry, /jelly\.register\(\)/);
  assert.doesNotMatch(ldrsEntry, /ripples\.register\(\)/);
  assert.match(ldrsEntry, /dotSpinner\.register\(\)/);
  assert.match(ldrsEntry, /quantum\.register\(\)/);
  assert.match(ldrsEntry, /grid\.register\(\)/);
  assert.match(ldrsEntry, /chaoticOrbit\.register\(\)/);
  assert.match(ldrsEntry, /hourglass\.register\(\)/);
  assert.match(ldrsEntry, /metronome\.register\(\)/);
  assert.match(ldrsEntry, /reuleaux\.register\(\)/);
});

test("webview vendors a local ldrs browser bundle for Hammerspoon", () => {
  assert.ok(existsSync(ldrsUrl), "webview/ldrs.lua should exist");
  assert.match(ldrs, /Generated from ldrs/);
  assert.match(ldrs, /--target=es2017/);
  assert.match(ldrs, /function M\.script\(\)/);
  assert.match(ldrs, /customElements\.define/);
  assert.match(ldrs, /l-dot-spinner/);
  assert.match(ldrs, /l-quantum/);
  assert.match(ldrs, /l-cardio/);
  assert.match(ldrs, /l-trio/);
  assert.match(ldrs, /l-grid/);
  assert.match(ldrs, /l-chaotic-orbit/);
  assert.match(ldrs, /l-hourglass/);
  assert.match(ldrs, /l-metronome/);
  assert.match(ldrs, /l-reuleaux/);
  assert.doesNotMatch(ldrs, /l-square/);
  assert.doesNotMatch(ldrs, /l-mirage/);
  assert.doesNotMatch(ldrs, /l-trefoil/);
  assert.doesNotMatch(ldrs, /l-helix/);
  assert.doesNotMatch(ldrs, /l-miyagi/);
  assert.doesNotMatch(ldrs, /l-hatch/);
  assert.doesNotMatch(ldrs, /l-bouncy/);
  assert.doesNotMatch(ldrs, /l-pulsar/);
  assert.doesNotMatch(ldrs, /l-treadmill/);
  assert.doesNotMatch(ldrs, /l-jelly/);
  assert.doesNotMatch(ldrs, /l-ripples/);
  assert.doesNotMatch(ldrs, /\?\./);
  assert.doesNotMatch(ldrs, /\?\?/);
});

test("state exposes an active-only loader flag in the centered header model", () => {
  assert.match(state, /local activeTotal = counts\.active \+ counts\.waiting/);
  assert.match(state, /loader = \{[\s\S]*active = activeTotal > 0,[\s\S]*size = 18,[\s\S]*speed = 1\.75,[\s\S]*color = "var\(--active-blue\)"/);
  assert.match(state, /activeCount = counts\.active/);
  assert.match(state, /waitingCount = counts\.waiting/);
});

test("header renders a top-left ldrs loader slot without shifting centered counts", () => {
  assert.match(html, /local ldrs = require\("webview\.ldrs"\)/);
  assert.match(html, /ldrs\.script\(\)/);
  assert.match(html, /<div class="loader-slot" data-loader-slot aria-hidden="true"><\/div>/);
  assert.match(styles, /grid-template-columns: 24px minmax\(0, 1fr\) 24px/);
  assert.doesNotMatch(html, /class="spinner"/);
  assert.match(html, /function renderLoader\(loader\)/);
  assert.match(html, /renderLoader\(header\.loader \|\| \{\}\)/);
});

test("header loader cycles local ldrs variants and respects reduced motion", () => {
  assert.match(html, /var LOADER_VARIANTS = \[[\s\S]*name: "dot-spinner"[\s\S]*tag: "l-dot-spinner"[\s\S]*speed: 0\.9[\s\S]*name: "quantum"[\s\S]*tag: "l-quantum"[\s\S]*name: "cardio"[\s\S]*tag: "l-cardio"[\s\S]*stroke: 4[\s\S]*name: "trio"[\s\S]*tag: "l-trio"[\s\S]*name: "grid"[\s\S]*tag: "l-grid"[\s\S]*name: "chaotic-orbit"[\s\S]*tag: "l-chaotic-orbit"[\s\S]*speed: 1\.5[\s\S]*name: "hourglass"[\s\S]*tag: "l-hourglass"[\s\S]*bgOpacity: 0\.1[\s\S]*name: "metronome"[\s\S]*tag: "l-metronome"[\s\S]*speed: 1\.6[\s\S]*name: "reuleaux"[\s\S]*tag: "l-reuleaux"[\s\S]*stroke: 5[\s\S]*strokeLength: 0\.15[\s\S]*bgOpacity: 0\.1[\s\S]*speed: 1\.2/);
  assert.doesNotMatch(html, /name: "square"/);
  assert.doesNotMatch(html, /tag: "l-square"/);
  assert.doesNotMatch(html, /name: "mirage"/);
  assert.doesNotMatch(html, /tag: "l-mirage"/);
  assert.doesNotMatch(html, /name: "trefoil"/);
  assert.doesNotMatch(html, /name: "helix"/);
  assert.doesNotMatch(html, /name: "miyagi"/);
  assert.doesNotMatch(html, /name: "hatch"/);
  assert.doesNotMatch(html, /name: "bouncy"/);
  assert.doesNotMatch(html, /name: "pulsar"/);
  assert.doesNotMatch(html, /name: "treadmill"/);
  assert.doesNotMatch(html, /name: "jelly"/);
  assert.doesNotMatch(html, /name: "ripples"/);
  assert.match(html, /var LOADER_ROTATE_INTERVAL_MS = 15000/);
  assert.match(html, /window\.matchMedia\("\(prefers-reduced-motion: reduce\)"\)/);
  assert.match(html, /document\.createElement\(variant\.tag\)/);
  assert.match(html, /element\.setAttribute\("size", String\(loader\.size \|\| 18\)\)/);
  assert.match(html, /element\.setAttribute\("speed", reducedMotion \? "0" : String\(variant\.speed \|\| loader\.speed \|\| 1\.75\)\)/);
  assert.match(html, /if \(variant\.stroke\) element\.setAttribute\("stroke", String\(variant\.stroke\)\)/);
  assert.match(html, /if \(variant\.strokeLength\) element\.setAttribute\("stroke-length", String\(variant\.strokeLength\)\)/);
  assert.match(html, /if \(variant\.bgOpacity\) element\.setAttribute\("bg-opacity", String\(variant\.bgOpacity\)\)/);
  assert.match(html, /setInterval\(function\(\) \{[\s\S]*renderLoader\(lastLoaderState\)[\s\S]*\}, LOADER_ROTATE_INTERVAL_MS\)/);
});

test("loader slot styling stays compact and non-alerting", () => {
  assert.match(styles, /\.loader-slot\s*\{[\s\S]*width: 24px;[\s\S]*height: 24px;[\s\S]*display: grid;[\s\S]*place-items: center;/);
  assert.match(styles, /\.widget:not\(\.compact\) \.loader-slot:not\(\.is-active\)::before\s*\{[\s\S]*width: 8px;[\s\S]*height: 8px;[\s\S]*background: var\(--active-blue\);/);
  assert.match(styles, /\.loader-slot\.is-active > \*\s*\{[\s\S]*filter: drop-shadow\(0 0 6px rgba\(115, 166, 255, 0\.42\)\);/);
  assert.match(styles, /@media \(prefers-reduced-motion: reduce\)[\s\S]*\.loader-slot\.is-active > \*[\s\S]*animation: none !important;/);
});

test("collapsed pill reserves enough width for animated loader and centered counts", () => {
  assert.match(state, /local PILL_WIDTH = 188/);
  assert.match(styles, /\.widget:not\(\.expanded\) \{ width: 188px; \}/);
});

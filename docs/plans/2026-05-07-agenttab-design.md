# AgentTAB — macOS Notch App for Claude Code Activity Tracking

**Date:** 2026-05-07
**Status:** Draft
**Authors:** Adrian (with design review by Opus 4.7)

## TL;DR

`AgentTAB.app` is a native macOS / SwiftUI application that lives in the MacBook notch and shows live activity for every Claude Code session running on the machine — across any terminal (Ghostty, iTerm, Terminal.app, Zellij, tmux). The compact pill is always visible; hovering expands it into a tab-grouped session list with click-to-focus. It ships as an unsigned drag-to-Applications DMG built with `dmgbuild`, and self-updates over Cloudflare R2 via Sparkle. When the existing `claude-tab-status` Zellij integration is detected, AgentTAB runs in **read-only drop-in mode** and modifies nothing on the user's machine.

## Goals

1. Single-binary install for engineers — drag DMG content into `/Applications`, launch, done.
2. Always-on visual presence at the notch with the same look-and-feel as the existing Hammerspoon webview overlay (dark glass, activity colors, cardio + coffee animations).
3. Universal coverage — works for Claude Code in any terminal, not only Zellij.
4. First-class Zellij awareness — when the existing `claude-tab-status` setup is present, surface tab/pane data and click-to-focus.
5. Self-update over the air — no "download the new DMG" emails to colleagues.
6. Zero-touch for power users who already run the existing Zellij integration.

## Non-Goals

- Not a replacement for the React pixel-art office (`webview-ui/`) — that project remains separate.
- No Windows / Linux support in v1. Notch is a macOS concept.
- No remote / cross-machine session aggregation. Single-host monitoring only.
- No Claude session control (start, stop, send input). Read-only observability.
- No code signing / notarization in v1. Unsigned DMG, colleagues approve via System Settings.

## Background

The existing repository contains three independent Claude Code observability surfaces:

1. **Pixel Agents** (`server/` + `webview-ui/`) — Node + React canvas app, watches `~/.claude/projects/*.jsonl`.
2. **`claude-tab-status`** (`claude-tab-status/src/`) — Rust WASM Zellij plugin, receives Claude hooks via `zellij pipe`, writes `/tmp/claude-tab-status/<id>.json`, renames Zellij tabs.
3. **Hammerspoon overlay** (`claude-tab-status/hammerspoon/`) — Lua + WKWebView floating widget, reads the JSON files, renders status with cardio/coffee animations.

AgentTAB replaces #3 (the macOS overlay role) with a native app while preserving compatibility with #2. #1 stays a separate project.

## High-Level Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                          AgentTAB.app                             │
│                                                                   │
│  ┌────────────────────┐   ┌──────────────────┐                   │
│  │  ActivityEngine    │◄─┤  JSONLWatcher    │ ~/.claude/         │
│  │  (@MainActor)      │   │  (DispatchSrc)   │   projects/*.jsonl │
│  │                    │   └──────────────────┘                   │
│  │  sessions: [Sess]  │                                          │
│  │  @Published        │   ┌──────────────────┐                   │
│  │                    │◄─┤  HookSocketL.    │ /Library/.../      │
│  │                    │   │  (NWListener)    │   hook.sock        │
│  │                    │   └──────────────────┘                   │
│  │                    │                                          │
│  │                    │   ┌──────────────────┐                   │
│  │                    │◄─┤  ZellijReader    │ /tmp/claude-       │
│  │                    │   │  (DispatchSrc)   │   tab-status/      │
│  └─────────┬──────────┘   └──────────────────┘                   │
│            │                                                      │
│            ▼                                                      │
│  ┌────────────────────┐   ┌──────────────────┐                   │
│  │  NotchPanel        │   │  ToastPanel      │                   │
│  │  (NSPanel +        │   │  (NSPanel +      │                   │
│  │   SwiftUI)         │   │   SwiftUI)       │                   │
│  └────────────────────┘   └──────────────────┘                   │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Sparkle (SPUUpdater) — daily appcast poll                 │ │
│  │  → https://updates.agenttab.roomss.dev/appcast.xml         │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
                            │
              ┌─────────────┴──────────────┐
              ▼                            ▼
    ┌──────────────────┐         ┌──────────────────┐
    │  Claude Code     │         │  Cloudflare R2   │
    │  + hooks         │         │  appcast + DMGs  │
    └──────────────────┘         └──────────────────┘
```

### Pipelines summary

| Pipeline | Direction | Frequency | Always on? |
|----------|-----------|-----------|------------|
| JSONL transcript watcher | in | continuous | yes |
| Hook IPC socket | in | per-event burst | only when AgentTAB hooks installed |
| Zellij plugin status reader | in | every ~5s + transitions | only when WASM plugin running |
| Sparkle update poller | out | daily | yes |

## Activity Engine

The engine is a single `@MainActor` class owning all state. SwiftUI observes its `@Published var sessions` directly.

```swift
@MainActor
final class ActivityEngine: ObservableObject {
    @Published private(set) var sessions: [Session] = []

    private let jsonlWatcher: JSONLWatcher
    private let hookSocket:   HookSocketListener?      // nil in drop-in mode
    private let zellijReader: ZellijStatusReader?      // nil if no plugin
    private var byClaudeId:   [String: Session.ID]    = [:]
}

struct Session: Identifiable, Equatable {
    let id: UUID
    let claudeSessionId: String           // matches .jsonl basename
    let projectName: String                // e.g. "alven-estate/feat-auth"
    let projectPath: String                // absolute path
    var activity: Activity                 // .thinking | .tool(name) | .waiting | .done | .init | .idle
    var currentTool: String?               // e.g. "Editing transcriptParser.ts"
    var activeToolIds: Set<String>
    var subagentTools: [String: Set<String>]  // parentToolId -> child toolIds
    var lastUpdate: Date
    var terminalKind: TerminalKind          // .zellij(ZellijInfo) | .generic(String?)
    var counts: SessionCounts               // total tool runs, duration so far
}

enum Activity {
    case initState, thinking, tool(String), waiting, done, idle
}

struct ZellijInfo: Equatable {
    let paneId: Int
    let tabIndex: Int
    let tabName: String
    let zellijSession: String   // ZELLIJ_SESSION_NAME
}
```

### JSONL pipeline

Direct port of `server/sessionManager.ts` + `server/transcriptParser.ts` + `server/fileWatcher.ts` to Swift:

- `DispatchSource.makeFileSystemObjectSource` on `~/.claude/projects/` for new directories and `.jsonl` files.
- Per-file watcher: primary `DispatchSource.makeReadSource`, secondary 2s polling fallback (matches the triple-redundant approach in the TS implementation — macOS `fs.watch` semantics aren't reliable enough alone).
- Tail reads via stored `UInt64 offset` per session, `FileHandle.seek(toOffset:)` + `readData(ofLength:)`. Line buffer for incomplete lines across reads.
- 30-min activity threshold for picking up sessions. 1-hour inactive threshold for marking sessions idle.

State machine ports verbatim from `transcriptParser.ts`:

| Record | Behavior |
|--------|----------|
| `assistant.message.content[].type == "tool_use"` | open tool — `agent.activeToolIds.insert(...)`, set `currentTool` to formatted status from `formatToolStatus()`, emit start |
| `user.message.content[].type == "tool_result"` | close tool — after 300ms (`TOOL_DONE_DELAY_MS`) |
| `progress` records with `parentToolUseID` | subagent tool tree (mirrors `Task`/`Agent` handling at `transcriptParser.ts:195–318`) |
| `system.subtype == "turn_duration"` | end of turn — flip to `.waiting`, clear all tools |
| timer fires (5s, `PERMISSION_TIMER_DELAY_MS`) with active non-exempt tools | flip to `.waiting` (permission required) |

`EXEMPT_TOOLS` set (`Read`/`Grep`/`Glob`/`ListDir`/`AskUserQuestion`) reused as-is — no permission timer for read-only tools.

### Hook IPC socket

`NWListener` configured with:

```swift
let parameters = NWParameters(tls: nil)
parameters.acceptLocalOnly = true
parameters.requiredLocalEndpoint = .unix(path: socketPath)
let listener = try NWListener(using: parameters)
```

Path: `~/Library/Application Support/AgentTAB/hook.sock`. Hook script writes one short JSON per invocation via `nc -U`. Decoded into:

```swift
struct HookPayload: Decodable {
    let pane_id: Int                 // 0 if not in Zellij
    let session_id: String
    let hook_event: String           // PreToolUse, PostToolUse, Stop, ...
    let tool_name: String?
    let term_program: String?        // $TERM_PROGRAM, e.g. "ghostty", "iTerm.app"
}
```

Each event maps to an explicit `Activity` transition:

| Hook event | Activity transition |
|-----------|---------------------|
| `SessionStart` | `.initState` |
| `UserPromptSubmit` | `.thinking` (clears tool name) |
| `PreToolUse` | `.tool(name)` |
| `PostToolUse` / `PostToolUseFailure` | `.thinking` |
| `PermissionRequest` | `.waiting` |
| `Stop` / `SubagentStop` / `ManualInterrupt` | `.done` (lingers 30s before `.idle`) |
| `SessionEnd` | session removed |

This table mirrors `event_handler.rs:94–103` in the existing Rust plugin.

### Pipeline precedence and de-duplication

Both the hook socket and JSONL watcher will see most events (hook fires AND the assistant message lands in the transcript). To avoid contradictory updates, the engine applies a "hook authority" flag per session:

- If a hook event arrived in the last 10s → JSONL-inferred `Activity` transitions are dropped, only explicit hook transitions win.
- JSONL parser still tracks tool IDs and history for the row's "current tool" string.
- Stale hook authority decays after 10s of silence so JSONL becomes authoritative again if hooks die.

The Zellij reader **only enriches** — it sets `session.terminalKind = .zellij(...)` and never changes `session.activity`. The plugin's view of activity is downstream of the same hooks.

### Threading model

- JSONL parser runs on `DispatchQueue.global(qos: .utility)`.
- Socket listener runs on its own `DispatchQueue(label: "agenttab.hooks")`.
- Zellij reader runs on `DispatchQueue.global(qos: .utility)`.
- All three call `Task { @MainActor in engine.apply(event) }` to mutate state — serialized through the actor.
- SwiftUI views observe `@Published var sessions` via Combine. Updates are throttled with `.throttle(for: .milliseconds(50))` to keep render rate sane during hook bursts.

## Adaptive Onboarding & Environment Detection

On every launch, the app probes the environment in ~5ms:

```swift
struct EnvironmentProbe {
    let zellij: ZellijState                   // .notInstalled, .installed, .running
    let wasmPlugin: PluginState               // .none, .configured, .producingStatusFiles
    let claudeHooks: HookState                // .none, .legacyClaudeTabStatus, .agentTAB, .mixed
}

enum PluginState {
    case none
    case configured                           // ~/.config/zellij/config.kdl mentions claude-tab-status.wasm
    case producingStatusFiles                 // /tmp/claude-tab-status/*.json with mtime < 60s
}

enum HookState {
    case none
    case legacyClaudeTabStatus                // ~/.claude/settings.json hooks point at claude-zj-hook.sh
    case agentTAB                             // hooks point at AgentTAB's bundled hook.sh
    case mixed                                // both AgentTAB and legacy hooks coexisting
}
```

The probe drives one of three onboarding paths.

### Path 1 — Drop-in mode

**Trigger:** `zellij == .running && wasmPlugin == .producingStatusFiles && claudeHooks != .none`

**Behavior:** A single welcome screen — *"Detected your existing Claude tab status setup. AgentTAB will read it live without modifying anything."* — then the notch becomes active. **Zero writes to `~/.claude/settings.json`. Zero new hook scripts. Zero changes to the dev environment.**

The activity engine boots in read-only mode:

- ✅ JSONL watcher → on (universal fallback for any non-Zellij sessions)
- ✅ Zellij status reader → on, **promoted to primary signal source for Zellij sessions**
- ❌ Hook socket → not bound (existing `claude-zj-hook.sh` writes to Zellij's pipe, not ours)

The Zellij `/tmp/claude-tab-status/<id>.json` files contain everything needed: `pane_id`, `tab_num`, `tab_name`, `activity`, `detail`, `counts`. The notch shows the union of all status files within ~5s of launch.

### Path 2 — Augment mode

**Trigger:** Same as Path 1, but user toggles "Switch to managed hooks" in Settings.

**Behavior:**

1. AgentTAB takes a backup copy of `claude-zj-hook.sh` to `~/Library/Application Support/AgentTAB/hook.sh.backup`.
2. Replaces it with the AgentTAB fanout version (writes to both Zellij pipe AND AgentTAB socket — Zellij integration unchanged).
3. Hook socket listener boots → AgentTAB now gets sub-100ms transitions instead of polling status files at 5s.

Reversible: a "Restore original" button puts the backup back.

### Path 3 — Fresh install

**Trigger:** `zellij not running` OR `wasmPlugin == .none` OR `claudeHooks == .none`.

**Behavior:** Full onboarding sheet:

1. **Welcome** — single screen with logo, one-line pitch, "Continue".
2. **Hook installation consent** — explains that AgentTAB will register hooks in `~/.claude/settings.json`. Two buttons: **Install hooks** / **Skip (JSONL only)**.
3. **Hook installer** — copies bundled `Resources/hook.sh` to `~/Library/Application Support/AgentTAB/hook.sh`, makes executable, merges into `~/.claude/settings.json` for all 8 events using a JSON merge (jq if present, embedded Swift JSON merge fallback).
4. **Optional: "Open at login"** — `SMAppService.mainApp.register()`.
5. **Optional: "Install Zellij integration"** — only shown if `which zellij` succeeds; runs `claude-tab-status/install.sh` from inside the bundle.
6. **Done** — notch panel becomes active.

### Settings transparency

Settings → General displays the current detection state:

> **Mode:** Drop-in (read-only)
> Reading from: `/tmp/claude-tab-status/` (Zellij plugin) and `~/.claude/projects/` (JSONL fallback).
> AgentTAB has not modified your Claude or Zellij configuration. [Switch to managed hooks…]

## UI Design — Notch Panel

### Window strategy: fixed-size panel, animate the content

The `NotchPanel` (`NSPanel` subclass) keeps a constant frame at the maximum needed size (e.g. 420×460pt) anchored to the top center of the built-in display. The pill and expanded view are both drawn inside SwiftUI; the window never resizes. This keeps animations buttery — only one animation timeline (SwiftUI springs), no `NSAnimationContext` ↔ `withAnimation` coordination problems.

Configuration:

```swift
styleMask = [.borderless, .nonactivatingPanel]
level = .statusBar
backgroundColor = .clear
isOpaque = false
hasShadow = false
collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
```

`ignoresMouseEvents` is toggled per-region via a hit-test override: only the visible pill/expanded shape intercepts clicks; outside the visible area, clicks pass through to whatever app is below.

### Notch detection and multi-display

```swift
let topInset = NSScreen.main?.safeAreaInsets.top ?? 0
let hasNotch = topInset > 0
```

- Notched MacBook (`topInset > 0` ≈ 32pt): pill hugs notch's bottom edge with curved cutouts.
- Non-notched Mac (mini, older MBP, externals): pill anchors to top center of menu bar with no cutout.
- Multiple displays: notch panel renders on built-in display only. Toast panel renders on the screen with the focused app's window.

### Visual language — palette ported from Hammerspoon webview overlay

Lifted from `claude-tab-status/hammerspoon/webview/styles.lua` so the new app feels like the same product:

```swift
// Background and chrome
let glassBG     = Color(red: 0.09, green: 0.09, blue: 0.13).opacity(0.94)
let borderOuter = Color(white: 0.52).opacity(0.55)
let borderInner = Color.white.opacity(0.04)
let textPrimary = Color.white.opacity(0.88)
let textDim     = Color.white.opacity(0.35)

// Activity colors
extension Activity {
    var color: Color { switch self {
        case .thinking:   Color(red: 0.45, green: 0.65, blue: 1.00)   // soft blue   #73A6FF
        case .tool:       Color(red: 1.00, green: 0.75, blue: 0.25)   // amber       #FFBF40
        case .waiting:    Color(red: 1.00, green: 0.55, blue: 0.35)   // orange      #FF8C59
        case .done:       Color(red: 0.45, green: 0.82, blue: 0.50)   // green       #73D280
        case .initState:  Color(red: 0.55, green: 0.55, blue: 0.60)   // gray
        case .idle:       Color(red: 0.45, green: 0.82, blue: 0.50).opacity(0.5)
    }}
}
```

Underneath the glass tint sits SwiftUI's `.background(.ultraThinMaterial)` — the native macOS Sequoia behind-the-glass blur that gives the see-through feel.

### Compact pill — three zones flanking the notch

```
   ╭──────╮ ╭──────╮         ╭──────╮ ╭──────╮
   │  ◌◌  │ │      │  notch  │      │ │ ⚡3  │
   │      │ │      │ ░░░░░░░ │      │ │ ✓4   │
   ╰──────╯ ╰──────╯         ╰──────╯ ╰──────╯
   left zone — loader slot              right zone — counts
   (cardio when active,                 (in-progress / done)
    coffee+steam when idle)
```

**Left zone — loader slot.** Two mutually exclusive states with a 0.4s cross-fade between them (`.transition(.opacity.combined(with: .scale(scale: 0.9)))`):

1. **Active** (any session is `.thinking` or `.tool`): horizontally-drawn cardio waveform, port of the LDRS `l-cardio` web component. Implemented as a SwiftUI `Canvas` with a `TimelineView(.animation)` driving phase. Color = `--active-blue` (`#73A6FF`). Drop-shadow glow `Color(red: 0.45, green: 0.65, blue: 1.0).opacity(0.42)` matches `loader-slot.is-active` filter.

2. **Idle** (no active sessions): coffee cup with three rising steam wisps. Direct port of the SVG paths from `claude-tab-status/hammerspoon/webview/icons.lua:13` and the `coffeeSteam` keyframes from `webview/styles.lua:255`. Period 4.8s, opacity wave 0 → 0.76 → 0, vertical translate +3px → -9px, stroke-dashoffset 9 → 0. Three wisps phase-shifted by 0.33 each.

```swift
TimelineView(.animation) { context in
    let t = context.date.timeIntervalSinceReferenceDate
    ZStack {
        CoffeeBody()
        SmokeWisp(phase: (t / 4.8).truncatingRemainder(dividingBy: 1.0))
        SmokeWisp(phase: ((t / 4.8) + 0.33).truncatingRemainder(dividingBy: 1.0))
        SmokeWisp(phase: ((t / 4.8) + 0.66).truncatingRemainder(dividingBy: 1.0))
    }
}
.foregroundStyle(Color.white.opacity(0.62))
.frame(width: 14, height: 14)
```

**Right zone — counts.** Three pill-shaped chips, each visible only when count > 0:

- `⚡ N` — sum of `.thinking + .tool` (in-progress). Amber pulse on increment (briefly bright, then settles).
- `✓ N` — `.done` count. Green for the first 30s after each completion, then dims.
- `⏸ N` — only appears when at least one session is `.waiting`. Orange, attention-getting.

Number changes use `.contentTransition(.numericText())` so digits roll smoothly.

### Expanded view — tab-grouped session list

On hover, the panel expands down. Sessions are grouped by terminal context:

```
┌────────────────────────────────────────────────────┐
│  ⚡3  ✓4               [pill row, condensed]       │
├────────────────────────────────────────────────────┤
│  Zellij · Tab 1 · main                             │
│  ⚡  alven-estate          Editing transcriptParser│ →
│                                                     │
│  Zellij · Tab 2 · feat-auth                        │
│  ●   alven-estate/feat-auth     Thinking…          │ →
│  ✓   alven-estate/feat-auth     Done · 14 tools    │ →
│                                                     │
│  Zellij · Tab 3 · scratch                          │
│  ⏸   dotfiles      Waiting for permission          │ →
│                                                     │
│  Ghostty (no Zellij)                               │
│  ⚡  side-project           Running: npm test      │ →
└────────────────────────────────────────────────────┘
```

Tab headers (`Zellij · Tab N · <name>`) come from the WASM plugin's `tab_num` + `tab_name`. Non-Zellij sessions group by `term_program` from the hook payload. The "current feature" string is reused from `transcriptParser.ts:formatToolStatus()` ("Editing X", "Running: cmd", etc.).

**Click action — focus the terminal.**

1. **Zellij row:**
   ```sh
   zellij action focus-pane <pane_id>
   open -a "<term_program>"
   ```

2. **Non-Zellij row:** Best-effort AppleScript bridge if `term_program` is iTerm/Ghostty/Terminal; otherwise `open -a` to bring the app forward. Final fallback: open the project folder in Finder.

3. **Cmd-click** opens the project folder in the user's default editor (`open -a Cursor <path>` if Cursor is set as default).

**Per-row right-edge controls** (revealed on row hover):

| Icon | Action |
|------|--------|
| `↗` | Explicit "go to terminal" |
| `📁` | Open project folder in Finder |
| `×` | Long-press 3s — dismiss session (mirrors existing `DENYLIST` 30-day TTL behavior) |

### Animations — single tuning constant

```swift
extension Animation {
    static let notch = Animation.spring(response: 0.42, dampingFraction: 0.78)
}
```

Used for: pill ↔ expanded transition, row appear/disappear, count changes, loader-slot cross-fade. Waiting pulse (`WAITING_PULSE_PERIOD = 1.6`) and completion flash (`FLASH_DURATION = 1.5`) port from `claude-status.lua:83, 139` using `.repeatForever(autoreverses: true)` modifiers.

### Hover detection

`NSTrackingArea` over the pill region. `mouseEntered` waits 120ms before flipping to expanded (avoids jitter from cursor crossing menu bar). `mouseExited` (with cursor outside both pill and expanded panel bounds) collapses after 250ms. Pure hover, no click handling for expand/collapse.

## UI Design — Notification Toasts

A second borderless `NSPanel` (`ToastPanel`), `level = .floating`, anchored to the configured screen corner. Reuses the same glass background and activity colors as the notch.

### Triggers

- Session enters `.waiting` → orange-tinted toast: *"Claude needs your input — `<project name>`"*
- Session enters `.done` after a long `.tool` run (>60s active) → green toast: *"Finished — N tool calls in M:SS"*
- Session enters `.waiting` again after 30s without dismissal → reminder toast (configurable interval, matches `WAITING_SOUND_REMINDER_INTERVAL`)

### Behavior

- Default position: bottom-right. Settings panel offers all four corners + offset slider.
- Auto-dismiss: 4s normal, 8s for `.waiting` (needs attention).
- Animation: slide-up entry, fade-out exit, both `Animation.notch`.
- Sounds: bundled `Glass.wav` (from `claude-tab-status/hammerspoon/sounds/`) for `.done`, system "Ping" for `.waiting`. Cooldown 0.75s between sounds (matches `SOUND_COOLDOWN`).
- The toast `NSPanel` doesn't intercept mouse events except on its own bounds, fully decoupled lifecycle from the notch panel.

## Hook Script & IPC

Single fanout script installed at `~/Library/Application Support/AgentTAB/hook.sh` and registered in `~/.claude/settings.json` for all 8 events:

```sh
#!/bin/sh
# AgentTAB hook fanout — writes to local socket and (if in Zellij) to zellij pipe.
[ -t 0 ] && exit 0
INPUT=$(cat 2>/dev/null) || exit 0
PAYLOAD=$(printf '%s' "$INPUT" | jq -c \
  --arg pid "${ZELLIJ_PANE_ID:-0}" \
  --arg term "${TERM_PROGRAM:-unknown}" \
  '
  select(.hook_event_name) | {
    pane_id:    ($pid | tonumber),
    session_id: .session_id,
    hook_event: .hook_event_name,
    tool_name:  .tool_name,
    term_program: $term
  }' 2>/dev/null) || exit 0
[ -z "$PAYLOAD" ] && exit 0

# Always: AgentTAB socket. -w 1 prevents Claude from blocking if app is dead.
printf '%s' "$PAYLOAD" | nc -U "$HOME/Library/Application Support/AgentTAB/hook.sock" -w 1 \
  >/dev/null 2>&1

# Additionally: Zellij plugin if running inside Zellij.
[ -n "$ZELLIJ_PANE_ID" ] && command -v zellij >/dev/null 2>&1 && \
  zellij pipe --name "claude-tab-status" -- "$PAYLOAD" >/dev/null 2>&1

exit 0
```

The `-w 1` timeout on `nc` is critical — if AgentTAB isn't running, the hook still completes in ≤1s and Claude never blocks.

### Hook installation in `~/.claude/settings.json`

For each of the 8 hook events (`PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `PermissionRequest`, `Stop`, `SubagentStop`, `SessionStart`, `SessionEnd`), AgentTAB merges in:

```json
{
  "type": "command",
  "command": "/Users/<user>/Library/Application Support/AgentTAB/hook.sh"
}
```

Existing user hooks are preserved (jq `+` merge or Swift JSON merge fallback). The set of hooks installed is recorded in `~/Library/Application Support/AgentTAB/installed-hooks.json` so uninstall can reverse exactly what was added.

## Zellij Integration

### Drop-in mode (read-only)

When the existing `claude-tab-status` Zellij setup is detected:

- AgentTAB watches `/tmp/claude-tab-status/` via `DispatchSource.makeFileSystemObjectSource`.
- Each `.json` file's content (one per Zellij session) is decoded into a `ZellijStatus` struct.
- Sessions are merged into the engine's session list, with `terminalKind = .zellij(...)` populated from `tab_num`, `tab_name`, `pane_id`.
- Activity is **not** taken from these files — JSONL is authoritative when no AgentTAB hooks are installed.

### Augment mode (managed hooks)

When the user explicitly opts in via Settings, AgentTAB:

1. Backs up the existing `claude-zj-hook.sh`.
2. Replaces it with the fanout version (writes to both Zellij pipe and AgentTAB socket).
3. Boots the hook socket listener.

Activity now flows through the hook socket with sub-100ms latency. The Zellij plugin still functions normally because the script also fans out to `zellij pipe`.

## Update Mechanism (Sparkle 2.x)

### Architecture

Sparkle 2.x is embedded as a framework inside the bundle (`AgentTAB.app/Contents/Frameworks/Sparkle.framework`). It periodically polls an appcast XML feed; if a newer version exists, it prompts the user, downloads the DMG, verifies an EdDSA signature with the public key embedded in the bundle, then quits/swaps/relaunches.

### Why this works for unsigned apps

Sparkle's update integrity is independent of Apple code signing:

- A keypair is generated once via `generate_keys` (Sparkle's CLI tool).
- The private key stays on the developer machine (or CI secret).
- The public key is embedded in `Info.plist` as `SUPublicEDKey`.
- Each released DMG is signed with the private key via `sign_update`.
- Sparkle verifies the signature client-side before installing.

Compromising the update channel requires both the EdDSA private key AND the ability to push a malicious DMG to the hosting bucket — equivalent to dev-machine compromise.

### Hosting on Cloudflare R2

- $0 egress fees (matters for binary distribution at scale).
- ~$0.015/GB stored — ~$0.02/year for AgentTAB-sized DMGs.
- S3-compatible API (`wrangler r2 object put …`).
- Custom domain free (e.g. `updates.agenttab.roomss.dev`).

Layout:

```
https://updates.agenttab.roomss.dev/
├── appcast.xml
├── releases/
│   ├── AgentTAB-1.0.0.dmg
│   ├── AgentTAB-1.0.1.dmg
│   └── AgentTAB-1.0.2.dmg
└── release-notes/
    └── 1.0.2.html
```

### `Info.plist` keys

```xml
<key>SUFeedURL</key>              <string>https://updates.agenttab.roomss.dev/appcast.xml</string>
<key>SUPublicEDKey</key>          <string><base64 public key></string>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUScheduledCheckInterval</key><integer>86400</integer>
<key>SUEnableInstallerLauncherService</key><true/>
```

### Update UX

- Daily background check.
- New version available → non-blocking notification: *"AgentTAB 1.0.2 available"*.
- User clicks → download (~3-15MB), verify, quit, swap, relaunch.
- Manual trigger via Settings → "Check for Updates Now".
- "Skip this version" checkbox — won't nag again until next version.

## Packaging — `.app` bundle and DMG

### Bundle layout

```
AgentTAB.app/
└── Contents/
    ├── Info.plist
    ├── MacOS/
    │   └── AgentTAB                            (compiled binary)
    ├── Frameworks/
    │   └── Sparkle.framework/                  (~5MB, embedded)
    └── Resources/
        ├── AppIcon.icns                        (generated from 1024×1024 PNG)
        ├── hook.sh                             (copied to ~/Library on first run)
        ├── sounds/Glass.wav                    (lifted from existing repo)
        └── Assets.car                          (compiled SwiftUI Asset Catalog)
```

### Key `Info.plist` fields

```xml
<key>LSUIElement</key>            <true/>     <!-- no Dock icon, no app switcher -->
<key>LSMinimumSystemVersion</key> <string>14.0</string>
<key>CFBundleIdentifier</key>     <string>com.roomss.agenttab</string>
<key>CFBundleName</key>           <string>AgentTAB</string>
<key>CFBundleIconFile</key>       <string>AppIcon</string>
<key>LSApplicationCategoryType</key> <string>public.app-category.developer-tools</string>
```

`LSUIElement = true` is critical — the app is a background-only agent, not a regular dockable app. Notch panel becomes the entire visual presence. A discreet `NSStatusItem` menu bar fallback exposes Settings/Quit on machines without notches.

### macOS minimum: Sonoma 14.0

Required for: `safeAreaInsets`, `.ultraThinMaterial`, `.symbolEffect`, modern `SMAppService` Login Items API, and Sparkle 2.x's modern installer service.

### Icon assets

User to provide:

1. **1024×1024 PNG** — single source for app icon. Converted to `.icns` automatically:

```sh
mkdir AppIcon.iconset
sips -z 16 16     icon-1024.png --out AppIcon.iconset/icon_16x16.png
sips -z 32 32     icon-1024.png --out AppIcon.iconset/icon_16x16@2x.png
sips -z 32 32     icon-1024.png --out AppIcon.iconset/icon_32x32.png
sips -z 64 64     icon-1024.png --out AppIcon.iconset/icon_32x32@2x.png
sips -z 128 128   icon-1024.png --out AppIcon.iconset/icon_128x128.png
sips -z 256 256   icon-1024.png --out AppIcon.iconset/icon_128x128@2x.png
sips -z 256 256   icon-1024.png --out AppIcon.iconset/icon_256x256.png
sips -z 512 512   icon-1024.png --out AppIcon.iconset/icon_256x256@2x.png
sips -z 512 512   icon-1024.png --out AppIcon.iconset/icon_512x512.png
cp icon-1024.png  AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns AppIcon.iconset
```

2. **Optional: 540×380 PNG** — DMG background. If not provided, generated placeholder using the dark-glass palette.

3. **Optional: 1024×1024 PNG** — DMG volume icon. Defaults to the app icon.

### DMG via dmgbuild (Python)

`dmg-settings.py`:

```python
import os
application = "build/AgentTAB.app"
appname     = "AgentTAB"
format      = "UDZO"
size        = "150M"
files       = [application]
symlinks    = {"Applications": "/Applications"}
icon        = "assets/volume-icon.icns"
background  = "assets/dmg-background.png"
window_rect = ((100, 100), (540, 380))
icon_locations = {
    "AgentTAB.app": (140, 200),
    "Applications": (400, 200),
}
default_view  = "icon-view"
icon_size     = 96
text_size     = 12
```

Build:

```sh
dmgbuild -s dmg-settings.py "AgentTAB" out/AgentTAB-${VERSION}.dmg
```

### Unsigned distribution UX

Colleagues:

1. Download / receive DMG.
2. Drag `AgentTAB.app` into `/Applications`.
3. First launch: macOS shows *"Apple cannot verify… is free of malware"*.
4. **System Settings → Privacy & Security → Open Anyway** → confirm with password. ~20 seconds, one time.
5. App launches, runs normally.

If `Open Anyway` fails (rare quarantine bit edge case):

```sh
xattr -dr com.apple.quarantine /Applications/AgentTAB.app
```

This command should be in the README.

## Build & Release Pipeline

Single shell script `scripts/release.sh ${VERSION}`:

```sh
#!/bin/sh
set -euo pipefail
VERSION="${1:?usage: release.sh <version>}"

# 1. Build
xcodebuild -scheme AgentTAB -configuration Release \
           -derivedDataPath build/ archive

# 2. Compile icon
iconutil -c icns assets/AppIcon.iconset

# 3. Copy bundled resources
cp claude-tab-status/hammerspoon/sounds/Glass.wav build/AgentTAB.app/Contents/Resources/sounds/
cp scripts/hook.sh build/AgentTAB.app/Contents/Resources/

# 4. Build DMG
dmgbuild -s dmg-settings.py "AgentTAB" out/AgentTAB-${VERSION}.dmg

# 5. Sign with Sparkle EdDSA
SIGNATURE=$(sign_update out/AgentTAB-${VERSION}.dmg)

# 6. Update appcast.xml with new <item>
python3 scripts/update_appcast.py \
    --version "${VERSION}" \
    --dmg "out/AgentTAB-${VERSION}.dmg" \
    --signature "${SIGNATURE}" \
    --notes "release-notes/${VERSION}.md" \
    --out "out/appcast.xml"

# 7. Upload to Cloudflare R2
wrangler r2 object put "updates-agenttab/releases/AgentTAB-${VERSION}.dmg" \
    --file="out/AgentTAB-${VERSION}.dmg"
wrangler r2 object put "updates-agenttab/appcast.xml" \
    --file="out/appcast.xml"

# 8. Print SHA-256 for out-of-band verification
shasum -a 256 "out/AgentTAB-${VERSION}.dmg"
```

CI (GitHub Actions) wraps this on `git tag v*` push, with the EdDSA private key as a repository secret.

## Settings & Persistence

### Persistent state

| Path | Contents |
|------|----------|
| `~/Library/Application Support/AgentTAB/hook.sh` | The fanout hook script (Augment/Fresh-install modes only) |
| `~/Library/Application Support/AgentTAB/hook.sock` | Unix domain socket (created at runtime) |
| `~/Library/Application Support/AgentTAB/installed-hooks.json` | Record of which hooks AgentTAB added — drives clean uninstall |
| `~/Library/Application Support/AgentTAB/denylist.json` | Dismissed sessions, 30-day TTL |
| `~/Library/Application Support/AgentTAB/hook.sh.backup` | Backup of original `claude-zj-hook.sh` (Augment mode only) |
| `UserDefaults` (com.roomss.agenttab) | All `@AppStorage`-backed preferences |

### `@AppStorage` keys

| Key | Default | Purpose |
|-----|---------|---------|
| `AgentTAB.onboarding.completed` | `false` | Skip onboarding sheet on subsequent launches |
| `AgentTAB.toast.corner` | `.bottomRight` | Toast position |
| `AgentTAB.toast.offset` | `(16, 16)` | Margin from screen edges |
| `AgentTAB.sounds.enabled` | `true` | Notification sounds |
| `AgentTAB.sounds.waitingReminder` | `true` | 30s waiting-reminder toast |
| `AgentTAB.waitingPulse.enabled` | `true` | Pulse animation on waiting rows |
| `AgentTAB.completionFlash.enabled` | `true` | Green flash on session completion |
| `AgentTAB.openAtLogin` | `false` | Toggles `SMAppService.mainApp.register/unregister` |
| `AgentTAB.updateChannel` | `.stable` | Future: stable / beta channels |
| `AgentTAB.inactiveThresholdMinutes` | `60` | Idle threshold |

### Settings window

Standard SwiftUI `Settings { … }` scene, opened from the menu-bar `NSStatusItem`. Sections:

- **General**: Open at login, mode display, "Switch to managed hooks" toggle.
- **Notifications**: Toast corner, sound preferences, waiting reminder interval.
- **Sessions**: Inactive threshold, denylist viewer (with "restore" button per entry).
- **Updates**: Channel, "Check for Updates Now", last-checked timestamp.
- **Advanced**: Reveal hook script in Finder, view JSONL parse log, reset onboarding, uninstall hooks.

## Lifecycle & Edge Cases

| Situation | Behavior |
|-----------|----------|
| App starts, Claude is mid-session, no hooks installed | JSONL watcher scans files modified in last 30 min, reconstructs state from tail |
| Hook fires, AgentTAB not running | `nc -U` times out in ≤1s, Claude unaffected, JSONL fills in when app relaunches |
| Multiple AgentTAB instances | `NWListener.bind` fails on second instance, alert shown, second exits |
| JSONL file rotated/deleted | File watcher catches `.delete`/`.rename`, removes session |
| Session inactive >1h | Marked `.idle`, fades to dim row, eventually removed (`INACTIVE_THRESHOLD_MS = 1h`) |
| System sleeps mid-session | `NSWorkspace.willSleep` notification suppresses notifications; `DispatchSource` watchers reattach on wake |
| Mac wakes, lots of stale sessions | First scan after wake reconciles via mtime — sessions older than threshold are cleared |
| User removes app | "Remove AgentTAB" menu item reverses `~/.claude/settings.json` merge using `installed-hooks.json`, removes support directory, unregisters Login Item, reveals app in Finder |
| Sparkle update fails verification | Update aborted, error logged, no app changes |
| Clock skew (Sparkle daily check) | Sparkle handles gracefully — server provides fresh appcast on each fetch |

## Open Decisions

These are deferred until implementation begins:

1. **Notch carve curve specifics** — exact corner radius for the bottom-of-notch transition. NotchNook uses 10pt; we may want to match Apple's actual notch bottom curve more precisely. Verifiable empirically once the project boots.
2. **Cardio waveform exact path** — the LDRS path is `M0.5,17.2h8.2l3-4.7l5.9,12l7.8-24l5.9,16.7v0h8.2`. Decision: replicate exactly, or design a custom Claude-themed pulse. Default: replicate.
3. **Coffee body SVG** — same question. Default: replicate the Lucide-style coffee icon from `icons.lua:13`.
4. **Augment-mode default** — should "Switch to managed hooks" default ON for the developer (Adrian) and OFF for colleagues, or always OFF? Default OFF for safety, opt-in via Settings.
5. **AppleScript bridge for non-Zellij terminals** — iTerm and Terminal.app have rich AppleScript dictionaries. Ghostty has a CLI bridge. Worth the time? V1 says "best-effort, fall back to `open -a`".
6. **Bundle Identifier prefix** — `com.roomss.agenttab` assumed. Confirm with Roomss Ltd's existing reverse-DNS namespace.
7. **Cloudflare R2 bucket name and custom domain** — bucket `updates-agenttab`, domain `updates.agenttab.roomss.dev` are placeholders.

## Implementation Milestones (rough phasing)

This is a sequencing suggestion, not a timeline:

**M1 — Skeleton (1 week)**
- Xcode project, `LSUIElement = true`, blank `NSPanel` at notch position with hover detection
- Stub `ActivityEngine` with hardcoded `Session` array
- Compact pill renders palette + counts (no animation yet)

**M2 — JSONL pipeline (1 week)**
- Port `transcriptParser.ts` to Swift
- Directory + file watching via `DispatchSource`
- State machine working end-to-end with real Claude sessions

**M3 — Animations and expanded view (1 week)**
- Cardio loader Canvas
- Coffee + steam animation
- Tab-grouped expanded list, click-to-focus for Zellij rows

**M4 — Hook socket pipeline (1 week)**
- `NWListener` on Unix domain socket
- Hook script + onboarding flow that installs it
- Augment mode: backup + replace `claude-zj-hook.sh`

**M5 — Drop-in mode + Zellij reader (3 days)**
- Environment probe
- `/tmp/claude-tab-status/*.json` reader
- Settings transparency screen

**M6 — Notifications (3 days)**
- `ToastPanel` with corner anchoring
- Sound triggers, waiting-reminder timer
- Settings for corner / sounds

**M7 — Sparkle + DMG (1 week)**
- Embed Sparkle, generate keypair
- `dmg-settings.py` and DMG build
- `scripts/release.sh`, Cloudflare R2 hosting setup
- First end-to-end OTA update test

**M8 — Polish and ship (1 week)**
- App icon, DMG background art
- Onboarding copy
- README with `xattr` quarantine note
- Internal alpha → colleague distribution

Total: ~8 weeks for a polished v1.

---

## References

- Existing repo's transcript parser: `server/src/transcriptParser.ts`
- Existing Rust state machine: `claude-tab-status/src/event_handler.rs`
- Existing Hammerspoon overlay: `claude-tab-status/hammerspoon/claude-status-webview.lua`
- Existing CSS for cardio + coffee: `claude-tab-status/hammerspoon/webview/styles.lua`
- Existing SVG icons: `claude-tab-status/hammerspoon/webview/icons.lua`
- Sparkle 2.x docs: https://sparkle-project.org/documentation/
- dmgbuild: https://dmgbuild.readthedocs.io/
- Cloudflare R2 + wrangler: https://developers.cloudflare.com/r2/

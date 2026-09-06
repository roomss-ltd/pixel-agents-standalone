# AgentTAB

Native macOS notch app for tracking Claude Code, Codex, and Devin session activity. Live cardio pulse while agents work, coffee idle while they rest, and a tab-grouped session list with click-to-focus.

![pill in the notch animates with whatever Claude is doing right now]

## Install

1. Download `AgentTAB-X.Y.Z.dmg` from your distribution channel.
2. Double-click the DMG and drag **AgentTAB.app** into the **Applications** folder.
3. **First launch — bypass Gatekeeper:**
   - Try to open AgentTAB from `/Applications`. macOS will say _"Apple cannot verify… is free of malware"_ and block it.
   - Click **Done** (don't trash it).
   - Open **System Settings → Privacy & Security**. Scroll to the "Security" section. There will be a row for AgentTAB with an **Open Anyway** button.
   - Click **Open Anyway** and confirm with your password. ~20 seconds, one-time only.
4. AgentTAB launches and shows a 4-step onboarding sheet. Follow the prompts.

If `Open Anyway` doesn't appear or fails, the binary may have a quarantine xattr from how the DMG was downloaded. One-line fix:

```sh
xattr -dr com.apple.quarantine /Applications/AgentTAB.app
```

Then launch normally.

## What it does

- Tracks Claude transcripts, Codex rollouts, and Devin CLI sessions, including token spend and active subagents.
- Optionally registers Claude hooks (consented during onboarding) for instant <100ms transitions.
- Auto-detects existing `claude-tab-status` Zellij setups and runs in **drop-in mode** — modifies nothing on your machine, just reads the live data.
- Prefixes each card's existing activity line with `Claude`, `Codex`, or `Devin`.
- Self-updates via [Sparkle](https://sparkle-project.org). Daily background check, EdDSA-signed payloads.

## Uninstall

Click the menu bar **AT** icon → Settings → Advanced → "Uninstall AgentTAB". This:

- Removes AgentTAB hooks from `~/.claude/settings.json` (preserves any other hooks you had).
- Removes `~/Library/Application Support/AgentTAB/`.
- Unregisters the Login Item.

Then drag `/Applications/AgentTAB.app` to Trash.

## Build from source

```sh
brew install xcodegen
git clone --recurse-submodules <repo-url>
cd <repo>/agenttab
./scripts/build-and-run.sh
```

`build-and-run.sh` regenerates the Xcode project, builds Debug, and launches the app from `/tmp/agenttab-build/...` (avoiding the macOS Desktop-folder TCC prompt that triggers when launching unsigned apps from inside `~/Desktop`).

For release builds + DMG packaging:

```sh
./scripts/build-dmg.sh 0.1.0       # produces out/AgentTAB-0.1.0.dmg
./scripts/release.sh 0.1.0         # build + sign + update appcast (+ optional R2 upload)
```

See [`SPARKLE-KEYS.md`](SPARKLE-KEYS.md) for signing-key setup.

## Architecture

The full design is at [`docs/plans/2026-05-07-agenttab-design.md`](../docs/plans/2026-05-07-agenttab-design.md). Implementation plan at [`docs/plans/2026-05-07-agenttab-implementation.md`](../docs/plans/2026-05-07-agenttab-implementation.md). Quick summary:

- **`AgentTAB/Engine/`** — JSONL transcript watcher, hook IPC socket listener, Zellij plugin status reader, all feeding a single `@MainActor ActivityEngine`.
- **`AgentTAB/UI/`** — Notch panel (NSPanel + SwiftUI), pill (cardio/coffee + counts), expanded view (tab-grouped session list), production palette in `Theme.swift`.
- **`AgentTAB/Onboarding/`** — first-launch sheet + adaptive drop-in detection.
- **`AgentTAB/Notifications/`** — toast panel + sound player with cooldown.
- **`AgentTAB/Updates/`** — Sparkle wrapper.

## Requirements

- macOS 14 (Sonoma) or later (uses `safeAreaInsets`, `.symbolEffect`, `SMAppService`).
- At least one supported agent CLI: Claude Code, Codex, or Devin.

## License

(TBD — match the parent repo's license.)

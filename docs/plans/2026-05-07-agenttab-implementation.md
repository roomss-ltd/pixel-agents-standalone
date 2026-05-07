# AgentTAB Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build `AgentTAB.app` v1.0 — a native macOS SwiftUI app that lives in the MacBook notch and shows live activity for every Claude Code session, distributable as an unsigned drag-to-Applications DMG with Sparkle-powered auto-updates.

**Architecture:** Single-binary background-only Swift app (`LSUIElement = true`). Three input pipelines (JSONL transcript watcher, Unix-domain hook socket, Zellij plugin status reader) feed a single `@MainActor ActivityEngine`. Two `NSPanel` instances render UI: a borderless `NotchPanel` hugging the notch with a hover-expand session list, and a corner-anchored `ToastPanel` for notifications. Sparkle 2.x signs and delivers updates over Cloudflare R2. Build pipeline uses `xcodebuild` + Python `dmgbuild` for unsigned DMG creation.

**Tech Stack:** Swift 5.10 · SwiftUI (macOS 14.0+) · Combine · Network.framework · DispatchSource · Sparkle 2.x · dmgbuild · Cloudflare R2

**Reference:** Full architecture details in `docs/plans/2026-05-07-agenttab-design.md`

---

## Prerequisites

Before starting:

- macOS 14.0 (Sonoma) or later on the dev machine
- Xcode 15.4+ installed
- Swift 5.10+ (bundled with Xcode)
- Python 3.10+ on PATH (`python3 --version`) for dmgbuild
- Homebrew available (`brew --version`)
- A Cloudflare account with R2 enabled (free tier OK)
- `wrangler` CLI: `npm install -g wrangler` and `wrangler login`
- Existing AgentTAB design doc reviewed: `docs/plans/2026-05-07-agenttab-design.md`

## Project Structure

Final directory layout under repo root after implementation:

```
agenttab/                                ← new directory at repo root
├── AgentTAB.xcodeproj/
├── AgentTAB/                            ← Swift source
│   ├── App/
│   │   ├── AgentTABApp.swift            (@main entry)
│   │   ├── AppDelegate.swift            (NSApplicationDelegate)
│   │   └── Info.plist
│   ├── Engine/
│   │   ├── ActivityEngine.swift
│   │   ├── Session.swift
│   │   ├── Activity.swift
│   │   ├── EnvironmentProbe.swift
│   │   ├── JSONL/
│   │   │   ├── JSONLWatcher.swift
│   │   │   ├── TranscriptParser.swift
│   │   │   ├── ToolStatusFormatter.swift
│   │   │   └── SessionDiscovery.swift
│   │   ├── Hooks/
│   │   │   ├── HookSocketListener.swift
│   │   │   └── HookPayload.swift
│   │   └── Zellij/
│   │       ├── ZellijStatusReader.swift
│   │       └── ZellijStatus.swift
│   ├── UI/
│   │   ├── NotchPanel.swift
│   │   ├── NotchView.swift
│   │   ├── PillView.swift
│   │   ├── ExpandedView.swift
│   │   ├── Animations/
│   │   │   ├── CardioLoader.swift
│   │   │   ├── CoffeeIdle.swift
│   │   │   └── NotchShape.swift
│   │   ├── Rows/
│   │   │   ├── SessionRow.swift
│   │   │   └── TabHeader.swift
│   │   └── Theme.swift
│   ├── Notifications/
│   │   ├── ToastPanel.swift
│   │   ├── ToastView.swift
│   │   └── SoundPlayer.swift
│   ├── Onboarding/
│   │   ├── OnboardingView.swift
│   │   ├── HookInstaller.swift
│   │   └── ZellijIntegrationInstaller.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── SettingsStore.swift
│   │   └── MenuBarItem.swift
│   ├── Updates/
│   │   └── UpdaterCoordinator.swift     (Sparkle wrapper)
│   └── Resources/
│       ├── Assets.xcassets
│       ├── hook.sh
│       └── sounds/Glass.wav
├── AgentTABTests/
│   ├── TranscriptParserTests.swift
│   ├── ToolStatusFormatterTests.swift
│   ├── EnvironmentProbeTests.swift
│   ├── HookPayloadTests.swift
│   └── Fixtures/
│       └── transcripts/
│           ├── tool_use_basic.jsonl
│           ├── subagent_progress.jsonl
│           └── turn_duration.jsonl
├── scripts/
│   ├── build-dmg.sh
│   ├── release.sh
│   └── update_appcast.py
├── packaging/
│   ├── dmg-settings.py
│   └── appcast-template.xml
└── assets/
    ├── app-icon-1024.png                ← user provides
    ├── dmg-background.png
    └── volume-icon-1024.png
```

The new `agenttab/` directory sits as a peer to the existing `server/`, `webview-ui/`, `claude-tab-status/`, and `dotfiles/` directories. The existing repo structure is unchanged.

---

## Milestone 1: Project Skeleton

**Goal:** Empty SwiftUI app builds and runs. A blank `NSPanel` appears anchored under the notch (or top-center on non-notched Macs), with a green debug rectangle inside that responds to hover by growing taller. App appears in `LSUIElement` mode (no Dock icon).

**End state:** `xcodebuild` produces an `.app` that runs and shows a hover-responsive box at the notch. No engine, no real UI, no hooks. Just confirms the windowing primitive works.

### Task 1.1: Initialize Xcode project via xcodegen

**Files:**
- Create: `agenttab/project.yml` (xcodegen config — source of truth for the project)
- Create: `agenttab/AgentTAB/App/AgentTABApp.swift`
- Create: `agenttab/AgentTAB/App/Info.plist`
- Create: `agenttab/AgentTABTests/AgentTABTests.swift` (placeholder test)
- Generate: `agenttab/AgentTAB.xcodeproj/` (via xcodegen, gitignored)
- Update: `agenttab/.gitignore` to exclude generated artifacts

**Why xcodegen:** Avoids the GUI step in `File → New → Project`. The `project.yml` is the canonical project definition; `xcodegen` regenerates the `.xcodeproj` deterministically from it. CI-friendly and reproducible.

**Step 1: Install xcodegen if missing**

```sh
which xcodegen >/dev/null 2>&1 || brew install xcodegen
xcodegen --version
```
Expected: a version string ≥ 2.38.

**Step 2: Create project.yml**

```yaml
# agenttab/project.yml
name: AgentTAB
options:
  bundleIdPrefix: com.roomss
  deploymentTarget:
    macOS: "14.0"
  developmentLanguage: en
  groupSortPosition: top
settings:
  base:
    SWIFT_VERSION: "5.10"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    PRODUCT_BUNDLE_IDENTIFIER: com.roomss.agenttab
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    CODE_SIGN_STYLE: Automatic
    CODE_SIGN_IDENTITY: "-"
    DEVELOPMENT_TEAM: ""
targets:
  AgentTAB:
    type: application
    platform: macOS
    sources:
      - path: AgentTAB
        excludes:
          - "**/*.md"
    resources:
      - AgentTAB/Resources
    info:
      path: AgentTAB/App/Info.plist
      properties:
        LSUIElement: true
        LSMinimumSystemVersion: "14.0"
        LSApplicationCategoryType: public.app-category.developer-tools
        CFBundleName: AgentTAB
        CFBundleDisplayName: AgentTAB
        CFBundleIdentifier: com.roomss.agenttab
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        CFBundleIconFile: AppIcon
        NSHumanReadableCopyright: "© Roomss Ltd"
    scheme:
      testTargets:
        - AgentTABTests
  AgentTABTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - AgentTABTests
    dependencies:
      - target: AgentTAB
```

**Step 3: Create source files**

`agenttab/AgentTAB/App/AgentTABApp.swift`:

```swift
import SwiftUI

@main
struct AgentTABApp: App {
    var body: some Scene {
        Settings {
            Text("AgentTAB Settings (placeholder)")
                .frame(width: 400, height: 300)
        }
    }
}
```

`agenttab/AgentTAB/App/Info.plist` — **gitignored.** xcodegen owns this file; it rewrites it from `project.yml`'s `info.properties` on every `xcodegen generate`. There is no source-of-truth plist file in the source tree — `project.yml` is canonical. The file's `info.path` location is required so xcodebuild can find a plist during compilation, but the file itself isn't tracked.

`agenttab/AgentTABTests/AgentTABTests.swift`:

```swift
import XCTest
@testable import AgentTAB

final class AgentTABTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true, "Placeholder test — replaced by real tests in M2")
    }
}
```

`agenttab/.gitignore`:

```
# xcodegen output (regenerate via `xcodegen generate`)
AgentTAB.xcodeproj/
# xcodegen rewrites this file on every generate from project.yml's info.properties.
# project.yml is the canonical source of plist keys.
AgentTAB/App/Info.plist

# Xcode build artifacts
build/
DerivedData/
*.xcuserdata/
xcuserdata/

# Sparkle private key (never commit)
sparkle-private-key.txt
```

**Step 4: Generate Xcode project**

```sh
cd agenttab && xcodegen generate
```
Expected: `Generated project successfully` and `agenttab/AgentTAB.xcodeproj/` exists.

**Step 5: Verify build via xcodebuild**

```sh
xcodebuild -project agenttab/AgentTAB.xcodeproj -scheme AgentTAB -configuration Debug -derivedDataPath /tmp/agenttab-build -destination 'platform=macOS' build
```
Expected: `** BUILD SUCCEEDED **`

**Note on `/tmp/agenttab-build`:** Build artifacts MUST live outside `~/Desktop`. Unsigned macOS apps launched from inside `~/Desktop/...` trigger a TCC permission dialog ("AgentTAB would like to access files in your Desktop folder") on every launch. Putting the derived data under `/tmp` avoids this entirely. The convenience script `agenttab/scripts/build-and-run.sh` enforces this path.

**Step 6: Verify LSUIElement at runtime**

```sh
open -n /tmp/agenttab-build/Build/Products/Debug/AgentTAB.app &
sleep 2
# verify no Dock icon — list visible app windows
osascript -e 'tell application "System Events" to get name of every application process whose visible is true' | grep -q AgentTAB && echo "BAD: AgentTAB visible in Dock" || echo "OK: LSUIElement working"
osascript -e 'tell application "AgentTAB" to quit' 2>/dev/null
```
Expected: `OK: LSUIElement working`. (If `open -W` doesn't return cleanly, kill via `pkill -x AgentTAB`.)

**Step 7: Commit**

```bash
git add agenttab/project.yml agenttab/AgentTAB/ agenttab/AgentTABTests/ agenttab/.gitignore
git commit -m "Initialize AgentTAB Xcode project via xcodegen"
```

(Note: `AgentTAB.xcodeproj/` is gitignored — it's regenerated from `project.yml` on each clone.)

---

### Task 1.2: Create AppDelegate with status item fallback

**Files:**
- Create: `agenttab/AgentTAB/App/AppDelegate.swift`
- Modify: `agenttab/AgentTAB/App/AgentTABApp.swift`

**Step 1: Implement AppDelegate**

```swift
// AppDelegate.swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "AT"
        statusItem?.menu = makeMenu()
    }
    
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit AgentTAB", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }
    
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

**Step 2: Wire AppDelegate to SwiftUI App**

```swift
// AgentTABApp.swift
import SwiftUI

@main
struct AgentTABApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            Text("AgentTAB Settings (placeholder)")
                .frame(width: 400, height: 300)
        }
    }
}
```

**Step 3: Run and verify**

Run app. Expected: `AT` text appears in menu bar (top-right), clicking it shows a 2-item menu with "Settings…" and "Quit AgentTAB".

**Step 4: Commit**

```bash
git commit -am "feat(agenttab): add menu bar fallback + Settings stub"
```

---

### Task 1.3: Create NotchPanel NSPanel subclass

**Files:**
- Create: `agenttab/AgentTAB/UI/NotchPanel.swift`

**Step 1: Implement NotchPanel**

```swift
// NotchPanel.swift
import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    init(rootView: AnyView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.level = .statusBar
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.isMovable = false
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]
        self.ignoresMouseEvents = false
        self.hidesOnDeactivate = false
        
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = self.contentLayoutRect
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    func anchorToNotch() {
        guard let screen = NSScreen.main else { return }
        let topInset = screen.safeAreaInsets.top
        let screenFrame = screen.frame
        let panelWidth: CGFloat = 420
        let panelHeight: CGFloat = 460
        
        // Anchor: top center of the screen, panel hanging down from menu bar / notch
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - panelHeight
        // Note: AppKit uses bottom-left origin, so subtracting from maxY puts the top edge of the panel at the top of the screen
        
        self.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        
        // Store inset for SwiftUI to query
        UserDefaults.standard.set(Double(topInset), forKey: "AgentTAB.lastNotchInset")
    }
}
```

**Step 2: Add the panel to AppDelegate**

```swift
// In AppDelegate.swift, add a property and instantiate in applicationDidFinishLaunching:
var notchPanel: NotchPanel?

// In applicationDidFinishLaunching, after status item setup:
notchPanel = NotchPanel(rootView: AnyView(NotchView()))
notchPanel?.anchorToNotch()
notchPanel?.orderFront(nil)
```

**Step 3: Create placeholder NotchView**

```swift
// agenttab/AgentTAB/UI/NotchView.swift
import SwiftUI

struct NotchView: View {
    @State private var isHovered = false
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Rectangle()
                    .fill(Color.green.opacity(0.5))
                    .frame(width: isHovered ? 300 : 200, height: isHovered ? 200 : 30)
                    .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isHovered)
                    .onHover { hovering in isHovered = hovering }
                Spacer()
            }
            Spacer()
        }
    }
}
```

**Step 4: Run and verify**

Run app. Expected: a translucent green rectangle appears centered at the top of the screen below where the notch would be. Hovering over it grows it from 200×30 to 300×200 with a spring animation. Mouse outside shrinks it back. App icon does not appear in Dock or app switcher.

**Step 5: Commit**

```bash
git add agenttab/AgentTAB/UI/NotchPanel.swift agenttab/AgentTAB/UI/NotchView.swift
git commit -m "feat(agenttab): add NotchPanel NSPanel + hover-responsive placeholder"
```

---

### Task 1.4: Detect notch and adapt geometry

**Files:**
- Create: `agenttab/AgentTAB/UI/Geometry.swift`
- Modify: `agenttab/AgentTAB/UI/NotchView.swift`

**Step 1: Implement geometry helper**

```swift
// Geometry.swift
import AppKit

struct NotchGeometry {
    let hasNotch: Bool
    let notchHeight: CGFloat       // ~32pt on notched MacBooks, 0 elsewhere
    let notchWidth: CGFloat        // approx 200pt centered, 0 if no notch
    let screenFrame: NSRect
    
    static func detect() -> NotchGeometry {
        guard let screen = NSScreen.main else {
            return NotchGeometry(hasNotch: false, notchHeight: 0, notchWidth: 0,
                                 screenFrame: .zero)
        }
        let topInset = screen.safeAreaInsets.top
        return NotchGeometry(
            hasNotch: topInset > 0,
            notchHeight: topInset,
            notchWidth: topInset > 0 ? 200 : 0,   // approximate; refine in M3
            screenFrame: screen.frame
        )
    }
}
```

**Step 2: Pass geometry to NotchView via environment**

```swift
// In AppDelegate after creating notchPanel:
let geometry = NotchGeometry.detect()
notchPanel = NotchPanel(rootView: AnyView(NotchView().environment(\.notchGeometry, geometry)))

// In Geometry.swift, add EnvironmentKey:
private struct NotchGeometryKey: EnvironmentKey {
    static let defaultValue = NotchGeometry(hasNotch: false, notchHeight: 0,
                                            notchWidth: 0, screenFrame: .zero)
}
extension EnvironmentValues {
    var notchGeometry: NotchGeometry {
        get { self[NotchGeometryKey.self] }
        set { self[NotchGeometryKey.self] = newValue }
    }
}
```

**Step 3: Update NotchView to log detection**

```swift
struct NotchView: View {
    @Environment(\.notchGeometry) var geometry
    @State private var isHovered = false
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Rectangle()
                        .fill(Color.green.opacity(0.5))
                        .frame(width: isHovered ? 300 : 200,
                               height: isHovered ? 200 : 30)
                        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isHovered)
                        .onHover { hovering in isHovered = hovering }
                    Text("hasNotch: \(geometry.hasNotch ? "yes" : "no") inset: \(Int(geometry.notchHeight))pt")
                        .font(.caption2)
                        .foregroundStyle(.white)
                }
                Spacer()
            }
            Spacer()
        }
    }
}
```

**Step 4: Run and visually verify**

Run on a notched MacBook (e.g. M-series MBP 14"/16"). Expected: caption shows `hasNotch: yes inset: 32pt` (or similar). On a Mac mini / non-notched display, shows `hasNotch: no inset: 0pt`.

**Step 5: Commit**

```bash
git add agenttab/AgentTAB/UI/Geometry.swift agenttab/AgentTAB/UI/NotchView.swift
git commit -m "feat(agenttab): detect notch presence via safeAreaInsets"
```

---

### Task 1.5: Multi-screen panel rebinding on display changes

**Files:**
- Modify: `agenttab/AgentTAB/App/AppDelegate.swift`

**Step 1: Subscribe to NSApplication.didChangeScreenParametersNotification**

```swift
// In AppDelegate.applicationDidFinishLaunching, after creating notchPanel:
NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.notchPanel?.anchorToNotch()
}
```

**Step 2: Verify**

Plug/unplug an external monitor. Expected: panel re-anchors to the built-in display correctly.

**Step 3: Commit**

```bash
git commit -am "feat(agenttab): rebind notch panel on display changes"
```

---

### Task 1.6: Quit and relaunch hotkey for development

**Files:**
- Modify: `agenttab/AgentTAB/App/AppDelegate.swift`

**Step 1: Add restart action to status menu**

Add menu item in `makeMenu()`:
```swift
menu.addItem(NSMenuItem(title: "Restart", action: #selector(restart), keyEquivalent: "r"))
```

Add method:
```swift
@objc private func restart() {
    let task = Process()
    task.launchPath = "/usr/bin/open"
    task.arguments = ["-n", Bundle.main.bundlePath]
    try? task.run()
    NSApp.terminate(nil)
}
```

**Step 2: Verify**

Click status menu → Restart. Expected: app quits and relaunches in ~1s.

**Step 3: Commit**

```bash
git commit -am "feat(agenttab): add Restart action to status menu"
```

---

**Milestone 1 complete.** You should now have an app that runs as `LSUIElement`, anchors a borderless panel under the notch, responds to hover, has a status menu with Settings/Restart/Quit, and rebinds on display changes.

---

## Milestone 2: JSONL Pipeline

**Goal:** Real Claude session activity displays in the notch via the JSONL transcript watcher. The compact pill shows live counts. The placeholder green rectangle is replaced with a styled debug-list view that confirms session detection works.

**End state:** Open Claude Code → see a session appear in the notch debug view with project name + current activity that updates as Claude does work. No animations yet, no hooks, no Zellij.

### Task 2.1: Define core data model

**Files:**
- Create: `agenttab/AgentTAB/Engine/Activity.swift`
- Create: `agenttab/AgentTAB/Engine/Session.swift`
- Create: `agenttab/AgentTABTests/SessionTests.swift`

**Step 1: Write failing test for Session creation**

```swift
// SessionTests.swift
import XCTest
@testable import AgentTAB

final class SessionTests: XCTestCase {
    func testSessionInitializesWithDefaults() {
        let session = Session(
            claudeSessionId: "abc-123",
            projectName: "my-repo",
            projectPath: "/Users/me/my-repo"
        )
        XCTAssertEqual(session.claudeSessionId, "abc-123")
        XCTAssertEqual(session.activity, .idle)
        XCTAssertTrue(session.activeToolIds.isEmpty)
    }
}
```

**Step 2: Run to verify fails**

`xcodebuild test -scheme AgentTAB`
Expected: `error: cannot find 'Session' in scope`

**Step 3: Implement Session and Activity**

```swift
// Activity.swift
import Foundation

enum Activity: Equatable {
    case initState
    case thinking
    case tool(String)        // tool name, e.g. "Bash", "Read"
    case waiting             // permission needed or end of turn
    case done                // recently finished, lingers 30s
    case idle                // long stale
}

extension Activity {
    var rank: Int {
        switch self {
        case .waiting:   return 5
        case .tool:      return 4
        case .thinking:  return 3
        case .done:      return 2
        case .initState: return 1
        case .idle:      return 0
        }
    }
}

// Session.swift
import Foundation

struct Session: Identifiable, Equatable {
    let id: UUID
    let claudeSessionId: String
    let projectName: String
    let projectPath: String
    var activity: Activity
    var currentTool: String?              // human-readable, e.g. "Editing foo.swift"
    var activeToolIds: Set<String>
    var subagentTools: [String: Set<String>]
    var lastUpdate: Date
    var terminalKind: TerminalKind
    
    init(claudeSessionId: String, projectName: String, projectPath: String) {
        self.id = UUID()
        self.claudeSessionId = claudeSessionId
        self.projectName = projectName
        self.projectPath = projectPath
        self.activity = .idle
        self.currentTool = nil
        self.activeToolIds = []
        self.subagentTools = [:]
        self.lastUpdate = Date()
        self.terminalKind = .generic(nil)
    }
}

enum TerminalKind: Equatable {
    case generic(String?)              // optional term_program string
    case zellij(ZellijInfo)
}

struct ZellijInfo: Equatable {
    let paneId: Int
    let tabIndex: Int
    let tabName: String
    let zellijSession: String
}
```

**Step 4: Run test to verify pass**

`xcodebuild test -scheme AgentTAB`
Expected: `Test Suite 'SessionTests' passed`

**Step 5: Commit**

```bash
git add agenttab/AgentTAB/Engine/ agenttab/AgentTABTests/SessionTests.swift
git commit -m "feat(agenttab): add Session and Activity data model"
```

---

### Task 2.2: TDD ToolStatusFormatter

**Files:**
- Create: `agenttab/AgentTAB/Engine/JSONL/ToolStatusFormatter.swift`
- Create: `agenttab/AgentTABTests/ToolStatusFormatterTests.swift`

**Step 1: Write failing tests for each tool**

```swift
import XCTest
@testable import AgentTAB

final class ToolStatusFormatterTests: XCTestCase {
    func testFormatsRead() {
        let result = ToolStatusFormatter.format(toolName: "Read",
                                                input: ["file_path": "/a/b/c.swift"])
        XCTAssertEqual(result, "Reading c.swift")
    }
    
    func testFormatsEdit() {
        let result = ToolStatusFormatter.format(toolName: "Edit",
                                                input: ["file_path": "/a/b/main.py"])
        XCTAssertEqual(result, "Editing main.py")
    }
    
    func testFormatsBashShortCommand() {
        let result = ToolStatusFormatter.format(toolName: "Bash",
                                                input: ["command": "ls -la"])
        XCTAssertEqual(result, "Running: ls -la")
    }
    
    func testFormatsBashLongCommandTruncates() {
        let cmd = String(repeating: "x", count: 100)
        let result = ToolStatusFormatter.format(toolName: "Bash",
                                                input: ["command": cmd])
        XCTAssertEqual(result.count, "Running: ".count + 50 + 1)  // 50 chars + ellipsis
        XCTAssertTrue(result.hasSuffix("\u{2026}"))
    }
    
    func testFormatsTaskWithDescription() {
        let result = ToolStatusFormatter.format(toolName: "Task",
                                                input: ["description": "Find auth bugs"])
        XCTAssertEqual(result, "Subtask: Find auth bugs")
    }
    
    func testFormatsUnknownTool() {
        let result = ToolStatusFormatter.format(toolName: "MysteryTool", input: [:])
        XCTAssertEqual(result, "Using MysteryTool")
    }
    
    func testFormatsAskUserQuestion() {
        let result = ToolStatusFormatter.format(toolName: "AskUserQuestion", input: [:])
        XCTAssertEqual(result, "Waiting for your answer")
    }
}
```

**Step 2: Run to verify fails**

`xcodebuild test -scheme AgentTAB -only-testing:AgentTABTests/ToolStatusFormatterTests`
Expected: all 7 tests fail with "ToolStatusFormatter not found".

**Step 3: Implement formatter**

Direct port of `server/src/transcriptParser.ts:formatToolStatus`:

```swift
// ToolStatusFormatter.swift
import Foundation

enum ToolStatusFormatter {
    static let truncateLength = 50
    
    static func format(toolName: String, input: [String: Any]) -> String {
        let basename: (Any?) -> String = { p in
            guard let s = p as? String else { return "" }
            return (s as NSString).lastPathComponent
        }
        
        switch toolName {
        case "Read":
            return "Reading \(basename(input["file_path"]))"
        case "Edit":
            return "Editing \(basename(input["file_path"]))"
        case "Write":
            return "Writing \(basename(input["file_path"]))"
        case "Bash":
            let cmd = (input["command"] as? String) ?? ""
            let body = cmd.count > truncateLength
                ? String(cmd.prefix(truncateLength)) + "\u{2026}"
                : cmd
            return "Running: \(body)"
        case "Glob":         return "Searching files"
        case "Grep":         return "Searching code"
        case "WebFetch":     return "Fetching web content"
        case "WebSearch":    return "Searching the web"
        case "Task", "Agent":
            let desc = (input["description"] as? String) ?? ""
            if desc.isEmpty { return "Running subtask" }
            let body = desc.count > truncateLength
                ? String(desc.prefix(truncateLength)) + "\u{2026}"
                : desc
            return "Subtask: \(body)"
        case "AskUserQuestion": return "Waiting for your answer"
        case "EnterPlanMode":   return "Planning"
        case "NotebookEdit":    return "Editing notebook"
        default:                return "Using \(toolName)"
        }
    }
}
```

**Step 4: Run tests to verify pass**

`xcodebuild test -scheme AgentTAB -only-testing:AgentTABTests/ToolStatusFormatterTests`
Expected: all 7 tests pass.

**Step 5: Commit**

```bash
git commit -am "feat(agenttab): port ToolStatusFormatter from transcriptParser.ts"
```

---

### Task 2.3: TDD TranscriptParser — assistant tool_use blocks

**Files:**
- Create: `agenttab/AgentTAB/Engine/JSONL/TranscriptParser.swift`
- Create: `agenttab/AgentTABTests/TranscriptParserTests.swift`
- Create: `agenttab/AgentTABTests/Fixtures/transcripts/tool_use_basic.jsonl`

**Step 1: Create fixture**

```jsonl
// tool_use_basic.jsonl — three records: assistant tool_use, then user tool_result
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tool_001","name":"Read","input":{"file_path":"/Users/x/foo.swift"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tool_001"}]}}
{"type":"system","subtype":"turn_duration"}
```

**Step 2: Write failing test**

```swift
import XCTest
@testable import AgentTAB

final class TranscriptParserTests: XCTestCase {
    func testParsesToolUseBlock() {
        let parser = TranscriptParser()
        var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/a/b.swift"}}]}}"#
        let events = parser.parseLine(line, session: &session)
        XCTAssertEqual(events, [.toolStarted(toolId: "t1", status: "Reading b.swift")])
        XCTAssertEqual(session.activity, .tool("Read"))
        XCTAssertEqual(session.activeToolIds, ["t1"])
        XCTAssertEqual(session.currentTool, "Reading b.swift")
    }
}
```

**Step 3: Run to verify fails**

Expected: `error: cannot find 'TranscriptParser' in scope`

**Step 4: Implement minimal**

```swift
// TranscriptParser.swift
import Foundation

enum TranscriptEvent: Equatable {
    case toolStarted(toolId: String, status: String)
    case toolCompleted(toolId: String)
    case turnEnded
    case subagentToolStarted(parentId: String, toolId: String, status: String)
    case subagentToolCompleted(parentId: String, toolId: String)
}

struct TranscriptParser {
    func parseLine(_ line: String, session: inout Session) -> [TranscriptEvent] {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        
        let recordType = json["type"] as? String ?? ""
        
        switch recordType {
        case "assistant":
            return handleAssistant(json: json, session: &session)
        case "user":
            return handleUser(json: json, session: &session)
        case "system":
            return handleSystem(json: json, session: &session)
        case "progress":
            return handleProgress(json: json, session: &session)
        default:
            return []
        }
    }
    
    private func handleAssistant(json: [String: Any], session: inout Session) -> [TranscriptEvent] {
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]]
        else { return [] }
        
        var events: [TranscriptEvent] = []
        for block in content where block["type"] as? String == "tool_use" {
            guard let toolId = block["id"] as? String,
                  let toolName = block["name"] as? String else { continue }
            let input = block["input"] as? [String: Any] ?? [:]
            let status = ToolStatusFormatter.format(toolName: toolName, input: input)
            
            session.activeToolIds.insert(toolId)
            session.activity = .tool(toolName)
            session.currentTool = status
            session.lastUpdate = Date()
            events.append(.toolStarted(toolId: toolId, status: status))
        }
        return events
    }
    
    private func handleUser(json: [String: Any], session: inout Session) -> [TranscriptEvent] {
        // Implemented in Task 2.4
        return []
    }
    
    private func handleSystem(json: [String: Any], session: inout Session) -> [TranscriptEvent] {
        // Implemented in Task 2.5
        return []
    }
    
    private func handleProgress(json: [String: Any], session: inout Session) -> [TranscriptEvent] {
        // Implemented in Task 2.6
        return []
    }
}
```

**Step 5: Run test to verify pass**

Expected: `testParsesToolUseBlock` passes.

**Step 6: Commit**

```bash
git commit -am "feat(agenttab): TranscriptParser handles assistant tool_use"
```

---

### Task 2.4: TDD TranscriptParser — user tool_result

**Files:**
- Modify: `agenttab/AgentTAB/Engine/JSONL/TranscriptParser.swift`
- Modify: `agenttab/AgentTABTests/TranscriptParserTests.swift`

**Step 1: Add failing test**

```swift
func testParsesToolResult() {
    let parser = TranscriptParser()
    var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")
    session.activeToolIds = ["t1"]
    session.activity = .tool("Read")
    
    let line = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}"#
    let events = parser.parseLine(line, session: &session)
    XCTAssertEqual(events, [.toolCompleted(toolId: "t1")])
    XCTAssertTrue(session.activeToolIds.isEmpty)
}

func testIgnoresUserTextPromptByDefault() {
    let parser = TranscriptParser()
    var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")
    let line = #"{"type":"user","message":{"content":"hello"}}"#
    let events = parser.parseLine(line, session: &session)
    XCTAssertTrue(events.isEmpty)
}
```

**Step 2: Run, expect fails**

**Step 3: Implement handleUser**

```swift
private func handleUser(json: [String: Any], session: inout Session) -> [TranscriptEvent] {
    guard let message = json["message"] as? [String: Any] else { return [] }
    
    if let content = message["content"] as? [[String: Any]] {
        var events: [TranscriptEvent] = []
        for block in content where block["type"] as? String == "tool_result" {
            guard let toolId = block["tool_use_id"] as? String else { continue }
            session.activeToolIds.remove(toolId)
            session.lastUpdate = Date()
            events.append(.toolCompleted(toolId: toolId))
        }
        return events
    }
    return []
}
```

**Step 4: Run, expect pass**

**Step 5: Commit**

```bash
git commit -am "feat(agenttab): TranscriptParser handles tool_result"
```

---

### Task 2.5: TDD TranscriptParser — turn_duration system record

**Files:**
- Modify: `agenttab/AgentTAB/Engine/JSONL/TranscriptParser.swift`
- Modify: `agenttab/AgentTABTests/TranscriptParserTests.swift`

**Step 1: Add failing test**

```swift
func testTurnDurationEndsTurnAndClearsTools() {
    let parser = TranscriptParser()
    var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")
    session.activeToolIds = ["t1", "t2"]
    session.activity = .thinking
    
    let line = #"{"type":"system","subtype":"turn_duration"}"#
    let events = parser.parseLine(line, session: &session)
    XCTAssertEqual(events, [.turnEnded])
    XCTAssertEqual(session.activity, .waiting)
    XCTAssertTrue(session.activeToolIds.isEmpty)
}
```

**Step 2: Run, expect fails**

**Step 3: Implement handleSystem**

```swift
private func handleSystem(json: [String: Any], session: inout Session) -> [TranscriptEvent] {
    guard json["subtype"] as? String == "turn_duration" else { return [] }
    session.activeToolIds.removeAll()
    session.subagentTools.removeAll()
    session.activity = .waiting
    session.currentTool = nil
    session.lastUpdate = Date()
    return [.turnEnded]
}
```

**Step 4: Run, expect pass**

**Step 5: Commit**

```bash
git commit -am "feat(agenttab): TranscriptParser handles turn_duration"
```

---

### Task 2.6: TDD TranscriptParser — subagent progress records

**Files:**
- Modify: `agenttab/AgentTAB/Engine/JSONL/TranscriptParser.swift`
- Modify: `agenttab/AgentTABTests/TranscriptParserTests.swift`

**Step 1: Add fixture and tests**

Create `agenttab/AgentTABTests/Fixtures/transcripts/subagent_progress.jsonl` with progress records mirroring the structure handled in `transcriptParser.ts:processProgressRecord`.

Test:

```swift
func testProgressRecordTracksSubagentTool() {
    let parser = TranscriptParser()
    var session = Session(claudeSessionId: "x", projectName: "p", projectPath: "/p")
    session.activeToolIds = ["parent_t"]
    
    // Set up parent tool tracking
    var nameMap: [String: String] = ["parent_t": "Task"]
    
    let line = #"{"type":"progress","parentToolUseID":"parent_t","data":{"type":"agent_progress","message":{"type":"assistant","message":{"content":[{"type":"tool_use","id":"sub_t","name":"Bash","input":{"command":"ls"}}]}}}}"#
    
    let events = parser.parseLineWithToolNames(line, session: &session, parentNames: nameMap)
    XCTAssertEqual(events, [.subagentToolStarted(parentId: "parent_t", toolId: "sub_t", status: "Running: ls")])
    XCTAssertEqual(session.subagentTools["parent_t"], ["sub_t"])
}
```

**Step 2: Implement handleProgress**

Port logic from `transcriptParser.ts:195–318`. Key behaviors:
- Verify `parentToolUseID` exists and parent is `Task` or `Agent` (using `parentNames` map for names)
- Distinguish `bash_progress`/`mcp_progress` (just keep timer alive) vs `agent_progress` (actual subagent tool tracking)
- For `agent_progress` with `assistant` inner message: track sub-tool IDs in `session.subagentTools[parentId]`
- For `agent_progress` with `user` inner message containing `tool_result`: remove from tracking

**Step 3: Pass tests, commit**

```bash
git commit -am "feat(agenttab): TranscriptParser handles subagent progress records"
```

---

### Task 2.7: TDD permission timer logic

**Files:**
- Create: `agenttab/AgentTAB/Engine/PermissionTimer.swift`
- Create: `agenttab/AgentTABTests/PermissionTimerTests.swift`

**Step 1: Write failing test**

```swift
import XCTest
@testable import AgentTAB

final class PermissionTimerTests: XCTestCase {
    func testFiresAfter5SecondsWithActiveNonExemptTool() async throws {
        let timer = PermissionTimer()
        var fired = false
        timer.start(for: "session1", hasNonExemptTool: true) { fired = true }
        
        try await Task.sleep(for: .seconds(6))
        XCTAssertTrue(fired)
    }
    
    func testDoesNotFireForExemptToolsOnly() async throws {
        let timer = PermissionTimer()
        var fired = false
        timer.start(for: "session1", hasNonExemptTool: false) { fired = true }
        
        try await Task.sleep(for: .seconds(6))
        XCTAssertFalse(fired)
    }
    
    func testCanCancel() async throws {
        let timer = PermissionTimer()
        var fired = false
        timer.start(for: "session1", hasNonExemptTool: true) { fired = true }
        timer.cancel(for: "session1")
        
        try await Task.sleep(for: .seconds(6))
        XCTAssertFalse(fired)
    }
}
```

**Step 2: Implement**

```swift
// PermissionTimer.swift
import Foundation

final class PermissionTimer {
    private var timers: [String: Task<Void, Never>] = [:]
    static let exemptTools: Set<String> = ["AskUserQuestion", "Read", "Grep", "Glob", "ListDir"]
    static let delaySeconds: TimeInterval = 5
    
    func start(for sessionId: String, hasNonExemptTool: Bool, fire: @escaping () -> Void) {
        cancel(for: sessionId)
        guard hasNonExemptTool else { return }
        timers[sessionId] = Task {
            try? await Task.sleep(for: .seconds(Self.delaySeconds))
            guard !Task.isCancelled else { return }
            fire()
        }
    }
    
    func cancel(for sessionId: String) {
        timers[sessionId]?.cancel()
        timers[sessionId] = nil
    }
}
```

**Step 3: Pass, commit**

```bash
git commit -am "feat(agenttab): permission timer with EXEMPT_TOOLS exemption"
```

---

### Task 2.8: TDD project name extraction from Claude path hash

**Files:**
- Create: `agenttab/AgentTAB/Engine/JSONL/SessionDiscovery.swift`
- Create: `agenttab/AgentTABTests/SessionDiscoveryTests.swift`

**Step 1: Write failing tests**

```swift
import XCTest
@testable import AgentTAB

final class SessionDiscoveryTests: XCTestCase {
    func testExtractsRepoNameFromSimpleProject() {
        let result = SessionDiscovery.hashToProjectName("-Users-adi-Desktop-my-repo")
        XCTAssertEqual(result, "my-repo")
    }
    
    func testExtractsRepoSlashBranchFromWorktree() {
        let result = SessionDiscovery.hashToProjectName("-Users-adi-Desktop-my-repo--worktrees-feat-x")
        XCTAssertEqual(result, "my-repo/feat-x")
    }
    
    func testFallsBackToLastSegmentIfDesktopMissing() {
        let result = SessionDiscovery.hashToProjectName("foo-bar-baz")
        XCTAssertEqual(result, "baz")
    }
}
```

**Step 2: Implement**

Port from `server/src/sessionManager.ts:hashToProjectName` (lines 168–197):

```swift
// SessionDiscovery.swift
import Foundation

enum SessionDiscovery {
    static func hashToProjectName(_ hash: String) -> String {
        let parts = hash.split(separator: "-").filter { !$0.isEmpty }.map(String.init)
        guard let desktopIdx = parts.firstIndex(of: "Desktop") else {
            return parts.last ?? hash
        }
        let afterDesktop = Array(parts[(desktopIdx + 1)...])
        guard let worktreeIdx = afterDesktop.firstIndex(where: { $0 == "worktrees" || $0 == "worktree" }) else {
            return afterDesktop.joined(separator: "-")
        }
        let repo = afterDesktop[..<worktreeIdx].joined(separator: "-")
        let branch = afterDesktop[(worktreeIdx + 1)...].joined(separator: "-")
        return branch.isEmpty ? repo : "\(repo)/\(branch)"
    }
}
```

**Step 3: Pass, commit**

```bash
git commit -am "feat(agenttab): port hashToProjectName from sessionManager.ts"
```

---

### Task 2.9: Implement JSONLWatcher — file system events

**Files:**
- Create: `agenttab/AgentTAB/Engine/JSONL/JSONLWatcher.swift`

**Step 1: Implement directory watcher**

```swift
// JSONLWatcher.swift
import Foundation

final class JSONLWatcher {
    private let projectsDir: URL
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSources: [URL: DispatchSourceFileSystemObject] = [:]
    private var fileOffsets: [URL: UInt64] = [:]
    private var lineBuffers: [URL: String] = [:]
    private let queue = DispatchQueue(label: "agenttab.jsonl", qos: .utility)
    
    let activeThresholdSeconds: TimeInterval = 30 * 60     // 30 min
    
    var onLine: ((URL, String) -> Void)?
    var onSessionDiscovered: ((URL, String) -> Void)?      // jsonlPath, projectHash
    
    init(projectsDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")) {
        self.projectsDir = projectsDir
    }
    
    func start() {
        guard FileManager.default.fileExists(atPath: projectsDir.path) else { return }
        
        // Initial scan
        scanProjectsDirectory()
        
        // Watch for new project dirs
        let fd = open(projectsDir.path, O_EVTONLY)
        directorySource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename], queue: queue)
        directorySource?.setEventHandler { [weak self] in self?.scanProjectsDirectory() }
        directorySource?.setCancelHandler { close(fd) }
        directorySource?.resume()
    }
    
    func stop() {
        directorySource?.cancel()
        directorySource = nil
        for (_, source) in fileSources { source.cancel() }
        fileSources.removeAll()
    }
    
    private func scanProjectsDirectory() {
        guard let projects = try? FileManager.default.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil) else { return }
        
        for projectURL in projects {
            guard let isDir = (try? projectURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory,
                  isDir else { continue }
            scanProjectFolder(projectURL)
        }
    }
    
    private func scanProjectFolder(_ projectURL: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: projectURL, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        
        for fileURL in files where fileURL.pathExtension == "jsonl" {
            guard fileSources[fileURL] == nil else { continue }
            
            // Skip stale files
            let mtime = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(mtime) > activeThresholdSeconds { continue }
            
            // Pick up
            let projectHash = projectURL.lastPathComponent
            onSessionDiscovered?(fileURL, projectHash)
            startWatching(fileURL: fileURL)
        }
    }
    
    private func startWatching(fileURL: URL) {
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend], queue: queue)
        source.setEventHandler { [weak self] in self?.readNewLines(from: fileURL) }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileSources[fileURL] = source
        
        // Initial read for catch-up
        readNewLines(from: fileURL)
    }
    
    private func readNewLines(from fileURL: URL) {
        let offset = fileOffsets[fileURL] ?? 0
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }
        
        do {
            try handle.seek(toOffset: offset)
            let data = handle.readDataToEndOfFile()
            guard !data.isEmpty else { return }
            
            let newOffset = offset + UInt64(data.count)
            fileOffsets[fileURL] = newOffset
            
            let buffer = (lineBuffers[fileURL] ?? "") + (String(data: data, encoding: .utf8) ?? "")
            var lines = buffer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            lineBuffers[fileURL] = lines.popLast() ?? ""
            
            for line in lines where !line.isEmpty {
                onLine?(fileURL, line)
            }
        } catch {
            // file may have been rotated — restart watch
        }
    }
}
```

**Step 2: Build to verify compiles**

Run: `xcodebuild build -scheme AgentTAB`
Expected: build succeeds, no warnings.

**Step 3: Commit**

```bash
git add agenttab/AgentTAB/Engine/JSONL/JSONLWatcher.swift
git commit -m "feat(agenttab): JSONLWatcher — directory + per-file DispatchSource"
```

---

### Task 2.10: Implement ActivityEngine actor

**Files:**
- Create: `agenttab/AgentTAB/Engine/ActivityEngine.swift`

**Step 1: Implement engine**

```swift
// ActivityEngine.swift
import Foundation
import Combine

@MainActor
final class ActivityEngine: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    
    private var sessionsByJsonlURL: [URL: UUID] = [:]
    private var sessionsByClaudeId: [String: UUID] = [:]
    private let parser = TranscriptParser()
    private let permissionTimer = PermissionTimer()
    private let jsonlWatcher: JSONLWatcher
    
    init(projectsDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")) {
        self.jsonlWatcher = JSONLWatcher(projectsDir: projectsDir)
    }
    
    func start() {
        jsonlWatcher.onSessionDiscovered = { [weak self] url, projectHash in
            Task { @MainActor in self?.discoverSession(jsonlURL: url, projectHash: projectHash) }
        }
        jsonlWatcher.onLine = { [weak self] url, line in
            Task { @MainActor in self?.applyLine(line, jsonlURL: url) }
        }
        jsonlWatcher.start()
    }
    
    private func discoverSession(jsonlURL: URL, projectHash: String) {
        let claudeSessionId = jsonlURL.deletingPathExtension().lastPathComponent
        let projectName = SessionDiscovery.hashToProjectName(projectHash)
        let projectPath = "/" + projectHash.replacingOccurrences(of: "-", with: "/")
        
        let session = Session(
            claudeSessionId: claudeSessionId,
            projectName: projectName,
            projectPath: projectPath
        )
        sessions.append(session)
        sessionsByJsonlURL[jsonlURL] = session.id
        sessionsByClaudeId[claudeSessionId] = session.id
        
        print("[Engine] New session: \(claudeSessionId) (\(projectName))")
    }
    
    private func applyLine(_ line: String, jsonlURL: URL) {
        guard let id = sessionsByJsonlURL[jsonlURL],
              let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var session = sessions[index]
        let events = parser.parseLine(line, session: &session)
        sessions[index] = session
        
        // Drive permission timer based on session state
        let nonExemptTool = session.activeToolIds.contains { _ in
            // For now, assume any active tool may need permission unless we track names
            true
        }
        permissionTimer.start(for: session.claudeSessionId, hasNonExemptTool: nonExemptTool) {
            Task { @MainActor in
                guard let idx = self.sessions.firstIndex(where: { $0.id == id }) else { return }
                self.sessions[idx].activity = .waiting
            }
        }
        
        if !events.isEmpty {
            print("[Engine] Session \(session.claudeSessionId): \(events)")
        }
    }
}
```

**Step 2: Build, commit**

```bash
git commit -am "feat(agenttab): ActivityEngine actor wiring JSONL pipeline"
```

---

### Task 2.11: Wire engine to NotchView with debug list

**Files:**
- Modify: `agenttab/AgentTAB/UI/NotchView.swift`
- Modify: `agenttab/AgentTAB/App/AppDelegate.swift`

**Step 1: Add engine to AppDelegate**

```swift
// In AppDelegate:
var engine = ActivityEngine()

// In applicationDidFinishLaunching, after creating notchPanel:
engine.start()
notchPanel = NotchPanel(rootView: AnyView(
    NotchView()
        .environment(\.notchGeometry, geometry)
        .environmentObject(engine)
))
```

**Step 2: Update NotchView to show real session list**

```swift
// NotchView.swift
import SwiftUI

struct NotchView: View {
    @Environment(\.notchGeometry) var geometry
    @EnvironmentObject var engine: ActivityEngine
    @State private var isHovered = false
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                if isHovered {
                    expanded
                } else {
                    pill
                }
                Spacer()
            }
            Spacer()
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isHovered)
    }
    
    private var pill: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.fill")
                .foregroundStyle(.blue)
            Text("\(activeCount)")
                .font(.system(size: 12, weight: .medium))
            Text("•")
            Text("\(doneCount) done")
                .font(.system(size: 11))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .onHover { hovering in isHovered = hovering }
    }
    
    private var expanded: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(engine.sessions) { session in
                HStack {
                    Text(session.projectName).font(.system(size: 11, weight: .medium))
                    Text("·").foregroundStyle(.secondary)
                    Text(session.currentTool ?? activityLabel(session.activity))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering in isHovered = hovering }
    }
    
    private var activeCount: Int {
        engine.sessions.filter {
            if case .thinking = $0.activity { return true }
            if case .tool = $0.activity { return true }
            return false
        }.count
    }
    private var doneCount: Int {
        engine.sessions.filter { $0.activity == .done }.count
    }
    private func activityLabel(_ a: Activity) -> String {
        switch a {
        case .thinking: return "Thinking…"
        case .tool(let n): return "Using \(n)"
        case .waiting: return "Waiting"
        case .done: return "Done"
        case .initState: return "Starting"
        case .idle: return "Idle"
        }
    }
}
```

**Step 3: Manually verify**

Open Claude Code in any terminal. Make Claude do something (e.g. ask a quick question). Expected:
- A debug pill appears at the notch showing `● 1 · 0 done` once Claude starts
- Hovering expands it to show the session row with project name + current tool
- As Claude transitions Thinking → Tool → Done, the row updates within ~1 second
- After 30s+ of no Claude activity, the session moves to "Done" (note: `.done` transition is currently driven only by `turn_duration` records; full timer-based "Idle" decay arrives in M5)

**Step 4: Commit**

```bash
git commit -am "feat(agenttab): wire ActivityEngine to NotchView debug list"
```

---

### Task 2.12: Add JSONL pipeline integration tests

**Files:**
- Create: `agenttab/AgentTABTests/JSONLPipelineIntegrationTests.swift`

**Step 1: Write integration test using temp directory**

```swift
import XCTest
@testable import AgentTAB

final class JSONLPipelineIntegrationTests: XCTestCase {
    func testEngineDiscoversSessionFromTempProjectDir() async throws {
        let tempProjectsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agenttab-test-\(UUID().uuidString)")
        let projectDir = tempProjectsDir.appendingPathComponent("-Users-test-myapp")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        
        // Pre-create a JSONL with one tool_use record
        let jsonlURL = projectDir.appendingPathComponent("session-abc.jsonl")
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/x.swift"}}]}}\n"#
        try line.write(to: jsonlURL, atomically: true, encoding: .utf8)
        
        let engine = ActivityEngine(projectsDir: tempProjectsDir)
        engine.start()
        
        // Wait for async discovery
        try await Task.sleep(for: .seconds(2))
        
        XCTAssertEqual(engine.sessions.count, 1)
        XCTAssertEqual(engine.sessions.first?.projectName, "myapp")
        XCTAssertEqual(engine.sessions.first?.currentTool, "Reading x.swift")
        
        try? FileManager.default.removeItem(at: tempProjectsDir)
    }
}
```

**Step 2: Run, ensure passes**

`xcodebuild test -scheme AgentTAB -only-testing:AgentTABTests/JSONLPipelineIntegrationTests`

**Step 3: Commit**

```bash
git commit -am "test(agenttab): JSONL pipeline integration test"
```

---

**Milestone 2 complete.** Real Claude sessions are discovered, parsed, and shown in the notch. State transitions work end-to-end via JSONL tailing alone.

---

## Milestone 3: Animations + Expanded View

**Goal:** Replace the debug pill with the production visual: dark glass pill, three zones (cardio loader / counts), coffee+steam animation when idle. Expanded view shows tab-grouped session list with click-to-focus actions.

**End state:** Visually indistinguishable from a polished native macOS app. Click on a session row jumps to the right Zellij pane (when applicable) or opens the project folder.

### Task 3.1: Theme module — palette and animation constants

**Files:**
- Create: `agenttab/AgentTAB/UI/Theme.swift`

**Step 1: Implement Theme**

```swift
// Theme.swift
import SwiftUI

enum Theme {
    // Glass / chrome — ported from Hammerspoon claude-status.lua
    static let glassBG     = Color(red: 0.09, green: 0.09, blue: 0.13).opacity(0.94)
    static let borderOuter = Color(white: 0.52).opacity(0.55)
    static let borderInner = Color.white.opacity(0.04)
    static let textPrimary = Color.white.opacity(0.88)
    static let textDim     = Color.white.opacity(0.35)
    static let rowEven     = Color.white.opacity(0.025)
    static let rowHighlight = Color.white.opacity(0.05)
    
    enum Activity {
        static let thinking  = Color(red: 0.45, green: 0.65, blue: 1.00)   // soft blue
        static let tool      = Color(red: 1.00, green: 0.75, blue: 0.25)   // amber
        static let waiting   = Color(red: 1.00, green: 0.55, blue: 0.35)   // orange
        static let done      = Color(red: 0.45, green: 0.82, blue: 0.50)   // green
        static let initState = Color(red: 0.55, green: 0.55, blue: 0.60)   // gray
        static let idle      = Color(red: 0.45, green: 0.82, blue: 0.50).opacity(0.5)
    }
    
    enum Animations {
        static let notch = SwiftUI.Animation.spring(response: 0.42, dampingFraction: 0.78)
        static let coffeeSteamPeriod: Double = 4.8
        static let cardioPeriod: Double = 1.5
        static let waitingPulsePeriod: Double = 1.6
        static let completionFlashDuration: Double = 1.5
    }
    
    enum Layout {
        static let pillHeight: CGFloat = 32
        static let pillWidthCollapsed: CGFloat = 180
        static let expandedWidth: CGFloat = 380
        static let expandedMaxHeight: CGFloat = 460
        static let notchCarveCornerRadius: CGFloat = 10
        static let panelMaxWidth: CGFloat = 420
        static let panelMaxHeight: CGFloat = 460
    }
}

extension AgentTAB.Activity {
    var color: Color {
        switch self {
        case .thinking:  return Theme.Activity.thinking
        case .tool:      return Theme.Activity.tool
        case .waiting:   return Theme.Activity.waiting
        case .done:      return Theme.Activity.done
        case .initState: return Theme.Activity.initState
        case .idle:      return Theme.Activity.idle
        }
    }
}
```

**Step 2: Commit**

```bash
git commit -am "feat(agenttab): Theme module with palette + animation constants"
```

---

### Task 3.2: NotchShape — pill silhouette with notch carve

**Files:**
- Create: `agenttab/AgentTAB/UI/Animations/NotchShape.swift`

**Step 1: Implement Shape**

```swift
// NotchShape.swift
import SwiftUI

/// A rounded-bottom pill with an optional notch carve at the top center.
/// Top corners curve INWARD (toward the notch's bottom edges) when notch is present.
struct NotchShape: Shape {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let cornerRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = cornerRadius
        let nw = notchWidth
        let nh = notchHeight
        let centerX = rect.midX
        
        // Start: top-left of pill
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        
        if nw > 0 {
            // Top edge: line up to where the notch carve begins
            let notchLeft = centerX - nw / 2
            let notchRight = centerX + nw / 2
            path.addLine(to: CGPoint(x: notchLeft - r, y: rect.minY))
            // Carve in: curve down to the notch's bottom edge
            path.addQuadCurve(
                to: CGPoint(x: notchLeft, y: rect.minY + r),
                control: CGPoint(x: notchLeft, y: rect.minY)
            )
            // Bottom of notch (straight across)
            path.addLine(to: CGPoint(x: notchRight, y: rect.minY + r))
            // Carve out: curve back up
            path.addQuadCurve(
                to: CGPoint(x: notchRight + r, y: rect.minY),
                control: CGPoint(x: notchRight, y: rect.minY)
            )
        }
        
        // Top-right corner
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + r),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        // Right edge
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        // Bottom-right
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        // Bottom edge
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        // Bottom-left
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        // Left edge
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        // Top-left
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        return path
    }
}
```

**Step 2: Visual verify with SwiftUI preview**

Add at bottom of file:

```swift
#Preview {
    VStack(spacing: 20) {
        NotchShape(notchWidth: 200, notchHeight: 32, cornerRadius: 10)
            .fill(Theme.glassBG)
            .frame(width: 420, height: 100)
        NotchShape(notchWidth: 0, notchHeight: 0, cornerRadius: 10)
            .fill(Theme.glassBG)
            .frame(width: 320, height: 50)
    }
    .padding(40)
    .background(Color.gray)
}
```

Open in Xcode preview canvas. Expected: dark glass shape with a clean curved cutout where the notch sits in the first variant; plain pill in the second.

**Step 3: Commit**

```bash
git commit -am "feat(agenttab): NotchShape with notch carve geometry"
```

---

### Task 3.3: CardioLoader — port l-cardio waveform

**Files:**
- Create: `agenttab/AgentTAB/UI/Animations/CardioLoader.swift`

**Step 1: Implement**

The original LDRS `l-cardio` path: `M0.5,17.2h8.2l3-4.7l5.9,12l7.8-24l5.9,16.7v0h8.2`. Render as Canvas with phase animation.

```swift
// CardioLoader.swift
import SwiftUI

struct CardioLoader: View {
    @State private var phase: Double = 0
    var color: Color = Theme.Activity.thinking
    var size: CGFloat = 24
    
    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let p = (elapsed / Theme.Animations.cardioPeriod).truncatingRemainder(dividingBy: 1)
            
            Canvas { ctx, canvasSize in
                let path = cardioPath(in: CGSize(width: canvasSize.width, height: canvasSize.height))
                
                // Trail: draw a fading window 0..p
                let trim = path.trimmedPath(from: max(0, p - 0.25), to: p)
                let stroke = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                
                ctx.opacity = 0.2 + 0.8 * sin(p * .pi)   // fade in/out per cycle
                ctx.stroke(trim, with: .color(color), style: stroke)
                
                // Glow
                ctx.addFilter(.shadow(color: color.opacity(0.4), radius: 4))
                ctx.stroke(trim, with: .color(color), style: stroke)
            }
            .frame(width: size, height: size * 0.625)
        }
    }
    
    private func cardioPath(in s: CGSize) -> Path {
        // Path coords from l-cardio: viewBox 40 x 25, scaled to (s.width / 40)
        let scale = s.width / 40
        let y0 = 17.2 * scale
        var path = Path()
        path.move(to: CGPoint(x: 0.5 * scale, y: y0))
        path.addLine(to: CGPoint(x: 8.7 * scale, y: y0))
        path.addLine(to: CGPoint(x: 11.7 * scale, y: (17.2 - 4.7) * scale))
        path.addLine(to: CGPoint(x: 17.6 * scale, y: (17.2 - 4.7 + 12) * scale))
        path.addLine(to: CGPoint(x: 25.4 * scale, y: (17.2 - 4.7 + 12 - 24) * scale))
        path.addLine(to: CGPoint(x: 31.3 * scale, y: (17.2 - 4.7 + 12 - 24 + 16.7) * scale))
        path.addLine(to: CGPoint(x: 39.5 * scale, y: y0))
        return path
    }
}

#Preview {
    CardioLoader()
        .padding()
        .background(Color.black)
}
```

**Step 2: Visual verify in preview**

Open preview canvas. Expected: a heart-monitor-style line continuously sweeps across the icon area with a glowing blue color, fading in and out.

**Step 3: Commit**

```bash
git commit -am "feat(agenttab): CardioLoader port of LDRS l-cardio"
```

---

### Task 3.4: CoffeeIdle — port coffee + steam animation

**Files:**
- Create: `agenttab/AgentTAB/UI/Animations/CoffeeIdle.swift`

**Step 1: Implement**

Port from `webview/icons.lua:13` (cup body) and `webview/styles.lua:255` (steam keyframes).

```swift
// CoffeeIdle.swift
import SwiftUI

struct CoffeeIdle: View {
    var size: CGFloat = 14
    
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                // Static cup body — paths from icons.lua:13
                CoffeeBody().stroke(
                    Color.white.opacity(0.62),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                )
                
                // Three steam wisps with phase-shifted animation
                SmokeWisp(pathIndex: 0, phase: phase(t, offset: 0.0))
                SmokeWisp(pathIndex: 1, phase: phase(t, offset: 0.33))
                SmokeWisp(pathIndex: 2, phase: phase(t, offset: 0.66))
            }
            .frame(width: size, height: size)
        }
    }
    
    private func phase(_ t: TimeInterval, offset: Double) -> Double {
        let p = ((t / Theme.Animations.coffeeSteamPeriod) + offset).truncatingRemainder(dividingBy: 1)
        return p < 0 ? p + 1 : p
    }
}

private struct CoffeeBody: Shape {
    func path(in rect: CGRect) -> Path {
        // viewBox 24×24 — paths from icons.lua:13 (cup outline only)
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        // path: M18 8 h1 a4 4 0 1 1 0 8 h-1
        // path: M4 8 h14 v7 a6 6 0 0 1-6 6 H10 a6 6 0 0 1-6-6 Z
        // path: M6 8 h10
        // For brevity, approximate with a simple cup shape:
        path.move(to: CGPoint(x: 4 * s, y: 8 * s))
        path.addLine(to: CGPoint(x: 18 * s, y: 8 * s))
        path.addLine(to: CGPoint(x: 18 * s, y: 15 * s))
        path.addArc(center: CGPoint(x: 12 * s, y: 15 * s), radius: 6 * s,
                    startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: 4 * s, y: 8 * s))
        path.closeSubpath()
        // Handle
        path.move(to: CGPoint(x: 18 * s, y: 8 * s))
        path.addLine(to: CGPoint(x: 19 * s, y: 8 * s))
        path.addArc(center: CGPoint(x: 19 * s, y: 12 * s), radius: 4 * s,
                    startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: 18 * s, y: 16 * s))
        return path
    }
}

private struct SmokeWisp: View {
    let pathIndex: Int
    let phase: Double
    
    var body: some View {
        // Opacity wave: 0 → 0.24 → 0.76 → 0.08 → 0 across 0..1 of phase
        let opacity: Double = {
            switch phase {
            case 0..<0.18: return phase / 0.18 * 0.24
            case 0.18..<0.42: return 0.24 + (phase - 0.18) / 0.24 * (0.76 - 0.24)
            case 0.42..<0.78: return 0.76 - (phase - 0.42) / 0.36 * (0.76 - 0.08)
            case 0.78..<1.0: return 0.08 - (phase - 0.78) / 0.22 * 0.08
            default: return 0
            }
        }()
        let dy: CGFloat = -CGFloat(phase * 12 - 3)   // +3 → -9 px translate
        
        SteamPath(index: pathIndex)
            .stroke(
                Color.white.opacity(0.62 * opacity),
                style: StrokeStyle(
                    lineWidth: pathIndex == 1 ? 2.15 : (pathIndex == 0 ? 1.45 : 1.55),
                    lineCap: .round
                )
            )
            .offset(y: dy)
    }
}

private struct SteamPath: Shape {
    let index: Int
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        // Three wisp paths from icons.lua:13:
        // 1: M7.1 7.1 C 4.2 5.2, 10.1 5.6, 7.4 4.6
        // 2: M11 7.1 C 8.1 5.1, 14 3.9, 11.2 1.3
        // 3: M14.9 7.1 C 12 5.2, 17.8 5.6, 15 4.6
        switch index {
        case 0:
            path.move(to: CGPoint(x: 7.1 * s, y: 7.1 * s))
            path.addCurve(to: CGPoint(x: 7.4 * s, y: 4.6 * s),
                          control1: CGPoint(x: 4.2 * s, y: 5.2 * s),
                          control2: CGPoint(x: 10.1 * s, y: 5.6 * s))
        case 1:
            path.move(to: CGPoint(x: 11 * s, y: 7.1 * s))
            path.addCurve(to: CGPoint(x: 11.2 * s, y: 1.3 * s),
                          control1: CGPoint(x: 8.1 * s, y: 5.1 * s),
                          control2: CGPoint(x: 14 * s, y: 3.9 * s))
        case 2:
            path.move(to: CGPoint(x: 14.9 * s, y: 7.1 * s))
            path.addCurve(to: CGPoint(x: 15 * s, y: 4.6 * s),
                          control1: CGPoint(x: 12 * s, y: 5.2 * s),
                          control2: CGPoint(x: 17.8 * s, y: 5.6 * s))
        default: break
        }
        return path
    }
}

#Preview {
    CoffeeIdle(size: 28)
        .padding()
        .background(Color.black)
}
```

**Step 2: Visual verify**

Preview canvas. Expected: small cup outline, three steam wisps rise from the cup mouth in sequence with the existing 4.8s period. Steam fades in, peaks around 42% of cycle, fades out as it rises.

**Step 3: Commit**

```bash
git commit -am "feat(agenttab): CoffeeIdle port of webview coffee+steam animation"
```

---

### Task 3.5: PillView — three-zone production pill

**Files:**
- Create: `agenttab/AgentTAB/UI/PillView.swift`

**Step 1: Implement PillView**

```swift
// PillView.swift
import SwiftUI

struct PillView: View {
    @EnvironmentObject var engine: ActivityEngine
    @Environment(\.notchGeometry) var geometry
    
    var body: some View {
        HStack(spacing: 0) {
            loaderSlot
                .frame(width: 28)
                .padding(.leading, 14)
            
            Spacer().frame(width: max(geometry.notchWidth, 16))
            
            countsSlot
                .padding(.trailing, 14)
        }
        .frame(height: Theme.Layout.pillHeight)
        .background(
            NotchShape(notchWidth: geometry.notchWidth,
                       notchHeight: 0,    // pill drawn below notch, no top carve
                       cornerRadius: Theme.Layout.notchCarveCornerRadius)
                .fill(Theme.glassBG)
                .background(.ultraThinMaterial)
        )
        .overlay(
            NotchShape(notchWidth: geometry.notchWidth,
                       notchHeight: 0,
                       cornerRadius: Theme.Layout.notchCarveCornerRadius)
                .stroke(Theme.borderOuter, lineWidth: 0.5)
        )
    }
    
    @ViewBuilder
    private var loaderSlot: some View {
        if hasActiveSession {
            CardioLoader(color: Theme.Activity.thinking, size: 24)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else {
            CoffeeIdle(size: 14)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
    
    private var countsSlot: some View {
        HStack(spacing: 8) {
            if waitingCount > 0 {
                Label("\(waitingCount)", systemImage: "pause.fill")
                    .foregroundStyle(Theme.Activity.waiting)
            }
            if inProgressCount > 0 {
                Label("\(inProgressCount)", systemImage: "bolt.fill")
                    .foregroundStyle(Theme.Activity.tool)
            }
            if doneCount > 0 {
                Label("\(doneCount)", systemImage: "checkmark")
                    .foregroundStyle(Theme.Activity.done)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .contentTransition(.numericText())
    }
    
    private var hasActiveSession: Bool {
        engine.sessions.contains { sess in
            switch sess.activity {
            case .thinking, .tool: return true
            default: return false
            }
        }
    }
    private var inProgressCount: Int {
        engine.sessions.filter {
            if case .thinking = $0.activity { return true }
            if case .tool = $0.activity { return true }
            return false
        }.count
    }
    private var waitingCount: Int { engine.sessions.filter { $0.activity == .waiting }.count }
    private var doneCount: Int { engine.sessions.filter { $0.activity == .done }.count }
}
```

**Step 2: Replace placeholder pill in NotchView**

Replace the `pill` computed property body with `PillView()`.

**Step 3: Visual verify**

Run app with at least one Claude session. Expected:
- Pill appears at the notch with dark glass + frosted background
- When sessions are active: cardio waveform animates on the left of the notch
- When no sessions are active: coffee icon with rising steam appears
- Right side: chips for waiting/in-progress/done counts (only visible when count > 0)
- Counts roll smoothly when they change

**Step 4: Commit**

```bash
git commit -am "feat(agenttab): production PillView with cardio + coffee + counts"
```

---

### Task 3.6: ExpandedView — tab-grouped session list

**Files:**
- Create: `agenttab/AgentTAB/UI/ExpandedView.swift`
- Create: `agenttab/AgentTAB/UI/Rows/SessionRow.swift`
- Create: `agenttab/AgentTAB/UI/Rows/TabHeader.swift`

**Step 1: Implement TabHeader**

```swift
// TabHeader.swift
import SwiftUI

struct TabHeader: View {
    let title: String           // "Zellij · Tab 2 · feat-auth"
    
    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.textDim)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }
}
```

**Step 2: Implement SessionRow**

```swift
// SessionRow.swift
import SwiftUI

struct SessionRow: View {
    let session: Session
    let onClick: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            iconForActivity
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(session.projectName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(session.currentTool ?? activityLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isHovered {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textDim)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovered ? Theme.rowHighlight : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(Theme.Animations.notch) { isHovered = hovering } }
        .onTapGesture { onClick() }
    }
    
    @ViewBuilder
    private var iconForActivity: some View {
        switch session.activity {
        case .thinking:
            Circle().fill(Theme.Activity.thinking).frame(width: 8, height: 8)
        case .tool:
            Image(systemName: "bolt.fill").foregroundStyle(Theme.Activity.tool).font(.system(size: 12))
        case .waiting:
            Image(systemName: "pause.fill").foregroundStyle(Theme.Activity.waiting).font(.system(size: 12))
        case .done:
            Image(systemName: "checkmark").foregroundStyle(Theme.Activity.done).font(.system(size: 12))
        case .initState:
            Circle().fill(Theme.Activity.initState).frame(width: 6, height: 6)
        case .idle:
            Circle().stroke(Theme.Activity.idle, lineWidth: 1).frame(width: 6, height: 6)
        }
    }
    
    private var activityLabel: String {
        switch session.activity {
        case .thinking: return "Thinking…"
        case .tool(let n): return "Using \(n)"
        case .waiting: return "Waiting"
        case .done: return "Done"
        case .initState: return "Starting"
        case .idle: return "Idle"
        }
    }
}
```

**Step 3: Implement ExpandedView with grouping**

```swift
// ExpandedView.swift
import SwiftUI

struct ExpandedView: View {
    @EnvironmentObject var engine: ActivityEngine
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Compact pill row at top
            PillView().scaleEffect(0.95)
            
            Divider().opacity(0.2)
            
            // Tab-grouped session list
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groupedSessions, id: \.0) { (groupTitle, groupSessions) in
                        TabHeader(title: groupTitle)
                        ForEach(groupSessions) { session in
                            SessionRow(session: session) {
                                handleClick(session)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: Theme.Layout.expandedMaxHeight - 80)
        }
        .frame(width: Theme.Layout.expandedWidth)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.glassBG)
                .background(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.borderOuter, lineWidth: 0.5)
        )
    }
    
    private var groupedSessions: [(String, [Session])] {
        let grouped = Dictionary(grouping: engine.sessions) { session -> String in
            switch session.terminalKind {
            case .zellij(let info): return "Zellij · Tab \(info.tabIndex) · \(info.tabName)"
            case .generic(let term): return term ?? "Other terminal"
            }
        }
        return grouped.sorted { $0.key < $1.key }
    }
    
    private func handleClick(_ session: Session) {
        switch session.terminalKind {
        case .zellij(let info):
            // Run zellij action focus-pane <id>
            let task = Process()
            task.launchPath = "/usr/bin/env"
            task.arguments = ["zellij", "action", "focus-pane", "\(info.paneId)"]
            try? task.run()
            // Bring the terminal app forward
            NSWorkspace.shared.launchApplication("Ghostty")  // Will refine in M5
        case .generic(let term):
            if let term = term {
                NSWorkspace.shared.launchApplication(term)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.projectPath)])
            }
        }
    }
}
```

**Step 4: Wire into NotchView**

```swift
// In NotchView, replace expanded body with:
ExpandedView()
```

**Step 5: Visual verify**

Hover over pill. Expected:
- Pill expands smoothly with spring animation into the wider expanded panel
- Sessions are grouped under headers
- Hovering a row highlights it and reveals an `↗` icon at the right edge
- Clicking a Zellij row triggers `zellij action focus-pane` and brings the terminal forward
- Clicking a non-Zellij row opens the project folder in Finder

**Step 6: Commit**

```bash
git commit -am "feat(agenttab): ExpandedView with tab grouping + click-to-focus"
```

---

### Task 3.7: NSTrackingArea hover detection with debounce

**Files:**
- Modify: `agenttab/AgentTAB/UI/NotchPanel.swift`
- Modify: `agenttab/AgentTAB/UI/NotchView.swift`

**Step 1: Replace SwiftUI .onHover with NSTrackingArea**

The `.onHover` modifier is unreliable for borderless panels because of how the panel intercepts mouse events. Switch to a `NSViewRepresentable` wrapping a tracking area with debounce.

```swift
// NotchView.swift addition
import AppKit

struct HoverTracker: NSViewRepresentable {
    let onHover: (Bool) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = TrackingNSView()
        view.onHover = onHover
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

private final class TrackingNSView: NSView {
    var onHover: ((Bool) -> Void)?
    private var debounceTask: DispatchWorkItem?
    
    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }
    
    override func mouseEntered(with event: NSEvent) {
        debounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.onHover?(true) }
        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: task)
    }
    
    override func mouseExited(with event: NSEvent) {
        debounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.onHover?(false) }
        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }
}
```

Replace `.onHover { ... }` calls with `.background(HoverTracker(onHover: { ... }))`.

**Step 2: Visual verify**

Move cursor across pill. Expected:
- Brief grace period (~120ms) before expand triggers (no jitter when crossing menu bar)
- Brief grace period (~250ms) before collapse triggers (no flicker)
- Both transitions feel deliberate but responsive

**Step 3: Commit**

```bash
git commit -am "feat(agenttab): NSTrackingArea hover with debounce"
```

---

### Task 3.8: Activity-tinted row pulse for waiting state

**Files:**
- Modify: `agenttab/AgentTAB/UI/Rows/SessionRow.swift`

**Step 1: Add waiting pulse**

```swift
// Inside SessionRow body, wrap the iconForActivity:
iconForActivity
    .modifier(WaitingPulse(isActive: session.activity == .waiting))

// Add at bottom of file:
struct WaitingPulse: ViewModifier {
    let isActive: Bool
    @State private var pulse: CGFloat = 1.0
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? pulse : 1.0)
            .onAppear {
                guard isActive else { return }
                withAnimation(.easeInOut(duration: Theme.Animations.waitingPulsePeriod)
                    .repeatForever(autoreverses: true)) {
                    pulse = 1.15
                }
            }
    }
}
```

**Step 2: Visual verify**

When a session enters waiting state, its icon pulses subtly. Expected period: 1.6s.

**Step 3: Commit**

```bash
git commit -am "feat(agenttab): waiting-state pulse animation on row icon"
```

---

### Task 3.9: Completion flash effect

**Files:**
- Modify: `agenttab/AgentTAB/UI/Rows/SessionRow.swift`

**Step 1: Add completion flash on transition to .done**

Use `.onChange(of: session.activity)` to trigger a 1.5s green flash overlay when entering `.done`.

```swift
// In SessionRow, add:
@State private var flashOpacity: Double = 0

// In body, add overlay:
.background(isHovered ? Theme.rowHighlight : Color.clear)
.overlay(Theme.Activity.done.opacity(flashOpacity).cornerRadius(4))
.onChange(of: session.activity) { _, newValue in
    if newValue == .done {
        withAnimation(.easeOut(duration: Theme.Animations.completionFlashDuration)) {
            flashOpacity = 0
        }
        flashOpacity = 0.35  // start
    }
}
```

**Step 2: Verify**

When a session completes, the row briefly flashes green and fades back. Duration 1.5s, easeOut.

**Step 3: Commit**

```bash
git commit -am "feat(agenttab): completion flash effect on row"
```

---

### Task 3.10: Per-row right-edge controls (open folder, dismiss)

**Files:**
- Modify: `agenttab/AgentTAB/UI/Rows/SessionRow.swift`

**Step 1: Add control buttons revealed on hover**

```swift
// Replace the simple `if isHovered { Image... }` block with:
if isHovered {
    HStack(spacing: 6) {
        Button(action: openFolder) {
            Image(systemName: "folder").font(.system(size: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textDim)
        
        Button(action: dismissSession) {
            Image(systemName: "xmark").font(.system(size: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textDim)
        .gesture(LongPressGesture(minimumDuration: 3.0).onEnded { _ in
            // long-press dismiss
        })
    }
    .transition(.opacity)
}

// Add methods:
private func openFolder() {
    NSWorkspace.shared.open(URL(fileURLWithPath: session.projectPath))
}
private func dismissSession() {
    // hooked up to denylist in M5
}
```

**Step 2: Visual verify**

Hover row → folder + × icons appear. Click folder → opens project in Finder. (× will be wired up in M5.)

**Step 3: Commit**

```bash
git commit -am "feat(agenttab): per-row hover controls (open folder, dismiss)"
```

---

**Milestone 3 complete.** The pill and expanded view look and feel like the production design. Animations match the existing Hammerspoon overlay's identity.

---

## Milestone 4: Hook Socket Pipeline

**Goal:** AgentTAB receives Claude hook events directly via a Unix domain socket, getting sub-100ms transitions instead of relying on JSONL polling. Onboarding flow installs the hook script and registers it in `~/.claude/settings.json`.

**End state:** First-launch onboarding sheet asks for hook installation consent; consenting installs `hook.sh` and updates Claude settings; sessions transition immediately on tool use (no JSONL lag).

### Task 4.1: Define HookPayload + decoding tests

**Files:**
- Create: `agenttab/AgentTAB/Engine/Hooks/HookPayload.swift`
- Create: `agenttab/AgentTABTests/HookPayloadTests.swift`

**Step 1: Write failing tests**

```swift
import XCTest
@testable import AgentTAB

final class HookPayloadTests: XCTestCase {
    func testDecodesPreToolUsePayload() throws {
        let json = #"{"pane_id":42,"session_id":"abc-123","hook_event":"PreToolUse","tool_name":"Bash","term_program":"ghostty"}"#
        let payload = try JSONDecoder().decode(HookPayload.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(payload.paneId, 42)
        XCTAssertEqual(payload.sessionId, "abc-123")
        XCTAssertEqual(payload.hookEvent, "PreToolUse")
        XCTAssertEqual(payload.toolName, "Bash")
        XCTAssertEqual(payload.termProgram, "ghostty")
    }
    
    func testDecodesWithMissingOptionalFields() throws {
        let json = #"{"pane_id":0,"session_id":"x","hook_event":"Stop"}"#
        let payload = try JSONDecoder().decode(HookPayload.self, from: json.data(using: .utf8)!)
        XCTAssertNil(payload.toolName)
        XCTAssertNil(payload.termProgram)
    }
}
```

**Step 2: Implement**

```swift
// HookPayload.swift
import Foundation

struct HookPayload: Codable, Equatable {
    let paneId: Int
    let sessionId: String
    let hookEvent: String
    let toolName: String?
    let termProgram: String?
    
    enum CodingKeys: String, CodingKey {
        case paneId = "pane_id"
        case sessionId = "session_id"
        case hookEvent = "hook_event"
        case toolName = "tool_name"
        case termProgram = "term_program"
    }
}
```

**Step 3: Pass, commit**

```bash
git commit -am "feat(agenttab): HookPayload Codable model"
```

---

### Task 4.2: HookSocketListener — NWListener on Unix socket

**Files:**
- Create: `agenttab/AgentTAB/Engine/Hooks/HookSocketListener.swift`

**Step 1: Implement**

```swift
// HookSocketListener.swift
import Foundation
import Network

final class HookSocketListener {
    private var listener: NWListener?
    private let socketPath: String
    private let queue = DispatchQueue(label: "agenttab.hooks")
    
    var onPayload: ((HookPayload) -> Void)?
    
    init(socketPath: String) {
        self.socketPath = socketPath
    }
    
    func start() throws {
        // Remove stale socket file
        try? FileManager.default.removeItem(atPath: socketPath)
        
        let parameters = NWParameters(tls: nil)
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)
        
        listener = try NWListener(using: parameters)
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener?.start(queue: queue)
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        try? FileManager.default.removeItem(atPath: socketPath)
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            defer { connection.cancel() }
            guard let data = data, !data.isEmpty else { return }
            do {
                let payload = try JSONDecoder().decode(HookPayload.self, from: data)
                self?.onPayload?(payload)
            } catch {
                print("[HookSocket] Decode error: \(error)")
            }
        }
    }
}
```

**Step 2: Build, commit**

```bash
git commit -am "feat(agenttab): HookSocketListener via Network.framework"
```

---

### Task 4.3: Wire hook events into ActivityEngine

**Files:**
- Modify: `agenttab/AgentTAB/Engine/ActivityEngine.swift`

**Step 1: Add hook handling**

```swift
// In ActivityEngine, add property:
private var hookSocket: HookSocketListener?
private var lastHookEvent: [String: Date] = [:]   // claudeSessionId -> when

// In start(), initialize socket if hooks-installed marker exists:
let socketPath = HookInstaller.socketPath
if HookInstaller.hooksInstalled {
    let listener = HookSocketListener(socketPath: socketPath)
    listener.onPayload = { [weak self] payload in
        Task { @MainActor in self?.applyHook(payload) }
    }
    do {
        try listener.start()
        hookSocket = listener
    } catch {
        print("[Engine] Hook socket failed: \(error)")
    }
}

// New method:
private func applyHook(_ payload: HookPayload) {
    guard let id = sessionsByClaudeId[payload.sessionId],
          let index = sessions.firstIndex(where: { $0.id == id }) else {
        // Hook fired before JSONL discovery — buffer or wait
        return
    }
    var session = sessions[index]
    
    switch payload.hookEvent {
    case "SessionStart":      session.activity = .initState
    case "UserPromptSubmit":  session.activity = .thinking; session.currentTool = nil
    case "PreToolUse":
        if let name = payload.toolName {
            session.activity = .tool(name)
            session.currentTool = name
        }
    case "PostToolUse", "PostToolUseFailure":
        session.activity = .thinking
        session.currentTool = nil
    case "PermissionRequest":
        session.activity = .waiting
    case "Stop", "SubagentStop", "ManualInterrupt":
        session.activity = .done
        // Lingers 30s; idle decay scheduled in M5
    case "SessionEnd":
        sessions.remove(at: index)
        sessionsByClaudeId.removeValue(forKey: payload.sessionId)
        return
    default: break
    }
    
    session.lastUpdate = Date()
    sessions[index] = session
    lastHookEvent[payload.sessionId] = Date()
}

// Modify applyLine to defer to hook authority:
private func applyLine(_ line: String, jsonlURL: URL) {
    guard let id = sessionsByJsonlURL[jsonlURL],
          let index = sessions.firstIndex(where: { $0.id == id }) else { return }
    
    let claudeId = sessions[index].claudeSessionId
    let hookActive = (lastHookEvent[claudeId].map { Date().timeIntervalSince($0) < 10 } ?? false)
    
    var session = sessions[index]
    let events = parser.parseLine(line, session: &session)
    
    if hookActive {
        // Drop activity changes from JSONL — hook is authoritative
        session.activity = sessions[index].activity
    }
    sessions[index] = session
    
    // ... permission timer unchanged
}
```

**Step 2: Build, commit**

```bash
git commit -am "feat(agenttab): wire hook socket events into ActivityEngine"
```

---

### Task 4.4: HookInstaller — JSON merge into ~/.claude/settings.json

**Files:**
- Create: `agenttab/AgentTAB/Onboarding/HookInstaller.swift`

**Step 1: Implement**

```swift
// HookInstaller.swift
import Foundation

enum HookInstaller {
    static let supportDir: URL = {
        let url = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AgentTAB")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    
    static var hookScriptPath: URL { supportDir.appendingPathComponent("hook.sh") }
    static var socketPath: String { supportDir.appendingPathComponent("hook.sock").path }
    static var installedHooksManifest: URL { supportDir.appendingPathComponent("installed-hooks.json") }
    
    static var hooksInstalled: Bool {
        FileManager.default.fileExists(atPath: installedHooksManifest.path)
    }
    
    static var claudeSettingsPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }
    
    static let hookEvents = [
        "PreToolUse", "PostToolUse", "UserPromptSubmit", "PermissionRequest",
        "Stop", "SubagentStop", "SessionStart", "SessionEnd",
    ]
    
    static func install() throws {
        // 1. Copy hook.sh from bundle to support dir
        guard let bundleHook = Bundle.main.url(forResource: "hook", withExtension: "sh") else {
            throw NSError(domain: "AgentTAB", code: 1, userInfo: [NSLocalizedDescriptionKey: "hook.sh missing from bundle"])
        }
        if FileManager.default.fileExists(atPath: hookScriptPath.path) {
            try FileManager.default.removeItem(at: hookScriptPath)
        }
        try FileManager.default.copyItem(at: bundleHook, to: hookScriptPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScriptPath.path)
        
        // 2. Read existing settings.json
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: claudeSettingsPath),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = obj
        }
        
        // 3. Merge our hooks
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let installedNow = Date().timeIntervalSince1970
        var manifest: [String: [String]] = [:]
        
        for event in hookEvents {
            var existing = hooks[event] as? [[String: Any]] ?? []
            let cmd: [String: Any] = [
                "hooks": [["type": "command", "command": hookScriptPath.path]]
            ]
            existing.append(cmd)
            hooks[event] = existing
            manifest[event] = [hookScriptPath.path]
        }
        settings["hooks"] = hooks
        
        // 4. Atomic write
        let tmpURL = claudeSettingsPath.appendingPathExtension("tmp")
        let data = try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
        try data.write(to: tmpURL)
        try FileManager.default.replaceItem(at: claudeSettingsPath, withItemAt: tmpURL,
                                            backupItemName: nil, options: [], resultingItemURL: nil)
        
        // 5. Write manifest
        let manifestData = try JSONSerialization.data(withJSONObject: [
            "installed_at": installedNow,
            "hooks": manifest,
        ], options: .prettyPrinted)
        try manifestData.write(to: installedHooksManifest)
    }
    
    static func uninstall() throws {
        // Read manifest, reverse the merge for each event
        guard let manifestData = try? Data(contentsOf: installedHooksManifest),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let installedHooks = manifest["hooks"] as? [String: [String]],
              let settingsData = try? Data(contentsOf: claudeSettingsPath),
              var settings = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any]
        else { return }
        
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, paths) in installedHooks {
            guard var entries = hooks[event] as? [[String: Any]] else { continue }
            entries.removeAll { entry in
                guard let nested = entry["hooks"] as? [[String: Any]] else { return false }
                return nested.contains { ($0["command"] as? String).map(paths.contains) ?? false }
            }
            hooks[event] = entries.isEmpty ? nil : entries
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        
        let tmpURL = claudeSettingsPath.appendingPathExtension("tmp")
        let data = try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
        try data.write(to: tmpURL)
        try FileManager.default.replaceItem(at: claudeSettingsPath, withItemAt: tmpURL,
                                            backupItemName: nil, options: [], resultingItemURL: nil)
        
        try FileManager.default.removeItem(at: installedHooksManifest)
        try FileManager.default.removeItem(at: hookScriptPath)
    }
}
```

**Step 2: Add hook.sh to bundle**

Create `agenttab/AgentTAB/Resources/hook.sh`:

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

printf '%s' "$PAYLOAD" | nc -U "$HOME/Library/Application Support/AgentTAB/hook.sock" -w 1 \
  >/dev/null 2>&1

[ -n "$ZELLIJ_PANE_ID" ] && command -v zellij >/dev/null 2>&1 && \
  zellij pipe --name "claude-tab-status" -- "$PAYLOAD" >/dev/null 2>&1

exit 0
```

In Xcode, add `hook.sh` to the AgentTAB target → Build Phases → Copy Bundle Resources.

**Step 3: Build, commit**

```bash
git commit -am "feat(agenttab): HookInstaller with idempotent JSON merge"
```

---

### Task 4.5: Onboarding sheet UI

**Files:**
- Create: `agenttab/AgentTAB/Onboarding/OnboardingView.swift`
- Modify: `agenttab/AgentTAB/App/AppDelegate.swift`

**Step 1: Implement onboarding**

```swift
// OnboardingView.swift
import SwiftUI

struct OnboardingView: View {
    @AppStorage("AgentTAB.onboarding.completed") var completed = false
    @State private var step = 0
    @State private var hookInstallError: String?
    
    var body: some View {
        VStack(spacing: 24) {
            switch step {
            case 0: welcome
            case 1: hookConsent
            case 2: optionalLogin
            default: done
            }
        }
        .frame(width: 480, height: 360)
        .padding(40)
    }
    
    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "circle.hexagonpath.fill").font(.system(size: 60))
            Text("Welcome to AgentTAB").font(.title)
            Text("Track every Claude Code session at a glance, right in your notch.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Continue") { step = 1 }.controlSize(.large)
        }
    }
    
    private var hookConsent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect to Claude Code").font(.headline)
            Text("AgentTAB monitors Claude by registering hooks in your existing config (~/.claude/settings.json). This lets it know when each session starts, uses a tool, or finishes — instantly.")
                .foregroundStyle(.secondary)
            Text("AgentTAB will only add its own hooks; existing user hooks are preserved.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if let err = hookInstallError {
                Text(err).foregroundStyle(.red).font(.caption)
            }
            
            HStack {
                Button("Skip (JSONL only)") { step = 2 }
                Spacer()
                Button("Install hooks") {
                    do {
                        try HookInstaller.install()
                        step = 2
                    } catch {
                        hookInstallError = error.localizedDescription
                    }
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
    
    private var optionalLogin: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Open at login?").font(.headline)
            Text("AgentTAB can launch automatically when you log in.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Not now") { step = 3 }
                Spacer()
                Button("Yes, open at login") {
                    LoginItem.register()
                    step = 3
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
    
    private var done: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("All set").font(.title)
            Text("AgentTAB is now tracking your Claude sessions.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done") {
                completed = true
                NSApp.windows.first { $0.title.contains("Onboarding") }?.close()
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }
}
```

**Step 2: Add LoginItem helper**

```swift
// agenttab/AgentTAB/Settings/LoginItem.swift
import ServiceManagement

enum LoginItem {
    static func register() {
        try? SMAppService.mainApp.register()
    }
    static func unregister() {
        try? SMAppService.mainApp.unregister()
    }
    static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
```

**Step 3: Show onboarding on first launch**

```swift
// In AppDelegate.applicationDidFinishLaunching:
let onboardingDone = UserDefaults.standard.bool(forKey: "AgentTAB.onboarding.completed")
if !onboardingDone {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
        styleMask: [.titled, .closable],
        backing: .buffered, defer: false
    )
    window.title = "AgentTAB Onboarding"
    window.contentView = NSHostingView(rootView: OnboardingView())
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}
```

**Step 4: Visual verify**

Delete `~/Library/Preferences/com.roomss.agenttab.plist` to reset onboarding. Run app. Expected: 4-step sheet appears, hook installation actually merges into `~/.claude/settings.json`. Verify via `cat ~/.claude/settings.json | jq .hooks.PreToolUse`.

**Step 5: Commit**

```bash
git commit -am "feat(agenttab): onboarding flow with hook installation"
```

---

### Task 4.6: Verify hook → socket → engine end-to-end

**Files:**
- (Manual verification, no new code)

**Step 1: Reset and run full flow**

1. Quit AgentTAB.
2. `rm ~/Library/Preferences/com.roomss.agenttab.plist`
3. `rm -rf ~/Library/Application\ Support/AgentTAB`
4. Launch AgentTAB → complete onboarding with hook install.
5. Verify hooks: `jq .hooks.PreToolUse < ~/.claude/settings.json` should show AgentTAB's hook.
6. Open Claude Code in any terminal.
7. Run: `claude "what's 2+2"` (or any quick prompt).
8. Watch the AgentTAB pill — expect transitions within ~100ms (hook-driven), much faster than the previous JSONL-only path.

**Step 2: Sanity check no double-counting**

When both pipelines see the same event, verify no duplicate state changes (the 10s hook-authority window should suppress JSONL).

**Step 3: Commit (no code changes — checkpoint commit)**

```bash
git commit --allow-empty -m "chore(agenttab): manual verification of hook pipeline end-to-end"
```

---

**Milestone 4 complete.** Hook socket gives instant transitions. Onboarding flow handles install consent and modifies `~/.claude/settings.json` cleanly.

---

## Milestone 5: Drop-in Mode + Zellij Reader

**Goal:** AgentTAB detects existing `claude-tab-status` setups and runs in read-only mode without touching the user's environment. Zellij sessions get tab/pane info; click-to-focus uses real Zellij data.

**End state:** Reinstalling AgentTAB on a machine with existing `claude-zj-hook.sh` setup produces zero writes outside AgentTAB's own support dir. Tab names and pane IDs visible in expanded view.

### Task 5.1: EnvironmentProbe

**Files:**
- Create: `agenttab/AgentTAB/Engine/EnvironmentProbe.swift`
- Create: `agenttab/AgentTABTests/EnvironmentProbeTests.swift`

**Step 1: Write failing tests + implement**

```swift
// EnvironmentProbe.swift
import Foundation

struct EnvironmentProbe {
    let zellijState: ZellijState
    let pluginState: PluginState
    let hookState: HookState
    
    enum ZellijState { case notInstalled, installed, running }
    enum PluginState { case none, configured, producingStatusFiles }
    enum HookState { case none, legacyClaudeTabStatus, agentTAB, mixed }
    
    static func detect() -> EnvironmentProbe {
        return EnvironmentProbe(
            zellijState: detectZellij(),
            pluginState: detectPlugin(),
            hookState: detectHooks()
        )
    }
    
    private static func detectZellij() -> ZellijState {
        let process = Process()
        process.launchPath = "/usr/bin/which"
        process.arguments = ["zellij"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return .notInstalled }
        
        // Check if running
        let psProcess = Process()
        psProcess.launchPath = "/bin/sh"
        psProcess.arguments = ["-c", "pgrep -x zellij"]
        psProcess.standardOutput = Pipe()
        psProcess.standardError = Pipe()
        try? psProcess.run()
        psProcess.waitUntilExit()
        return psProcess.terminationStatus == 0 ? .running : .installed
    }
    
    private static func detectPlugin() -> PluginState {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/zellij/config.kdl")
        let configured = (try? String(contentsOf: configPath))?
            .contains("claude-tab-status.wasm") ?? false
        
        let statusDir = URL(fileURLWithPath: "/tmp/claude-tab-status")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: statusDir, includingPropertiesForKeys: [.contentModificationDateKey]),
              !files.isEmpty else {
            return configured ? .configured : .none
        }
        let recentlyWritten = files.contains { url in
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return Date().timeIntervalSince(mtime) < 60
        }
        return recentlyWritten ? .producingStatusFiles : .configured
    }
    
    private static func detectHooks() -> HookState {
        let claudeSettings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: claudeSettings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any]
        else { return .none }
        
        let allHookCommands = hooks.values
            .compactMap { $0 as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["command"] as? String }
        
        let hasAgentTAB = allHookCommands.contains { $0.contains("/AgentTAB/hook.sh") }
        let hasLegacy = allHookCommands.contains { $0.contains("claude-zj-hook.sh") }
        
        switch (hasAgentTAB, hasLegacy) {
        case (true, true): return .mixed
        case (true, false): return .agentTAB
        case (false, true): return .legacyClaudeTabStatus
        case (false, false): return .none
        }
    }
}

extension EnvironmentProbe {
    /// Drop-in mode: existing setup detected, AgentTAB should not modify the environment.
    var isDropInCandidate: Bool {
        return zellijState == .running &&
               pluginState == .producingStatusFiles &&
               hookState != .none
    }
}
```

**Step 2: Pass tests, commit**

```bash
git commit -am "feat(agenttab): EnvironmentProbe detects Zellij/plugin/hook state"
```

---

### Task 5.2: ZellijStatusReader

**Files:**
- Create: `agenttab/AgentTAB/Engine/Zellij/ZellijStatus.swift`
- Create: `agenttab/AgentTAB/Engine/Zellij/ZellijStatusReader.swift`

**Step 1: Define status format**

```swift
// ZellijStatus.swift
import Foundation

struct ZellijStatusFile: Codable {
    let sessions: [ZellijSession]
    let counts: ZellijCounts
    let updatedAt: TimeInterval
    
    enum CodingKeys: String, CodingKey {
        case sessions, counts
        case updatedAt = "updated_at"
    }
}

struct ZellijSession: Codable {
    let paneId: Int
    let runId: String?
    let tabNum: Int
    let tabName: String
    let icon: String
    let detail: String?
    let activity: String        // "Init", "Thinking", "Tool", "Waiting", "Done", "Idle"
    
    enum CodingKeys: String, CodingKey {
        case paneId = "pane_id"
        case runId = "run_id"
        case tabNum = "tab_num"
        case tabName = "tab_name"
        case icon, detail, activity
    }
}

struct ZellijCounts: Codable {
    let active: Int
    let waiting: Int
    let done: Int
}
```

**Step 2: Implement reader**

```swift
// ZellijStatusReader.swift
import Foundation

final class ZellijStatusReader {
    private let statusDir = URL(fileURLWithPath: "/tmp/claude-tab-status")
    private var dirSource: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "agenttab.zellij")
    
    var onUpdate: (([URL: ZellijStatusFile]) -> Void)?
    
    func start() {
        guard FileManager.default.fileExists(atPath: statusDir.path) else { return }
        let fd = open(statusDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        
        dirSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: queue
        )
        dirSource?.setEventHandler { [weak self] in self?.scan() }
        dirSource?.setCancelHandler { close(fd) }
        dirSource?.resume()
        
        scan()
    }
    
    func stop() { dirSource?.cancel() }
    
    private func scan() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: statusDir, includingPropertiesForKeys: nil) else { return }
        var result: [URL: ZellijStatusFile] = [:]
        for fileURL in files where fileURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let parsed = try? JSONDecoder().decode(ZellijStatusFile.self, from: data),
                  // Skip stale (>120s old)
                  Date().timeIntervalSince1970 - parsed.updatedAt < 120
            else { continue }
            result[fileURL] = parsed
        }
        onUpdate?(result)
    }
}
```

**Step 3: Wire into ActivityEngine**

In `ActivityEngine.start()`, conditionally start the Zellij reader and merge updates:

```swift
private var zellijReader: ZellijStatusReader?

// In start():
let probe = EnvironmentProbe.detect()
if probe.pluginState == .producingStatusFiles {
    zellijReader = ZellijStatusReader()
    zellijReader?.onUpdate = { [weak self] fileMap in
        Task { @MainActor in self?.applyZellijStatus(fileMap) }
    }
    zellijReader?.start()
}

// New method:
private func applyZellijStatus(_ files: [URL: ZellijStatusFile]) {
    for (_, statusFile) in files {
        for zSession in statusFile.sessions {
            // Match by run_id or pane_id heuristic
            // For each matching session, set terminalKind = .zellij
            for index in sessions.indices {
                if case .generic = sessions[index].terminalKind,
                   sessions[index].claudeSessionId == zSession.runId {
                    sessions[index].terminalKind = .zellij(ZellijInfo(
                        paneId: zSession.paneId,
                        tabIndex: zSession.tabNum,
                        tabName: zSession.tabName,
                        zellijSession: ""
                    ))
                }
            }
        }
    }
}
```

**Step 4: Visual verify**

With Zellij + plugin running, expanded view shows tab/pane info on Zellij sessions.

**Step 5: Commit**

```bash
git commit -am "feat(agenttab): ZellijStatusReader merges plugin /tmp/* JSON files"
```

---

### Task 5.3: Drop-in mode onboarding path

**Files:**
- Modify: `agenttab/AgentTAB/Onboarding/OnboardingView.swift`

**Step 1: Detect probe at start; show drop-in step if applicable**

```swift
// In OnboardingView, inject probe:
@State private var probe = EnvironmentProbe.detect()

// Add new step at the start (step 0.5):
if probe.isDropInCandidate && step == 0 {
    dropInWelcome
}

// Drop-in welcome:
private var dropInWelcome: some View {
    VStack(spacing: 16) {
        Image(systemName: "checkmark.shield.fill").font(.system(size: 60)).foregroundStyle(.green)
        Text("Existing setup detected").font(.title)
        Text("AgentTAB found your existing Claude tab status integration. It will read live data without modifying anything on your machine.")
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
        Spacer()
        Button("Continue in drop-in mode") {
            UserDefaults.standard.set(true, forKey: "AgentTAB.onboarding.completed")
            UserDefaults.standard.set(true, forKey: "AgentTAB.dropInMode")
            step = 99   // skip rest
        }
        .controlSize(.large)
    }
}
```

**Step 2: Manual verify**

On a machine with the existing claude-tab-status setup, running AgentTAB shows the drop-in welcome and skips hook installation.

**Step 3: Commit**

```bash
git commit -am "feat(agenttab): drop-in mode onboarding path"
```

---

**Milestone 5 complete.** Drop-in mode works end-to-end; existing setups are detected and preserved.

---

## Milestone 6: Notifications

**Goal:** Toast panel renders in configurable corner with sound cues for waiting/done events.

### Task 6.1: ToastPanel

**Files:**
- Create: `agenttab/AgentTAB/Notifications/ToastPanel.swift`
- Create: `agenttab/AgentTAB/Notifications/ToastView.swift`

**Step 1: Implement**

```swift
// ToastPanel.swift
import AppKit
import SwiftUI

final class ToastPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        self.level = .floating
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.isReleasedWhenClosed = false
    }
    
    override var canBecomeKey: Bool { false }
    
    func show(_ toast: Toast, corner: ToastCorner, duration: TimeInterval) {
        contentView = NSHostingView(rootView: ToastView(toast: toast))
        anchor(corner: corner)
        orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.orderOut(nil)
        }
    }
    
    private func anchor(corner: ToastCorner) {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let pad: CGFloat = 16
        let myFrame = self.frame
        let origin: NSPoint
        switch corner {
        case .topLeft:     origin = NSPoint(x: f.minX + pad, y: f.maxY - myFrame.height - pad)
        case .topRight:    origin = NSPoint(x: f.maxX - myFrame.width - pad, y: f.maxY - myFrame.height - pad)
        case .bottomLeft:  origin = NSPoint(x: f.minX + pad, y: f.minY + pad)
        case .bottomRight: origin = NSPoint(x: f.maxX - myFrame.width - pad, y: f.minY + pad)
        }
        setFrameOrigin(origin)
    }
}

enum ToastCorner: String { case topLeft, topRight, bottomLeft, bottomRight }

struct Toast: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let activity: AgentTAB.Activity
}
```

**Step 2: Implement ToastView**

```swift
// ToastView.swift
import SwiftUI

struct ToastView: View {
    let toast: Toast
    
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(toast.activity.color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(.system(size: 12, weight: .semibold))
                Text(toast.subtitle).font(.system(size: 11)).foregroundStyle(Theme.textDim).lineLimit(1)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(toast.activity.color.opacity(0.3), lineWidth: 1))
        .shadow(radius: 8)
    }
}
```

**Step 3: Commit**

```bash
git commit -am "feat(agenttab): ToastPanel + ToastView for notifications"
```

---

### Task 6.2: Sound triggers + cooldown

**Files:**
- Create: `agenttab/AgentTAB/Notifications/SoundPlayer.swift`

**Step 1: Implement**

```swift
// SoundPlayer.swift
import AppKit

final class SoundPlayer {
    private var lastPlayedAt: Date = .distantPast
    let cooldown: TimeInterval = 0.75
    
    func playWaiting() { play(systemNamed: "Ping") }
    func playDone() {
        guard let url = Bundle.main.url(forResource: "Glass", withExtension: "wav"),
              let sound = NSSound(contentsOf: url, byReference: false) else { return }
        playWithCooldown(sound)
    }
    
    private func play(systemNamed name: String) {
        guard let sound = NSSound(named: name) else { return }
        playWithCooldown(sound)
    }
    
    private func playWithCooldown(_ sound: NSSound) {
        guard Date().timeIntervalSince(lastPlayedAt) > cooldown else { return }
        sound.play()
        lastPlayedAt = Date()
    }
}
```

**Step 2: Wire to ActivityEngine state changes**

In ActivityEngine, observe transitions:

```swift
private let toastPanel = ToastPanel()
private let soundPlayer = SoundPlayer()
@AppStorage("AgentTAB.toast.corner") private var toastCorner: ToastCorner = .bottomRight
@AppStorage("AgentTAB.sounds.enabled") private var soundsEnabled = true

private func sessionStateChanged(_ session: Session, oldActivity: AgentTAB.Activity) {
    if session.activity == .waiting && oldActivity != .waiting {
        let toast = Toast(
            title: "Claude needs your input",
            subtitle: session.projectName,
            activity: .waiting
        )
        toastPanel.show(toast, corner: toastCorner, duration: 8)
        if soundsEnabled { soundPlayer.playWaiting() }
    } else if session.activity == .done && oldActivity != .done {
        let toast = Toast(title: "Finished", subtitle: session.projectName, activity: .done)
        toastPanel.show(toast, corner: toastCorner, duration: 4)
        if soundsEnabled { soundPlayer.playDone() }
    }
}
```

**Step 3: Visual verify**

Trigger waiting/done on a Claude session. Expected: toast slides in at configured corner, sound plays.

**Step 4: Commit**

```bash
git commit -am "feat(agenttab): notification sounds with cooldown"
```

---

### Task 6.3: Settings UI for toast/sound

**Files:**
- Create: `agenttab/AgentTAB/Settings/SettingsView.swift`

**Step 1: Implement settings tabs**

```swift
// SettingsView.swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gear") }
            NotificationsSettings().tabItem { Label("Notifications", systemImage: "bell") }
            UpdatesSettings().tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 480, height: 360)
    }
}

struct NotificationsSettings: View {
    @AppStorage("AgentTAB.toast.corner") var toastCorner: String = ToastCorner.bottomRight.rawValue
    @AppStorage("AgentTAB.sounds.enabled") var soundsEnabled: Bool = true
    @AppStorage("AgentTAB.sounds.waitingReminder") var waitingReminder: Bool = true
    
    var body: some View {
        Form {
            Picker("Toast position", selection: $toastCorner) {
                Text("Top left").tag("topLeft")
                Text("Top right").tag("topRight")
                Text("Bottom left").tag("bottomLeft")
                Text("Bottom right").tag("bottomRight")
            }
            Toggle("Notification sounds", isOn: $soundsEnabled)
            Toggle("Waiting reminder every 30s", isOn: $waitingReminder)
        }
        .padding()
    }
}

struct GeneralSettings: View {
    @AppStorage("AgentTAB.openAtLogin") var openAtLogin = false
    
    var body: some View {
        Form {
            Toggle("Open AgentTAB at login", isOn: $openAtLogin)
                .onChange(of: openAtLogin) { _, on in
                    if on { LoginItem.register() } else { LoginItem.unregister() }
                }
            Section("Mode") {
                Text(EnvironmentProbe.detect().isDropInCandidate ? "Drop-in (read-only)" : "Managed hooks")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

struct UpdatesSettings: View {
    var body: some View {
        Form {
            Button("Check for updates now") { /* wired in M7 */ }
        }
        .padding()
    }
}
```

**Step 2: Replace stub in AgentTABApp.swift**

```swift
Settings { SettingsView() }
```

**Step 3: Commit**

```bash
git commit -am "feat(agenttab): Settings panes with toast/sound controls"
```

---

**Milestone 6 complete.** Notifications work, settings panel exposes preferences.

---

## Milestone 7: Sparkle + DMG + Updates

**Goal:** App auto-updates over Cloudflare R2; DMG builds via Python `dmgbuild`.

### Task 7.1: Generate Sparkle EdDSA keypair

**Files:**
- (No code; key files stored locally + as CI secret)

**Step 1: Install Sparkle CLI tools**

```bash
brew install --cask sparkle
```

**Step 2: Generate keypair**

```bash
generate_keys
```

Outputs:
- Private key → stored in macOS Keychain under `Sparkle EdDSA private key for AgentTAB`
- Public key (base64) → printed to stdout, copy this

**Step 3: Save public key**

Add to a file `agenttab/sparkle-public-key.txt` (gitignored):

```bash
echo "<paste base64 public key here>" > agenttab/sparkle-public-key.txt
echo "agenttab/sparkle-public-key.txt" >> .gitignore
```

**Step 4: Document private-key handling**

Create `agenttab/SPARKLE-KEYS.md`:

```markdown
# Sparkle Signing Keys

Public key: see agenttab/sparkle-public-key.txt
Private key: macOS Keychain → "Sparkle EdDSA private key for AgentTAB"

For CI: export private key once via `generate_keys -x sparkle-private.key`,
add to repository secrets as SPARKLE_PRIVATE_KEY, then DELETE the local file.
```

**Step 5: Commit (excluding keys)**

```bash
git add agenttab/SPARKLE-KEYS.md .gitignore
git commit -m "chore(agenttab): document Sparkle key handling"
```

---

### Task 7.2: Embed Sparkle framework

**Files:**
- Modify: Xcode project (add Sparkle as Swift Package)

**Step 1: Add via Swift Package Manager**

In Xcode → File → Add Package Dependencies → URL: `https://github.com/sparkle-project/Sparkle` → version 2.6.0+ → Add to target AgentTAB.

**Step 2: Add Info.plist keys**

```xml
<key>SUFeedURL</key>              <string>https://updates.agenttab.roomss.dev/appcast.xml</string>
<key>SUPublicEDKey</key>          <string><PASTE PUBLIC KEY HERE></string>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUScheduledCheckInterval</key><integer>86400</integer>
<key>SUEnableInstallerLauncherService</key><true/>
```

**Step 3: Implement UpdaterCoordinator**

```swift
// UpdaterCoordinator.swift
import Sparkle

final class UpdaterCoordinator: NSObject, SPUUpdaterDelegate {
    let updater: SPUStandardUpdaterController
    
    override init() {
        updater = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }
    
    func checkForUpdates() {
        updater.checkForUpdates(self)
    }
}
```

**Step 4: Wire into AppDelegate and Settings**

```swift
// In AppDelegate:
let updater = UpdaterCoordinator()

// In UpdatesSettings, wire button:
Button("Check for updates now") {
    (NSApp.delegate as? AppDelegate)?.updater.checkForUpdates()
}
```

**Step 5: Build + commit**

```bash
git commit -am "feat(agenttab): embed Sparkle 2.6 with updater coordinator"
```

---

### Task 7.3: dmgbuild config + build script

**Files:**
- Create: `agenttab/packaging/dmg-settings.py`
- Create: `agenttab/scripts/build-dmg.sh`

**Step 1: Implement dmg config**

```python
# dmg-settings.py
import os, sys

application = sys.argv[-1] if len(sys.argv) > 1 else "build/AgentTAB.app"
appname = "AgentTAB"

format = "UDZO"
size = "150M"
files = [application]
symlinks = {"Applications": "/Applications"}

icon = "agenttab/assets/volume-icon.icns"
background = "agenttab/assets/dmg-background.png"

window_rect = ((100, 100), (540, 380))
icon_locations = {
    "AgentTAB.app": (140, 200),
    "Applications": (400, 200),
}
default_view = "icon-view"
icon_size = 96
text_size = 12
```

**Step 2: Build script**

```sh
#!/bin/sh
set -euo pipefail
VERSION="${1:?usage: build-dmg.sh <version>}"

cd agenttab

# 1. Build
xcodebuild -project AgentTAB.xcodeproj -scheme AgentTAB \
  -configuration Release -derivedDataPath build/ archive

# 2. Bundle pre-built icon
# assets/AppIcon.icns is committed alongside the iconset PNGs.
# To regenerate from the iconset: iconutil -c icns assets/AppIcon.iconset
cp assets/AppIcon.icns "build/Build/Products/Release/AgentTAB.app/Contents/Resources/AppIcon.icns"

# 3. DMG
mkdir -p out
pip3 install --user dmgbuild 2>/dev/null
dmgbuild -s packaging/dmg-settings.py "AgentTAB" "out/AgentTAB-${VERSION}.dmg" \
    "build/Build/Products/Release/AgentTAB.app"

# 4. Sparkle sign
SIG=$(sign_update "out/AgentTAB-${VERSION}.dmg")
echo "Signature: $SIG"

# 5. SHA-256
shasum -a 256 "out/AgentTAB-${VERSION}.dmg"

echo "DMG: out/AgentTAB-${VERSION}.dmg"
```

Make executable: `chmod +x agenttab/scripts/build-dmg.sh`

**Step 3: Test build**

```bash
./agenttab/scripts/build-dmg.sh 0.1.0
open out/AgentTAB-0.1.0.dmg
```

Expected: DMG window opens with AgentTAB.app on left, Applications shortcut on right, dark glass background. Drag the app into Applications, launch, verify it runs.

**Step 4: Commit**

```bash
git commit -am "feat(agenttab): dmgbuild config + build-dmg.sh"
```

---

### Task 7.4: Appcast generator + R2 upload

**Files:**
- Create: `agenttab/scripts/update_appcast.py`
- Create: `agenttab/packaging/appcast-template.xml`
- Create: `agenttab/scripts/release.sh`

**Step 1: Implement appcast template**

```xml
<?xml version="1.0" standalone="yes"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>AgentTAB Updates</title>
    <link>https://updates.agenttab.roomss.dev/appcast.xml</link>
    <description>AgentTAB release feed</description>
    <language>en</language>
    {items}
  </channel>
</rss>
```

**Step 2: Implement updater script**

```python
# update_appcast.py
import argparse, os, datetime
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--version", required=True)
p.add_argument("--dmg", required=True)
p.add_argument("--signature", required=True)
p.add_argument("--notes", required=True)
p.add_argument("--out", required=True)
args = p.parse_args()

dmg_size = os.path.getsize(args.dmg)
release_date = datetime.datetime.utcnow().strftime("%a, %d %b %Y %H:%M:%S +0000")
notes_html = Path(args.notes).read_text()

new_item = f"""
    <item>
      <title>Version {args.version}</title>
      <description><![CDATA[{notes_html}]]></description>
      <pubDate>{release_date}</pubDate>
      <enclosure
        url="https://updates.agenttab.roomss.dev/releases/AgentTAB-{args.version}.dmg"
        sparkle:version="{args.version}"
        sparkle:edSignature="{args.signature}"
        length="{dmg_size}"
        type="application/octet-stream"/>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    </item>
"""

# Read existing or create new
if os.path.exists(args.out):
    text = Path(args.out).read_text()
    items_start = text.index("</language>") + len("</language>")
    text = text[:items_start] + new_item + text[items_start:]
else:
    template = Path("agenttab/packaging/appcast-template.xml").read_text()
    text = template.replace("{items}", new_item)

Path(args.out).write_text(text)
print(f"Appcast updated: {args.out}")
```

**Step 3: Release script**

```sh
#!/bin/sh
set -euo pipefail
VERSION="${1:?usage: release.sh <version>}"

# 1. Build DMG
./agenttab/scripts/build-dmg.sh "$VERSION"

# 2. Sign
SIG=$(sign_update "out/AgentTAB-${VERSION}.dmg" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)

# 3. Update appcast
python3 agenttab/scripts/update_appcast.py \
    --version "$VERSION" \
    --dmg "out/AgentTAB-${VERSION}.dmg" \
    --signature "$SIG" \
    --notes "agenttab/release-notes/${VERSION}.md" \
    --out "out/appcast.xml"

# 4. Upload
wrangler r2 object put "updates-agenttab/releases/AgentTAB-${VERSION}.dmg" \
    --file="out/AgentTAB-${VERSION}.dmg"
wrangler r2 object put "updates-agenttab/appcast.xml" \
    --file="out/appcast.xml"

# 5. Tag and push
git tag "v${VERSION}"
git push --tags

echo ""
echo "Release ${VERSION} published."
echo "SHA-256:"
shasum -a 256 "out/AgentTAB-${VERSION}.dmg"
```

**Step 4: First release**

```bash
mkdir -p agenttab/release-notes
echo "<p>Initial release.</p>" > agenttab/release-notes/0.1.0.md
./agenttab/scripts/release.sh 0.1.0
```

**Step 5: Commit**

```bash
git commit -am "feat(agenttab): appcast generator + release.sh end-to-end"
```

---

### Task 7.5: Verify update flow end-to-end

**Files:**
- (Manual)

**Step 1: Test update**

1. Install AgentTAB-0.1.0.dmg.
2. Bump version to 0.1.1, run `./agenttab/scripts/release.sh 0.1.1`.
3. In the running 0.1.0 instance, click "Check for updates now".
4. Expect Sparkle prompt: "AgentTAB 0.1.1 is available. Download and Install."
5. Click Install.
6. App quits, swaps, relaunches as 0.1.1.

**Step 2: Verify version**

Click status menu → About → "AgentTAB 0.1.1".

**Step 3: Commit checkpoint**

```bash
git commit --allow-empty -m "chore(agenttab): manual verification of Sparkle update flow"
```

---

**Milestone 7 complete.** Auto-updates work over the air.

---

## Milestone 8: Polish + Ship

### Task 8.1: App icon

**Files (already committed before implementation began):**
- `agenttab/assets/AgentTAB.svg` — vector source (1024×1024 viewbox)
- `agenttab/assets/app-icon-1024.png` — 1024 raster, used as DMG volume icon fallback
- `agenttab/assets/AppIcon.iconset/` — full multi-size iconset (16/32/128/256/512 with @2x)
- `agenttab/assets/AppIcon.icns` — compiled icns ready to embed

**Step 1: Verify build picks up icon**

Run `./agenttab/scripts/build-dmg.sh 0.1.0`. Inspect the resulting `.app/Contents/Resources/AppIcon.icns` is the same as `agenttab/assets/AppIcon.icns`. Open the `.app` in Finder — the AgentTAB icon should appear.

**Step 2: If the iconset ever needs regeneration**

```sh
cd agenttab/assets
iconutil -c icns AppIcon.iconset
```

This rebuilds `AppIcon.icns` from the `iconset` folder. The PNGs in the iconset were originally rendered from `AgentTAB.svg` and committed pre-sized.

**Step 3: No commit needed**

Icons are already in the repo. Just verify the build picks them up.

---

### Task 8.2: DMG background art

**Files:**
- Create or place: `agenttab/assets/dmg-background.png` (540×380)

**Step 1: Mock or use user-provided PNG**

If user provides, copy. Otherwise generate placeholder (e.g. via Apple Pages or a simple ImageMagick command):

```sh
convert -size 540x380 'gradient:#0a0a14-#1a1a2e' agenttab/assets/dmg-background.png
```

**Step 2: Rebuild and verify**

```bash
./agenttab/scripts/build-dmg.sh 0.1.0
open out/AgentTAB-0.1.0.dmg
```

Expected: dark gradient background visible in DMG window.

**Step 3: Commit**

```bash
git commit -am "feat(agenttab): DMG background art"
```

---

### Task 8.3: README with installation instructions

**Files:**
- Create: `agenttab/README.md`

**Step 1: Write README**

```markdown
# AgentTAB

Native macOS notch app for tracking Claude Code session activity.

## Install

1. Download `AgentTAB-X.Y.Z.dmg` from your distribution channel.
2. Open the DMG and drag AgentTAB.app into the Applications folder.
3. **First launch:** macOS will show "Apple cannot verify…". Click Done, then:
   - Open **System Settings → Privacy & Security**
   - Scroll to "Security" and click **Open Anyway** next to AgentTAB
   - Confirm with your password
4. AgentTAB launches and shows an onboarding sheet. Follow the prompts.

If `Open Anyway` is unavailable, run:

```bash
xattr -dr com.apple.quarantine /Applications/AgentTAB.app
```

then launch normally.

## What it does

- Watches every Claude Code session in `~/.claude/projects/` and shows activity in the notch
- Optional Claude hook integration for instant transitions (installed via onboarding)
- Auto-detects existing `claude-tab-status` Zellij setups — runs in read-only drop-in mode without modifying anything
- Self-updates via Sparkle (daily check, EdDSA-signed)

## Uninstall

Click the menu bar AgentTAB icon → Settings → Advanced → "Uninstall AgentTAB". This:

- Removes the AgentTAB hooks from `~/.claude/settings.json`
- Removes `~/Library/Application Support/AgentTAB/`
- Unregisters the Login Item

Then drag `/Applications/AgentTAB.app` to Trash.

## Build from source

See `docs/plans/2026-05-07-agenttab-implementation.md`.
```

**Step 2: Commit**

```bash
git commit -am "docs(agenttab): README with install + uninstall instructions"
```

---

### Task 8.4: Uninstall menu action

**Files:**
- Modify: `agenttab/AgentTAB/Settings/SettingsView.swift`

**Step 1: Add uninstall**

```swift
struct AdvancedSettings: View {
    @State private var showConfirm = false
    
    var body: some View {
        Form {
            Button("Reveal hook script in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([HookInstaller.hookScriptPath])
            }
            Button("Uninstall AgentTAB") { showConfirm = true }
                .foregroundStyle(.red)
        }
        .padding()
        .alert("Uninstall AgentTAB?", isPresented: $showConfirm) {
            Button("Uninstall", role: .destructive) { performUninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove AgentTAB hooks from ~/.claude/settings.json and remove its support directory. The app itself in /Applications must be deleted manually.")
        }
    }
    
    private func performUninstall() {
        try? HookInstaller.uninstall()
        let support = HookInstaller.supportDir
        try? FileManager.default.removeItem(at: support)
        LoginItem.unregister()
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: "/Applications/AgentTAB.app")])
        NSApp.terminate(nil)
    }
}
```

Add the new tab to `SettingsView`.

**Step 2: Commit**

```bash
git commit -am "feat(agenttab): uninstall flow in Advanced settings"
```

---

### Task 8.5: Final integration test on a clean machine

**Files:**
- (Manual verification)

**Step 1: Set up clean test**

On a colleague's Mac (or fresh user account):

1. Download the DMG from R2.
2. Drag to Applications.
3. Open Anyway via System Settings.
4. Run AgentTAB.
5. Complete onboarding (install hooks).
6. Open Claude Code in a terminal.
7. Verify notch pill shows session, transitions in real time.
8. Click "Check for updates" — verify it polls R2 and reports up-to-date.
9. Trigger waiting state in Claude — verify toast notification.
10. Click expanded session row — verify terminal focus action.
11. Test uninstall flow.

**Step 2: Tag the release**

```bash
git tag v1.0.0
git push --tags
./agenttab/scripts/release.sh 1.0.0
```

**Step 3: Final commit**

```bash
git commit --allow-empty -m "release(agenttab): v1.0.0 — first colleague distribution"
```

---

**Milestone 8 complete.** AgentTAB v1.0.0 ships.

---

## Final Verification Checklist

Before declaring v1.0 done, verify on a fresh machine:

- [ ] DMG opens, drag-to-Applications works
- [ ] System Settings → Privacy & Security → Open Anyway path works
- [ ] App appears in notch (or top-center on non-notched Macs) within 1s
- [ ] Onboarding flow completes without errors
- [ ] Hook installation merges cleanly into `~/.claude/settings.json`
- [ ] Drop-in mode triggers correctly when `claude-tab-status` is detected
- [ ] Cardio loader animates when sessions are active
- [ ] Coffee+steam animates when sessions are idle
- [ ] Counts update live as Claude works
- [ ] Hover expands to tab-grouped session list
- [ ] Click-to-focus works for Zellij rows
- [ ] Toast notifications fire on waiting/done with correct sounds
- [ ] Sparkle update prompt appears for newer versions
- [ ] EdDSA signature verification rejects a tampered DMG
- [ ] Uninstall flow reverses all environment changes
- [ ] LSUIElement: no Dock icon, no app switcher entry
- [ ] Multi-display: panel rebinds on display change

---

## Notes for the Implementing Engineer

- **Build with `xcodebuild` from CLI**, not just Xcode GUI. The `release.sh` script must work headlessly.
- **Test on a notched MacBook** for the notch carve geometry. Visual verification cannot be skipped.
- **Don't skip the 10s hook-authority window.** Without it, JSONL and hook events fight for state on every tool call.
- **Sparkle private key is single-source-of-truth.** If lost, all installed copies of the app must be reinstalled (the public key in their bundle won't match a new private key). Back up to a password manager.
- **Cloudflare R2 bucket name `updates-agenttab` is a placeholder.** Replace with the actual bucket once provisioned.
- **macOS 14.0+ requirement is firm.** `safeAreaInsets`, `.symbolEffect`, `SMAppService` modern API, and Sparkle 2.6's installer launcher service all require Sonoma.

End of plan.

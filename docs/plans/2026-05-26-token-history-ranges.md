# Token History Ranges Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add 30d-bar and ~4-month-squares views to the expanded-view token history dashboard, switchable via a segmented control.

**Architecture:** `TokenTracker` grows a ranged history model (week/month/window) populated from one shared 119-day file walk; `ActivityHistoryView` adds a 3-position switcher and a `SquaresHistoryGrid` subview. Existing 7-day code path is preserved by parameter, not duplicated.

**Tech Stack:** Swift 5.x, SwiftUI, XCTest. Built with `xcodebuild` via the existing `AgentTAB` scheme. Test fixtures use `FileManager` temp dirs (pattern matches `SessionDiscoveryTests.swift`).

**Design doc:** `docs/2026-05-26-token-history-ranges-design.md` (commit `9f0280a`).

**Build/test commands:**
- Build only: `xcodebuild -project agenttab/AgentTAB.xcodeproj -scheme AgentTAB -configuration Debug build`
- Run tests: `xcodebuild test -project agenttab/AgentTAB.xcodeproj -scheme AgentTAB -destination 'platform=macOS'`
- Run one test: append `-only-testing:AgentTABTests/TokenTrackerHistoryTests/testName`

---

## Task 1: TokenTracker — failing test for ranged scan

**Files:**
- Create: `agenttab/AgentTABTests/TokenTrackerHistoryTests.swift`

**Step 1: Write the failing test.** This test seeds a temp `projects` dir with one jsonl whose lines cover today, 5 days ago, and 40 days ago, then asserts that the ranged API returns the correct per-range buckets.

```swift
import XCTest
@testable import AgentTAB

@MainActor
final class TokenTrackerHistoryTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("tt-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    /// Write one assistant line into `<projectsDir>/<project>/<session>.jsonl`
    /// dated `daysAgo`, with the given token totals.
    private func writeAssistantLine(
        project: String,
        session: String,
        daysAgo: Int,
        input: Int = 0, output: Int = 0, cacheCreate: Int = 0, cacheRead: Int = 0
    ) throws {
        let projectDir = tempRoot.appendingPathComponent(project)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let file = projectDir.appendingPathComponent("\(session).jsonl")
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = iso.string(from: day)
        let line: [String: Any] = [
            "type": "assistant",
            "timestamp": ts,
            "message": [
                "usage": [
                    "input_tokens": input,
                    "output_tokens": output,
                    "cache_creation_input_tokens": cacheCreate,
                    "cache_read_input_tokens": cacheRead,
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: line)
        let handle: FileHandle
        if FileManager.default.fileExists(atPath: file.path) {
            handle = try FileHandle(forWritingTo: file)
            try handle.seekToEnd()
        } else {
            FileManager.default.createFile(atPath: file.path, contents: nil)
            handle = try FileHandle(forWritingTo: file)
        }
        handle.write(data)
        handle.write("\n".data(using: .utf8)!)
        try handle.close()
    }

    /// Wait for the detached scan in `refreshHistory()` to publish.
    private func waitForScan(_ tracker: TokenTracker) async {
        try? await Task.sleep(nanoseconds: 400_000_000)
        _ = tracker.days(for: .week)
    }

    func testRangedHistoryBucketsByRange() async throws {
        try writeAssistantLine(project: "-Users-x-repoA", session: "s1",
                               daysAgo: 0, input: 1_000)
        try writeAssistantLine(project: "-Users-x-repoA", session: "s1",
                               daysAgo: 5, input: 2_000)
        try writeAssistantLine(project: "-Users-x-repoB", session: "s2",
                               daysAgo: 40, output: 5_000)
        // Outside the 119-day window — must be excluded from every range.
        try writeAssistantLine(project: "-Users-x-repoB", session: "s2",
                               daysAgo: 200, output: 9_999)

        let tracker = TokenTracker(projectsDir: tempRoot)
        tracker.refreshHistory()
        await waitForScan(tracker)

        let week  = tracker.days(for: .week)
        let month = tracker.days(for: .month)
        let win   = tracker.days(for: .window)

        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(month.count, 30)
        XCTAssertEqual(win.count, 119)

        // Today + 5-days-ago = 3_000 tokens in week range.
        XCTAssertEqual(week.reduce(0) { $0 + $1.tokens }, 3_000)
        // Month adds nothing new (40-days-ago still outside).
        XCTAssertEqual(month.reduce(0) { $0 + $1.tokens }, 3_000)
        // Window picks up the 40-days-ago line.
        XCTAssertEqual(win.reduce(0) { $0 + $1.tokens }, 8_000)
        // 200-days-ago line excluded.
        XCTAssertFalse(win.contains { $0.tokens == 9_999 })
    }

    func testRangedProjectsRollupIsPerRange() async throws {
        try writeAssistantLine(project: "-Users-x-repoA", session: "s1",
                               daysAgo: 1, input: 1_000)
        try writeAssistantLine(project: "-Users-x-repoB", session: "s2",
                               daysAgo: 40, output: 5_000)

        let tracker = TokenTracker(projectsDir: tempRoot)
        tracker.refreshHistory()
        await waitForScan(tracker)

        let weekProjects   = tracker.projects(for: .week)
        let windowProjects = tracker.projects(for: .window)

        XCTAssertEqual(weekProjects.map(\.name), ["repoA"])
        XCTAssertEqual(Set(windowProjects.map(\.name)), ["repoA", "repoB"])
    }
}
```

**Step 2: Run test to verify it fails.**

Run:
```
xcodebuild test -project agenttab/AgentTAB.xcodeproj -scheme AgentTAB -destination 'platform=macOS' -only-testing:AgentTABTests/TokenTrackerHistoryTests
```
Expected: FAIL — `days(for:)`, `projects(for:)`, `refreshHistory()`, `HistoryRange` do not exist yet (compile error).

**Step 3: Commit the failing test.**

```bash
git add agenttab/AgentTABTests/TokenTrackerHistoryTests.swift
git commit -m "test: ranged token history API (failing)"
```

---

## Task 2: TokenTracker — implement ranged scan to pass test

**Files:**
- Modify: `agenttab/AgentTAB/Engine/TokenTracker.swift`

**Step 1: Add `HistoryRange` enum + new `@Published` properties.** Insert near the top of `TokenTracker`, after `weeklyProjects` declaration (which will be removed in step 3):

```swift
enum HistoryRange {
    case week, month, window
    var days: Int { self == .week ? 7 : self == .month ? 30 : 119 }
}

@Published private(set) var daysShort:  [DailyActivity] = []
@Published private(set) var daysMonth:  [DailyActivity] = []
@Published private(set) var daysWindow: [DailyActivity] = []

@Published private(set) var projectsShort:  [ProjectSpend] = []
@Published private(set) var projectsMonth:  [ProjectSpend] = []
@Published private(set) var projectsWindow: [ProjectSpend] = []

func days(for range: HistoryRange) -> [DailyActivity] {
    switch range {
    case .week:   return daysShort
    case .month:  return daysMonth
    case .window: return daysWindow
    }
}

func projects(for range: HistoryRange) -> [ProjectSpend] {
    switch range {
    case .week:   return projectsShort
    case .month:  return projectsMonth
    case .window: return projectsWindow
    }
}
```

**Step 2: Add `refreshHistory()` and `scanRanges` helper.** `refreshHistory` runs one detached scan over the widest window; `scanRanges` returns all three days+projects tuples. Insert after `refreshWeekly()`:

```swift
/// Kick off a fresh ranged scan covering the widest window (119d).
/// Cheap to call on every history open — stale buckets stay visible
/// while the rescan runs.
func refreshHistory() {
    let dir = projectsDir
    Task.detached(priority: .utility) {
        let result = Self.scanRanges(projectsDir: dir)
        await MainActor.run { [weak self] in
            self?.daysShort      = result.short.days
            self?.daysMonth      = result.month.days
            self?.daysWindow     = result.window.days
            self?.projectsShort  = result.short.projects
            self?.projectsMonth  = result.month.projects
            self?.projectsWindow = result.window.projects
        }
    }
}

/// Pure file walk. Buckets every `assistant` line's tokens by the day
/// of its `timestamp` across the 119-day window; the 7d/30d ranges are
/// tail-windows of the same bucket map. Per-range project rollups are
/// computed independently because activeDays and totals differ per
/// range.
private nonisolated static func scanRanges(
    projectsDir: URL
) -> (
    short:  (days: [DailyActivity], projects: [ProjectSpend]),
    month:  (days: [DailyActivity], projects: [ProjectSpend]),
    window: (days: [DailyActivity], projects: [ProjectSpend])
) {
    let cal = Calendar.current
    let todayStart = cal.startOfDay(for: Date())
    guard let windowStart = cal.date(byAdding: .day, value: -118, to: todayStart) else {
        return ((days: [], projects: []), (days: [], projects: []), (days: [], projects: []))
    }

    let isoFractional = ISO8601DateFormatter()
    isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let isoPlain = ISO8601DateFormatter()

    // For each day: (tokens, sessions seen, projects seen).
    var buckets: [Date: (tokens: Int, sessions: Set<String>, projects: Set<String>)] = [:]

    let fm = FileManager.default
    guard let projects = try? fm.contentsOfDirectory(
        at: projectsDir, includingPropertiesForKeys: nil
    ) else { return ((days: [], projects: []), (days: [], projects: []), (days: [], projects: [])) }

    for project in projects {
        guard let isDir = (try? project.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory,
              isDir
        else { continue }
        let projectName = SessionDiscovery.hashToProjectName(project.lastPathComponent)

        guard let files = try? fm.contentsOfDirectory(
            at: project, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { continue }

        for file in files where file.pathExtension == "jsonl" {
            let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            // A file untouched in the window can't hold a window line.
            guard mtime >= windowStart else { continue }
            let sessionId = file.deletingPathExtension().lastPathComponent
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }

            for line in text.split(separator: "\n") where !line.isEmpty {
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["type"] as? String == "assistant",
                      let tsString = json["timestamp"] as? String,
                      let ts = isoFractional.date(from: tsString) ?? isoPlain.date(from: tsString)
                else { continue }

                let day = cal.startOfDay(for: ts)
                guard day >= windowStart, day <= todayStart else { continue }

                let message = json["message"] as? [String: Any]
                let usage = message?["usage"] as? [String: Any]
                let tokens = (usage?["input_tokens"] as? Int ?? 0)
                    + (usage?["output_tokens"] as? Int ?? 0)
                    + (usage?["cache_creation_input_tokens"] as? Int ?? 0)
                    + (usage?["cache_read_input_tokens"] as? Int ?? 0)

                var bucket = buckets[day] ?? (0, [], [])
                bucket.tokens += tokens
                bucket.sessions.insert(sessionId)
                bucket.projects.insert(projectName)
                buckets[day] = bucket
            }
        }
    }

    func slice(daysBack: Int) -> (days: [DailyActivity], projects: [ProjectSpend]) {
        guard let start = cal.date(byAdding: .day, value: -(daysBack - 1), to: todayStart) else {
            return ([], [])
        }
        let days: [DailyActivity] = (0 ..< daysBack).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            let b = buckets[day]
            return DailyActivity(
                day: day,
                tokens: b?.tokens ?? 0,
                agentCount: b?.sessions.count ?? 0,
                projects: Array(b?.projects ?? []).sorted()
            )
        }

        // Per-range project rollup.
        var projectTokens: [String: Int] = [:]
        var projectDays:   [String: Set<Date>] = [:]
        for day in days where day.tokens > 0 {
            if let b = buckets[day.day] {
                for name in b.projects {
                    projectTokens[name, default: 0] += 0   // ensure key exists
                    projectDays[name, default: []].insert(day.day)
                }
                // Distribute b.tokens proportionally? No — a day-bucket's
                // tokens are shared across the day's projects without
                // per-project attribution at this layer. To keep
                // per-project totals accurate we need a finer scan.
                _ = b   // see TODO below
            }
        }

        // Per-project token attribution requires a second pass — buckets
        // collapsed across projects. Redo the file walk constrained to
        // this range, summing per-project tokens directly.
        let rangeStart = days.first?.day ?? todayStart
        var projectTokensExact: [String: Int] = [:]
        for project in (try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)) ?? [] {
            guard let isDir = (try? project.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory,
                  isDir else { continue }
            let projectName = SessionDiscovery.hashToProjectName(project.lastPathComponent)
            guard let files = try? fm.contentsOfDirectory(
                at: project, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                guard mtime >= rangeStart else { continue }
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                for line in text.split(separator: "\n") where !line.isEmpty {
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          json["type"] as? String == "assistant",
                          let tsString = json["timestamp"] as? String,
                          let ts = isoFractional.date(from: tsString) ?? isoPlain.date(from: tsString)
                    else { continue }
                    let day = cal.startOfDay(for: ts)
                    guard day >= rangeStart, day <= todayStart else { continue }
                    let message = json["message"] as? [String: Any]
                    let usage = message?["usage"] as? [String: Any]
                    let tokens = (usage?["input_tokens"] as? Int ?? 0)
                        + (usage?["output_tokens"] as? Int ?? 0)
                        + (usage?["cache_creation_input_tokens"] as? Int ?? 0)
                        + (usage?["cache_read_input_tokens"] as? Int ?? 0)
                    projectTokensExact[projectName, default: 0] += tokens
                    projectDays[projectName, default: []].insert(day)
                }
            }
        }

        let list = projectTokensExact.map { name, tokens in
            ProjectSpend(name: name, tokens: tokens, activeDays: projectDays[name]?.count ?? 0)
        }
        .sorted { $0.tokens > $1.tokens }

        return (days, list)
    }

    return (
        short:  slice(daysBack: 7),
        month:  slice(daysBack: 30),
        window: slice(daysBack: 119)
    )
}
```

**Note on the second pass:** the inner `slice` re-walks files to attribute per-project tokens accurately (the outer `buckets` collapses tokens across projects on the same day). Three slices × file walk × 1 widest range = OK perf for a backgrounded refresh.

**Optimisation pass (refactor before commit):** the two file walks (outer bucket build + per-slice attribution) can be merged into one pass that records `(day, project) → tokens`. Defer to step 5; verify tests pass first.

**Step 3: Remove the old API.** Delete `@Published var weekly`, `@Published var weeklyProjects`, `refreshWeekly()`, and `scanWeekly`. Call sites updated in Task 3.

**Step 4: Run the failing test — should now compile and pass.**

Run:
```
xcodebuild test -project agenttab/AgentTAB.xcodeproj -scheme AgentTAB -destination 'platform=macOS' -only-testing:AgentTABTests/TokenTrackerHistoryTests
```
Expected: PASS for both `testRangedHistoryBucketsByRange` and `testRangedProjectsRollupIsPerRange`. If the wait time is too short on a slow CI, bump `waitForScan` sleep to 800ms.

**Step 5: Refactor — collapse the double walk.** Replace the outer `buckets` map with `[Date: [String: Int]]` keyed by `(day, project)`. The slice loop derives `DailyActivity` and `ProjectSpend` directly from this without a second pass. Re-run tests; must still pass.

**Step 6: Commit.**

```bash
git add agenttab/AgentTAB/Engine/TokenTracker.swift
git commit -m "tracker: ranged history (week/month/window) replacing weeklyOnly"
```

---

## Task 3: ExpandedView — wire tracker into ActivityHistoryView

**Files:**
- Modify: `agenttab/AgentTAB/UI/ExpandedView.swift` (around line 113)
- Modify: `agenttab/AgentTAB/UI/ActivityHistoryView.swift` (header + state)

**Step 1: Change `ActivityHistoryView` signature to accept the tracker.** Replace the `weekly` + `projects` params with a single `@ObservedObject var tracker: TokenTracker`. Add `@State private var range: HistoryRange = .week`. Compute `weekly` and `projects` from `tracker.days(for: range)` / `tracker.projects(for: range)`. Update all body refs.

**Step 2: Update the call site in `ExpandedView.swift`:**

Replace:
```swift
ActivityHistoryView(
    weekly: tokenTracker.weekly,
    projects: tokenTracker.weeklyProjects,
    onBack: { showHistory = false }
)
```

With:
```swift
ActivityHistoryView(
    tracker: tokenTracker,
    onBack: { showHistory = false }
)
```

**Step 3: Find the `showHistory` toggle and switch `refreshWeekly()` call to `refreshHistory()`.**

Run:
```
grep -n "refreshWeekly\|weekly\|weeklyProjects" agenttab/AgentTAB/UI/ExpandedView.swift
```
Replace any remaining `tokenTracker.refreshWeekly()` with `tokenTracker.refreshHistory()`.

**Step 4: Build to confirm everything still compiles.**

Run:
```
xcodebuild -project agenttab/AgentTAB.xcodeproj -scheme AgentTAB -configuration Debug build 2>&1 | tail -20
```
Expected: `BUILD SUCCEEDED`. App at this point still behaves identically (only 7d data flows through the chart even though month+window now exist).

**Step 5: Commit.**

```bash
git add agenttab/AgentTAB/UI/ExpandedView.swift agenttab/AgentTAB/UI/ActivityHistoryView.swift
git commit -m "expanded: route tracker into history view, range state ready"
```

---

## Task 4: Range switcher segmented control

**Files:**
- Modify: `agenttab/AgentTAB/UI/ActivityHistoryView.swift`

**Step 1: Replace the static `Text("Last 7 days")` in `header` with a segmented control.** Implement as an inline `HStack` of `Button`s sharing a rounded background.

```swift
private var header: some View {
    HStack(spacing: 10) {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textDim)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help("Back to agents")

        rangeSwitcher
        Spacer()
    }
}

private var rangeSwitcher: some View {
    HStack(spacing: 0) {
        rangePill(.week,   label: "7d")
        rangePill(.month,  label: "30d")
        rangePill(.window, icon: "square.grid.3x3.fill")
    }
    .padding(2)
    .background(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 0.5)
            )
    )
}

@ViewBuilder
private func rangePill(_ r: HistoryRange, label: String? = nil, icon: String? = nil) -> some View {
    Button {
        range = r
    } label: {
        Group {
            if let label {
                Text(label)
                    .font(.system(size: 10.5, weight: .bold))
            } else if let icon {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(range == r ? Theme.Neon.blue : Theme.textDim)
        .frame(minWidth: 30)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(range == r ? Theme.Neon.blue.opacity(0.18) : Color.clear)
        )
    }
    .buttonStyle(.plain)
}
```

**Step 2: Animate range switches in the body.** Add `.animation(.easeOut(duration: 0.18), value: range)` to the outer `VStack`.

**Step 3: Build and launch the app manually to sanity-check the switcher renders + responds.**

Run:
```
cd /Users/adrianzabica/Desktop/pixel-agents-standalone
bash agenttab/scripts/install.sh --no-launch
open -a AgentTab
```
Click the token counter → dashboard opens → all three pills are visible. Clicking switches selected pill colour. (Chart/grid content still 7d-only at this step — that's fine.)

**Step 4: Commit.**

```bash
git add agenttab/AgentTAB/UI/ActivityHistoryView.swift
git commit -m "history: 3-position range switcher (7d / 30d / squares)"
```

---

## Task 5: 30d bar variant

**Files:**
- Modify: `agenttab/AgentTAB/UI/ActivityHistoryView.swift`

**Step 1: Parameterise `barChart` on the data + range.** Change `private var barChart: some View {` to `private func barChart(_ days: [DailyActivity], dense: Bool) -> some View`. Use `dense` to drive `spacing`, label-rule, top-label font-size, and the week-hairline overlay.

Inside the body, change the `barChart` reference to:
```swift
switch range {
case .week:   barChart(tracker.days(for: .week),  dense: false)
case .month:  barChart(tracker.days(for: .month), dense: true)
case .window: SquaresHistoryGrid(days: tracker.days(for: .window))   // added in Task 6
}
```

**Step 2: Implement dense-mode differences inside `barChart`:**

- `HStack(alignment: .bottom, spacing: dense ? 3 : 6)`
- Top label font: `dense ? 7 : 8`pt
- Weekday letter: `dense ? bottomTick(for: day) : weekdayLabel(day.day)` where:

```swift
private func bottomTick(for day: DailyActivity) -> String {
    // Show day-of-month every 7th day (week starts) + today.
    let cal = Calendar.current
    if cal.isDateInToday(day.day) { return "\(cal.component(.day, from: day.day))" }
    if cal.component(.weekday, from: day.day) == cal.firstWeekday {
        return "\(cal.component(.day, from: day.day))"
    }
    return " "
}
```

- For the week-boundary hairline: wrap each bar's `VStack` in a ZStack and conditionally underlay a `Rectangle().fill(Theme.hairline).frame(height: 0.5)` aligned to `bottom`, only for dense mode and only when `bottomTick` is non-blank.

**Step 3: Build and launch.** Switch to 30d. Verify ~30 thin bars render, today is labelled, week-tick numbers appear sparsely, hovering still swaps top label to token spend.

**Step 4: Commit.**

```bash
git add agenttab/AgentTAB/UI/ActivityHistoryView.swift
git commit -m "history: 30d bar variant with sparse week ticks"
```

---

## Task 6: SquaresHistoryGrid subview

**Files:**
- Modify: `agenttab/AgentTAB/UI/ActivityHistoryView.swift` (append at end of file)

**Step 1: Add the subview.**

```swift
struct SquaresHistoryGrid: View {
    let days: [DailyActivity]      // exactly 119, oldest first

    @State private var hovered: DailyActivity?

    private let cols = 17
    private let rows = 7
    private let gap: CGFloat = 5
    private let rowLabelWidth: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            hoverChip
            GeometryReader { geo in
                let cell = max(((geo.size.width - rowLabelWidth) / CGFloat(cols)) - gap, 12)
                HStack(alignment: .top, spacing: gap) {
                    rowLabels(cell: cell)
                    grid(cell: cell)
                }
            }
            .frame(height: CGFloat(rows) * 34 + CGFloat(rows - 1) * gap)
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    // MARK: hover chip

    @ViewBuilder
    private var hoverChip: some View {
        if let d = hovered {
            HStack(spacing: 6) {
                Text(dateLabel(d.day))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Neon.blue)
                Text("·").font(.system(size: 10)).foregroundStyle(Theme.textFaint)
                Text("\(TokenTracker.format(d.tokens)) tokens")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textStrong)
                if d.agentCount > 0 {
                    Text("·").font(.system(size: 10)).foregroundStyle(Theme.textFaint)
                    Text("\(d.agentCount) agent\(d.agentCount == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Theme.hairline, lineWidth: 0.5)
                    )
            )
        } else {
            Color.clear.frame(height: 25)
        }
    }

    // MARK: row labels (M W F)

    private func rowLabels(cell: CGFloat) -> some View {
        VStack(spacing: gap) {
            ForEach(0 ..< rows, id: \.self) { r in
                let labels: [Int: String] = [1: "M", 3: "W", 5: "F"]
                Text(labels[r] ?? "")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
                    .frame(width: rowLabelWidth, height: cell, alignment: .trailing)
            }
        }
    }

    // MARK: grid

    private func grid(cell: CGFloat) -> some View {
        // Days arrive oldest first; today is the last entry. Layout cols
        // left-to-right oldest → newest, with today's column being whichever
        // weekday today is. Cells in today's column past today render as
        // clear so we don't fake-fill future days.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // weekdayIndex: 0=Sun, 6=Sat (cal.component returns 1...7)
        let todayRow = (cal.component(.weekday, from: today) - 1) % 7

        // Build a Date → DailyActivity map for fast lookup.
        var byDate: [Date: DailyActivity] = [:]
        for d in days { byDate[d.day] = d }

        // Walk back from today to today - 16 weeks, building cells in
        // [col][row] order.
        let maxTokens = max(days.map(\.tokens).max() ?? 1, 1)
        // Column 0 is the oldest visible week (16 weeks back).
        let firstColMonday: Date = {
            // The oldest visible day is the Sun at start of col 0.
            // todayRow tells us how many days into today's col we are.
            let daysBack = (cols - 1) * 7 + todayRow
            return cal.date(byAdding: .day, value: -daysBack, to: today)!
        }()

        return HStack(spacing: gap) {
            ForEach(0 ..< cols, id: \.self) { c in
                VStack(spacing: gap) {
                    ForEach(0 ..< rows, id: \.self) { r in
                        cellView(
                            col: c, row: r, cell: cell,
                            firstDay: firstColMonday,
                            todayRow: todayRow,
                            today: today,
                            byDate: byDate,
                            maxTokens: maxTokens
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cellView(
        col: Int, row: Int, cell: CGFloat,
        firstDay: Date, todayRow: Int, today: Date,
        byDate: [Date: DailyActivity], maxTokens: Int
    ) -> some View {
        let cal = Calendar.current
        let dayOffset = col * 7 + row
        let date = cal.date(byAdding: .day, value: dayOffset, to: firstDay)!
        let isFuture = date > today
        let isToday = cal.isDate(date, inSameDayAs: today)

        let activity = byDate[date]
        let tokens = activity?.tokens ?? 0
        let fill: Color = {
            if isFuture { return .clear }
            if tokens == 0 { return Color.white.opacity(0.04) }
            let pct = Double(tokens) / Double(maxTokens) * 100
            switch pct {
            case ..<26:  return Theme.Neon.blue.opacity(0.22)
            case ..<51:  return Theme.Neon.blue.opacity(0.45)
            case ..<76:  return Theme.Neon.blue.opacity(0.70)
            default:     return Theme.Neon.blue.opacity(1.00)
            }
        }()

        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isToday ? Theme.Neon.blue : Color.clear, lineWidth: 1)
            )
            .frame(width: cell, height: cell)
            .contentShape(Rectangle())
            .onHover { inside in
                if isFuture { return }
                if inside {
                    hovered = activity ?? DailyActivity(day: date, tokens: 0, agentCount: 0, projects: [])
                } else if hovered?.day == date {
                    hovered = nil
                }
            }
    }

    private func dateLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: d)
    }
}
```

**Step 2: Build and launch.** Switch to squares. Verify:
- 17 columns × 7 rows render, no overflow.
- Today has a blue outline.
- Hovering a square pops the chip above showing date + tokens.
- Cells past today (e.g. Sat when today is Wed) are blank, no outline.
- Empty days are faint grey; q4 days are saturated blue.

**Step 3: Commit.**

```bash
git add agenttab/AgentTAB/UI/ActivityHistoryView.swift
git commit -m "history: squares heatmap view (17w x 7d, 5 buckets, hover chip)"
```

---

## Task 7: Summary + projects per range

**Files:**
- Modify: `agenttab/AgentTAB/UI/ActivityHistoryView.swift`

**Step 1: Bind summary strip to current range.** Replace `weekly.reduce(...)` with computed properties off `tracker.days(for: range)`:

```swift
private var totalTokens: Int { tracker.days(for: range).reduce(0) { $0 + $1.tokens } }
private var activeDays:  Int { tracker.days(for: range).filter { $0.tokens > 0 }.count }
private var projectsList: [ProjectSpend] { tracker.projects(for: range) }
```

**Step 2: Update `projectsList` view body.** Replace the parameter `projects` with `projectsList`. Update empty state copy to `"No agent activity in this range."`.

**Step 3: Build and launch.** Switch between 7d / 30d / squares. Confirm:
- Totals update.
- Project list reorders/changes.
- Empty range still renders the placeholder cleanly.

**Step 4: Commit.**

```bash
git add agenttab/AgentTAB/UI/ActivityHistoryView.swift
git commit -m "history: summary + project list rebind to selected range"
```

---

## Task 8: Verification + final polish

**Step 1: Run the full test suite.**

Run:
```
xcodebuild test -project agenttab/AgentTAB.xcodeproj -scheme AgentTAB -destination 'platform=macOS' 2>&1 | tail -30
```
Expected: all tests pass, including the two new `TokenTrackerHistoryTests`.

**Step 2: Manual UX pass.** With the app running, exercise each range. Look for:
- Animation glitches when switching range.
- Layout overflow at the panel edge in squares view.
- Hover chip appearing/disappearing cleanly.
- Today highlight visible in every view.
- Scroll position in the projects list resetting on range change (acceptable; not blocking).

**Step 3: If anything broken, fix and commit.** Otherwise note "manual pass clean" in the next commit message.

**Step 4: Final summary commit (if any polish edits).**

```bash
git add -p
git commit -m "history: polish — <specifics>"
```

---

## Out of scope (do NOT add)

- Persisting selected range across panel close.
- Inefficiency-specific stats (avg/active-day, idle days, day-of-week aggregate).
- Hour-of-day breakdowns.
- Square-grid options (cell size, week-start day) as user settings.

These were explicitly deferred in the design doc. Leave them for a follow-up if the basic view doesn't surface enough.

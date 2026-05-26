# Token History Ranges — Design

Date: 2026-05-26
Status: Design accepted; ready for implementation.

## Goal

Extend the expanded-view token-usage history dashboard with two new views
(30 days and a ~4-month squares grid) so the user gets a reality-check on
token spend and can spot workflow inefficiencies (idle days where more work
fits, busy days that explain why nothing else got done, day-of-week
patterns in output).

## Scope

Three views, switched via a segmented control in the dashboard header:

1. **7d** — existing daily bar chart (unchanged).
2. **30d** — same bar engine, slimmer pillars, sparse week-marker labels.
3. **Squares (▣)** — GitHub-style heatmap of the last ~17 weeks (119 days),
   today rightmost, 5-bucket colour scale, per-day hover chip.

Out of scope:
- Hour-of-day breakdowns.
- Persisting the selected range across panel close.
- Inefficiency-specific stats (avg/active-day, idle-day count, etc.).
  Current 3 stats (tokens · projects · active days) recompute per range;
  richer metrics can be added later if the basic view doesn't surface
  enough.

## Architecture

### Data layer — `TokenTracker`

Replace `weekly`, `weeklyProjects`, and `refreshWeekly()` with a single
ranged history model.

```swift
enum HistoryRange {
    case week    // last 7 days
    case month   // last 30 days
    case window  // last 119 days (17 weeks × 7) — matches squares grid
}

@Published private(set) var daysShort:  [DailyActivity]   // 7
@Published private(set) var daysMonth:  [DailyActivity]   // 30
@Published private(set) var daysWindow: [DailyActivity]   // 119

@Published private(set) var projectsShort:  [ProjectSpend]
@Published private(set) var projectsMonth:  [ProjectSpend]
@Published private(set) var projectsWindow: [ProjectSpend]

func refreshHistory()                                       // populates all three
func days(for: HistoryRange) -> [DailyActivity]
func projects(for: HistoryRange) -> [ProjectSpend]
```

`refreshHistory()` runs one `Task.detached` that scans the widest window
(119 days). The narrower ranges are tail-windows of the same `buckets`
dictionary plus their own per-range project rollup (each range needs its
own rollup because a project's `activeDays` count and per-range token
total differ).

Live `todayTokens` counter and its incremental `refresh()` path stay
untouched — separate concern, runs on a 60s timer.

### View layer — `ActivityHistoryView`

Add `@State private var range: HistoryRange = .week`.

Header replaces the static "Last 7 days" label with a 3-position
segmented control:

```
[← back]   [ 7d │ 30d │ ▣ ]
```

- Pill container, rounded 8pt, hairline stroke.
- Selected pill: `Theme.Neon.blue.opacity(0.18)` fill, `Theme.Neon.blue`
  text.
- Unselected: clear fill, `Theme.textDim` text (hover → `textStrong`).
- Squares position is icon-only (`square.grid.3x3.fill` or a hand-rolled
  3×3 dot grid) to signal its different paradigm.

Switching range fades the chart, summary strip, and project list with
`.animation(.easeOut(duration: 0.18), value: range)`.

#### 7d view
Unchanged. Existing `barChart` body, fed `daysShort`.

#### 30d view
Reuses the same bar-chart code path, fed `daysMonth`. Parameterised
differences driven by count:

- `spacing: count > 7 ? 3 : 6` on the outer `HStack`.
- Bottom weekday letter (`M T W T F S S`) suppressed; replaced with
  sparse week-start ticks: every 7th bar shows its day-of-month number
  (`5  12  19  26  2`). Today's bar always labeled.
- Faint hairline below every 7th column to anchor week boundaries
  visually.
- Top label (agent count) shrinks to 7pt; hover still swaps it for token
  spend at 8pt blue (unchanged hover behaviour).
- Today's bar: fully saturated blue. Other active days: 0.7 opacity.

#### Squares view — `SquaresHistoryGrid`
New subview. Layout:

- 7 rows × 17 cols. Row 0 = Sunday, row 6 = Saturday.
- Today at `(weekday(today), 16)` — rightmost column; days beyond today
  in that column render as `Color.clear` (no stroke) so the grid stays
  rectangular without showing future cells.
- Cell sizing: `cell = floor((innerWidth − rowLabelWidth) / 17) − gap`.
  Target: `gap = 5`, `cell ≈ 34pt`. Computed at render time from the
  actual frame.
- Square corners: `RoundedRectangle(cornerRadius: 6)`.
- Row labels on the left: `M  W  F` only (rows 1, 3, 5) at 8pt
  `Theme.textFaint`. Tue/Thu/Sat/Sun omitted (GitHub convention,
  reduces clutter).

Colour buckets, thresholds against window `max`:

| Bucket    | Threshold (% of max) | Fill |
|-----------|---------------------:|------|
| empty     | 0                    | `Color.white.opacity(0.04)` |
| q1        | 1–25                 | `Theme.Neon.blue.opacity(0.22)` |
| q2        | 26–50                | `Theme.Neon.blue.opacity(0.45)` |
| q3        | 51–75                | `Theme.Neon.blue.opacity(0.70)` |
| q4        | 76–100               | `Theme.Neon.blue.opacity(1.00)` |

Today's cell gets a 1pt `Theme.Neon.blue` stroke overlay so it remains
visible even on a low-volume day.

Hover: per-cell `onHover`. While hovered, a floating chip appears above
the grid: `"Wed May 6 · 12.4M tokens · 3 agents"`. Empty days:
`"Wed May 6 · 0 tokens"`. Chip uses the same chip styling as the
existing bar-hover token readout — `Theme.Neon.blue` text on a faint
backdrop.

### Summary strip + projects list

Both bound to `tokenTracker.{days,projects}(for: range)`. Schema unchanged
across ranges:

- Summary: `<totalTokens> tokens · <projectCount> projects · <activeDays> active days`.
- Project rows unchanged; `activeDays` value is range-scoped.
- Empty state: `"No agent activity in this range."` (one string, no
  range branching).

### Vertical budget

Squares mode is taller than the bars views (~7×34pt + 6×5pt = 268pt
for the grid alone vs 108pt for the bar chart). Accepted: panel grows
to fit. `ExpandedView`'s `VStack` already sizes to content; no width
or container changes needed.

## Files touched

- `agenttab/AgentTAB/Engine/TokenTracker.swift`
  - Replace `weekly`/`weeklyProjects`/`refreshWeekly()` with the
    ranged model above. Refactor `scanWeekly` into a `scanRange(days:)`
    private helper that returns `(buckets, projectsByRange)` for all
    three windows in one pass.
- `agenttab/AgentTAB/UI/ActivityHistoryView.swift`
  - Add segmented switcher.
  - Add `range` state, route `daysShort`/`daysMonth`/`daysWindow` into
    the chart.
  - Parameterise `barChart` on `[DailyActivity]` + range (drives spacing
    + label rules).
  - Add `SquaresHistoryGrid` subview.
  - Update summary strip + projects list to read from
    `tokenTracker.{days,projects}(for: range)`.
- `agenttab/AgentTAB/UI/ExpandedView.swift`
  - Pass the full `tokenTracker` (not the resolved `weekly`/`projects`
    arrays) into `ActivityHistoryView` so the subview can read any
    range.

## Migration / compatibility

Internal-only data structures. No persisted state changes. The old
`weekly` and `weeklyProjects` properties are removed in the same change;
no shim needed.

## Sequencing

1. `TokenTracker` ranged model + scan refactor. Compile check: nothing
   reads `weekly` after the call sites are updated.
2. `ActivityHistoryView` switcher + range plumbing (7d still the only
   live tab while the other two are scaffolded).
3. 30d bar variant — spacing, sparse labels, week hairlines.
4. `SquaresHistoryGrid` subview + hover chip.
5. Visual pass: opacity buckets, today stroke, animation timing.

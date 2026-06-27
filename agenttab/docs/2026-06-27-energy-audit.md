# AgentTAB Energy / Battery Audit — 2026-06-27

Grounded in three read-only probes (render/animation, timers/IO, state model) plus
direct verification of the headline render path.

## The one principle

An always-on overlay's energy is dominated by **frames rendered per second at rest**.
The target steady state — idle, or occluded, or screen asleep — is **zero rendered
frames and zero timer wakeups**. Today the app violates both: a decorative animation
holds the render pipeline at display refresh 24/7, and two wall-clock timers poll
forever. Everything below serves that principle.

Key mechanism to internalize: **`TimelineView(.animation)` re-runs its closure every
display frame (60 Hz, or 120 Hz on ProMotion) for as long as it is mounted — whether or
not anything visually changes.** Gating the *visuals* inside the closure (`if p < 1 {…}`)
does NOT stop the ticking. Only unmounting the `TimelineView` (or switching it to a
coarse `.periodic` schedule) stops the cost.

---

## The 10 culprits (ranked by real battery impact)

### 1. Status-line river never stops ticking — `NotchShape.swift:373` (railView)
`TimelineView(.animation)` drives the rail. The river only moves while `p < 1`
(0.9 s after a transition); afterwards the closure still re-evaluates every frame and
redraws an identical line. The status line is always visible → effectively a 24/7
60–120 fps render of a static image. **#1 drain by an order of magnitude.**
**Fix:** mount the animated `TimelineView` only while a flow is in progress. Keep an
`isFlowing` flag that flips false ~`duration` after `flowStart`; render a plain static
`ZStack` (idle stroke + settled active trims) at rest with no `TimelineView`. Net idle
GPU for the bar → ~0.

### 2. `plusLighter` blend + animated shadow on the river fronts — `NotchShape.swift:400–405`
Two `.blendMode(.plusLighter)` strokes plus a `.shadow(radius: 4)` ride the fronts.
Additive blends and shadows are offscreen/fill-rate-heavy; an *animated* shadow can't be
cached (re-rasterized each frame). Compounds #1.
**Fix:** these are transient sparks — fine *during* a flow, but they must die with #1's
gating. Never run plusLighter/shadow on an always-mounted layer. For the settled bar use
a flat gradient/opacity, no blend, no shadow.

### 3. Idle "creature" loops run at display rate while the panel is open — `NotchShape.swift:1312` (BearLoader), `:1006` (CoffeeIdleIcon), `IdleSprites.swift:100`, `CoffeeIdle.swift:22`
These breathe/loop via `TimelineView(.animation)` / keyframes whenever the expanded
panel is visible with no active work — i.e. the **most common interactive state**. A
breathing dog does not need 120 fps.
**Fix:** (a) drop them to `TimelineView(.periodic(from:by:))` at 12–15 fps — a 4–8×
reduction invisible to the eye; (b) unmount when the panel is not actually on screen
(app not frontmost, display asleep, occluded); (c) freeze under Low Power Mode /
Reduce Motion.

### 4. Attention pulse animates `shadow` radius forever while a session waits — `AttnGlyph.swift:11`, dock `AttentionPulse` (`SessionDockPanel.swift:991`)
Animating `shadow(radius:)` is the single most expensive property to animate (re-raster
every frame), and it runs continuously for the whole time any agent is waiting on you —
potentially hours.
**Fix:** animate `opacity`/`scale` (cheap GPU transforms) instead of shadow radius; or a
`.periodic` low-fps pulse; or a static glow. Pair with the visibility gate from #3.

### 5. `FullscreenDetector` polls at 1 Hz with a full window enumeration — `FullscreenDetector.swift:36`
`Timer.publish(every: 1.0)` → `CGWindowListCopyWindowInfo()` enumerates **every on-screen
window** each second, iterating layers/alpha/bounds. Prevents deep CPU idle once per
second, all day.
**Fix:** fullscreen state is an *event*, not a continuous variable. Subscribe to
`NSWorkspace.shared.notificationCenter` (active-space / frontmost-app change) +
`NSApplication.didChangeScreenParametersNotification`, debounce, and run the window
enumeration only on those events. Deletes the 1 Hz timer.

### 6. `TokenTracker` rescans the project tree every 60 s, always-on — `TokenTracker.swift:159`
`Timer.publish(every: 60)` → two directory scans of `~/.claude/projects/` + JSONL tail
reads, even when the token UI (expanded panel) is closed.
**Fix:** two parts. (a) Suspend the timer when the expanded panel is not visible; refresh
on-expand (already does). (b) Better — token deltas come from the **same JSONL files
`JSONLWatcher` already watches via FSEvents**. Compute deltas incrementally on file-change
events and delete the wall-clock timer entirely.

### 7. Coarse `ObservableObject` re-renders 6 view trees on any change — `ActivityEngine.swift:6`
One `ObservableObject` with 3 `@Published` fields, observed by **6 views** (`NotchView`,
`CompactNotchView`, `ExpandedView`, `AgentRow`, `HoverPreviewView`, `SessionDockPanel`).
Any session mutation → every observer re-renders. During active work, sessions mutate on
each hook event, so this fires constantly.
**Fix:** migrate to the Observation framework (`@Observable`, macOS 14+). It tracks
per-field access, so a view re-renders only when the specific data it reads changes —
turning "any change → all 6 trees" into "only the affected view."

### 8. `displaySessions` is recomputed every render, then re-filtered in views — `ActivityEngine.swift:33`; `ExpandedView` (6 filter chains); `SessionDockPanel.swift:294` (re-sort)
Un-memoized computed property (filter → filter), recomputed on every body evaluation of
every observer, after which each view filters/sorts again. 3–5× redundant O(n) passes per
render over the same data.
**Fix:** compute the derived/sorted/bucketed lists **once per engine update** (cache as
stored state recomputed only when `sessions`/`zellijDetected`/`deniedPaneIds` change).
Views read the precomputed arrays.

### 9. `.animation(value: sessions.map(\.id))` allocates a new array every render — `SessionDockPanel.swift:343`
`sessions.map(\.id)` mints a fresh `[UUID]` on every render; SwiftUI must compare it,
forcing animation re-evaluation and O(n) garbage each frame.
**Fix:** animate on a cheap stable token (`sessions.count`, or a precomputed identity hash
stored when the list actually changes) rather than allocating in the modifier.

### 10. No global "quiet" policy — cross-cutting
Nothing centrally stops decorative motion when the user cannot see it: display asleep,
app not frontmost, overlay occluded by a fullscreen app (the data #5's detector already
computes!), Low Power Mode, or Reduce Motion. Each animation independently ignores all of
this.
**Fix:** one `Environment(\.energyState)` derived from {frontmost, screenAwake, occluded,
lowPower, reduceMotion}. Every `TimelineView` consults it to freeze or drop to low fps.
Highest-leverage systemic change: makes every animation cost ~0 exactly when it's
invisible. This is also what redeems the FullscreenDetector — its output becomes a
*savings* input instead of pure overhead.

**Honorable mentions:** `@AppStorage` read in `ExpandedView` body (minor); `KeyedGIFView`
ticks at display rate though sampled at 26 fps (transient, but `.periodic(by: 1/26)`
would halve it); animated `.blur` on smoke (transient, acceptable).

---

## The overhaul (over-engineered, but coherent)

The 10 fixes above are surgical. If you want to attack the *root*, three structural moves
collapse most of these into the architecture so they can't regress:

### A. Observation-first, per-session nodes
Replace the monolithic `@Published var sessions: [Session]` value array with an
`@Observable` store holding stable, individually-`@Observable` session nodes keyed by id.
Consequences:
- A square re-renders only when **its** node changes (kills #7).
- Identity is intrinsic to the node, so `ForEach` deltas are minimal and
  `sessions.map(\.id)` disappears (kills #9).
- Inserts/removes/updates touch only the affected subtree.

### B. A memoized "selectors" layer (push, not pull)
A small derived-state layer recomputes `displaySessions`, the dock order, and the
expanded buckets **once when an input changes**, caches them, and exposes them as plain
reads. Think Reselect/memoized selectors. Kills #8 and removes the 6 redundant filter
chains. Views become dumb projections.

### C. One `AnimationDirector` instead of N independent `TimelineView`s
Today every animated component owns its own `TimelineView(.animation)`, each independently
pinning the render loop to vsync. Replace with a single coordinator:
- Components **register** as active animators (with a desired fps + a visibility/priority
  predicate) only while they need to move.
- One top-level clock (a single `TimelineView` or `CADisplayLink`) ticks **only while the
  active-animator set is non-empty**, publishing a phase that children read as a pure
  function. No child owns a clock.
- The director consults `Environment(\.energyState)` (move #D) to pause everything or drop
  cadence under occlusion / sleep / Low Power.
Result: **at rest the app renders zero frames**; during motion, exactly one clock drives
everything; and you get global fps/energy control for free. This single abstraction
subsumes culprits #1–#4 and #10.

### D. Fully event-driven, zero idle timers
Fold {FullscreenDetector, frontmost, screen-sleep, LowPowerMode, ReduceMotion} into the
`energyState` value via `NSWorkspace`/`NSApplication`/`IOKit` notifications, and drive
`TokenTracker` off the existing FSEvents stream. Outcome: **no recurring timers at all** —
the process wakes only on real input (file change, hook, hotkey, mouse, space change).

### E. (The truly over-engineered extreme — optional)
A declarative animation DSL where each animation declares priority/fps/visibility, and the
director schedules within a frame/energy budget, shedding low-priority decorative loops
first under Low Power. Overkill for a notch app, but it's the logical endpoint of the
principle.

---

## Pragmatic rollout (80/20)

In order of (impact ÷ risk):
1. **Gate the railView `TimelineView` to active flow** (#1+#2). Smallest diff, biggest win.
2. **Visibility/Low-Power gate for the idle loops + attention pulse** (#3+#4+#10 lite) —
   one `energyState` env value, consulted by the existing animators.
3. **Event-drive FullscreenDetector and TokenTracker** (#5+#6). Deletes both idle timers.
4. **Migrate `ActivityEngine` to `@Observable` + cache derived lists** (#7+#8+#9).
5. Only if still warranted: the full `AnimationDirector` (move C).

## Measure, don't guess
Quantify before/after with: Xcode **Instruments → Energy Log** + **Animation Hitches** +
**Time Profiler**; **Activity Monitor → Energy** ("Energy Impact" / "App Nap"); and
`powermetrics --samplers gpu_power,cpu_power` while idle vs. active. Watch idle CPU% (goal:
~0 at rest) and GPU residency. The single most telling check: with the app idle and
frontmost, is the GPU rendering frames? After fix #1 it should not be.

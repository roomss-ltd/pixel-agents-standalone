// PixelLoops.swift — SwiftUI port of the AgentTab "Pixel Loops" design canvas.
//
// 11 looping pixel-art animations on a 3×3 grid, rendered in 6 monotone
// palettes (blue · amber · pink · green · purple · white). Mirrors the
// vanilla-JS prototype in `agenttab/project/Pixel Loops.html` and the
// React reference in `agenttab/project/pixel-loops.jsx`, both shipped in
// the Claude Design handoff bundle.
//
// Each variant either walks a SHAPE through a PATH of waypoints, or
// cycles a fixed list of FRAMES. All 9 cells of the 3×3 grid are always
// visible at a dim base opacity; the animation modulates the active
// cells above that base — every cell the shape passes through over one
// cycle peaks at full brightness.
//
// Public API:
//   PixelLoopView(variant:palette:size:running:...)
//   PixelLoopVariant.allCases   — 11 variants
//   PixelLoopPalette.allCases   — 6 palettes
//
// The rotating loader (`Loaders.swift:RotatingLoader`) cycles through
// both axes on the `Theme.Animations.loaderRotationSeconds` interval.

import SwiftUI

// MARK: - Palette

enum PixelLoopPalette: String, CaseIterable {
    case blue
    case pink
    case white
    case purple
    case cyan
    case darkBlue = "dark-blue"

    /// Core fill — the lit pixel color. `blue`/`pink`/`white`/`purple`
    /// values come from `pixel-loops.jsx:24-31` (Claude Design handoff);
    /// `cyan` and `dark-blue` are added per user request as replacements
    /// for the original `amber` and `green` accents.
    var core: Color {
        switch self {
        case .blue:     return Color(red: 0x7C/255.0, green: 0xC0/255.0, blue: 0xFF/255.0)
        case .pink:     return Color(red: 0xFF/255.0, green: 0x7E/255.0, blue: 0x8E/255.0)
        case .white:    return Color(red: 0xE6/255.0, green: 0xE8/255.0, blue: 0xEE/255.0)
        case .purple:   return Color(red: 0xC2/255.0, green: 0x9C/255.0, blue: 0xFF/255.0)
        case .cyan:     return Color(red: 0x7C/255.0, green: 0xF0/255.0, blue: 0xF0/255.0)
        case .darkBlue: return Color(red: 0x5A/255.0, green: 0x7A/255.0, blue: 0xFF/255.0)
        }
    }

    /// Glow color — used for the outer shadow halo on active cells.
    var glow: Color {
        switch self {
        case .blue:     return Color(red: 0x5A/255.0, green: 0xA9/255.0, blue: 0xFF/255.0)
        case .pink:     return Color(red: 0xFF/255.0, green: 0x65/255.0, blue: 0x77/255.0)
        case .white:    return Color(red: 0xB7/255.0, green: 0xBC/255.0, blue: 0xC7/255.0)
        case .purple:   return Color(red: 0xA7/255.0, green: 0x7B/255.0, blue: 0xFF/255.0)
        case .cyan:     return Color(red: 0x5A/255.0, green: 0xD8/255.0, blue: 0xE8/255.0)
        case .darkBlue: return Color(red: 0x3D/255.0, green: 0x5A/255.0, blue: 0xE0/255.0)
        }
    }
}

// MARK: - Variant catalog

enum PixelLoopVariant: String, CaseIterable {
    case soloRotate    = "solo-rotate"
    case lineHRotate   = "line-h-rotate"
    case lineVRotate   = "line-v-rotate"
    case diagRotate    = "diag-rotate"
    case cornersRotate = "corners-rotate"
    case plusHollow    = "plus-hollow"
    case lRotate       = "L-rotate"
    case tRotate       = "T-rotate"
    case duoRotate     = "duo-rotate"
    case frameRotate   = "frame-rotate"
    case sparseRotate  = "sparse-rotate"
    case chaosRotate   = "chaos-rotate"

    /// Seconds per full cycle. Mirrors `LOOPS[id].period` in the prototype.
    var period: Double {
        switch self {
        case .soloRotate:    return 1.4
        case .lineHRotate:   return 1.2
        case .lineVRotate:   return 1.2
        case .diagRotate:    return 0.9
        case .cornersRotate: return 1.3
        case .plusHollow:    return 0.9
        case .lRotate:       return 1.3
        case .tRotate:       return 1.4
        case .duoRotate:     return 1.0
        case .frameRotate:   return 1.8
        case .sparseRotate:  return 1.2
        case .chaosRotate:   return 2.4
        }
    }

    /// `shape+path` definition — a single shape walks through path waypoints.
    /// Returns `nil` for frame-based variants (handled by `frames`).
    var motion: PixelLoopMotion {
        switch self {
        case .soloRotate:
            return .path(
                shape: [Cell(0,0)],
                path:  [Cell(0,0), Cell(1,0), Cell(2,0),
                        Cell(2,1),
                        Cell(2,2), Cell(1,2), Cell(0,2),
                        Cell(0,1),
                        Cell(1,1)]
            )
        case .lineHRotate:
            return .path(
                shape: [Cell(0,0), Cell(1,0)],
                path:  [Cell(0,0), Cell(1,0),
                        Cell(0,1), Cell(1,1),
                        Cell(0,2), Cell(1,2)]
            )
        case .lineVRotate:
            return .path(
                shape: [Cell(0,0), Cell(0,1)],
                path:  [Cell(0,0), Cell(0,1),
                        Cell(1,0), Cell(1,1),
                        Cell(2,0), Cell(2,1)]
            )
        case .plusHollow:
            return .path(
                shape: [Cell(0,0)],
                path:  PixelLoopVariant.plusOutline
            )

        case .diagRotate:
            return .frames([
                [Cell(0,2), Cell(1,1), Cell(2,0)],
                [Cell(0,0), Cell(1,1), Cell(2,2)],
            ])
        case .cornersRotate:
            return .frames([
                [Cell(0,0)],
                [Cell(2,0)],
                [Cell(2,2)],
                [Cell(0,2)],
                [Cell(0,0), Cell(2,0), Cell(2,2), Cell(0,2)],
            ])
        case .lRotate:
            return .frames([
                [Cell(0,0), Cell(1,0), Cell(0,1)],
                [Cell(1,0), Cell(2,0), Cell(2,1)],
                [Cell(2,1), Cell(1,2), Cell(2,2)],
                [Cell(0,1), Cell(0,2), Cell(1,2)],
            ])
        case .tRotate:
            return .frames([
                [Cell(0,0), Cell(1,0), Cell(2,0), Cell(1,1)],
                [Cell(2,0), Cell(2,1), Cell(1,1), Cell(2,2)],
                [Cell(1,1), Cell(0,2), Cell(1,2), Cell(2,2)],
                [Cell(0,0), Cell(0,1), Cell(1,1), Cell(0,2)],
            ])
        case .duoRotate:
            return .frames([
                [Cell(0,1), Cell(2,1)],
                [Cell(1,0), Cell(1,2)],
                [Cell(0,0), Cell(2,2)],
            ])
        case .frameRotate:
            var frames: [[Cell]] = PixelLoopVariant.perimeter.map { [$0] }
            frames.append(PixelLoopVariant.perimeter)
            return .frames(frames)
        case .sparseRotate:
            return .frames([
                [Cell(2,0), Cell(1,1), Cell(0,2), Cell(2,2)],
                [Cell(0,0), Cell(2,1), Cell(1,2)],
                [Cell(1,0), Cell(0,1), Cell(2,2)],
            ])
        case .chaosRotate:
            return .chaos
        }
    }

    /// Clockwise perimeter of a 3×3 starting at top-left (8 cells).
    static let perimeter: [Cell] = [
        Cell(0,0), Cell(1,0), Cell(2,0),
        Cell(2,1),
        Cell(2,2), Cell(1,2), Cell(0,2),
        Cell(0,1),
    ]

    /// Outline cells of a `+` (top, right, bottom, left around centre).
    static let plusOutline: [Cell] = [Cell(1,0), Cell(2,1), Cell(1,2), Cell(0,1)]
}

// MARK: - Cell + motion mode

struct Cell: Equatable, Hashable {
    let x: Int
    let y: Int
    init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
}

enum PixelLoopMotion {
    case path(shape: [Cell], path: [Cell])
    case frames([[Cell]])
    /// A "snake" head walks the 3×3 grid in 4-connected steps. At each
    /// tick the next cell is picked at random from the current cell's
    /// neighbours (the immediately previous cell is excluded so the
    /// snake never instantly backtracks). Recent visits fade out behind
    /// the head, giving the same trailing pulse used by the other
    /// `solo`/`line` variants — only the path is procedural instead of
    /// fixed, so the animation never repeats. Used by `chaos-rotate`.
    case chaos
}

/// One visit of the snake-walk head: which cell it just arrived at, and
/// when (in seconds, matching the TimelineView's clock).
struct SnakeStep: Equatable {
    let cell: Cell
    let arrivedAt: Double
}

/// 4-connected neighbours of a cell, clipped to the 3×3 grid.
func snakeNeighbours(of c: Cell) -> [Cell] {
    var out: [Cell] = []
    for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
        let nx = c.x + dx, ny = c.y + dy
        if nx >= 0, nx < 3, ny >= 0, ny < 3 { out.append(Cell(nx, ny)) }
    }
    return out
}

/// Pick the next snake step uniformly from `current`'s neighbours.
///
/// Filters applied in priority order:
///   1. Drop the immediately previous cell so the snake doesn't
///      instantly reverse direction.
///   2. Drop any cell in `blocked` — these are the current head cells
///      of other snakes; the rule is that no two snake heads may
///      occupy the same cell at the same time.
///
/// On a 3×3 grid with multiple snakes both filters can leave zero
/// candidates (e.g. a snake cornered between its previous cell and
/// another head). We then relax progressively: allow backtrack first,
/// then allow head-overlap, and finally fall back to any neighbour —
/// so the snake always advances by exactly one cell per step.
func nextSnakeStep(current: Cell, previous: Cell?, blocked: Set<Cell> = []) -> Cell {
    let all = snakeNeighbours(of: current)

    // Preferred: avoid both backtracking AND head collisions.
    let primary = all.filter { $0 != previous && !blocked.contains($0) }
    if let pick = primary.randomElement() { return pick }

    // Relax 1: allow backtracking, still avoid other heads.
    let avoidBlocked = all.filter { !blocked.contains($0) }
    if let pick = avoidBlocked.randomElement() { return pick }

    // Relax 2: avoid backtracking, allow head overlap (rare corner case).
    let avoidPrev = all.filter { $0 != previous }
    if let pick = avoidPrev.randomElement() { return pick }

    return all.randomElement() ?? current
}

// MARK: - Brightness math
//
// For each cell `(cx,cy)` and a normalised time `t01 ∈ [0,1)`, walk the
// path or frame list and find every visit where the shape (or frame)
// covers that cell. Each visit contributes a wrap-aware Gaussian pulse
// centred at `i/n`. The cell's brightness is the max across visits.

private enum PixelMath {
    static func cellBrightness(_ motion: PixelLoopMotion,
                               cx: Int, cy: Int, t01: Double) -> Double {
        switch motion {
        case .path(let shape, let path):
            return pathBrightness(shape: shape, path: path, cx: cx, cy: cy, t01: t01)
        case .frames(let frames):
            return frameBrightness(frames: frames, cx: cx, cy: cy, t01: t01)
        case .chaos:
            // Chaos brightness is driven by a stateful snake-walk; the
            // view computes it directly via `snakeBrightness`. Return 0
            // here so the abstract motion API stays pure.
            return 0
        }
    }

    /// Brightness for a single cell given a list of recent snake visits.
    /// Each visit contributes a Gaussian pulse centred on `arrivedAt`;
    /// the cell's brightness is the max contribution across visits.
    ///
    /// `sigma` controls the trail length — set it slightly larger than
    /// the snake's step interval so adjacent cells overlap and the head
    /// always has a soft fading tail behind it.
    static func snakeBrightness(cx: Int, cy: Int, now: Double,
                                history: [SnakeStep], sigma: Double) -> Double {
        var maxB = 0.0
        for step in history where step.cell.x == cx && step.cell.y == cy {
            let age = now - step.arrivedAt
            if age < 0 { continue }
            let b = exp(-(age * age) / (2 * sigma * sigma))
            if b > maxB { maxB = b }
        }
        return maxB
    }

    private static func pathBrightness(shape: [Cell], path: [Cell], cx: Int, cy: Int, t01: Double) -> Double {
        let n = path.count
        guard n > 0 else { return 0 }
        // Narrower sigma when there are more waypoints so each visit reads
        // as its own pulse. Floor for n=1: ≈ 0.28 (snappy breath).
        let sigma = n == 1 ? 0.28 : 0.42 / Double(n)
        var maxB = 0.0
        for i in 0..<n {
            let p = path[i]
            // Does shape (translated to p) cover (cx, cy)?
            var inShape = false
            for s in shape where (s.x + p.x) == cx && (s.y + p.y) == cy {
                inShape = true; break
            }
            if !inShape { continue }
            let wt = Double(i) / Double(n)
            var dt = t01 - wt
            dt -= dt.rounded()
            let b = exp(-(dt * dt) / (2 * sigma * sigma))
            if b > maxB { maxB = b }
        }
        return maxB
    }

    private static func frameBrightness(frames: [[Cell]], cx: Int, cy: Int, t01: Double) -> Double {
        let n = frames.count
        guard n > 0 else { return 0 }
        let sigma = n == 1 ? 0.28 : 0.42 / Double(n)
        var maxB = 0.0
        for i in 0..<n {
            let cells = frames[i]
            var inFrame = false
            for c in cells where c.x == cx && c.y == cy { inFrame = true; break }
            if !inFrame { continue }
            let wt = Double(i) / Double(n)
            var dt = t01 - wt
            dt -= dt.rounded()
            let b = exp(-(dt * dt) / (2 * sigma * sigma))
            if b > maxB { maxB = b }
        }
        return maxB
    }

    /// All cells the motion ever covers — used to decide which cells get
    /// the animated treatment vs. the dim base-only treatment.
    static func activeCells(_ motion: PixelLoopMotion) -> Set<Cell> {
        var set: Set<Cell> = []
        switch motion {
        case .path(let shape, let path):
            for p in path {
                for s in shape {
                    let x = s.x + p.x, y = s.y + p.y
                    if x >= 0, x < 3, y >= 0, y < 3 { set.insert(Cell(x, y)) }
                }
            }
        case .frames(let frames):
            for f in frames { for c in f { set.insert(c) } }
        case .chaos:
            for y in 0..<3 { for x in 0..<3 { set.insert(Cell(x, y)) } }
        }
        return set
    }
}

// MARK: - PixelLoopView

struct PixelLoopView: View {
    var variant: PixelLoopVariant
    var palette: PixelLoopPalette = .blue
    /// Explicit color override for the lit-pixel fill. When non-nil it
    /// supersedes `palette.core`. Used by `RotatingLoader` to crossfade
    /// smoothly between palettes via `withAnimation`.
    var coreOverride: Color? = nil
    /// Companion override for the outer-shadow glow halo.
    var glowOverride: Color? = nil
    /// Outer container edge in points. cellSize and gap are derived to fit.
    var size: CGFloat = 18
    var running: Bool = true
    var brightness: Double = 1.0
    var glow: Double = 1.0
    var speed: Double = 1.0
    /// Dim opacity for cells that are part of the active set but not lit
    /// at this moment, and for cells the motion never touches.
    var baseOpacity: Double = 0.12

    private var coreColor: Color { coreOverride ?? palette.core }
    private var glowColor: Color { glowOverride ?? palette.glow }

    /// One sliding window of recent visits per snake. Three snakes walk
    /// the same 3×3 grid independently; their brightness contributions
    /// are max-blended so overlaps just read as a brighter cell.
    @State private var snakes: [[SnakeStep]] = Array(repeating: [], count: 3)

    /// Per-snake step intervals. All three differ so the heads drift in
    /// and out of phase instead of marching in lockstep. The first is
    /// the `solo-rotate` pace (1.4s ÷ 9 waypoints); the other two are
    /// chosen with no integer ratio between them so collisions on the
    /// 3×3 grid read as occasional, not patterned.
    private static let snakeStepIntervals: [Double] = [0.155, 0.205, 0.175]

    /// Per-snake starting cells. Three of the four corners so the heads
    /// light up well-separated parts of the grid from frame 1.
    private static let snakeStartCells: [Cell] = [Cell(0, 0), Cell(2, 2), Cell(2, 0)]

    /// Gaussian tail length for the snake trail. ~2× the fastest step
    /// interval so the head's pulse softly overlaps the cell just
    /// behind it.
    private static let snakeSigma: Double = 0.31

    /// How many recent steps to retain per snake; ~5σ is enough that
    /// any older step's contribution is below 1% brightness.
    private static let snakeWindow: Int = 12

    var body: some View {
        let gap = max(1.0, size * 0.08)
        let cellSize = max(1.0, (size - 2 * gap) / 3.0)
        let motion = variant.motion
        let active = PixelMath.activeCells(motion)
        let period = variant.period

        Group {
            if running {
                TimelineView(.animation(
                    minimumInterval: Theme.Animations.timelineMinimumInterval
                )) { context in
                    grid(
                        at: context.date.timeIntervalSinceReferenceDate * speed,
                        period: period,
                        motion: motion,
                        active: active,
                        gap: gap,
                        cellSize: cellSize
                    )
                }
            } else {
                grid(
                    at: Date().timeIntervalSinceReferenceDate * speed,
                    period: period,
                    motion: motion,
                    active: active,
                    gap: gap,
                    cellSize: cellSize
                )
            }
        }
        .frame(width: size, height: size)
        .task(id: running) { await runSnakes() }
    }

    private func grid(
        at time: Double,
        period: Double,
        motion: PixelLoopMotion,
        active: Set<Cell>,
        gap: CGFloat,
        cellSize: CGFloat
    ) -> some View {
        let raw = time / period
        let t01 = raw - floor(raw)
        return VStack(spacing: gap) {
            ForEach(0..<3, id: \.self) { y in
                HStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { x in
                        cell(x: x, y: y,
                             isActive: active.contains(Cell(x, y)),
                             t01: t01, tNow: time, motion: motion,
                             cellSize: cellSize)
                    }
                }
            }
        }
        .frame(width: cellSize * 3 + gap * 2,
               height: cellSize * 3 + gap * 2)
    }

    /// Drive every snake from one loop.
    ///
    /// Originally each snake had its own `.task(id:)` modifier, but
    /// stacking N identical-id task modifiers turned out to be unreliable
    /// for N ≥ 3 (visually only the first two would advance). This
    /// version polls once per rendered frame and advances each snake
    /// independently when its own per-snake interval has elapsed. Polling
    /// faster than the UI can render only wakes the CPU without producing
    /// a visible frame.
    private func runSnakes() async {
        let n = Self.snakeStepIntervals.count

        guard running else {
            let now = Date().timeIntervalSinceReferenceDate * speed
            snakes = Self.snakeStartCells.map { [SnakeStep(cell: $0, arrivedAt: now)] }
            return
        }
        guard variant == .chaosRotate else {
            snakes = Array(repeating: [], count: n)
            return
        }

        // Seed each snake at its start cell so all heads are lit from
        // frame 1 and there are no empty histories for the head-collision
        // check to trip over.
        let seed = Date().timeIntervalSinceReferenceDate * speed
        for i in 0..<n where snakes[i].isEmpty {
            snakes[i] = [SnakeStep(cell: Self.snakeStartCells[i], arrivedAt: seed)]
        }

        // Per-snake "next eligible step time" in the same clock as the
        // SnakeStep.arrivedAt values, so step timing stays consistent
        // with the Gaussian trail's age calculation.
        var nextStepAt: [Double] = (0..<n).map { i in
            seed + Self.snakeStepIntervals[i] / max(speed, 0.01)
        }

        let baseTick = Theme.Animations.timelineMinimumInterval
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(baseTick * 1_000_000_000))
            let now = Date().timeIntervalSinceReferenceDate * speed
            for i in 0..<n where now >= nextStepAt[i] {
                let history  = snakes[i]
                let current  = history.last?.cell ?? Self.snakeStartCells[i]
                let previous = history.count >= 2 ? history[history.count - 2].cell : nil

                // Heads must not collide; trails (bodies) may overlap
                // freely. Block only the other snakes' current head cells.
                var blocked: Set<Cell> = []
                for j in 0..<n where j != i {
                    if let head = snakes[j].last?.cell { blocked.insert(head) }
                }

                let next = nextSnakeStep(current: current, previous: previous, blocked: blocked)
                var updated = history
                updated.append(SnakeStep(cell: next, arrivedAt: now))
                if updated.count > Self.snakeWindow {
                    updated.removeFirst(updated.count - Self.snakeWindow)
                }
                snakes[i] = updated
                nextStepAt[i] = now + Self.snakeStepIntervals[i] / max(speed, 0.01)
            }
        }
    }

    private func rawBrightness(x: Int, y: Int, isActive: Bool,
                               t01: Double, tNow: Double,
                               motion: PixelLoopMotion) -> Double {
        if case .chaos = motion {
            // Max-blend across all snakes so overlapping heads just read
            // as one brighter cell rather than fighting for the pixel.
            var maxB = 0.0
            for history in snakes {
                let b = PixelMath.snakeBrightness(cx: x, cy: y, now: tNow,
                                                  history: history,
                                                  sigma: Self.snakeSigma)
                if b > maxB { maxB = b }
            }
            return maxB
        }
        return isActive
            ? PixelMath.cellBrightness(motion, cx: x, cy: y, t01: t01)
            : 0
    }

    @ViewBuilder
    private func cell(x: Int, y: Int, isActive: Bool, t01: Double, tNow: Double,
                      motion: PixelLoopMotion, cellSize: CGFloat) -> some View {
        let raw = rawBrightness(x: x, y: y, isActive: isActive,
                                t01: t01, tNow: tNow, motion: motion)
        let v = min(1.0, max(0.0, raw * brightness))
        let opacity = isActive
            ? (baseOpacity + (1.0 - baseOpacity) * v)
            : baseOpacity
        let blurPx = cellSize * 0.95 * glow * v

        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(coreColor)
            .opacity(opacity)
            .shadow(color: (isActive && v > 0.08) ? glowColor.opacity(0.4) : .clear,
                    radius: blurPx)
    }
}

// MARK: - Previews

#Preview("Catalogue") {
    ScrollView {
        VStack(spacing: 24) {
            ForEach(PixelLoopPalette.allCases, id: \.self) { pal in
                VStack(alignment: .leading, spacing: 8) {
                    Text(pal.rawValue.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                        ForEach(PixelLoopVariant.allCases, id: \.self) { v in
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.black)
                                        .frame(width: 96, height: 96)
                                    PixelLoopView(variant: v, palette: pal, size: 68)
                                }
                                Text(v.rawValue)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
    }
    .frame(width: 600, height: 800)
    .background(Color(red: 0x0B/255.0, green: 0x0C/255.0, blue: 0x0F/255.0))
}

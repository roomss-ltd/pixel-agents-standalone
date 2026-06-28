// NotchShape.swift — geometries used by the AgentTab UI.
//
// All three panel sizes (compact 230×34, hover 360×86, expanded 720×460)
// share the same shape pattern: a flat top edge that meets the hardware
// notch, plus rounded bottom corners. There is no carve in the panel
// itself — the carve IS the hardware notch above it; the panel just hangs
// flush below.
//
// Mirrors the React prototype exactly:
//   * `borderRadius: "0 0 16px 16px"` for compact (`notch.jsx:141`)
//   * `borderRadius: "0 0 20px 20px"` for hover  (`notch.jsx:178`)
//   * `borderRadius: "0 0 22px 22px"` for expanded (`notch.jsx:316`)

import SwiftUI
import AppKit
import ImageIO
import AVFoundation
import Lottie

/// Flat top, rounded bottom corners.
struct DropPanelShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}

/// Compact-bar shape used by the notch overlay.
///
/// The TOP corners flare OUTWARD with concave/inverted curves so the bar
/// reads as "morphing into the end of the screen": the top edge extends
/// full-width to the screen edges, and the body narrows down via gentle
/// inward-curving shoulders. The BOTTOM corners are normal convex
/// rounds where the bar rejoins the menu bar.
///
///   ╲                       ╱       <- top flares outward
///    ╲_____________________╱
///    |                     |        <- straight body sides
///    ╲                     ╱        <- convex bottom rounds
///     ╲___________________╱
struct CompactBarShape: Shape {
    let topRadius: CGFloat
    let bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let maxTR = min(rect.width / 4, rect.height)
        let maxBR = min(rect.width / 4, rect.height / 2)
        let tR = max(0, min(topRadius, maxTR))
        let bR = max(0, min(bottomRadius, maxBR))

        var path = Path()
        // CW from top-left of frame.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Full-width top edge.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Top-right inverted shoulder — curves DOWN-LEFT into the body.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - tR, y: rect.minY + tR),
            control: CGPoint(x: rect.maxX - tR, y: rect.minY)
        )
        // Right body edge.
        path.addLine(to: CGPoint(x: rect.maxX - tR, y: rect.maxY - bR))
        // Bottom-right convex round.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - tR - bR, y: rect.maxY),
            control: CGPoint(x: rect.maxX - tR, y: rect.maxY)
        )
        // Bottom edge.
        path.addLine(to: CGPoint(x: rect.minX + tR + bR, y: rect.maxY))
        // Bottom-left convex round.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tR, y: rect.maxY - bR),
            control: CGPoint(x: rect.minX + tR, y: rect.maxY)
        )
        // Left body edge.
        path.addLine(to: CGPoint(x: rect.minX + tR, y: rect.minY + tR))
        // Top-left inverted shoulder — curves UP-LEFT to the frame corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.minX + tR, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// Left half of the compact panel: flat top, flat right edge (the inner edge
/// that meets the notch hardware), rounded only at the bottom-left.
struct LeftWingShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

/// Mirror of `LeftWingShape` for the right side of the notch.
struct RightWingShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Status line (siphon rail)

/// The VISIBLE outline of the compact bar — the "U" contour that hangs below
/// the menu bar (everything EXCEPT the top edge). Drawn top-RIGHT clockwise to
/// top-LEFT, so a `.trim(from:to:)` fills right → bottom → left. The siphon
/// droplet rides this path.
struct NotchOutlineShape: Shape {
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    /// Pushes ONLY the bottom edge this far below the frame so a stroke on it
    /// clears the camera cutout's bottom boundary at the centre — without
    /// moving the top (the shoulders stay connected to the screen edge).
    var bottomExtend: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let maxTR = min(rect.width / 4, rect.height)
        let maxBR = min(rect.width / 4, rect.height / 2)
        let tR = max(0, min(topRadius, maxTR))
        let bR = max(0, min(bottomRadius, maxBR))
        let bottomY = rect.maxY + bottomExtend

        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - tR, y: rect.minY + tR),
            control: CGPoint(x: rect.maxX - tR, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - tR, y: bottomY - bR))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - tR - bR, y: bottomY),
            control: CGPoint(x: rect.maxX - tR, y: bottomY)
        )
        path.addLine(to: CGPoint(x: rect.minX + tR + bR, y: bottomY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tR, y: bottomY - bR),
            control: CGPoint(x: rect.minX + tR, y: bottomY)
        )
        path.addLine(to: CGPoint(x: rect.minX + tR, y: rect.minY + tR))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.minX + tR, y: rect.minY)
        )
        return path
    }
}

/// PROTOTYPE — the notch outline as a quiet dark "rail". It just sits there;
/// the only motion is a SIPHON droplet that runs the bottom between the wings
/// when an agent flips state (left→right when work STARTS, right→left when it
/// finishes). The COUNTS live in the left/right badges, not the line.
/// Which wing currently has the shooter GIF over it — so the badge/icon behind
/// it can fade out of the way.
enum ShooterWing { case left, right, both }

struct NotchStatusLine: View {
    let idle: Int
    let working: Int
    /// Published up to the header so the wing behind the gun fades while it plays.
    @Binding var activeShooter: ShooterWing?

    /// Brighter, more saturated than `Theme.Neon.blue` (#4EA1FF).
    private let blueVivid = Color(red: 0x66/255.0, green: 0xB5/255.0, blue: 0xFF/255.0)
    /// Quiet dark rail — the structural outline, not a status colour.
    private let trackColor = Color(white: 0.30)

    /// How long the "shooter" GIF poses at the origin wing before the bullet
    /// (siphon comet) is fired across the rail.
    private static let shootDelay: TimeInterval = 0.5

    // Siphon firing state — geometry is set on each working-count transition,
    // then `siphonID` bumps to (re)trigger the droplet animation.
    @State private var siphonID = 0
    @State private var siphonStart: CGFloat = 1.0
    @State private var siphonEnd: CGFloat = 0.0
    @State private var siphonColor = Color.white

    // "Shoot" flourish — the hand GIF appears at the origin wing, then fires.
    @State private var showShoot = false
    @State private var shooterOnLeft = true
    /// Bumped on every transition so the GIF view remounts and replays from
    /// frame 0 (used as its `.id`).
    @State private var shootEventID = 0
    /// Duotone tint for the hand — matched to the bullet it's about to fire.
    @State private var shootTint = Color(red: 0x66/255.0, green: 0xB5/255.0, blue: 0xFF/255.0)
    /// Rail "river" colour flow. `flowToActive` is the current/target state
    /// (true = neon active, false = gray idle); `flowProgress` 0→1 animates the
    /// flow. Active→ neon flows in from both ends to centre; idle→ gray flows
    /// out from the centre.
    @State private var flowToActive = false
    /// Far past → the rail starts settled (no flow) until a transition.
    @State private var flowStart = Date(timeIntervalSinceReferenceDate: -1000)
    /// True ONLY during a flow transition (~`flowDuration`). The rail's
    /// `TimelineView(.animation)` is mounted only while this is true; at rest
    /// the rail is a static stroke so it stops forcing display-rate redraws
    /// (energy culprit #1). A generation token guards against a stale timer
    /// from an earlier flow clearing a newer one.
    @State private var railAnimating = false
    @State private var railFlowGen = 0
    /// Length of the river-flow animation; also how long `railAnimating` holds.
    private static let flowDuration: Double = 0.9
    /// After the flow completes, sparks keep spraying off the settled fronts for
    /// this long, then fade out — so the sparkle covers the whole merge/unmerge
    /// (both ends, both directions) plus a short tail.
    private static let sparkTail: TimeInterval = 0.5

    var body: some View {
        let total = idle + working
        let shape = NotchOutlineShape(topRadius: 6, bottomRadius: 10, bottomExtend: 1.5)

        return ZStack {
            if total > 0 {
                // Rail: ALWAYS a soft gray base (idle stays pure gray). A single
                // "active" colour overlays it where active — the colour that
                // white + blue + green MERGE into: a bright aqua/cyan. (TEMP:
                // sampling the wallpaper colour behind the notch instead.) Its
                // extent rivers in from the ends (active) or recedes (idle).
                railView(shape)

                // Industrial freight rides the bottom rail while work is active.
                RailFreight(working: working, shape: shape)

                // A dirigible drifts across the upper band now and then — a rare,
                // lighter flourish (the airplanes were retired).
                RailAircraft(working: working, shape: shape)

                // The siphon droplet — the "bullet", fired after the shooter.
                SiphonDroplet(trigger: siphonID,
                              start: siphonStart, end: siphonEnd,
                              color: siphonColor, outline: shape)
                // Sparks thrown off the comet as it flies — a lit fuse igniting
                // the far wing.
                CometSparks(trigger: siphonID,
                            start: siphonStart, end: siphonEnd,
                            outline: shape)

                // LEFT-wing flourish: a target on a FINISH only (no funnel on
                // a start — the start just plays bullets on the right).
                if showShoot, !shooterOnLeft, !ShootAsset.target.isEmpty {
                    KeyedGIFView(frames: ShootAsset.target)
                        .id(shootEventID)   // fresh instance per shot → replays from 0
                        .frame(width: 21, height: 21)
                        .clipped()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .offset(x: 6)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // RIGHT-wing flourish: bullets on a START, gun hand on a FINISH.
                if showShoot {
                    let frames = shooterOnLeft ? ShootAsset.bullets : ShootAsset.frames
                    if !frames.isEmpty {
                        KeyedGIFView(frames: frames)
                            .id(shootEventID)
                            .frame(width: shooterOnLeft ? 21 : 30,
                                   height: shooterOnLeft ? 21 : 30)
                            .clipped()
                            // Duotone only on the gun (finish); bullets stay native.
                            .saturation(shooterOnLeft ? 1 : 0)
                            .colorMultiply(shooterOnLeft ? .white : shootTint)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.horizontal, 4)
                            .offset(x: shooterOnLeft ? -8 : -6)   // gun hand pulled left
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
            }
        }
        .onChange(of: working) { old, new in
            guard new != old else { return }
            let starting = new > old
            shooterOnLeft = starting
            // Pre-stage the bullet's geometry — it launches FROM the shooter.
            // Work STARTS → shooter on LEFT, sweep top-LEFT ⇒ top-RIGHT;
            // FINISHES → shooter on RIGHT, sweep top-RIGHT ⇒ top-LEFT.
            // Spark orange whenever the comet travels over an already-active
            // (coloured) line — a blue comet on a blue line is invisible.
            // Blue is used only when depositing colour onto an idle line.
            let cometOrange = Color(red: 1.0, green: 0.74, blue: 0.28)
            if starting {
                siphonStart = 1.0; siphonEnd = 0.0
                // First session igniting an idle rail → a white-hot "fuse" comet
                // (no blue), sparking as it flies to ignite the right wing.
                let igniteWhite = Color(red: 1.0, green: 0.95, blue: 0.84)
                siphonColor = (old == 0) ? igniteWhite : cometOrange
                shootTint = (old == 0) ? igniteWhite : blueVivid
            } else {
                siphonStart = 0.0; siphonEnd = 1.0
                siphonColor = cometOrange
                shootTint = Color(white: 0.85)
            }

            let sound = starting ? SoundFX.reload : SoundFX.shot

            // No GIF available → fire the bullet + sound immediately, no pose.
            let poseFrames = starting ? ShootAsset.funnel : ShootAsset.frames
            guard !poseFrames.isEmpty else {
                siphonID += 1
                SoundFX.play(sound)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    if starting { FireStoker.shared.stoke() }
                    flowRail(toActive: new > 0)
                }
                return
            }

            shootEventID += 1   // remount the GIF so it replays from frame 0
            withAnimation(.easeIn(duration: 0.15)) { showShoot = true }
            // Fade the wing behind the gun (left when starting, right when
            // finishing) so the GIF doesn't visibly stack over the badge/icon.
            // Start: only bullets on the RIGHT, so just the right wing fades
            // (left counter stays). Finish: gun (right) + target (left) → both.
            withAnimation(.easeInOut(duration: 0.25)) {
                activeShooter = shooterOnLeft ? .right : .both
            }
            // Start sound (reload) fires immediately on prompt send — no delay.
            // Finish sound (shot) stays synced to the comet firing below.
            if starting { SoundFX.play(sound) }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.shootDelay))
                siphonID += 1        // FIRE — comet sweeps the rail...
                if !starting { SoundFX.play(sound) }  // ...in sync with the SFX.
                try? await Task.sleep(for: .milliseconds(200))
                withAnimation(.easeOut(duration: 0.3)) {
                    showShoot = false
                    activeShooter = nil   // bring the badge/icon back
                }
                // Comet lands ~0.55s later → river-flow the rail to its colour.
                try? await Task.sleep(for: .milliseconds(550))
                // Input comet sweeps left→RIGHT and reaches the fire here —
                // toss a log on so the right-wing flame flares for a beat.
                if starting { FireStoker.shared.stoke() }
                flowRail(toActive: new > 0)
            }
        }
        .onAppear { flowToActive = working > 0 }
    }

    /// Start the rail's "river" colour flow toward a new state. No-op if already
    /// in that state. Clock-driven so the moving fronts can flicker.
    private func flowRail(toActive: Bool) {
        guard toActive != flowToActive else { return }
        flowToActive = toActive
        flowStart = Date()
        // Run the clock just for the flow, then settle to a static stroke.
        railAnimating = true
        railFlowGen += 1
        let gen = railFlowGen
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.flowDuration + Self.sparkTail + 0.1))
            if gen == railFlowGen { railAnimating = false }
        }
    }

    /// The rail: a base colour (wallpaper-average when idle) with the active
    /// aqua overlay rivering in from the ends / receding to them. The moving
    /// fronts flash bright like lava with sparks.
    @ViewBuilder
    private func railView(_ shape: NotchOutlineShape) -> some View {
        // Magma palette — a layered molten vein: deep-red base, hot-orange body,
        // gold-white core, with a gold→red bloom + slow white-hot spots drifting
        // through it (the "alive"). The front + white sparks add the highlights.
        // Sourced from the shared `Magma` palette (the single source of truth);
        // the dock heat ramp re-bases its hot end on these same numbers.
        let idle = WallpaperColor.average.opacity(0.70)
        let deep = Magma.deep          // deep-red base
        let mid = Magma.body           // hot-orange body
        let core = Magma.core          // gold-white core
        let glowInner = Magma.gold     // gold bloom (tight)
        let glowOuter = Magma.ember    // deep red-orange (wide)
        let hot = Magma.white          // white-hot drifting spot
        let rs = StrokeStyle(lineWidth: 2.0, lineCap: .round)
        let duration = Self.flowDuration
        if railAnimating {
            // Flowing — drive the moving fronts at display rate for ~0.9s.
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
                let elapsed = ctx.date.timeIntervalSince(flowStart)
                let p = min(1.0, max(0.0, elapsed / duration))
                let half = CGFloat(p) * 0.5
                let leftTo = flowToActive ? half : (0.5 - half)
                let rightFrom = flowToActive ? (1 - half) : (0.5 + half)
                // Sparks run the WHOLE flow at full strength, then fade over the
                // tail — so they never blink out mid-merge at either end.
                let tailFade = elapsed <= duration
                    ? 1.0 : max(0.0, 1.0 - (elapsed - duration) / Self.sparkTail)
                ZStack {
                    shape.stroke(idle, style: rs)
                    // Active fill rivering from the ends as the layered molten
                    // vein, carrying the gold→red bloom.
                    moltenVein(shape, from: 0, to: leftTo, deep: deep, mid: mid, core: core,
                               glowInner: glowInner, glowOuter: glowOuter)
                    moltenVein(shape, from: rightFrom, to: 1, deep: deep, mid: mid, core: core,
                               glowInner: glowInner, glowOuter: glowOuter)
                    if p < 1 {
                        let flick = 0.55 + 0.45 * sin(ctx.date.timeIntervalSinceReferenceDate * 34)
                        railFront(shape, at: leftTo, flick: flick)
                        railFront(shape, at: rightFrom, flick: flick)
                    }
                    // Both fronts, both directions, full duration + tail. Drawn
                    // as Shapes (NOT a Canvas) so sparks on the rail's bottom
                    // edge — which sits a hair below the bar — aren't clipped.
                    if tailFade > 0.01 {
                        let sparkColor = hot
                        let bands = 4
                        ForEach(0 ..< bands, id: \.self) { band in
                            RailSparkLayer(outline: shape, flowToActive: flowToActive,
                                           elapsed: elapsed, duration: duration,
                                           band: band, bandCount: bands)
                                .stroke(sparkColor.opacity(tailFade * (Double(band) + 0.5) / Double(bands)),
                                        style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
                                .blendMode(.plusLighter)
                        }
                    }
                }
            }
        } else if flowToActive {
            // Settled but ACTIVE — the static layered molten vein + bloom. No
            // clock here: the travelling white comets now live on the crates.
            ZStack {
                shape.stroke(idle, style: rs)
                moltenVein(shape, from: 0, to: 1, deep: deep, mid: mid, core: core,
                           glowInner: glowInner, glowOuter: glowOuter)
            }
        } else {
            // Idle — pure gray base, no clock.
            shape.stroke(idle, style: rs)
        }
    }

    /// One run of the molten vein over a trim range: a deep-red base (carrying
    /// the bloom), a hot-orange body, and a thin gold-white core on top.
    @ViewBuilder
    private func moltenVein(_ shape: NotchOutlineShape, from: CGFloat, to: CGFloat,
                            deep: Color, mid: Color, core: Color,
                            glowInner: Color, glowOuter: Color) -> some View {
        if to > from {
            let seg = shape.trim(from: from, to: to)
            // MOLTEN, not neon: a wider deep-red base so the line's edges read as
            // cooling lava, a THINNER bright body so it doesn't flatten into a
            // uniform orange, and a brighter white-hot core for the hot peak — so
            // the eye sees tonal range (red → orange → white) instead of one hue.
            seg.stroke(deep, style: StrokeStyle(lineWidth: 4.2, lineCap: .round))
                .shadow(color: glowOuter.opacity(0.55), radius: 7)
                .shadow(color: glowInner.opacity(0.55), radius: 3)
            seg.stroke(mid, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            seg.stroke(core, style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
                .blendMode(.plusLighter)
                .opacity(1.0)
        }
    }

    /// A hot, flickering "lava" spark riding a river front.
    @ViewBuilder
    private func railFront(_ shape: NotchOutlineShape, at center: CGFloat, flick: Double) -> some View {
        let w: CGFloat = 0.018
        let from = max(0, center - w), to = min(1, center + w)
        if to > from {
            shape.trim(from: from, to: to)
                .stroke(Color(red: 1.0, green: 0.74, blue: 0.28),
                        style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
                .shadow(color: Color(red: 1.0, green: 0.45, blue: 0.10), radius: 4)
                .blendMode(.plusLighter)
                .opacity(flick)
            shape.trim(from: max(0, center - w * 0.4), to: min(1, center + w * 0.4))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
                .blendMode(.plusLighter)
                .opacity(flick)
        }
    }

}

/// One opacity band of the river-front sparks, drawn as a Shape so it does NOT
/// clip to the bar's frame — a Canvas would, and the rail's bottom edge sits a
/// hair below the bar, which is where the fronts spend most of the flow. The
/// caller layers several bands at matching opacities for a faded twinkle.
///
/// Sparks fly back-and-out (opposite each front's travel) on a fast sub-cycle.
/// Both fronts emit in both directions; only the geometry sample is clamped off
/// the degenerate path ends, so a front sitting at an end still sparks.
private struct RailSparkLayer: Shape {
    let outline: NotchOutlineShape
    let flowToActive: Bool
    let elapsed: Double
    let duration: Double
    let band: Int
    let bandCount: Int

    /// Where a front sits at flow-progress `p` (0…1). side 0 = the front growing
    /// from param 0; side 1 = the front growing from param 1.
    private func frontParam(side: Int, p: Double) -> CGFloat {
        let half = CGFloat(p) * 0.5
        return side == 0 ? (flowToActive ? half : 0.5 - half)
                         : (flowToActive ? 1 - half : 0.5 + half)
    }

    func path(in rect: CGRect) -> Path {
        let src = outline.path(in: rect)
        var out = Path()
        let cycle = 0.40          // spark lifetime — wider so emits are less frequent
        let perFront = 2          // fewer concurrent sparks (~2x bigger gaps between emits)
        let maxFly: CGFloat = 12  // how far a spark drifts from its birth point
        let len: CGFloat = 2.0    // tiny, thin streaks
        for side in 0 ..< 2 {
            // Param direction the front travels — sparks fly OPPOSITE it.
            let sign: CGFloat = (side == 0) ? (flowToActive ? 1 : -1)
                                            : (flowToActive ? -1 : 1)
            for i in 0 ..< perFront {
                // Each spark has a phase 0→1 over its life; staggered per slot
                // and offset between the two fronts so they don't pulse together.
                let phase = ((elapsed / cycle) + Double(i) / Double(perFront) + Double(side) * 0.5)
                    .truncatingRemainder(dividingBy: 1)
                let life = 1 - phase
                guard min(bandCount - 1, Int(life * Double(bandCount))) == band else { continue }
                // BIRTH-anchored: the spark was emitted `age` ago, where the
                // front WAS then — it then flies off that fixed point while the
                // front keeps advancing, so it detaches and trails away.
                let age = phase * cycle
                let birthElapsed = elapsed - age
                guard birthElapsed >= 0 else { continue }
                let pBirth = min(1.0, max(0.0, birthElapsed / duration))
                let cp = min(0.97, max(0.03, frontParam(side: side, p: pBirth)))
                let pt = railPointOn(src, at: cp)
                let back = railTangent(src, at: cp)
                let trail = CGVector(dx: -sign * back.dx, dy: -sign * back.dy)
                let fly = CGFloat(phase) * maxFly
                for sgn in [CGFloat(1), -1] {
                    let dir = rotateVec(trail, by: sgn * 0.7)
                    let base = CGPoint(x: pt.x + dir.dx * fly, y: pt.y + dir.dy * fly)
                    let tip = CGPoint(x: base.x + dir.dx * len, y: base.y + dir.dy * len)
                    out.move(to: base)
                    out.addLine(to: tip)
                }
            }
        }
        return out
    }
}

/// Pixel point on a path at normalized-arc-length `t`.
private func railPointOn(_ path: Path, at t: CGFloat) -> CGPoint {
    let eps: CGFloat = 0.0015
    let seg = path.trimmedPath(from: max(0, t - eps), to: min(1, t + eps))
    let r = seg.boundingRect
    return CGPoint(x: r.midX, y: r.midY)
}

/// Unit tangent (increasing-parameter direction) on a path at `t`.
private func railTangent(_ path: Path, at t: CGFloat) -> CGVector {
    let d: CGFloat = 0.004
    let a = railPointOn(path, at: max(0, t - d))
    let b = railPointOn(path, at: min(1, t + d))
    let dx = b.x - a.x, dy = b.y - a.y
    let m = max(0.0001, hypot(dx, dy))
    return CGVector(dx: dx / m, dy: dy / m)
}

private func rotateVec(_ v: CGVector, by a: CGFloat) -> CGVector {
    let c = cos(a), s = sin(a)
    return CGVector(dx: v.dx * c - v.dy * s, dy: v.dx * s + v.dy * c)
}

/// Plays the white-keyed GIF frames on their own clock via `TimelineView`.
/// Each frame is a CGImage with near-white pixels already made transparent.
/// Plays a pre-rendered frame sequence on a `DecorativeTimeline` — slow fps, and
/// FREEZES to a static frame when the screens sleep / Low Power / Reduce Motion.
/// The cheap NATIVE replacement for a WKWebView CSS loop (no browser engine, no
/// always-on display-rate clock). Loops over `frames.count / fps` seconds.
struct FrameSequence: View {
    let frames: [ShootAsset.Frame]
    var fps: Double = 15

    var body: some View {
        if frames.isEmpty {
            Color.clear
        } else {
            DecorativeTimeline(fps: fps) { ctx in
                let total = Double(frames.count) / max(1, fps)
                let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: total)
                let idx = min(frames.count - 1, max(0, Int(t * fps)))
                Image(decorative: frames[idx].image, scale: 1)
                    .resizable()
                    .interpolation(.high)
            }
        }
    }
}

struct KeyedGIFView: View {
    let frames: [ShootAsset.Frame]
    /// When set, ignore the GIF's embedded per-frame delays and play every
    /// frame for an equal `1/fps` slice. Some GIFs bake in slow delays (e.g.
    /// `smoke.gif` is 106 frames stamped at 200ms = 5fps) that step choppily
    /// even though there are plenty of frames — overriding the rate makes the
    /// motion flow the way it was authored.
    var fps: Double? = nil
    /// Loop forever (default) or play through once and hold the last frame.
    var loop: Bool = true
    /// Captured when this instance is created. Because the caller gives the
    /// view a fresh `.id` per shot, every appearance starts at frame 0.
    @State private var start = Date()

    var body: some View {
        let spf = fps.map { 1.0 / max(0.0001, $0) }
        let total = spf.map { $0 * Double(frames.count) }
            ?? max(0.0001, frames.reduce(0) { $0 + $1.duration })
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(start))
            let t = loop ? elapsed.truncatingRemainder(dividingBy: total)
                         : min(elapsed, total - 0.0001)
            Image(decorative: frame(at: t, spf: spf), scale: 1.0)
                .resizable()
                .interpolation(.high)
        }
        .onAppear { start = Date() }
    }

    private func frame(at t: Double, spf: Double?) -> CGImage {
        if let spf, spf > 0 {
            let idx = min(frames.count - 1, max(0, Int(t / spf)))
            return frames[idx].image
        }
        var acc = 0.0
        for f in frames {
            acc += f.duration
            if t < acc { return f.image }
        }
        return frames.last!.image
    }
}

/// Resolves runtime art shipped INSIDE the app bundle — `Resources/Animations`
/// for GIF/PNG/Lottie, `Resources/sounds` for audio. Everything used to be read
/// from the user's `~/Downloads`, which broke on any other machine; bundling
/// makes the app portable and self-contained.
enum BundledAsset {
    static func url(_ filename: String, in subdir: String = "Animations") -> URL? {
        let ns = filename as NSString
        return Bundle.main.url(forResource: ns.deletingPathExtension,
                               withExtension: ns.pathExtension,
                               subdirectory: subdir)
    }
}

/// Loads the gun / finish / start GIFs and rail art from the app bundle
/// (`Resources/Animations`), decodes + downscales the frames, and keys out the
/// white background where needed so they read as transparent cut-outs. Cached
/// once. Bundled (not `~/Downloads`) so the app ships self-contained.
enum ShootAsset {
    struct Frame { let image: CGImage; let duration: Double }

    static let frames: [Frame] = load()

    /// Left-wing shooter (work starts). TEMP: funnel instead of bullets.
    static let funnel: [Frame] = loadNamed("start-funnel.gif")
    /// Left-wing target when work finishes (gun fires right→left).
    static let target: [Frame] = loadNamed("finish-target.gif")
    /// Right-wing projectiles while work STARTS (funnel pours on the left).
    static let bullets: [Frame] = loadNamed("start-bullets.gif")
    /// Muzzle smoke for the dock cannon — a gray wisp on a WHITE page. We drop
    /// the page with a luminance key and tint the wisp warm so it reads as a
    /// translucent plume over the near-black drawer (see `loadKeyedLuma`).
    static let smoke: [Frame] = loadKeyedLuma("muzzle-smoke.gif")
    /// Dirigibles/blimps that drift across the upper band.
    static let airship: [Frame] = loadStatic("airship-1.png", pixelHeight: 256)
    static let airship1: [Frame] = loadStatic("airship-2.png", pixelHeight: 256)
    /// Wooden crate box (SVG) — replaces the drawn crate, still hung by OUR
    /// trolley+cable crane. Recolour variants come later.
    static let crateImage: CGImage? = loadStatic("crate.png", pixelHeight: 128).first?.image
    /// Shipping containers that ship WITH their own crane rig baked in (hook +
    /// cables + posts); they ride solo, no extra crane from us.
    static let containerImages: [CGImage] = ["container-1.png", "container-2.png"]
        .compactMap { loadNamed($0, keyed: false).first?.image }
    /// Forge-railway cargo that rides the rail SOLO (own footprint, no harness):
    /// just the molten-metal ladle now (barrels/oil moved to chained loads).
    static let railProps: [CGImage] = ["molten-ladle.png"]
        .compactMap { loadNamed($0, keyed: false).first?.image }
    /// Boxes for chained, HARNESSED loads.
    static let mineCartImage: CGImage? = loadStatic("mine-cart.png", pixelHeight: 128).first?.image
    static let oilImage: CGImage? = loadStatic("oil-drum.png", pixelHeight: 128).first?.image       // oil group
    static let barrel1Image: CGImage? = loadStatic("barrel-metal.png", pixelHeight: 128).first?.image // oil group
    static let barrelImage: CGImage? = loadStatic("barrel-wood.png", pixelHeight: 128).first?.image  // wooden barrel
    private static func load() -> [Frame] {
        guard let url = BundledAsset.url("gun-fire.gif") else { return [] }
        return frames(at: url)
    }

    /// Load a specific GIF/PNG by bundled filename, optionally keying out its
    /// white background.
    static func loadNamed(_ filename: String, keyed: Bool = true) -> [Frame] {
        guard let url = BundledAsset.url(filename) else { return [] }
        return frames(at: url, keyed: keyed)
    }

    /// Rasterise a single bundled static image into one frame, `pixelHeight` tall
    /// at the source aspect — crisp enough to display well above its on-screen
    /// size. The offscreen bitmap starts transparent, so the art's own alpha is
    /// preserved (no keying). Returns [] if the file is missing or can't be drawn.
    static func loadStatic(_ filename: String, pixelHeight: Int = 480) -> [Frame] {
        guard let url = BundledAsset.url(filename),
              let img = NSImage(contentsOf: url),
              img.size.width > 0, img.size.height > 0 else { return [] }
        let aspect = img.size.width / img.size.height
        let pxH = max(1, pixelHeight)
        let pxW = max(1, Int((Double(pxH) * aspect).rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return [] }
        rep.size = NSSize(width: pxW, height: pxH)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: pxW, height: pxH),
                 from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = rep.cgImage else { return [] }
        return [Frame(image: cg, duration: 0.1)]
    }

    /// Decode each frame DOWNSCALED to `maxPixel` on its longest side via an
    /// ImageIO thumbnail (ImageIO decodes at reduced scale — it never materialises
    /// the full bitmap), optionally keying out white. These GIFs are authored at
    /// 640² yet render ≤30 pt, so 128 px is 2×+ the on-screen size while cutting
    /// RAM ~25× (e.g. 72 MB → ~3 MB). Per-frame timing is read separately, so the
    /// cadence is unchanged.
    private static func frames(at url: URL, keyed: Bool = true, maxPixel: Int = 128) -> [Frame] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        let n = CGImageSourceGetCount(src)
        let thumbOpts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        var out: [Frame] = []
        for i in 0 ..< n {
            // Drain the full-size decode intermediate each iteration so it never
            // piles up (thumbnail-from-image decodes the full frame transiently).
            autoreleasepool {
                guard let cg = CGImageSourceCreateThumbnailAtIndex(src, i, thumbOpts) else { return }
                guard let img = keyed ? keyWhite(cg) : cg else { return }
                out.append(Frame(image: img, duration: frameDuration(src, i)))
            }
        }
        return out
    }

    /// Downscale a CGImage so its longest side is ≤ `maxPixel`, preserving aspect
    /// + alpha. Caps the resident size of keyed/cropped frames (used by the smoke
    /// loader, which keys + crops at source res then shrinks the small result).
    private static func downscale(_ cg: CGImage, maxPixel: Int) -> CGImage {
        let w = cg.width, h = cg.height
        let longest = max(w, h)
        guard longest > maxPixel, longest > 0 else { return cg }
        let scale = Double(maxPixel) / Double(longest)
        let nw = max(1, Int((Double(w) * scale).rounded()))
        let nh = max(1, Int((Double(h) * scale).rounded()))
        guard let ctx = CGContext(
            data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cg }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage() ?? cg
    }

    private static func frameDuration(_ src: CGImageSource, _ i: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else { return 0.1 }
        let d = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        return d < 0.011 ? 0.1 : d
    }

    /// Redraw a frame into RGBA and zero the alpha of near-white pixels.
    private static func keyWhite(_ cg: CGImage, threshold: UInt8 = 240) -> CGImage? {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        let bytesPerRow = w * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * h)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &data, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var i = 0
        while i < data.count {
            if data[i] >= threshold, data[i + 1] >= threshold, data[i + 2] >= threshold {
                data[i] = 0; data[i + 1] = 0; data[i + 2] = 0; data[i + 3] = 0
            }
            i += 4
        }
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow, space: cs,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Load a GIF of dark/gray art on a WHITE page (the muzzle-smoke wisp) and
    /// luminance-key every frame, then crop them all to the SAME union bounding
    /// box of the wisp. A shared crop is what keeps the plume from jittering —
    /// per-frame boxes would jump as the curls move. The wide letterboxed source
    /// (mostly white) collapses to a tight, near-square plume.
    static func loadKeyedLuma(_ filename: String) -> [Frame] {
        guard let url = BundledAsset.url(filename),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        let n = CGImageSourceGetCount(src)
        var keyed: [(img: CGImage, dur: Double, box: CGRect)] = []
        for i in 0 ..< n {
            autoreleasepool {
                guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil),
                      let (img, box) = keyLuma(cg) else { return }
                keyed.append((img, frameDuration(src, i), box))
            }
        }
        let union = keyed.reduce(CGRect?.none) { acc, item in
            acc.map { $0.union(item.box) } ?? item.box
        }
        return keyed.map { item in
            let cropped = union.flatMap { item.img.cropping(to: $0) } ?? item.img
            // Key + crop at source res for clean edges, THEN downscale the small
            // result — the wisp renders at ~77 pt, so ~200 px stays crisp at a
            // fraction of the RAM (~20 MB → ~3 MB across the 25 frames).
            return Frame(image: downscale(cropped, maxPixel: 200), duration: item.dur)
        }
    }

    /// Redraw a frame into RGBA, set alpha from darkness (alpha rises as the
    /// pixel darkens — a white page goes fully transparent), and paint the
    /// survivor a soft warm-smoke tint so it reads as a translucent plume over
    /// the near-black drawer instead of a flat gray decal. Premultiplied to match
    /// the context. Returns the keyed image plus the bbox of its visible pixels.
    private static func keyLuma(
        _ cg: CGImage,
        tint: (r: Double, g: Double, b: Double) = (220, 213, 203),
        floor: Double = 200,
        slope: Double = 2.6,
        inset: Int = 6
    ) -> (image: CGImage, box: CGRect)? {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        let bytesPerRow = w * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * h)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &data, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var minX = w, minY = h, maxX = -1, maxY = -1
        var idx = 0
        for y in 0 ..< h {
            for x in 0 ..< w {
                let lum = 0.21 * Double(data[idx]) + 0.72 * Double(data[idx + 1])
                    + 0.07 * Double(data[idx + 2])
                // Hard floor: anything brighter than `floor` is page, not smoke —
                // force it fully transparent. Only the darker wisp ramps in. Without
                // the floor the near-white field (250–255) still earned alpha ~5–8,
                // a faint warm wash that read as a rectangle behind the plume.
                let a = lum >= floor ? 0.0 : min(255.0, (floor - lum) * slope)
                let af = a / 255.0
                data[idx] = UInt8(tint.r * af)
                data[idx + 1] = UInt8(tint.g * af)
                data[idx + 2] = UInt8(tint.b * af)
                data[idx + 3] = UInt8(a)
                // Track the wisp's bbox ONLY over the inset interior. This GIF
                // carries a 1px dark border around the whole frame; left in, it
                // would force the crop out to the full letterbox. The inset skips
                // it (the wisp itself sits well inside), so the crop is tight.
                if a >= 24, x >= inset, x < w - inset, y >= inset, y < h - inset {
                    if x < minX { minX = x }; if x > maxX { maxX = x }
                    if y < minY { minY = y }; if y > maxY { maxY = y }
                }
                idx += 4
            }
        }
        guard let provider = CGDataProvider(data: Data(data) as CFData),
              let img = CGImage(
                width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: bytesPerRow, space: cs,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        let box = maxX >= minX
            ? CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            : CGRect(x: 0, y: 0, width: w, height: h)
        return (img, box)
    }
}

/// While work is in progress, small freight crates occasionally ride the
/// bottom of the rail from one wing to the other — an "industrial conveyor"
/// that keeps the line alive without being noisy. Spawns are sparse + random.
struct RailFreight: View {
    let working: Int
    let shape: NotchOutlineShape

    @State private var crates: [Crate] = []
    @State private var spawner: Task<Void, Never>?

    struct Crate: Identifiable {
        let id = UUID()
        let leftToRight: Bool
        let tint: Color
        let duration: Double
        let boxes: Int          // >1 = a chained load that moves as one unit
        let style: CrateStyle
        /// Non-nil → a solo shipping container (its own crane); the value indexes
        /// `ShootAsset.containerImages`. Nil → a crate chain on our crane.
        var containerIndex: Int? = nil
        /// Non-nil → a solo forge-railway prop, indexing `ShootAsset.railProps`
        /// (the molten ladle).
        var propIndex: Int? = nil
        /// Per-box image for a chained, harnessed load (carts / barrels / oil).
        /// Empty → the default wooden crate (`crate.png`). Length == `boxes`.
        var boxImages: [CGImage] = []
        /// Box footprint for the chain, how far the boxes hang below the harness
        /// (extra cable), and the spacing between boxes. Defaults suit the crate.
        var boxSize: CGFloat = 9
        var boxDrop: CGFloat = 0
        var boxGap: CGFloat = 1.0
    }

    /// Visual crate variants.
    enum CrateStyle: CaseIterable {
        case plain    // single lid seam
        case vSplit   // lid + centre divider (two panels)
        case slats    // horizontal planks
        case wide     // wider container, panelled
        case xbrace   // diagonal cross-brace

        var width: CGFloat {
            switch self {
            case .wide:   return 28   // ~3 standard crates wide
            case .xbrace: return 11
            default:      return 9
            }
        }
    }

    /// Muted, natural cargo colours — no neon / garish hues.
    private static let tints: [Color] = [
        Color(red: 0.86, green: 0.55, blue: 0.20),   // amber
        Color(red: 0.80, green: 0.32, blue: 0.22),   // rust red
        Color(red: 0.48, green: 0.56, blue: 0.62),   // steel
        Color(red: 0.45, green: 0.55, blue: 0.33),   // olive green
        Color(red: 0.36, green: 0.46, blue: 0.58),   // slate blue
        Color(red: 0.56, green: 0.41, blue: 0.27),   // wood brown
        Color(red: 0.78, green: 0.66, blue: 0.30),   // mustard
        Color(red: 0.32, green: 0.54, blue: 0.50),   // muted teal
    ]

    /// Styles for crates in a multi-box chain — excludes `.wide`, which only
    /// ever travels as a lone container.
    private static func randomStyle() -> CrateStyle {
        [.plain, .vSplit, .slats, .xbrace].randomElement() ?? .plain
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(crates) { crate in
                    CrateView(crate: crate, shape: shape, size: geo.size) {
                        crates.removeAll { $0.id == crate.id }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        // Density tracks the ACTIVE-session count: restart the spawner whenever
        // it changes so the cadence + load size re-scale. Fewer sessions working
        // → fewer, smaller loads; none working → nothing rides the rail.
        .onChange(of: working) { _, w in
            stopSpawning()
            if w > 0 { startSpawning(working: w) }
        }
        .onAppear { if working > 0 { startSpawning(working: working) } }
        .onDisappear { stopSpawning() }
    }

    private func startSpawning(working w: Int) {
        guard spawner == nil else { return }
        let intensity = min(w, 6)            // cap so a big fleet never floods the rail
        spawner = Task { @MainActor in
            while !Task.isCancelled {
                // Cadence scales with the active-session count — sparse with one
                // session, busier as more agents work.
                let lo = max(6.5, 13.0 - 1.0 * Double(intensity))
                let hi = max(12.0, 22.0 - 1.4 * Double(intensity))
                try? await Task.sleep(for: .seconds(Double.random(in: lo ... hi)))
                if Task.isCancelled { return }
                let dir = Bool.random()
                let dur = Double.random(in: 3.6 ... 5.4)        // slower, smoother glide
                let tint = Self.tints.randomElement() ?? .orange
                func container() -> Crate {
                    // Solo loads: the molten ladle, or a shipping container.
                    let props = ShootAsset.railProps
                    if !props.isEmpty, Int.random(in: 0 ..< 100) < 55 {
                        return Crate(leftToRight: dir, tint: tint, duration: dur,
                                     boxes: 1, style: .wide, propIndex: Int.random(in: 0 ..< props.count))
                    }
                    let idx = ShootAsset.containerImages.isEmpty
                        ? nil : Int.random(in: 0 ..< ShootAsset.containerImages.count)
                    return Crate(leftToRight: dir, tint: tint, duration: dur,
                                 boxes: 1, style: .wide, containerIndex: idx)
                }
                // A harnessed chain whose boxes are `img` (or a mix), n boxes long.
                func chain(_ imgs: [CGImage], size: CGFloat, drop: CGFloat, gap: CGFloat = 1.0) -> Crate {
                    Crate(leftToRight: dir, tint: tint, duration: dur, boxes: imgs.count,
                          style: .plain, boxImages: imgs, boxSize: size, boxDrop: drop, boxGap: gap)
                }

                // ONE load per cycle — no loose trains.
                switch Int.random(in: 0 ..< 100) {
                case 0 ..< 30:
                    // Crate chain — 2-3 common, 4 RARE.
                    let n = Int.random(in: 0 ..< 100) < 15 ? 4 : Int.random(in: 2 ... 3)
                    crates.append(Crate(leftToRight: dir, tint: tint, duration: dur,
                                        boxes: n, style: Self.randomStyle()))
                case 30 ..< 48:
                    // Mine-cart chain (2 … 3).
                    if let cart = ShootAsset.mineCartImage {
                        let n = Int.random(in: 2 ... 3)
                        crates.append(chain(Array(repeating: cart, count: n), size: 13, drop: 0))
                    }
                case 48 ..< 66:
                    // Oil group — oil drums + generic barrels mixed (1 … 3).
                    let pool = [ShootAsset.oilImage, ShootAsset.barrel1Image].compactMap { $0 }
                    if !pool.isEmpty {
                        let n = Int.random(in: 1 ... 3)
                        // 15% bigger, tighter spacing, slightly shorter harness.
                        crates.append(chain((0 ..< n).map { _ in pool.randomElement()! },
                                            size: 11.5, drop: 0.5, gap: 0.2))
                    }
                case 66 ..< 84:
                    // Wooden-barrel chain (2 … 3).
                    if let wood = ShootAsset.barrelImage {
                        let n = Int.random(in: 2 ... 3)
                        crates.append(chain(Array(repeating: wood, count: n), size: 10, drop: 1))
                    }
                default:
                    crates.append(container())
                }
            }
        }
    }

    private func stopSpawning() {
        spawner?.cancel()
        spawner = nil
    }
}

/// One crate suspended BELOW the bottom rail (cable-car style) — a trolley nub
/// clamps the line, a cable hangs down, and the crate dangles into the visible
/// strip under the bar. Slides wing-to-wing.
private struct CrateView: View {
    let crate: RailFreight.Crate
    let shape: NotchOutlineShape
    let size: CGSize
    let onDone: () -> Void

    @State private var start = Date()

    private let hookD: CGFloat = 2.5
    private let cableLen: CGFloat = 3
    private let containerSize: CGFloat = 24  // solo container, own crane baked in

    var body: some View {
        // Bottom rail runs ~0.30 (right end) … 0.70 (left end) in path-param.
        let tStart: CGFloat = crate.leftToRight ? 0.70 : 0.30
        let tEnd: CGFloat = crate.leftToRight ? 0.30 : 0.70
        let isContainer = crate.containerIndex != nil && !ShootAsset.containerImages.isEmpty
        let isProp = crate.propIndex != nil && !ShootAsset.railProps.isEmpty
        let propSize: CGFloat = 22
        // container1 (index 0) renders 25% smaller than container2.
        let cSize: CGFloat = crate.containerIndex == 0 ? containerSize * 0.75 : containerSize
        let boxW: CGFloat = crate.boxSize
        let unitH = hookD + cableLen + crate.boxDrop + crate.boxSize
        let n = max(1, crate.boxes)
        let unitW = isContainer ? cSize
                  : isProp ? propSize
                  : CGFloat(n) * boxW + CGFloat(n - 1) * crate.boxGap

        // A real clock drives progress so the body re-evaluates each frame —
        // letting the triangular fade (0 → 1 → 0) actually peak in the middle.
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
            let p = min(1, max(0, ctx.date.timeIntervalSince(start) / crate.duration))
            let t = tStart + (tEnd - tStart) * CGFloat(p)
            let pt = railPoint(t)
            let fade = max(0, min(1, min(CGFloat(p) / 0.12, (1 - CGFloat(p)) / 0.12)))

            ZStack {
                // A proper steel RAIL segment travelling with the load — a metal
                // track with a bright rail-head — so the trolley reads as riding
                // a rail rather than dangling from a glow.
                railSegment(at: pt, width: unitW, fade: Double(fade))

                if isProp {
                    // A solo forge-railway prop (boulder / mine-cart / molten
                    // ladle) riding the rail — its own footprint, hung just under
                    // the line like the container.
                    Image(decorative: ShootAsset.railProps[crate.propIndex!], scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: propSize, height: propSize)
                        // molten.png points RIGHT by default — mirror it when the
                        // load is travelling left so it faces its direction.
                        .scaleEffect(x: crate.leftToRight ? 1 : -1, y: 1)
                        .shadow(color: .black.opacity(0.45), radius: 1, y: 0.5)
                        .opacity(Double(fade))
                        .position(x: pt.x, y: pt.y + propSize / 2)
                } else if isContainer {
                    // Shipping container with its OWN crane baked in: the image's
                    // built-in hook sits on the rail, the box hangs below. No
                    // trolley/cable from us.
                    Image(decorative: ShootAsset.containerImages[crate.containerIndex!], scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: cSize, height: cSize)
                        .shadow(color: .black.opacity(0.45), radius: 1, y: 0.5)
                        .opacity(Double(fade))
                        .position(x: pt.x, y: pt.y + cSize / 2)
                } else {
                    // Crate / mine-cart chain hung from OUR crane (trolley + cable
                    // per box).
                    ZStack(alignment: .top) {
                        // Beam linking the trolleys of a chained load.
                        if n > 1 {
                            Rectangle().fill(Color(white: 0.5))
                                .frame(width: unitW - boxW, height: 0.8)
                                .offset(y: hookD / 2 - 0.4)
                        }
                        HStack(spacing: crate.boxGap) {
                            ForEach(0 ..< n, id: \.self) { i in chainColumn(i) }
                        }
                    }
                    .frame(width: unitW, height: unitH)
                    .opacity(Double(fade))
                    // Hook centred on the rail; everything else hangs below it.
                    .position(x: pt.x, y: pt.y + unitH / 2 - hookD / 2)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .onAppear {
            start = Date()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(crate.duration + 0.1))
                onDone()
            }
        }
    }

    /// A proper STEEL RAIL segment riding the status line above the load and
    /// travelling with it: a dark steel web with a bright rail-head (the running
    /// surface) and a faint warm under-glow tying it to the magma line. The
    /// trolley/hook rides on this, so the cargo reads as on a track, not a glow.
    private func railSegment(at pt: CGPoint, width: CGFloat, fade: Double) -> some View {
        let w = width + 12
        return ZStack {
            // Warm under-glow — keeps the magma read.
            Capsule().fill(Magma.body)
                .frame(width: w, height: 2)
                .blur(radius: 2.5)
                .opacity(0.45)
            // Rail web (darker steel base).
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.50), Color(white: 0.26)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: w, height: 3.2)
            // Rail head — the bright running surface on top.
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.66)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: w, height: 1.3)
                .offset(y: -0.95)
        }
        .opacity(fade)
        .shadow(color: .black.opacity(0.4), radius: 1, y: 0.6)
        .position(x: pt.x, y: pt.y)
        .allowsHitTesting(false)
    }

    /// One harness column: trolley + cable + the box for chain index `i`. The
    /// box image comes from `crate.boxImages` (carts / barrels / oil), falling
    /// back to the wooden crate; `boxDrop` adds cable so a box hangs lower.
    private func chainColumn(_ i: Int) -> some View {
        let img = i < crate.boxImages.count ? crate.boxImages[i] : ShootAsset.crateImage
        return VStack(spacing: 0) {
            Circle().fill(Color(white: 0.55)).frame(width: hookD, height: hookD)
            Rectangle().fill(Color(white: 0.45)).frame(width: 0.8, height: cableLen + crate.boxDrop)
            Group {
                if let img {
                    Image(decorative: img, scale: 1).resizable().interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 1.4).fill(crate.tint)
                }
            }
            .frame(width: crate.boxSize, height: crate.boxSize)
            .shadow(color: .black.opacity(0.45), radius: 1, y: 0.5)
        }
    }

    private func railPoint(_ t: CGFloat) -> CGPoint {
        let path = shape.path(in: CGRect(origin: .zero, size: size))
        let eps: CGFloat = 0.0015
        let seg = path.trimmedPath(from: max(0, t - eps), to: min(1, t + eps))
        let r = seg.boundingRect
        return CGPoint(x: r.midX, y: r.midY)
    }
}

/// While work is active, an airplane occasionally drifts across the upper band
/// of the status line — a rarer, lighter counterpart to the freight crates.
/// Spawns are sparse + random; only one plane is ever in the air at a time-ish,
/// and the GIFs are picked at random (the square jet, or the slim contrail one).
struct RailAircraft: View {
    let working: Int
    let shape: NotchOutlineShape

    @State private var planes: [Plane] = []
    @State private var spawner: Task<Void, Never>?

    struct Plane: Identifiable {
        let id = UUID()
        let leftToRight: Bool
        let frames: [ShootAsset.Frame]
        let height: CGFloat
        /// Which way the source art's nose points — so it can be mirrored to
        /// lead in the travel direction. The two GIFs face opposite ways.
        let facesLeft: Bool
        let duration: Double
    }

    /// One GIF/SVG + the on-screen height that reads in the crate strip + a
    /// mirror flag. `facesLeft` is empirical: both source arts face the same way,
    /// so both share a value — flip a plane's flag if it ever flies tail-first.
    private static var catalog: [(frames: [ShootAsset.Frame], height: CGFloat, facesLeft: Bool)] {
        [
            (ShootAsset.airship, 30, false),    // dirigible — reversed
            (ShootAsset.airship1, 30, false),   // second blimp variant
        ].filter { !$0.frames.isEmpty }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(planes) { plane in
                    AircraftView(plane: plane, shape: shape, size: geo.size) {
                        planes.removeAll { $0.id == plane.id }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        // Blimps only fly once at least THREE agents are running; cadence still
        // eases with the count above that.
        .onChange(of: working) { _, w in
            stopSpawning()
            if w >= 3 { startSpawning(working: w) }
        }
        .onAppear { if working >= 3 { startSpawning(working: working) } }
        .onDisappear { stopSpawning() }
    }

    private func startSpawning(working w: Int) {
        guard spawner == nil else { return }
        let catalog = Self.catalog
        guard !catalog.isEmpty else { return }
        let intensity = min(w, 6)
        spawner = Task { @MainActor in
            while !Task.isCancelled {
                // Planes stay a RARE flourish; their cadence still eases with the
                // active-session count (very rare with one session).
                let lo = max(10.0, 26.0 - 2.6 * Double(intensity))
                let hi = max(20.0, 46.0 - 3.4 * Double(intensity))
                try? await Task.sleep(for: .seconds(Double.random(in: lo ... hi)))
                if Task.isCancelled { return }
                let pick = catalog.randomElement()!
                planes.append(Plane(
                    leftToRight: Bool.random(),
                    frames: pick.frames,
                    height: pick.height,
                    facesLeft: pick.facesLeft,
                    duration: Double.random(in: 3.6 ... 5.4)   // matches the crates
                ))
            }
        }
    }

    private func stopSpawning() {
        spawner?.cancel()
        spawner = nil
    }
}

/// One airplane gliding the same bottom-rail path the crates ride — tucked just
/// below the status line (clear of the physical camera notch), wing-to-wing, at
/// crate speed and with the crates' fade. Each GIF declares its native nose
/// direction (`facesLeft`) and is mirrored as needed to fly nose-first.
private struct AircraftView: View {
    let plane: RailAircraft.Plane
    let shape: NotchOutlineShape
    let size: CGSize
    let onDone: () -> Void

    @State private var start = Date()

    var body: some View {
        // Same rail span the crates use: 0.70 (left end) … 0.30 (right end).
        let tStart: CGFloat = plane.leftToRight ? 0.70 : 0.30
        let tEnd: CGFloat = plane.leftToRight ? 0.30 : 0.70
        let h = plane.height
        let img = plane.frames.first?.image
        let aspect = img.map { CGFloat($0.width) / CGFloat(max(1, $0.height)) } ?? 1
        let w = h * aspect

        return TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
            let p = min(1, max(0, ctx.date.timeIntervalSince(start) / plane.duration))
            let t = tStart + (tEnd - tStart) * CGFloat(p)
            let pt = railPoint(t)
            // Same trapezoidal fade as the crates (in over 12%, out over 12%).
            let fade = max(0, min(1, min(CGFloat(p) / 0.12, (1 - CGFloat(p)) / 0.12)))

            ZStack {
                KeyedGIFView(frames: plane.frames)
                    .frame(width: w, height: h)
                    // Mirror only when the travel direction fights the native
                    // nose, so the plane always flies nose-first.
                    .scaleEffect(x: (plane.leftToRight == plane.facesLeft) ? -1 : 1, y: 1)
                    .opacity(Double(fade))
                    // Tuck below the rail — a bit lower so it clears the border.
                    .position(x: pt.x, y: pt.y + h / 2 + 6)
            }
            .frame(width: size.width, height: size.height)
        }
        .onAppear {
            start = Date()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(plane.duration + 0.1))
                onDone()
            }
        }
    }

    private func railPoint(_ t: CGFloat) -> CGPoint {
        let path = shape.path(in: CGRect(origin: .zero, size: size))
        let eps: CGFloat = 0.0015
        let seg = path.trimmedPath(from: max(0, t - eps), to: min(1, t + eps))
        let r = seg.boundingRect
        return CGPoint(x: r.midX, y: r.midY)
    }
}

/// A short comet-segment that slides along the notch outline from `start` to
/// `end` (path-fractions) as `progress` goes 0→1. `animatableData` lets
/// SwiftUI tween `progress`, so the segment travels smoothly.
struct TravelingComet: Shape {
    var progress: CGFloat
    var start: CGFloat
    var end: CGFloat
    var halfWidth: CGFloat = 0.045
    var topRadius: CGFloat = 6
    var bottomRadius: CGFloat = 10
    var bottomExtend: CGFloat = 1.5

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = start + (end - start) * progress
        let from = max(0, center - halfWidth)
        let to = min(1, center + halfWidth)
        let full = NotchOutlineShape(topRadius: topRadius,
                                     bottomRadius: bottomRadius,
                                     bottomExtend: bottomExtend).path(in: rect)
        return full.trimmedPath(from: from, to: to)
    }
}

/// One-shot siphon comet sweeping the WHOLE outline. Built from concentric
/// segments centred on the same travelling point — wide+faint out to
/// narrow+bright — stacked additively (`plusLighter`) so they sum into a
/// SMOOTH bell that fades from a hot core to transparent ends (a gradient
/// along the path, no rough edges). Re-runs whenever `trigger` changes, then
/// fades. Invisible at rest.
struct SiphonDroplet: View {
    let trigger: Int
    let start: CGFloat
    let end: CGFloat
    let color: Color
    let outline: NotchOutlineShape

    @State private var progress: CGFloat = 1
    @State private var visible = false

    /// (halfWidth along path, opacity, stroke thickness). Many closely-spaced
    /// rings → the summed profile is smooth rather than stepped.
    private static let layers: [(hw: CGFloat, op: Double, lw: CGFloat)] = [
        (0.150, 0.06, 4.2),
        (0.120, 0.09, 3.8),
        (0.094, 0.13, 3.4),
        (0.072, 0.18, 3.0),
        (0.053, 0.25, 2.7),
        (0.037, 0.35, 2.4),
        (0.024, 0.50, 2.2),
        (0.014, 0.70, 2.0),
        (0.007, 1.00, 1.8),
    ]

    private func comet(_ hw: CGFloat) -> TravelingComet {
        TravelingComet(progress: progress, start: start, end: end, halfWidth: hw,
                       topRadius: outline.topRadius,
                       bottomRadius: outline.bottomRadius,
                       bottomExtend: outline.bottomExtend)
    }

    var body: some View {
        ZStack {
            ForEach(Array(Self.layers.enumerated()), id: \.offset) { _, l in
                comet(l.hw)
                    .stroke(color.opacity(l.op),
                            style: StrokeStyle(lineWidth: l.lw, lineCap: .round))
                    .blendMode(.plusLighter)
            }
            // Bright white-hot core — a touch more flash so it's easy to spot.
            comet(0.006)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .blendMode(.plusLighter)
        }
        // Soft coloured halo around the comet for extra pop.
        .shadow(color: color.opacity(visible ? 0.9 : 0), radius: 5)
        .opacity(visible ? 1 : 0)
        .onChange(of: trigger) { _, newValue in
            guard newValue > 0 else { return }
            progress = 0
            visible = true
            withAnimation(.easeInOut(duration: 0.9)) { progress = 1 }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(920))
                withAnimation(.easeOut(duration: 0.25)) { visible = false }
            }
        }
    }
}

/// White-hot sparks thrown off the siphon comet as it flies — so the bullet
/// reads like a lit fuse igniting the far wing. Runs its own brief clock that
/// mirrors the comet's eased sweep (the comet uses an implicit animation, so its
/// in-flight position isn't observable; we re-derive it here). Sparks brighten
/// as the comet nears its target.
struct CometSparks: View {
    let trigger: Int
    let start: CGFloat
    let end: CGFloat
    let outline: NotchOutlineShape

    @State private var fireTime: Date? = nil
    private static let dur: Double = 0.9

    var body: some View {
        Group {
            if let ft = fireTime {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
                    let elapsed = ctx.date.timeIntervalSince(ft)
                    let raw = min(1.0, max(0.0, elapsed / Self.dur))
                    let eased = raw * raw * (3 - 2 * raw)        // smoothstep ≈ easeInOut
                    let param = start + (end - start) * CGFloat(eased)
                    let sign: CGFloat = end >= start ? 1 : -1
                    let intensity = 0.35 + 0.65 * eased          // hotter near the target
                    let spark = Color(red: 1.0, green: 0.96, blue: 0.86)
                    let bands = 3
                    ZStack {
                        ForEach(0 ..< bands, id: \.self) { band in
                            CometSparkLayer(outline: outline, param: param, sign: sign,
                                            t: ctx.date.timeIntervalSinceReferenceDate,
                                            band: band, bandCount: bands)
                                .stroke(spark.opacity(intensity * (Double(band) + 0.5) / Double(bands)),
                                        style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
                                .blendMode(.plusLighter)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .onChange(of: trigger) { _, v in
            guard v > 0 else { return }
            fireTime = Date()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.dur + 0.2))
                fireTime = nil
            }
        }
    }
}

/// One opacity band of the comet's spark spray — short white-hot streaks thrown
/// back-and-out from the comet's current rail position. A Shape (not a Canvas)
/// so it never clips on the rail's bottom edge.
private struct CometSparkLayer: Shape {
    let outline: NotchOutlineShape
    let param: CGFloat
    let sign: CGFloat        // comet's param-travel direction; sparks trail opposite
    let t: Double
    let band: Int
    let bandCount: Int

    func path(in rect: CGRect) -> Path {
        let src = outline.path(in: rect)
        let cp = min(0.985, max(0.015, param))
        let pt = railPointOn(src, at: cp)
        let tan = railTangent(src, at: cp)
        let back = CGVector(dx: -sign * tan.dx, dy: -sign * tan.dy)
        var out = Path()
        let perSpot = 4
        let cycle = 0.16
        let maxFly: CGFloat = 9, len: CGFloat = 2.4
        for i in 0 ..< perSpot {
            let phase = ((t / cycle) + Double(i) / Double(perSpot))
                .truncatingRemainder(dividingBy: 1)
            let life = 1 - phase
            guard min(bandCount - 1, Int(life * Double(bandCount))) == band else { continue }
            let fly = CGFloat(phase) * maxFly
            for s in [CGFloat(1), -1] {
                let dir = rotateVec(back, by: s * 0.8)
                let base = CGPoint(x: pt.x + dir.dx * fly, y: pt.y + dir.dy * fly)
                let tip = CGPoint(x: base.x + dir.dx * len, y: base.y + dir.dy * len)
                out.move(to: base)
                out.addLine(to: tip)
            }
        }
        return out
    }
}

/// Compact-bar count badge — a circle sized to match the opposite wing's
/// badge. The number digit-tumbles on change; an optional pulse glow marks an
/// alert (e.g. agents waiting on you).
struct CompactStateBadge: View {
    let color: Color
    let count: Int
    let size: CGFloat
    var pulsing: Bool = false
    var dimWhenZero: Bool = false

    @State private var pulse = false

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .foregroundStyle(color)
            .contentTransition(.numericText())
            .frame(width: size, height: size)
            .background(Circle().fill(color.opacity(0.16)))
            .overlay(Circle().stroke(color.opacity(0.4), lineWidth: 0.5))
            .shadow(color: (pulsing && pulse) ? color.opacity(0.75) : .clear,
                    radius: (pulsing && pulse) ? 5 : 0)
            .opacity(dimWhenZero && count == 0 ? 0.4 : 1)
            .animation(.snappy(duration: 0.35), value: count)
            .onAppear { startPulseIfNeeded(pulsing) }
            .onChange(of: pulsing) { _, now in startPulseIfNeeded(now) }
    }

    private func startPulseIfNeeded(_ on: Bool) {
        if on {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulse = true
            }
        } else {
            withAnimation(.default) { pulse = false }
        }
    }
}

/// Idle-count badge: a soft continuous-rounded "squircle" with a subtle
/// translucent fill, a hairline edge, and clean tabular digits. Tidy and calm.
struct CrateBadge: View {
    let count: Int
    let color: Color
    let size: CGFloat

    var body: some View {
        Text("\(count)")
            .font(.system(size: size * 0.55, weight: .bold))
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            // Digit scrolls up when the count rises, down when it falls.
            .contentTransition(.numericText(value: Double(count)))
            .animation(.snappy(duration: 0.45), value: count)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(color.opacity(0.20))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .stroke(color.opacity(0.50), lineWidth: 0.7)
            )
    }
}

/// Attention badge: the exact same squircle box as `CrateBadge`, but with
/// a pause glyph in the middle instead of a count — shown when a session
/// is waiting on the user (paused, needs input).
struct CratePauseBadge: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        // Hand-drawn pause (two capsules) so the glyph sits dead-center in
        // the square and we control the gap between the bars precisely.
        HStack(spacing: size * 0.13) {
            Capsule().fill(color).frame(width: size * 0.13, height: size * 0.40)
            Capsule().fill(color).frame(width: size * 0.13, height: size * 0.40)
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(color.opacity(0.20))
        )
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .stroke(color.opacity(0.50), lineWidth: 0.7)
        )
    }
}

/// Port of the claude-tab-status coffee idle icon (Lucide "coffee"): a stroked
/// cup with three steam wisps that rise, fade, and draw in via a dash sweep on
/// a 4.8s loop. Used as the right-wing icon when nothing is in progress.
struct CoffeeIdleIcon: View {
    var color = Color(red: 190/255.0, green: 198/255.0, blue: 214/255.0).opacity(0.62)

    var body: some View {
        DecorativeTimeline(fps: 15) { ctx in
            Canvas { gc, size in
                let s = size.width / 24.0
                gc.scaleBy(x: s, y: s)
                gc.translateBy(x: 0, y: 13)   // headroom above the cup for steam

                let cupStyle = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                gc.stroke(Self.cupBody, with: .color(color), style: cupStyle)
                gc.stroke(Self.handle, with: .color(color), style: cupStyle)
                gc.stroke(Self.rim, with: .color(color), style: cupStyle)

                let t = ctx.date.timeIntervalSinceReferenceDate
                // All three wisps share one phase — they rise together.
                let f = Self.steamFrame((t / 4.8).truncatingRemainder(dividingBy: 1))
                for w in Self.wisps {
                    var g = gc
                    g.opacity = f.op
                    g.translateBy(x: 0, y: f.ty)
                    g.stroke(w.path.trimmedPath(from: 0, to: f.reveal),
                             with: .color(color),
                             style: StrokeStyle(lineWidth: w.width, lineCap: .round))
                }
            }
        }
    }

    private struct Wisp { let path: Path; let width: CGFloat }

    private static let cupBody: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 4, y: 8))
        p.addLine(to: CGPoint(x: 18, y: 8))
        p.addLine(to: CGPoint(x: 18, y: 15))
        p.addQuadCurve(to: CGPoint(x: 12, y: 21), control: CGPoint(x: 18, y: 21))
        p.addLine(to: CGPoint(x: 10, y: 21))
        p.addQuadCurve(to: CGPoint(x: 4, y: 15), control: CGPoint(x: 4, y: 21))
        p.closeSubpath()
        return p
    }()

    private static let handle: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 18, y: 8))
        p.addLine(to: CGPoint(x: 19, y: 8))
        p.addQuadCurve(to: CGPoint(x: 19, y: 16), control: CGPoint(x: 25.5, y: 12))
        p.addLine(to: CGPoint(x: 18, y: 16))
        return p
    }()

    private static let rim: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 6, y: 8))
        p.addLine(to: CGPoint(x: 16, y: 8))
        return p
    }()

    private static let wisps: [Wisp] = [
        Wisp(path: cubic((7.1, 7.1), (4.2, 5.2), (10.1, 5.6), (7.4, 4.6)), width: 1.6),
        Wisp(path: cubic((11, 7.1), (8.1, 5.1), (14, 3.9), (11.2, 1.3)), width: 2.2),
        Wisp(path: cubic((14.9, 7.1), (12, 5.2), (17.8, 5.6), (15, 4.6)), width: 1.7),
    ]

    private static func cubic(_ a: (CGFloat, CGFloat), _ c1: (CGFloat, CGFloat),
                              _ c2: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: a.0, y: a.1))
        p.addCurve(to: CGPoint(x: b.0, y: b.1),
                   control1: CGPoint(x: c1.0, y: c1.1),
                   control2: CGPoint(x: c2.0, y: c2.1))
        return p
    }

    /// Interpolate the `coffeeSteam` keyframes (opacity, rise, dash reveal).
    private static func steamFrame(_ p: Double) -> (op: Double, ty: CGFloat, reveal: CGFloat) {
        let kf: [(p: Double, op: Double, ty: CGFloat, reveal: CGFloat)] = [
            (0.00, 0.00,   3, 0.00),
            (0.16, 0.30,   0, 0.31),
            (0.45, 0.80,  -6, 0.70),
            (0.80, 0.42, -12, 1.00),   // still visible up high
            (1.00, 0.00, -16, 1.00),   // fades at the very top
        ]
        for i in 1 ..< kf.count where p <= kf[i].p {
            let a = kf[i - 1], b = kf[i]
            let f = CGFloat((p - a.p) / (b.p - a.p))
            return (a.op + (b.op - a.op) * Double(f),
                    a.ty + (b.ty - a.ty) * f,
                    a.reveal + (b.reveal - a.reveal) * f)
        }
        return (0, -9, 1)
    }
}

/// SwiftUI port of the "washing machine" CSS loader: a white body with a
/// control panel (3 knobs), feet, and a round door whose drum spins with an
/// accelerating cycle (0→360→750→1800° over 3s) while the body shakes.
struct WashingMachineLoader: View {
    private static let ddd = Color(white: 0.867)
    private static let eee = Color(white: 0.933)
    private static let aaa = Color(white: 0.667)
    private static let n999 = Color(white: 0.60)
    private static let blue = Color(red: 0.392, green: 0.710, blue: 0.965)   // #64b5f6
    private static let slate = Color(red: 0.376, green: 0.490, blue: 0.545)  // #607d8b

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / 120, geo.size.height / 150)
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let p = t.truncatingRemainder(dividingBy: 3.0) / 3.0
                let b = shakeBurst(t)          // 0…1 envelope, brief, every ~8s
                let w = sin(t * 26)            // gentler shimmy oscillation
                let idle = sin(t * 6)          // always-on, very subtle wobble
                machine(spin: spinAngle(p))
                    .rotationEffect(.degrees(Double(b) * w * 0.6 + Double(idle) * 0.15),
                                    anchor: UnitPoint(x: 0.5, y: 1.1))
                    .scaleEffect(scale)
                    .offset(x: b * CGFloat(w) * 0.9 + CGFloat(idle) * 0.3)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    private func machine(spin: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(Color.white)
            Rectangle().fill(Self.ddd).frame(width: 120, height: 4).position(x: 60, y: 22)
            Rectangle().fill(Self.eee).frame(width: 30, height: 8).position(x: 23, y: 10)
            Rectangle().fill(Self.eee).frame(width: 1, height: 23).position(x: 45, y: 11)
            knob().position(x: 62, y: 10)
            knob().position(x: 82, y: 10)
            knob().position(x: 102, y: 10)
            door(spin: spin).frame(width: 95, height: 95).position(x: 60, y: 82.5)
            foot().position(x: 8, y: 151)
            foot().position(x: 110, y: 151)
        }
        .frame(width: 120, height: 150)
    }

    private func knob() -> some View {
        Circle().fill(RadialGradient(
            stops: [.init(color: Self.aaa, location: 0.25),
                    .init(color: Self.eee, location: 0.26),
                    .init(color: Self.eee, location: 0.50),
                    .init(color: .clear, location: 0.55)],
            center: .center, startRadius: 0, endRadius: 7.5))
            .frame(width: 15, height: 15)
    }

    private func foot() -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 4,
                               bottomTrailingRadius: 4, topTrailingRadius: 0)
            .fill(Self.aaa).frame(width: 7, height: 5)
    }

    private func door(spin: Double) -> some View {
        ZStack {
            Circle().fill(Self.ddd)                                   // outer border ring
            LinearGradient(stops: [
                .init(color: Self.blue, location: 0),
                .init(color: Self.blue, location: 0.5),
                .init(color: Self.slate, location: 0.5),
                .init(color: Self.slate, location: 1)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(Circle())
                .rotationEffect(.degrees(spin))
                .padding(10)
            Circle().strokeBorder(Self.n999, lineWidth: 4).padding(10)        // #999 ring
            Circle().strokeBorder(Color.black.opacity(0.20), lineWidth: 6)    // inner shadow
                .blur(radius: 2).padding(11)
        }
    }

    /// Accelerating spin: 0→360 (0–50%), →750 (50–75%), →1800 (75–100%).
    private func spinAngle(_ p: Double) -> Double {
        if p < 0.5 { return 360 * (p / 0.5) }
        if p < 0.75 { return 360 + 390 * ((p - 0.5) / 0.25) }
        return 750 + 1050 * ((p - 0.75) / 0.25)
    }

    /// A brief, smooth horizontal shimmy every ~8s — controlled, not constant,
    /// so it accents the spin without competing with it.
    private func shakeBurst(_ t: Double) -> CGFloat {
        let period = 8.0
        let local = t.truncatingRemainder(dividingBy: period)
        let dur = 1.0
        guard local < dur else { return 0 }
        return CGFloat(sin(.pi * local / dur))   // 0 → 1 → 0 envelope
    }
}

/// SwiftUI port of the "jumping box" CSS spinner: a white rounded square that
/// tumbles 90° each 0.5s cycle, dipping + squashing (bottom-right corner
/// splats) at mid-cycle while the shadow beneath widens on impact.
struct JumpingBoxLoader: View {
    var color = Color.white

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) * 0.46
            let base = s * 0.083
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
                let period = 0.5
                let p = ctx.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period) / period
                let dip = 1 - abs(2 * p - 1)                  // 0 → 1 → 0
                let ty = s * 0.42 * dip                        // dips DOWN at mid-cycle
                let brr = base + (s * 0.7 - base) * pow(dip, 2)// bottom-right splat
                ZStack {
                    Ellipse()
                        .fill(Color.black.opacity(0.25))
                        .frame(width: s, height: s * 0.12)
                        .scaleEffect(x: 1 + 0.25 * dip, y: 1) // shadow widens on impact
                        .offset(y: s * 0.62)
                    UnevenRoundedRectangle(
                        topLeadingRadius: base, bottomLeadingRadius: base,
                        bottomTrailingRadius: brr, topTrailingRadius: base)
                        .fill(color)
                        .frame(width: s, height: s)
                        .scaleEffect(x: 1, y: 1 - 0.1 * dip, anchor: .bottom)
                        .rotationEffect(.degrees(p * 90))
                        .offset(y: -s * 0.15 + ty)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

/// SwiftUI port of the "atom" CSS spinner: two crossed elliptical orbits
/// (foreshortened by the 70° rotateX/rotateY, whole thing tilted 45°) each
/// carrying a dot — white and orange-red (#FF3D00) — phase-offset by 0.4s.
struct AtomLoader: View {
    var white = Color.white
    var orange = Color(red: 1.0, green: 0x3D/255.0, blue: 0.0)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
            Canvas { gc, size in
                let s = min(size.width, size.height)
                let cx = size.width / 2, cy = size.height / 2
                let rLong = s * 0.40
                let rShort = rLong * 0.36          // cos(70°) foreshortening
                let dot = s * 0.20
                let ringWidth = s * 0.035
                let period = 1.0
                let t = ctx.date.timeIntervalSinceReferenceDate

                gc.translateBy(x: cx, y: cy)
                gc.rotate(by: .degrees(45))        // parent rotateZ(45deg)
                gc.translateBy(x: -cx, y: -cy)

                func orbit(longHorizontal: Bool, angle: Double, color: Color) {
                    let ex = longHorizontal ? rLong : rShort
                    let ey = longHorizontal ? rShort : rLong
                    let ring = CGRect(x: cx - ex, y: cy - ey, width: ex * 2, height: ey * 2)
                    gc.stroke(Path(ellipseIn: ring),
                              with: .color(color.opacity(0.22)), lineWidth: ringWidth)
                    let p = CGPoint(x: cx + ex * cos(angle), y: cy + ey * sin(angle))
                    let d = CGRect(x: p.x - dot / 2, y: p.y - dot / 2, width: dot, height: dot)
                    gc.fill(Path(ellipseIn: d), with: .color(color))
                }

                let base = (t / period) * 2 * .pi
                orbit(longHorizontal: true,  angle: base, color: white)
                orbit(longHorizontal: false, angle: base - (0.4 / period) * 2 * .pi, color: orange)
            }
        }
    }
}

/// SwiftUI port of the triple-ring CSS spinner (`.loader` + ::before/::after):
/// three concentric quarter-arc rings spinning clockwise at 1s / 2s / 3s per
/// turn. Stroke width and insets are proportional to the slot size.
struct RingLoader: View {
    var color = Color(red: 0x25/255.0, green: 0xB0/255.0, blue: 0x9B/255.0)

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let lw = s * 0.08
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                ZStack {
                    ring(lw).rotationEffect(.degrees(t / 1.0 * 360))
                    ring(lw).padding(s * 0.04).rotationEffect(.degrees(t / 2.0 * 360))
                    ring(lw).padding(s * 0.16).rotationEffect(.degrees(t / 3.0 * 360))
                }
                .frame(width: s, height: s)
            }
        }
    }

    private func ring(_ lw: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: 0.25)
            .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round))
    }
}

/// The Uiverse "wheel and hamster" loader (by Nawsome), run as its ORIGINAL
/// CSS inside a transparent WKWebView so it's pixel-faithful — the elliptical
/// radii, inset-shadow shading, clip-path paws and 8 synced keyframes are hard
/// to reproduce natively. Shown while work is in progress. (A live webview is
/// heavier than the hand-built loaders; bake to a GIF/native port if it stays.)
/// The "working" hamster — formerly a WKWebView (CSS hamster wheel, ~8% CPU in a
/// browser process). Now a native Lottie (`R.json`): full fidelity, tiny, native
/// alpha, paused when quiet. The caller frames + mirrors it.
struct HamsterWheelLoader: View {
    @ObservedObject private var energy = EnergyMonitor.shared

    var body: some View {
        LottieLoop(filename: "hamster-wheel.json", paused: energy.quiet, loopMode: .loop)
            .allowsHitTesting(false)
    }
}








/// The Uiverse flame loader (HTML + CSS by Admin12121): a flickering orange fire
/// with rising ember particles. Markup + CSS verbatim, run in a transparent
/// WKWebView. TEMP swap in the working badge — fits the gun/"still hot" theme.
/// A native Lottie loader — the proper replacement for the WKWebView CSS loaders:
/// tiny vector animation, full fidelity, native alpha, paused when quiet. Uses
/// lottie-ios's SwiftUI `LottieView` + `.resizable()` so it HONOURS the SwiftUI
/// frame (the raw `LottieAnimationView` ignored it and rendered at native size).
struct LottieLoop: View {
    let filename: String       // e.g. "Fire.json"
    let paused: Bool
    var loopMode: LottieLoopMode = .loop

    var body: some View {
        let url = BundledAsset.url(filename)
        LottieView(animation: LottieAnimation.filepath(url?.path ?? ""))
            .configuration(LottieConfiguration(renderingEngine: .coreAnimation))
            .resizable()
            .playbackMode(paused
                ? .paused
                : .playing(.fromProgress(0, toProgress: 1, loopMode: loopMode)))
    }
}

/// Fires a one-shot "stoke" pulse at the right-wing fire when the input comet
/// reaches it — the FireLoader flares as if a fresh log was tossed on. Decoupled
/// through a shared object because the comet (notch rail) and the fire (right
/// wing) live in sibling subviews.
@MainActor final class FireStoker: ObservableObject {
    static let shared = FireStoker()
    @Published private(set) var stokeID = 0
    func stoke() { stokeID += 1 }
}

struct FireLoader: View {
    @ObservedObject private var energy = EnergyMonitor.shared
    @ObservedObject private var stoker = FireStoker.shared
    /// Scale of the flame relative to the badge (the flame is allowed to spill
    /// past the glyph box — it reads as a bigger fire).
    private static let fill: CGFloat = 1.25
    /// 0 at rest … 1 immediately after a log is added. Drives a brief glow + a
    /// small upward leap, then settles. A `withAnimation` one-shot — no clock, so
    /// it costs nothing at rest (battery-safe even while the Lottie is frozen).
    @State private var stoke: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let target = max(8, min(geo.size.width, geo.size.height))
            ZStack {
                // Fuel flash — a warm ember bloom that surges with the new wood,
                // then dies back. Kept additive so it brightens the flame itself.
                RadialGradient(
                    colors: [Color(red: 1.0, green: 0.80, blue: 0.40).opacity(0.85 * stoke),
                             Color(red: 1.0, green: 0.46, blue: 0.10).opacity(0.45 * stoke),
                             .clear],
                    center: .center, startRadius: 0, endRadius: target * 0.7)
                    .frame(width: target * 1.5, height: target * 1.5)
                    .offset(x: target * 0.05 + 1, y: -target * 0.12)
                    .blendMode(.plusLighter)

                LottieLoop(filename: "forge-fire.json", paused: energy.quiet, loopMode: .loop)
                    .frame(width: target * Self.fill, height: target * Self.fill)
                    .offset(x: target * 0.05 + 1, y: -target * 0.12)   // nudge up + a hair right (+1px)
                    // Small leap from the base (anchored low so it doesn't punch
                    // into the border just above) — fuel makes the flames jump.
                    .scaleEffect(1 + 0.13 * stoke, anchor: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .onChange(of: stoker.stokeID) { _, _ in
            // Surge fast (the log lands), then ease back down over ~0.9s.
            withAnimation(.easeOut(duration: 0.15)) { stoke = 1 }
            withAnimation(.easeIn(duration: 0.9).delay(0.15)) { stoke = 0 }
        }
    }
}




/// Native re-draw of the Uiverse turntable (TheAbieza): a spinning vinyl record
/// (cream label) on a sage-green body with a tonearm; SOLID background, so it
/// reads as a small card. Colours + sizes from the original CSS; the plate
/// rotates via `DecorativeTimeline`, which ticks slowly and FREEZES on
/// screen-sleep / Low Power / Reduce Motion.
struct TurntableLoader: View {
    private static let render: CGFloat = 190   // body is 175px; room for the drop shadow
    private static let green = Color(red: 0xAB/255.0, green: 0xC4/255.0, blue: 0xAA/255.0)
    private static let dark  = Color(red: 0x67/255.0, green: 0x5D/255.0, blue: 0x50/255.0)
    private static let cream = Color(red: 0xF3/255.0, green: 0xDE/255.0, blue: 0xBA/255.0)

    var body: some View {
        GeometryReader { geo in
            let target = max(8, min(geo.size.width, geo.size.height))
            card
                .frame(width: Self.render, height: Self.render)
                .scaleEffect(target / Self.render)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }

    private var card: some View {
        ZStack {
            // Hard offset shadow (CSS `box-shadow: 5px 5px 0 0`).
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Self.dark).frame(width: 175, height: 175).offset(x: 5, y: 5)
            // Body card.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Self.green).frame(width: 175, height: 175)
            // Rotating plate, centred on the body.
            plate
            // Tone-arm in the bottom-right of the body (over the plate).
            arm.frame(width: 175, height: 175, alignment: .bottomTrailing)
        }
    }

    private var plate: some View {
        DecorativeTimeline(fps: 12) { ctx in
            let angle = (ctx.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 2.0) / 2.0) * 360.0
            ZStack {
                Circle().fill(Self.dark).frame(width: 150, height: 150)
                // 2-tone border ring: cream top + bottom, dark left + right.
                ZStack {
                    Circle().stroke(Self.dark, lineWidth: 3)
                    Circle().trim(from: 0.625, to: 0.875).stroke(Self.cream, lineWidth: 3)
                    Circle().trim(from: 0.125, to: 0.375).stroke(Self.cream, lineWidth: 3)
                }
                .frame(width: 111, height: 111)
                Circle().fill(Self.cream).frame(width: 70, height: 70)
                Circle().fill(Self.dark).frame(width: 20, height: 20)
            }
            .rotationEffect(.degrees(angle))
        }
        .frame(width: 150, height: 150)
    }

    private var arm: some View {
        VStack(spacing: -8) {
            Circle().fill(Self.cream).frame(width: 25, height: 25)        // counterweight head
            Capsule().fill(Self.cream).frame(width: 10, height: 45)       // arm shaft
        }
        .rotationEffect(.degrees(-45))
        .padding(8)
    }
}




/// SwiftUI port of the CSS "sleeping bear" loader: a white arch head with two
/// ears, a light-blue muzzle/cheeks, black eyes + nose. The face sways side to
/// side (faceLift) and the ears drift (earLift) on a 3s alternating cycle.
struct BearLoader: View {
    private let blue = Color(red: 0xCF/255.0, green: 0xEC/255.0, blue: 0xF9/255.0)

    var body: some View {
        DecorativeTimeline(fps: 15) { ctx in
            Canvas { gc, size in
                let s = min(size.width / 160, size.height / 185)
                gc.translateBy(x: (size.width - 160 * s) / 2, y: (size.height - 185 * s) / 2)
                gc.scaleBy(x: s, y: s)

                let t = ctx.date.timeIntervalSinceReferenceDate
                let fp = Self.triangle(t, period: 3)        // 0 → 1 → 0
                let faceShift = -10.0 + 26.0 * fp           // sway
                let earShift = 6.0 * (1 - fp)

                // Ears (white) — behind the head, peeking at the top corners.
                var ge = gc; ge.translateBy(x: earShift, y: 0)
                ge.fill(Path(ellipseIn: CGRect(x: 6, y: 4, width: 52, height: 52)), with: .color(.white))
                ge.fill(Path(ellipseIn: CGRect(x: 102, y: 4, width: 52, height: 52)), with: .color(.white))

                // Head arch (white).
                var head = Path()
                head.move(to: CGPoint(x: 0, y: 185))
                head.addLine(to: CGPoint(x: 0, y: 80))
                head.addQuadCurve(to: CGPoint(x: 80, y: 0), control: CGPoint(x: 0, y: 0))
                head.addQuadCurve(to: CGPoint(x: 160, y: 80), control: CGPoint(x: 160, y: 0))
                head.addLine(to: CGPoint(x: 160, y: 185))
                head.closeSubpath()
                gc.fill(head, with: .color(.white))

                // Face group (sways).
                var gf = gc; gf.translateBy(x: faceShift, y: 0)
                gf.fill(Path(ellipseIn: CGRect(x: 45, y: 70, width: 70, height: 70)), with: .color(blue))
                gf.fill(Path(ellipseIn: CGRect(x: 45, y: 47, width: 70, height: 70)), with: .color(blue))
                gf.fill(Path(roundedRect: CGRect(x: 55, y: 76, width: 50, height: 25), cornerRadius: 10), with: .color(blue))
                gf.fill(Path(ellipseIn: CGRect(x: 59, y: 55, width: 42, height: 42)), with: .color(.black))
                gf.fill(Path(ellipseIn: CGRect(x: 66, y: 69, width: 10, height: 10)), with: .color(.white))
                gf.fill(Path(roundedRect: CGRect(x: 74, y: 110, width: 12, height: 3.5), cornerSize: CGSize(width: 1.5, height: 1.5)), with: .color(.black))
                gf.fill(Path(ellipseIn: CGRect(x: 55, y: 35, width: 16, height: 16)), with: .color(.black))
                gf.fill(Path(ellipseIn: CGRect(x: 89, y: 35, width: 16, height: 16)), with: .color(.black))
            }
        }
    }

    private static func triangle(_ t: Double, period: Double) -> Double {
        let p = t.truncatingRemainder(dividingBy: period) / period
        return 1 - abs(2 * p - 1)
    }
}

/// A solid chunky "Z" — a thick round-joined stroke of the Z polyline, so the
/// stroke itself IS the fill (matches the sleep SVG's blocky style, but solid).
struct ZShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))     // top-left
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))  // top bar
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))  // diagonal
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))  // bottom bar
        return p
    }
}

/// Idle "sleep" mark — three solid white Z's rising to the right, growing as
/// they drift up.
struct SleepIcon: View {
    var size: CGFloat
    var color = Color.white.opacity(0.92)

    var body: some View {
        ZStack {
            z(0.34, x: -0.30, y: 0.26)
            z(0.48, x: -0.02, y: 0.02)
            z(0.64, x: 0.30, y: -0.24)
        }
        .frame(width: size, height: size)
    }

    private func z(_ s: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        let d = size * s
        return ZShape()
            .stroke(color, style: StrokeStyle(lineWidth: d * 0.13,
                                              lineCap: .round, lineJoin: .round))
            .frame(width: d * 0.78, height: d * 0.86)
            .offset(x: size * x, y: size * y)
    }
}

/// Samples the desktop wallpaper's colour near the top-centre (behind the
/// notch). Cached once at launch.
enum WallpaperColor {
    static let top: Color = sample() ?? Color(red: 0.45, green: 0.93, blue: 0.88)

    /// The most vibrant (saturated × bright) colour anywhere in the wallpaper —
    /// grabs the signature accent (e.g. the orange in a teal→orange gradient).
    static let accent: Color = vibrant() ?? top

    /// The average of ALL wallpaper colours combined.
    static let average: Color = averageAll() ?? top

    private static func averageAll() -> Color? {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let img = NSImage(contentsOf: url),
              let tiff = img.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff) else { return nil }
        let w = bmp.pixelsWide, h = bmp.pixelsHigh
        guard w > 4, h > 4 else { return nil }
        let step = max(1, max(w, h) / 90)
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                if let c = bmp.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    r += Double(c.redComponent); g += Double(c.greenComponent)
                    b += Double(c.blueComponent); n += 1
                }
                x += step
            }
            y += step
        }
        guard n > 0 else { return nil }
        return Color(red: r / n, green: g / n, blue: b / n)
    }

    private static func vibrant() -> Color? {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let img = NSImage(contentsOf: url),
              let tiff = img.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff) else { return nil }
        let w = bmp.pixelsWide, h = bmp.pixelsHigh
        guard w > 4, h > 4 else { return nil }
        let step = max(1, max(w, h) / 90)
        var bestScore = -1.0
        var best: NSColor?
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                if let c = bmp.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    let score = Double(c.saturationComponent) * Double(c.brightnessComponent)
                    if score > bestScore { bestScore = score; best = c }
                }
                x += step
            }
            y += step
        }
        guard let c = best else { return nil }
        return Color(red: Double(c.redComponent), green: Double(c.greenComponent),
                     blue: Double(c.blueComponent))
    }

    private static func sample() -> Color? {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let img = NSImage(contentsOf: url),
              let tiff = img.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff) else { return nil }
        let w = bmp.pixelsWide, h = bmp.pixelsHigh
        guard w > 4, h > 4 else { return nil }
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        let ys = stride(from: Int(Double(h) * 0.02), through: Int(Double(h) * 0.08), by: max(1, h / 60))
        let xs = [0.44, 0.50, 0.56].map { Int(Double(w) * $0) }
        for y in ys {
            for x in xs where x < w && y < h {
                if let c = bmp.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    r += Double(c.redComponent); g += Double(c.greenComponent)
                    b += Double(c.blueComponent); n += 1
                }
            }
        }
        guard n > 0 else { return nil }
        return Color(red: r / n, green: g / n, blue: b / n)
    }
}

/// Gunshot SFX for the siphon — `gun-reload.mp3` when a session starts work,
/// `gun-shot.mp3` when one finishes. Loaded once from ~/Downloads.
enum SoundFX {
    static let reload = make("gun-reload.mp3", volume: 0.5)
    static let shot = make("gun-shot.mp3", volume: 1.0)
    /// Played when a session starts waiting on the user (needs input).
    static let waiting = make("awp-shot.mp3", volume: 1.0)
    /// The "flick the cylinder" widget — the revolver spins to a stop.
    static let spin = make("revolver-spin.mp3", volume: 1.0)

    /// `volume` is 0.0–1.0 (fraction of the file's full level).
    private static func make(_ filename: String, volume: Float = 1.0) -> AVAudioPlayer? {
        guard let url = BundledAsset.url(filename, in: "sounds") else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = volume
        player?.prepareToPlay()
        return player
    }

    /// Restart from the top so rapid transitions always re-fire the sound.
    static func play(_ player: AVAudioPlayer?) {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }
}

// MARK: - Backwards-compat aliases

/// Some legacy call sites still reference `ExpandedPanelShape`. Provide a
/// thin shim so they keep compiling — internally it's just `DropPanelShape`.
struct ExpandedPanelShape: Shape {
    let notchWidth: CGFloat
    let notchCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        DropPanelShape(cornerRadius: bottomCornerRadius).path(in: rect)
    }
}

#Preview {
    VStack(spacing: 16) {
        DropPanelShape(cornerRadius: 16)
            .fill(Color.black)
            .frame(width: 230, height: 34)
        DropPanelShape(cornerRadius: 20)
            .fill(Color.black)
            .frame(width: 360, height: 86)
        DropPanelShape(cornerRadius: 22)
            .fill(Color.black)
            .frame(width: 480, height: 200)
    }
    .padding(40)
    .background(Color.gray.opacity(0.3))
}

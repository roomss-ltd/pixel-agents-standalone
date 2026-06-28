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
import WebKit

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

                // Every so often a small airplane rides the same rail as the
                // freight — a rarer, lighter flourish, tucked in the crate strip.
                RailAircraft(working: working, shape: shape)

                // The siphon droplet — the "bullet", fired after the shooter.
                SiphonDroplet(trigger: siphonID,
                              start: siphonStart, end: siphonEnd,
                              color: siphonColor, outline: shape)

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
                siphonColor = (old == 0) ? blueVivid : cometOrange
                shootTint = blueVivid
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
        let active = Color(red: 0.45, green: 0.93, blue: 0.88)   // white+blue+green merge
        let idle = WallpaperColor.average.opacity(0.70)
        let rs = StrokeStyle(lineWidth: 2.0, lineCap: .round)
        let duration = Self.flowDuration
        if railAnimating {
            // Flowing — drive the moving fronts at display rate for ~0.9s.
            TimelineView(.animation) { ctx in
                let elapsed = ctx.date.timeIntervalSince(flowStart)
                let p = min(1.0, max(0.0, elapsed / duration))
                let half = CGFloat(p) * 0.5
                let leftTo = flowToActive ? half : (0.5 - half)
                let rightFrom = flowToActive ? (1 - half) : (0.5 + half)
                // Param direction each front travels (merge → in toward centre,
                // unmerge → out toward the ends). Sparks trail opposite this.
                let leftSign: CGFloat = flowToActive ? 1 : -1
                let rightSign: CGFloat = flowToActive ? -1 : 1
                // Sparks run the WHOLE flow at full strength, then fade over the
                // tail — so they never blink out mid-merge at either end.
                let tailFade = elapsed <= duration
                    ? 1.0 : max(0.0, 1.0 - (elapsed - duration) / Self.sparkTail)
                ZStack {
                    shape.stroke(idle, style: rs)
                    // Active fill rivering from the ends, carrying the river's
                    // own-colour glow (borrowed from the spark loader).
                    shape.trim(from: 0, to: leftTo).stroke(active, style: rs)
                        .shadow(color: active.opacity(0.6), radius: 2.5)
                        .shadow(color: active.opacity(0.4), radius: 6)
                    shape.trim(from: rightFrom, to: 1).stroke(active, style: rs)
                        .shadow(color: active.opacity(0.6), radius: 2.5)
                        .shadow(color: active.opacity(0.4), radius: 6)
                    if p < 1 {
                        let flick = 0.55 + 0.45 * sin(ctx.date.timeIntervalSinceReferenceDate * 34)
                        railFront(shape, at: leftTo, flick: flick)
                        railFront(shape, at: rightFrom, flick: flick)
                    }
                    // Both fronts, both directions, full duration + tail. Drawn
                    // as Shapes (NOT a Canvas) so sparks on the rail's bottom
                    // edge — which sits a hair below the bar — aren't clipped.
                    if tailFade > 0.01 {
                        let sparkColor = Color(red: 1.0, green: 0.95, blue: 0.82)
                        let fronts = [(param: leftTo, sign: leftSign),
                                      (param: rightFrom, sign: rightSign)]
                        let bands = 4
                        ForEach(0 ..< bands, id: \.self) { band in
                            RailSparkLayer(outline: shape, fronts: fronts,
                                           t: ctx.date.timeIntervalSinceReferenceDate,
                                           band: band, bandCount: bands)
                                .stroke(sparkColor.opacity(tailFade * (Double(band) + 0.5) / Double(bands)),
                                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                                .blendMode(.plusLighter)
                        }
                    }
                }
            }
        } else {
            // Settled — NO clock. idle base, plus the full active stroke (with a
            // resting own-colour glow) once the rail has flowed to active.
            ZStack {
                shape.stroke(idle, style: rs)
                if flowToActive {
                    shape.stroke(active, style: rs)
                        .shadow(color: active.opacity(0.6), radius: 2.5)
                        .shadow(color: active.opacity(0.4), radius: 6)
                }
            }
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
    let fronts: [(param: CGFloat, sign: CGFloat)]
    let t: Double
    let band: Int
    let bandCount: Int

    func path(in rect: CGRect) -> Path {
        let src = outline.path(in: rect)
        var out = Path()
        let cycle = 0.34
        let perFront = 6
        let maxDist: CGFloat = 9, len: CGFloat = 3.5   // shorter streaks, trimmed tails
        for front in fronts {
            let cp = min(0.97, max(0.03, front.param))
            let pt = railPointOn(src, at: cp)
            let tan = railTangent(src, at: cp)
            let back = CGVector(dx: -front.sign * tan.dx, dy: -front.sign * tan.dy)
            for i in 0 ..< perFront {
                let phase = ((t / cycle) + Double(i) / Double(perFront))
                    .truncatingRemainder(dividingBy: 1)
                let life = max(0, 1 - phase)
                guard min(bandCount - 1, Int(life * Double(bandCount))) == band else { continue }
                let dist = CGFloat(phase) * maxDist
                for sgn in [CGFloat(1), -1] {
                    let dir = rotateVec(back, by: sgn * 0.7)
                    let base = CGPoint(x: pt.x + dir.dx * dist, y: pt.y + dir.dy * dist)
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
        TimelineView(.animation) { context in
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

/// Loads the "shoot" hand GIF from ~/Downloads (prefers `Shoot.gif`, else the
/// newest .gif), decodes its frames, and keys out the white background so it
/// reads as a transparent cut-out. Cached once. Reading Downloads on a
/// non-sandboxed app may trigger a one-time macOS permission prompt.
enum ShootAsset {
    struct Frame { let image: CGImage; let duration: Double }

    static let frames: [Frame] = load()

    // TEMP (preview): right-wing GIFs — laundry while working, cat while idle.
    static let laundry: [Frame] = loadNamed("loading.gif", keyed: false)
    static let cat: [Frame] = loadNamed("cat.gif")
    /// Idle right-wing icon (nothing in progress).
    static let coffee: [Frame] = loadNamed("Hot Beverage.gif")
    static let sleepBear: [Frame] = loadNamed("Sleeping bear.gif")
    /// Left-wing shooter (work starts). TEMP: funnel instead of bullets.
    static let funnel: [Frame] = loadNamed("funnel.gif")
    /// Left-wing target when work finishes (gun fires right→left).
    static let target: [Frame] = loadNamed("target.gif")
    /// Right-wing projectiles while work STARTS (funnel pours on the left).
    static let bullets: [Frame] = loadNamed("bullets (1).gif")
    /// Muzzle smoke for the dock cannon. Already transparent, so no keying.
    static let smoke: [Frame] = loadNamed("smoke.gif", keyed: false)
    /// Occasional flyover props that cross the status line while work is active.
    /// Both GIFs ship with native alpha (no white to key) and face LEFT, so the
    /// crossing view flips them when travelling left→right. The square jet reads
    /// cleanly; the slim one drags a contrail.
    static let airplane: [Frame] = loadNamed("Airplane flying.gif", keyed: false)
    /// Static SVG jet (dark teal body + orange exhaust). Rasterised once.
    static let contrailPlane: [Frame] = loadStatic("Airplane.svg")
    /// Wooden crate box (SVG) — replaces the drawn crate, still hung by OUR
    /// trolley+cable crane. Recolour variants come later.
    static let crateImage: CGImage? = loadStatic("crate.svg", pixelHeight: 128).first?.image
    /// Shipping containers that ship WITH their own crane rig baked in (hook +
    /// cables + posts); they ride solo, no extra crane from us.
    static let containerImages: [CGImage] = ["container1.png", "container2.png"]
        .compactMap { loadNamed($0, keyed: false).first?.image }

    private static func load() -> [Frame] {
        guard let url = sourceURL else { return [] }
        return frames(at: url)
    }

    /// Load a specific GIF by filename from ~/Downloads, optionally keying out
    /// its white background.
    static func loadNamed(_ filename: String, keyed: Bool = true) -> [Frame] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads").appendingPathComponent(filename)
        return frames(at: url, keyed: keyed)
    }

    /// Rasterise a single static image (e.g. an SVG) from ~/Downloads into one
    /// frame, `pixelHeight` tall at the source aspect — crisp enough to display
    /// well above its on-screen size. macOS draws SVG natively via NSImage. The
    /// offscreen bitmap starts transparent, so the art's own alpha is preserved
    /// (no keying). Returns [] if the file is missing or can't be drawn.
    static func loadStatic(_ filename: String, pixelHeight: Int = 480) -> [Frame] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads").appendingPathComponent(filename)
        guard let img = NSImage(contentsOf: url),
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

    private static func frames(at url: URL, keyed: Bool = true) -> [Frame] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        let n = CGImageSourceGetCount(src)
        var out: [Frame] = []
        for i in 0 ..< n {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            guard let img = keyed ? keyWhite(cg) : cg else { continue }
            out.append(Frame(image: img, duration: frameDuration(src, i)))
        }
        return out
    }

    private static var sourceURL: URL? {
        let dl = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
        let named = dl.appendingPathComponent("Shoot.gif")
        if FileManager.default.fileExists(atPath: named.path) { return named }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dl, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "gif" }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return da < db
            }
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
        .onChange(of: working > 0) { _, active in
            if active { startSpawning() } else { stopSpawning() }
        }
        // PREVIEW: spawn even at rest so the new freight art is verifiable
        // without an active agent. Revert to `if working > 0 { startSpawning() }`.
        .onAppear { startSpawning() }
        .onDisappear { stopSpawning() }
    }

    private func startSpawning() {
        guard spawner == nil else { return }
        spawner = Task { @MainActor in
            while !Task.isCancelled {
                // PREVIEW cadence — frequent so the new freight art is easy to
                // verify. Revert to `Double.random(in: 7.0 ... 15.0)`.
                try? await Task.sleep(for: .seconds(Double.random(in: 2.0 ... 4.0)))
                if Task.isCancelled { return }
                let dir = Bool.random()
                let dur = Double.random(in: 3.6 ... 5.4)        // slower, smoother glide
                let tint = Self.tints.randomElement() ?? .orange
                switch Int.random(in: 0 ..< 100) {
                case 0 ..< 40:
                    // Chained load — 2–4 boxes linked, moving as one.
                    crates.append(Crate(leftToRight: dir, tint: tint, duration: dur,
                                        boxes: Int.random(in: 2 ... 4), style: Self.randomStyle()))
                case 40 ..< 62:
                    // Loose train — separate CHAINED groups (each 2+ crates),
                    // generously spaced so even a wide group fully clears before
                    // the next spawns. Stagger scales with group width + speed.
                    let groups = Int.random(in: 2 ... 3)
                    for i in 0 ..< groups {
                        if Task.isCancelled { return }
                        let boxes = Int.random(in: 2 ... 4)
                        crates.append(Crate(leftToRight: dir,
                                            tint: Self.tints.randomElement() ?? .orange,
                                            duration: dur, boxes: boxes, style: Self.randomStyle()))
                        if i < groups - 1 {
                            let staggerSec = dur * (Double(boxes) * 0.07 + 0.10)
                            try? await Task.sleep(for: .seconds(staggerSec))
                        }
                    }
                case 62 ..< 82:
                    // Big chained load — 4–6 boxes linked.
                    crates.append(Crate(leftToRight: dir, tint: tint, duration: dur,
                                        boxes: Int.random(in: 4 ... 6), style: Self.randomStyle()))
                default:
                    // A single shipping container, travelling solo on its OWN
                    // built-in crane (one of the container PNGs at random).
                    let idx = ShootAsset.containerImages.isEmpty
                        ? nil : Int.random(in: 0 ..< ShootAsset.containerImages.count)
                    crates.append(Crate(leftToRight: dir, tint: tint, duration: dur,
                                        boxes: 1, style: .wide, containerIndex: idx))
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
    private let crateW: CGFloat = 9          // crate.svg is square
    private let crateH: CGFloat = 9
    private let containerSize: CGFloat = 24  // solo container, own crane baked in
    private let linkGap: CGFloat = 1.0       // tight chains

    var body: some View {
        // Bottom rail runs ~0.30 (right end) … 0.70 (left end) in path-param.
        let tStart: CGFloat = crate.leftToRight ? 0.70 : 0.30
        let tEnd: CGFloat = crate.leftToRight ? 0.30 : 0.70
        let isContainer = crate.containerIndex != nil && !ShootAsset.containerImages.isEmpty
        let unitH = hookD + cableLen + crateH
        let n = max(1, crate.boxes)
        let unitW = isContainer ? containerSize
                                : CGFloat(n) * crateW + CGFloat(n - 1) * linkGap

        // A real clock drives progress so the body re-evaluates each frame —
        // letting the triangular fade (0 → 1 → 0) actually peak in the middle.
        return TimelineView(.animation) { ctx in
            let p = min(1, max(0, ctx.date.timeIntervalSince(start) / crate.duration))
            let t = tStart + (tEnd - tStart) * CGFloat(p)
            let pt = railPoint(t)
            let fade = max(0, min(1, min(CGFloat(p) / 0.12, (1 - CGFloat(p)) / 0.12)))
            // Convert the load's PIXEL width into rail-param space so the glow
            // spans the whole train (plus a bit), accounting for the rail's
            // local scale (pixels travelled per unit of path parameter).
            let dδ: CGFloat = 0.004
            let pa = railPoint(t - dδ), pb = railPoint(t + dδ)
            let pxPerParam = max(1, hypot(pb.x - pa.x, pb.y - pa.y) / (2 * dδ))
            let edge = isContainer ? containerSize : crateW
            let glowHalf = min(0.30, (unitW / 2 + edge * 0.6) / pxPerParam)

            ZStack {
                // The STATUS LINE glow above the load: the yellowish river-end
                // colour painted onto the rail at the load's current position,
                // travelling with it from corner to corner.
                railGlow(at: t, halfWidth: glowHalf)
                    .opacity(Double(fade))

                if isContainer {
                    // Shipping container with its OWN crane baked in: the image's
                    // built-in hook sits on the rail, the box hangs below. No
                    // trolley/cable from us.
                    Image(decorative: ShootAsset.containerImages[crate.containerIndex!], scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: containerSize, height: containerSize)
                        .shadow(color: .black.opacity(0.45), radius: 1, y: 0.5)
                        .opacity(Double(fade))
                        .position(x: pt.x, y: pt.y + containerSize / 2)
                } else {
                    // Crate chain hung from OUR crane (trolley + cable per box).
                    ZStack(alignment: .top) {
                        // Beam linking the trolleys of a chained load.
                        if n > 1 {
                            Rectangle().fill(Color(white: 0.5))
                                .frame(width: unitW - crateW, height: 0.8)
                                .offset(y: hookD / 2 - 0.4)
                        }
                        HStack(spacing: linkGap) {
                            ForEach(0 ..< n, id: \.self) { _ in container }
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

    /// A short glowing segment of the rail at parameter `center`, painted like
    /// the river's ends: NOT a flat slab but a graduated neon — concentric
    /// trims from a wide dim orange up to a narrow white-hot core, so the centre
    /// blooms and the ends taper out through amber → deep orange. Rides the
    /// status line directly above the crate as it travels.
    private func railGlow(at center: CGFloat, halfWidth w: CGFloat) -> some View {
        let deep  = Color(red: 1.0, green: 0.50, blue: 0.14)   // deep orange — the soft edges
        let amber = Color(red: 1.0, green: 0.72, blue: 0.26)   // river-spark amber — mid
        let gold  = Color(red: 1.0, green: 0.88, blue: 0.52)   // pale gold — inner
        // Each layer is narrower + brighter than the last; stacked with
        // plusLighter they sum to white-hot in the middle and fade to a dim
        // orange at the ends (the layers drop out one by one outward). An empty
        // trim range just renders nothing, so no guard is needed.
        func seg(_ hw: CGFloat) -> (CGFloat, CGFloat) {
            (max(0, center - hw), min(1, center + hw))
        }
        let l0 = seg(w), l1 = seg(w * 0.66), l2 = seg(w * 0.40), l3 = seg(w * 0.16)
        return ZStack {
            shape.trim(from: l0.0, to: l0.1)
                .stroke(deep.opacity(0.42), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
                .shadow(color: deep.opacity(0.8), radius: 5)
                .blendMode(.plusLighter)
            shape.trim(from: l1.0, to: l1.1)
                .stroke(amber.opacity(0.80), style: StrokeStyle(lineWidth: 3.0, lineCap: .round))
                .blendMode(.plusLighter)
            shape.trim(from: l2.0, to: l2.1)
                .stroke(gold.opacity(0.95), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .blendMode(.plusLighter)
            shape.trim(from: l3.0, to: l3.1)
                .stroke(.white, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }

    /// One trolley + cable + crate column.
    private var container: some View {
        VStack(spacing: 0) {
            Circle().fill(Color(white: 0.55)).frame(width: hookD, height: hookD)
            Rectangle().fill(Color(white: 0.45)).frame(width: 0.8, height: cableLen)
            crateBox
        }
    }

    /// The crate box — the wooden crate SVG (recolour variants come later),
    /// falling back to a tinted rounded rect if the asset didn't load.
    private var crateBox: some View {
        Group {
            if let img = ShootAsset.crateImage {
                Image(decorative: img, scale: 1)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 1.4).fill(crate.tint)
            }
        }
        .frame(width: crateW, height: crateH)
        .shadow(color: .black.opacity(0.45), radius: 1, y: 0.5)
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
            (ShootAsset.airplane, 31.5, false),     // square jet
            (ShootAsset.contrailPlane, 32, false),  // SVG jet + exhaust
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
        .onChange(of: working > 0) { _, active in
            if active { startSpawning() } else { stopSpawning() }
        }
        // PREVIEW: spawn even at rest so the look can be verified without an
        // active agent. Revert to `if working > 0 { startSpawning() }`.
        .onAppear { startSpawning() }
        .onDisappear { stopSpawning() }
    }

    private func startSpawning() {
        guard spawner == nil else { return }
        let catalog = Self.catalog
        guard !catalog.isEmpty else { return }
        spawner = Task { @MainActor in
            while !Task.isCancelled {
                // PREVIEW cadence — frequent so the look is easy to verify.
                // Revert to `Double.random(in: 12.0 ... 26.0)`.
                try? await Task.sleep(for: .seconds(Double.random(in: 1.6 ... 3.2)))
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

        return TimelineView(.animation) { ctx in
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
                    // Tuck just below the rail, in the same strip as the crates.
                    .position(x: pt.x, y: pt.y + h / 2 + 1.5)
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
            TimelineView(.animation) { ctx in
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
            TimelineView(.animation) { ctx in
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
        TimelineView(.animation) { ctx in
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
            TimelineView(.animation) { ctx in
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
struct HamsterWheelLoader: View {
    /// Render the CSS at its native 168px (font-size 14) for full detail, then
    /// scale the whole webview DOWN to the badge. That supersamples it (a big
    /// crisp render sampled into few pixels) rather than rasterising the CSS at
    /// the tiny point size — which is what made it look pixelated.
    private static let render: CGFloat = 168

    var body: some View {
        GeometryReader { geo in
            let target = max(8, min(geo.size.width, geo.size.height))
            HamsterWebView(px: Self.render)
                .frame(width: Self.render, height: Self.render)
                .scaleEffect(target / Self.render)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}

/// Transparent WKWebView host that renders the hamster-wheel CSS at `px` points
/// (font-size scales the whole rig: 12em = px). Retina backing keeps it crisp.
private struct HamsterWebView: NSViewRepresentable {
    let px: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: px, height: px))
        wv.setValue(false, forKey: "drawsBackground")   // transparent background
        wv.loadHTMLString(Self.document(px: px), baseURL: nil)
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    private static func document(px: CGFloat) -> String {
        let fs = px / 12.0   // .wheel-and-hamster is 12em wide → 12em = px
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        html,body{margin:0;padding:0;background:transparent;overflow:hidden;width:\(px)px;height:\(px)px}
        body{display:flex;align-items:center;justify-content:center}
        \(css)
        .wheel-and-hamster{font-size:\(fs)px}
        </style></head><body>
        <div class="wheel-and-hamster" role="img">
          <div class="wheel"></div>
          <div class="hamster"><div class="hamster__body">
            <div class="hamster__head"><div class="hamster__ear"></div><div class="hamster__eye"></div><div class="hamster__nose"></div></div>
            <div class="hamster__limb--fr"></div><div class="hamster__limb--fl"></div>
            <div class="hamster__limb--br"></div><div class="hamster__limb--bl"></div>
            <div class="hamster__tail"></div>
          </div></div>
          <div class="spoke"></div>
        </div>
        </body></html>
        """
    }

    /// The CSS exactly as authored (Uiverse.io / Nawsome).
    private static let css = #"""
    .wheel-and-hamster {
      --dur: 1s;
      position: relative;
      width: 12em;
      height: 12em;
      font-size: 14px;
    }
    .wheel,
    .hamster,
    .hamster div,
    .spoke {
      position: absolute;
    }
    .wheel,
    .spoke {
      border-radius: 50%;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
    }
    .wheel {
      background: radial-gradient(100% 100% at center,hsla(0,0%,60%,0) 45.8%,hsl(0,0%,60%) 46%);
      z-index: 2;
    }
    .hamster {
      animation: hamster var(--dur) ease-in-out infinite;
      top: 50%;
      left: calc(50% - 3.5em);
      width: 7em;
      height: 3.75em;
      transform: rotate(4deg) translate(-0.8em,1.85em);
      transform-origin: 50% 0;
      z-index: 1;
    }
    .hamster__head {
      animation: hamsterHead var(--dur) ease-in-out infinite;
      background: hsl(30,90%,55%);
      border-radius: 70% 30% 0 100% / 40% 25% 25% 60%;
      box-shadow: 0 -0.25em 0 hsl(30,90%,80%) inset,
            0.75em -1.55em 0 hsl(30,90%,90%) inset;
      top: 0;
      left: -2em;
      width: 2.75em;
      height: 2.5em;
      transform-origin: 100% 50%;
    }
    .hamster__ear {
      animation: hamsterEar var(--dur) ease-in-out infinite;
      background: hsl(0,90%,85%);
      border-radius: 50%;
      box-shadow: -0.25em 0 hsl(30,90%,55%) inset;
      top: -0.25em;
      right: -0.25em;
      width: 0.75em;
      height: 0.75em;
      transform-origin: 50% 75%;
    }
    .hamster__eye {
      animation: hamsterEye var(--dur) linear infinite;
      background-color: hsl(0,0%,0%);
      border-radius: 50%;
      top: 0.375em;
      left: 1.25em;
      width: 0.5em;
      height: 0.5em;
    }
    .hamster__nose {
      background: hsl(0,90%,75%);
      border-radius: 35% 65% 85% 15% / 70% 50% 50% 30%;
      top: 0.75em;
      left: 0;
      width: 0.2em;
      height: 0.25em;
    }
    .hamster__body {
      animation: hamsterBody var(--dur) ease-in-out infinite;
      background: hsl(30,90%,90%);
      border-radius: 50% 30% 50% 30% / 15% 60% 40% 40%;
      box-shadow: 0.1em 0.75em 0 hsl(30,90%,55%) inset,
            0.15em -0.5em 0 hsl(30,90%,80%) inset;
      top: 0.25em;
      left: 2em;
      width: 4.5em;
      height: 3em;
      transform-origin: 17% 50%;
      transform-style: preserve-3d;
    }
    .hamster__limb--fr,
    .hamster__limb--fl {
      clip-path: polygon(0 0,100% 0,70% 80%,60% 100%,0% 100%,40% 80%);
      top: 2em;
      left: 0.5em;
      width: 1em;
      height: 1.5em;
      transform-origin: 50% 0;
    }
    .hamster__limb--fr {
      animation: hamsterFRLimb var(--dur) linear infinite;
      background: linear-gradient(hsl(30,90%,80%) 80%,hsl(0,90%,75%) 80%);
      transform: rotate(15deg) translateZ(-1px);
    }
    .hamster__limb--fl {
      animation: hamsterFLLimb var(--dur) linear infinite;
      background: linear-gradient(hsl(30,90%,90%) 80%,hsl(0,90%,85%) 80%);
      transform: rotate(15deg);
    }
    .hamster__limb--br,
    .hamster__limb--bl {
      border-radius: 0.75em 0.75em 0 0;
      clip-path: polygon(0 0,100% 0,100% 30%,70% 90%,70% 100%,30% 100%,40% 90%,0% 30%);
      top: 1em;
      left: 2.8em;
      width: 1.5em;
      height: 2.5em;
      transform-origin: 50% 30%;
    }
    .hamster__limb--br {
      animation: hamsterBRLimb var(--dur) linear infinite;
      background: linear-gradient(hsl(30,90%,80%) 90%,hsl(0,90%,75%) 90%);
      transform: rotate(-25deg) translateZ(-1px);
    }
    .hamster__limb--bl {
      animation: hamsterBLLimb var(--dur) linear infinite;
      background: linear-gradient(hsl(30,90%,90%) 90%,hsl(0,90%,85%) 90%);
      transform: rotate(-25deg);
    }
    .hamster__tail {
      animation: hamsterTail var(--dur) linear infinite;
      background: hsl(0,90%,85%);
      border-radius: 0.25em 50% 50% 0.25em;
      box-shadow: 0 -0.2em 0 hsl(0,90%,75%) inset;
      top: 1.5em;
      right: -0.5em;
      width: 1em;
      height: 0.5em;
      transform: rotate(30deg) translateZ(-1px);
      transform-origin: 0.25em 0.25em;
    }
    .spoke {
      animation: spoke calc(var(--dur) * 3) linear infinite;
      background: radial-gradient(100% 100% at center,hsl(0,0%,60%) 4.8%,hsla(0,0%,60%,0) 5%),
            linear-gradient(hsla(0,0%,55%,0) 46.9%,hsl(0,0%,65%) 47% 52.9%,hsla(0,0%,65%,0) 53%) 50% 50% / 99% 99% no-repeat;
    }
    @keyframes hamster {
      from, to { transform: rotate(4deg) translate(-0.8em,1.85em); }
      50% { transform: rotate(0) translate(-0.8em,1.85em); }
    }
    @keyframes hamsterHead {
      from, 25%, 50%, 75%, to { transform: rotate(0); }
      12.5%, 37.5%, 62.5%, 87.5% { transform: rotate(8deg); }
    }
    @keyframes hamsterEye {
      from, 90%, to { transform: scaleY(1); }
      95% { transform: scaleY(0); }
    }
    @keyframes hamsterEar {
      from, 25%, 50%, 75%, to { transform: rotate(0); }
      12.5%, 37.5%, 62.5%, 87.5% { transform: rotate(12deg); }
    }
    @keyframes hamsterBody {
      from, 25%, 50%, 75%, to { transform: rotate(0); }
      12.5%, 37.5%, 62.5%, 87.5% { transform: rotate(-2deg); }
    }
    @keyframes hamsterFRLimb {
      from, 25%, 50%, 75%, to { transform: rotate(50deg) translateZ(-1px); }
      12.5%, 37.5%, 62.5%, 87.5% { transform: rotate(-30deg) translateZ(-1px); }
    }
    @keyframes hamsterFLLimb {
      from, 25%, 50%, 75%, to { transform: rotate(-30deg); }
      12.5%, 37.5%, 62.5%, 87.5% { transform: rotate(50deg); }
    }
    @keyframes hamsterBRLimb {
      from, 25%, 50%, 75%, to { transform: rotate(-60deg) translateZ(-1px); }
      12.5%, 37.5%, 62.5%, 87.5% { transform: rotate(20deg) translateZ(-1px); }
    }
    @keyframes hamsterBLLimb {
      from, 25%, 50%, 75%, to { transform: rotate(20deg); }
      12.5%, 37.5%, 62.5%, 87.5% { transform: rotate(-60deg); }
    }
    @keyframes hamsterTail {
      from, 25%, 50%, 75%, to { transform: rotate(30deg) translateZ(-1px); }
      12.5%, 37.5%, 62.5%, 87.5% { transform: rotate(10deg) translateZ(-1px); }
    }
    @keyframes spoke {
      from { transform: rotate(0); }
      to { transform: rotate(-1turn); }
    }
    """#
}

/// The Uiverse "svg-frame" loader (CSS by Nawsome). The original ships an SVG
/// whose element IDs the CSS animates; that markup wasn't provided, so the
/// geometry here is authored to match (concentric polygons with the same IDs,
/// yellow on #out3/#center1 per the CSS). The CSS itself is verbatim. TEMP swap
/// in place of `HamsterWheelLoader` — drop in the real <svg> to make it exact.
struct SvgFrameLoader: View {
    private static let render: CGFloat = 344   // the CSS's svg size; scaled to fit

    var body: some View {
        GeometryReader { geo in
            let target = max(8, min(geo.size.width, geo.size.height))
            SvgFrameWebView()
                .frame(width: Self.render, height: Self.render)
                .scaleEffect(target / Self.render)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}

private struct SvgFrameWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 344, height: 344))
        wv.setValue(false, forKey: "drawsBackground")   // transparent
        wv.loadHTMLString(Self.document, baseURL: nil)
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    private static let document = """
    <!doctype html><html><head><meta charset="utf-8"><style>
    html,body{margin:0;padding:0;background:transparent;overflow:hidden;width:344px;height:344px}
    body{display:flex;align-items:center;justify-content:center}
    \(css)
    /* spin each animated layer around the true SVG centre */
    .svg-frame svg #out2,.svg-frame svg #out3,.svg-frame svg #inner1,
    .svg-frame svg #inner3,.svg-frame svg #center,.svg-frame svg #center1{transform-box:view-box}
    </style></head><body>
    <div class="svg-frame">
      <svg viewBox="0 0 344 344" style="--i:1;--j:1">
        <polygon id="out2" points="172,22 302,97 302,247 172,322 42,247 42,97" stroke="#fff" stroke-width="3"/>
        <polygon id="out3" points="297,172 235,280 110,280 47,172 110,64 235,64" stroke-width="4"/>
        <polygon id="inner1" points="172,74 270,172 172,270 74,172" stroke="#fff" stroke-width="3"/>
        <polygon id="inner3" points="172,100 234,136 234,208 172,244 110,208 110,136" stroke="#fff" stroke-width="3"/>
        <polygon id="center" points="172,126 218,172 172,218 126,172" stroke="#fff" stroke-width="3"/>
        <polygon id="center1" points="200,172 186,196 158,196 144,172 158,148 186,148"/>
      </svg>
    </div>
    </body></html>
    """

    /// The CSS exactly as authored (Uiverse.io / Nawsome).
    private static let css = #"""
    .svg-frame {
      position: relative;
      width: 300px;
      height: 300px;
      transform-style: preserve-3d;
      display: flex;
      justify-content: center;
      align-items: center;
    }
    .svg-frame svg {
      position: absolute;
      transition: .5s;
      z-index: calc(1 - (0.2 * var(--j)));
      transform-origin: center;
      width: 344px;
      height: 344px;
      fill: none;
    }
    .svg-frame:hover svg {
      transform: rotate(-80deg) skew(30deg) translateX(calc(45px * var(--i))) translateY(calc(-35px * var(--i)));
    }
    .svg-frame svg #center {
      transition: .5s;
      transform-origin: center;
    }
    .svg-frame:hover svg #center {
      transform: rotate(-30deg) translateX(45px) translateY(-3px);
    }
    #out2 {
      animation: rotate16 7s ease-in-out infinite alternate;
      transform-origin: center;
    }
    #out3 {
      animation: rotate16 3s ease-in-out infinite alternate;
      transform-origin: center;
      stroke: #ff0;
    }
    #inner3,
    #inner1 {
      animation: rotate16 4s ease-in-out infinite alternate;
      transform-origin: center;
    }
    #center1 {
      fill: #ff0;
      animation: rotate16 2s ease-in-out infinite alternate;
      transform-origin: center;
    }
    @keyframes rotate16 {
      to {
        transform: rotate(360deg);
      }
    }
    """#
}

/// The Uiverse "orbit" loader (CSS by mrhyddenn): two counter-spinning arcs
/// (gold + lime) each trailing a glowing dot. Pure CSS + divs (standard markup),
/// run verbatim in a transparent WKWebView. TEMP swap in the working badge.
struct OrbitLoader: View {
    private static let render: CGFloat = 120   // loader is 60px; extra room for the glow

    var body: some View {
        GeometryReader { geo in
            let target = max(8, min(geo.size.width, geo.size.height))
            OrbitWebView()
                .frame(width: Self.render, height: Self.render)
                .scaleEffect(target / Self.render)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}

private struct OrbitWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        wv.setValue(false, forKey: "drawsBackground")   // transparent
        wv.loadHTMLString(Self.document, baseURL: nil)
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    private static let document = """
    <!doctype html><html><head><meta charset="utf-8"><style>
    html,body{margin:0;padding:0;background:transparent;overflow:hidden;width:120px;height:120px}
    body{display:flex;align-items:center;justify-content:center}
    \(css)
    </style></head><body>
    <div class="loader">
      <div class="face"><div class="circle"></div></div>
      <div class="face"><div class="circle"></div></div>
    </div>
    </body></html>
    """

    /// The CSS exactly as authored (Uiverse.io / mrhyddenn).
    private static let css = #"""
    .loader {
      width: 6em;
      height: 6em;
      font-size: 10px;
      position: relative;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .loader .face {
      position: absolute;
      border-radius: 50%;
      border-style: solid;
      animation: animate023845 3s linear infinite;
    }
    .loader .face:nth-child(1) {
      width: 100%;
      height: 100%;
      color: gold;
      border-color: currentColor transparent transparent currentColor;
      border-width: 0.2em 0.2em 0em 0em;
      --deg: -45deg;
      animation-direction: normal;
    }
    .loader .face:nth-child(2) {
      width: 70%;
      height: 70%;
      color: lime;
      border-color: currentColor currentColor transparent transparent;
      border-width: 0.2em 0em 0em 0.2em;
      --deg: -135deg;
      animation-direction: reverse;
    }
    .loader .face .circle {
      position: absolute;
      width: 50%;
      height: 0.1em;
      top: 50%;
      left: 50%;
      background-color: transparent;
      transform: rotate(var(--deg));
      transform-origin: left;
    }
    .loader .face .circle::before {
      position: absolute;
      top: -0.5em;
      right: -0.5em;
      content: '';
      width: 1em;
      height: 1em;
      background-color: currentColor;
      border-radius: 50%;
      box-shadow: 0 0 2em,
                    0 0 4em,
                    0 0 6em,
                    0 0 8em,
                    0 0 10em,
                    0 0 0 0.5em rgba(255, 255, 0, 0.1);
    }
    @keyframes animate023845 {
      to {
        transform: rotate(1turn);
      }
    }
    """#
}

/// The Uiverse "sitNSpin" 3D loader (CSS by Nawsome): two swoosh planes counter-
/// rotating in 3D perspective. The shape is a base64 SVG, recoloured from black
/// to gray (#9ca3af) so it reads on the dark notch. CSS verbatim otherwise, run
/// in a transparent WKWebView. TEMP swap in the working badge.
struct SitSpinLoader: View {
    private static let render: CGFloat = 200   // spinner is 10em≈160px; room for the 3D tilt

    var body: some View {
        GeometryReader { geo in
            let target = max(8, min(geo.size.width, geo.size.height))
            SitSpinWebView()
                .frame(width: Self.render, height: Self.render)
                .scaleEffect(target / Self.render)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}

private struct SitSpinWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        wv.setValue(false, forKey: "drawsBackground")   // transparent
        wv.loadHTMLString(Self.document, baseURL: nil)
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    private static let document = """
    <!doctype html><html><head><meta charset="utf-8"><style>
    html,body{margin:0;padding:0;background:transparent;overflow:hidden;width:200px;height:200px}
    body{display:flex;align-items:center;justify-content:center}
    .spinner{position:relative}
    \(css)
    </style></head><body>
    <div class="spinner"></div>
    </body></html>
    """

    /// The CSS as authored (Uiverse.io / Nawsome), with the SVG fill recoloured
    /// from #000000 to gray (#9ca3af).
    private static let css = #"""
    .spinner:before {
      transform: rotateX(60deg) rotateY(45deg) rotateZ(45deg);
      animation: 750ms rotateBefore infinite linear reverse;
    }
    .spinner:after {
      transform: rotateX(240deg) rotateY(45deg) rotateZ(45deg);
      animation: 750ms rotateAfter infinite linear;
    }
    .spinner:before,
    .spinner:after {
      box-sizing: border-box;
      content: '';
      display: block;
      position: absolute;
      margin-top: -5em;
      margin-left: -5em;
      width: 10em;
      height: 10em;
      transform-style: preserve-3d;
      transform-origin: 50%;
      transform: rotateY(50%);
      perspective-origin: 50% 50%;
      perspective: 340px;
      background-size: 10em 10em;
      background-image: url(data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiIHN0YW5kYWxvbmU9Im5vIj8+Cjxzdmcgd2lkdGg9IjI2NnB4IiBoZWlnaHQ9IjI5N3B4IiB2aWV3Qm94PSIwIDAgMjY2IDI5NyIgdmVyc2lvbj0iMS4xIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rIiB4bWxuczpza2V0Y2g9Imh0dHA6Ly93d3cuYm9oZW1pYW5jb2RpbmcuY29tL3NrZXRjaC9ucyI+CiAgICA8dGl0bGU+c3Bpbm5lcjwvdGl0bGU+CiAgICA8ZGVzY3JpcHRpb24+Q3JlYXRlZCB3aXRoIFNrZXRjaCAoaHR0cDovL3d3dy5ib2hlbWlhbmNvZGluZy5jb20vc2tldGNoKTwvZGVzY3JpcHRpb24+CiAgICA8ZGVmcz48L2RlZnM+CiAgICA8ZyBpZD0iUGFnZS0xIiBzdHJva2U9Im5vbmUiIHN0cm9rZS13aWR0aD0iMSIgZmlsbD0ibm9uZSIgZmlsbC1ydWxlPSJldmVub2RkIiBza2V0Y2g6dHlwZT0iTVNQYWdlIj4KICAgICAgICA8cGF0aCBkPSJNMTcxLjUwNzgxMywzLjI1MDAwMDM4IEMyMjYuMjA4MTgzLDEyLjg1NzcxMTEgMjk3LjExMjcyMiw3MS40OTEyODIzIDI1MC44OTU1OTksMTA4LjQxMDE1NSBDMjE2LjU4MjAyNCwxMzUuODIwMzEgMTg2LjUyODQwNSw5Ny4wNjI0OTY0IDE1Ni44MDA3NzQsODUuNzczNDM0NiBDMTI3LjA3MzE0Myw3NC40ODQzNzIxIDc2Ljg4ODQ2MzIsODQuMjE2MTQ2MiA2MC4xMjg5MDY1LDEwOC40MTAxNTMgQy0xNS45ODA0Njg1LDIxOC4yODEyNDcgMTQ1LjI3NzM0NCwyOTYuNjY3OTY4IDE0NS4yNzczNDQsMjk2LjY2Nzk2OCBDMTQ1LjI3NzM0NCwyOTYuNjY3OTY4IC0yNS40NDkyMTg3LDI1Ny4yNDIxOTggMy4zOTg0Mzc1LDEwOC40MTAxNTUgQzE2LjMwNzA2NjEsNDEuODExNDE3NCA4NC43Mjc1ODI5LC0xMS45OTIyOTg1IDE3MS41MDc4MTMsMy4yNTAwMDAzOCBaIiBpZD0iUGF0aC0xIiBmaWxsPSIjOWNhM2FmIiBza2V0Y2g6dHlwZT0iTVNTaGFwZUdyb3VwIj48L3BhdGg+CiAgICA8L2c+Cjwvc3ZnPg==);
    }
    @keyframes rotateBefore {
      from {
        transform: rotateX(60deg) rotateY(45deg) rotateZ(0deg);
      }
      to {
        transform: rotateX(60deg) rotateY(45deg) rotateZ(-360deg);
      }
    }
    @keyframes rotateAfter {
      from {
        transform: rotateX(240deg) rotateY(45deg) rotateZ(0deg);
      }
      to {
        transform: rotateX(240deg) rotateY(45deg) rotateZ(360deg);
      }
    }
    """#
}

/// The Uiverse flame loader (HTML + CSS by Admin12121): a flickering orange fire
/// with rising ember particles. Markup + CSS verbatim, run in a transparent
/// WKWebView. TEMP swap in the working badge — fits the gun/"still hot" theme.
struct FireLoader: View {
    private static let render: CGFloat = 150   // the flame is 100px; room for shadow + embers

    var body: some View {
        GeometryReader { geo in
            let target = max(8, min(geo.size.width, geo.size.height))
            FireWebView()
                .frame(width: Self.render, height: Self.render)
                .scaleEffect(target / Self.render)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}

private struct FireWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 150, height: 150))
        wv.setValue(false, forKey: "drawsBackground")   // transparent
        wv.loadHTMLString(Self.document, baseURL: nil)
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    private static let document = """
    <!doctype html><html><head><meta charset="utf-8"><style>
    html,body{margin:0;padding:0;background:transparent;overflow:hidden;width:150px;height:150px;position:relative}
    \(css)
    </style></head><body>
    <div class="fire">
      <div class="fire-left"><div class="main-fire"></div><div class="particle-fire"></div></div>
      <div class="fire-center"><div class="main-fire"></div><div class="particle-fire"></div></div>
      <div class="fire-right"><div class="main-fire"></div><div class="particle-fire"></div></div>
      <div class="fire-bottom"><div class="main-fire"></div></div>
    </div>
    </body></html>
    """

    /// The CSS exactly as authored (Uiverse.io / Admin12121).
    private static let css = #"""
    @keyframes scaleUpDown {
      0%, 100% { transform: scaleY(1) scaleX(1); }
      50%, 90% { transform: scaleY(1.1); }
      75% { transform: scaleY(0.95); }
      80% { transform: scaleX(0.95); }
    }
    @keyframes shake {
      0%, 100% { transform: skewX(0) scale(1); }
      50% { transform: skewX(5deg) scale(0.9); }
    }
    @keyframes particleUp {
      0% { opacity: 0; }
      20% { opacity: 1; }
      80% { opacity: 1; }
      100% { opacity: 0; top: -100%; transform: scale(0.5); }
    }
    @keyframes glow {
      0%, 100% { background-color: #ef5a00; }
      50% { background-color: #ff7800; }
    }
    .fire {
      position: absolute;
      top: calc(50% - 50px);
      left: calc(50% - 50px);
      width: 100px;
      height: 100px;
      background-color: transparent;
      margin-left: auto;
      margin-right: auto;
    }
    .fire-center {
      position: absolute;
      height: 100%;
      width: 100%;
      animation: scaleUpDown 3s ease-out;
      animation-iteration-count: infinite;
      animation-fill-mode: both;
    }
    .fire-center .main-fire {
      position: absolute;
      width: 100%;
      height: 100%;
      background-image: radial-gradient(farthest-corner at 10px 0, #d43300 0%, #ef5a00 95%);
      transform: scaleX(0.8) rotate(45deg);
      border-radius: 0 40% 60% 40%;
      filter: drop-shadow(0 0 10px #d43322);
    }
    .fire-center .particle-fire {
      position: absolute;
      top: 60%;
      left: 45%;
      width: 10px;
      height: 10px;
      background-color: #ef5a00;
      border-radius: 50%;
      filter: drop-shadow(0 0 10px #d43322);
      animation: particleUp 2s ease-out 0;
      animation-iteration-count: infinite;
      animation-fill-mode: both;
    }
    .fire-right {
      height: 100%;
      width: 100%;
      position: absolute;
      animation: shake 2s ease-out 0;
      animation-iteration-count: infinite;
      animation-fill-mode: both;
    }
    .fire-right .main-fire {
      position: absolute;
      top: 15%;
      right: -25%;
      width: 80%;
      height: 80%;
      background-color: #ef5a00;
      transform: scaleX(0.8) rotate(45deg);
      border-radius: 0 40% 60% 40%;
      filter: drop-shadow(0 0 10px #d43322);
    }
    .fire-right .particle-fire {
      position: absolute;
      top: 45%;
      left: 50%;
      width: 15px;
      height: 15px;
      background-color: #ef5a00;
      transform: scaleX(0.8) rotate(45deg);
      border-radius: 50%;
      filter: drop-shadow(0 0 10px #d43322);
      animation: particleUp 2s ease-out 0;
      animation-iteration-count: infinite;
      animation-fill-mode: both;
    }
    .fire-left {
      position: absolute;
      height: 100%;
      width: 100%;
      animation: shake 3s ease-out 0;
      animation-iteration-count: infinite;
      animation-fill-mode: both;
    }
    .fire-left .main-fire {
      position: absolute;
      top: 15%;
      left: -20%;
      width: 80%;
      height: 80%;
      background-color: #ef5a00;
      transform: scaleX(0.8) rotate(45deg);
      border-radius: 0 40% 60% 40%;
      filter: drop-shadow(0 0 10px #d43322);
    }
    .fire-left .particle-fire {
      position: absolute;
      top: 10%;
      left: 20%;
      width: 10%;
      height: 10%;
      background-color: #ef5a00;
      border-radius: 50%;
      filter: drop-shadow(0 0 10px #d43322);
      animation: particleUp 3s infinite ease-out 0;
      animation-fill-mode: both;
    }
    .fire-bottom .main-fire {
      position: absolute;
      top: 30%;
      left: 20%;
      width: 75%;
      height: 75%;
      background-color: #ff7800;
      transform: scaleX(0.8) rotate(45deg);
      border-radius: 0 40% 100% 40%;
      filter: blur(10px);
      animation: glow 2s ease-out 0;
      animation-iteration-count: infinite;
      animation-fill-mode: both;
    }
    """#
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

/// Static SVG icons loaded from ~/Downloads (AppKit renders SVG natively).
enum SVGAsset {
    static let sleep: NSImage? = load("sleep.svg")

    private static func load(_ name: String) -> NSImage? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads").appendingPathComponent(name)
        let img = NSImage(contentsOf: url)
        img?.isTemplate = true   // render as a tintable mask
        return img
    }
}

/// Gunshot SFX for the siphon — `gun-reload.mp3` when a session starts work,
/// `gun-shot.mp3` when one finishes. Loaded once from ~/Downloads.
enum SoundFX {
    static let reload = make("gun-reload-3.mp3", volume: 0.5)
    static let shot = make("gun-shot.mp3", volume: 1.0)
    /// Played when a session starts waiting on the user (needs input).
    static let waiting = make("awp-shot.mp3", volume: 1.0)
    /// The "flick the cylinder" widget — the revolver spins to a stop.
    static let spin = make("revolver-spin.mp3", volume: 1.0)

    /// `volume` is 0.0–1.0 (fraction of the file's full level).
    private static func make(_ filename: String, volume: Float = 1.0) -> AVAudioPlayer? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads").appendingPathComponent(filename)
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

// SessionDockPanel.swift — an always-on horizontal strip of session
// squares pinned to the bottom-right corner of the active screen.
//
// Each square is one live agent session, tinted by its activity state.
// Clicking a square calls `engine.focus(session)` — the same jump-to-
// terminal action the expanded panel's rows and the toasts use — so the
// dock is a permanent, glanceable launcher into every running agent.
//
// Like the notch and toast panels this is a borderless, non-activating
// NSPanel drawn on top of everything (it is NOT a system UI element).
// It sizes itself to its content via a SwiftUI size preference and
// re-anchors to the bottom-right whenever the content or screen changes.

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import SwiftUI

// MARK: - Global hot key (Carbon)

extension Notification.Name {
    /// Posted from the Carbon hot-key callback when ⌃⌥D is pressed.
    static let agentTabToggleDock = Notification.Name("AgentTAB.ToggleDock")
    /// Posted by `ActivityEngine` when a session crosses a notify-worthy
    /// threshold (needs input / finished / urgent-still-waiting). The dock
    /// listens and fires its cannon: the firing square launches a tracer
    /// upward that lands as a toast card above the strip. Replaces the
    /// teammate's top-right `ToastPanel`. `object` is a `DockEventPayload`.
    static let agentTabSessionEvent = Notification.Name("AgentTAB.SessionEvent")
    /// Posted by `ActivityEngine` when a sub-agent (Agent/Task tool) finishes
    /// for a session — distinct from a real completion. The dock flicks a spent
    /// brass casing off that session's square (no toast, no sound). `object` is
    /// the session's `UUID`.
    static let agentTabSubagentDone = Notification.Name("AgentTAB.SubagentDone")
}

/// The three notify-worthy situations the dock surfaces, carried over 1:1
/// from the old `Toast.Variant` so the engine's trigger points map cleanly.
enum DockToastVariant {
    case attention   // amber — agent needs input
    case success     // green — task complete
    case urgent      // pink  — urgent agent finished, still unattended
}

/// Payload posted on `.agentTabSessionEvent`. Plain values (the session's
/// stable `id` plus pre-rendered display strings) so the dock never has to
/// reach back into the engine to render the card.
struct DockEventPayload {
    let sessionId: UUID
    let variant: DockToastVariant
    let taskId: String
    let projectName: String
    let message: String
}

private var dockHotKeyRef: EventHotKeyRef?
private var dockHotKeyHandler: EventHandlerRef?

/// Registers ⌃⌥⌘V as a system-wide hot key via the Carbon Event Manager.
/// Unlike an NSEvent global keyboard monitor, this needs no Accessibility
/// permission, so the shortcut works the moment the app launches. The
/// four-key chord avoids two-modifier conflicts, and V sits right above the
/// ⌃⌥⌘ cluster so the whole thing is a one-handed left-hand grip. The
/// handler simply posts `.agentTabToggleDock`.
@MainActor
func registerDockHotKey() {
    guard dockHotKeyRef == nil else { return }

    var eventType = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
    )
    let callback: EventHandlerUPP = { _, _, _ in
        NotificationCenter.default.post(name: .agentTabToggleDock, object: nil)
        return noErr
    }
    InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, nil, &dockHotKeyHandler)

    let hotKeyID = EventHotKeyID(signature: OSType(0x4154_4442), id: 1)  // 'ATDB'
    RegisterEventHotKey(
        UInt32(kVK_ANSI_V),
        UInt32(controlKey | optionKey | cmdKey),
        hotKeyID,
        GetApplicationEventTarget(),
        0,
        &dockHotKeyRef
    )
}

/// Collapse state shared by the chevron button and the global hotkey, so
/// either can toggle the dock and the SwiftUI view reacts. Persisted so
/// the dock reopens in whatever state you left it.
@MainActor
final class DockState: ObservableObject {
    @Published var collapsed: Bool
    private static let key = "AgentTAB.dock.collapsed"
    /// Coalesces near-simultaneous toggles so the Carbon hot key and the
    /// NSEvent monitor firing on the same keypress count as one.
    private var lastToggle = Date.distantPast

    init() { collapsed = UserDefaults.standard.bool(forKey: Self.key) }

    func toggle() {
        let now = Date()
        guard now.timeIntervalSince(lastToggle) > 0.25 else { return }
        lastToggle = now
        collapsed.toggle()
        UserDefaults.standard.set(collapsed, forKey: Self.key)
    }
}

@MainActor
final class SessionDockPanel: NSPanel {
    /// Gap from the screen's visible corner (kept clear of the menu bar
    /// and the macOS Dock by using `visibleFrame`).
    private static let edgeInset: CGFloat = 16

    private var currentScreen: NSScreen?
    private var contentSize: CGSize = .zero

    let dockState = DockState()
    private var hotKeyObserver: NSObjectProtocol?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
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
        self.isReleasedWhenClosed = false
        // The dock is interactive (squares are buttons). It's content-sized
        // so there's almost no transparent margin to swallow stray clicks.
        self.ignoresMouseEvents = false
        self.hidesOnDeactivate = false

        installToggleHotkey()
    }

    deinit {
        if let o = hotKeyObserver { NotificationCenter.default.removeObserver(o) }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m) }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m) }
    }

    // Never steal key/main focus — clicking a square must keep the user's
    // terminal app frontmost so `focus()` can swap straight to it.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// ⌃⌥⌘V collapse / expand, wired two independent ways so it's robust:
    ///   1. A Carbon hot key (`RegisterEventHotKey`) — permission-free, but
    ///      silently fails if another app already owns the combo.
    ///   2. NSEvent global + local monitors — universal, but need Input-
    ///      Monitoring / Accessibility permission (which we prompt for).
    /// `DockState.toggle()` debounces so both firing on one press = one flip.
    private func installToggleHotkey() {
        registerDockHotKey()
        hotKeyObserver = NotificationCenter.default.addObserver(
            forName: .agentTabToggleDock, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dockState.toggle() }
        }

        promptForInputMonitoringIfNeeded()
        let isToggle: (NSEvent) -> Bool = { event in
            event.keyCode == UInt16(kVK_ANSI_V) &&
            event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.control, .option, .command]
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard isToggle(event) else { return }
            DispatchQueue.main.async { self?.dockState.toggle() }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard isToggle(event) else { return event }
            DispatchQueue.main.async { self?.dockState.toggle() }
            return nil
        }
    }

    /// Shows the system Accessibility prompt (and adds AgentTAB to the
    /// list) the first time, so the NSEvent keyboard monitors are allowed
    /// to fire. No-op once already trusted.
    private func promptForInputMonitoringIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Install the SwiftUI strip, wired to the shared activity engine.
    func install(engine: ActivityEngine) {
        let root = SessionDockView(onSizeChange: { [weak self] size in
            self?.resize(to: size)
        })
        .environmentObject(engine)
        .environmentObject(dockState)

        let host = NSHostingView(rootView: AnyView(root))
        host.frame = NSRect(origin: .zero, size: self.frame.size)
        host.autoresizingMask = [.width, .height]
        self.contentView = host
    }

    /// Re-anchor to a specific screen (called on launch and on every
    /// follow-cursor screen change).
    func reposition(to screen: NSScreen) {
        currentScreen = screen
        anchorBottomRight()
    }

    private func resize(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        contentSize = size
        setContentSize(size)
        anchorBottomRight()
    }

    private func anchorBottomRight() {
        guard let screen = currentScreen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = contentSize == .zero ? frame.size : contentSize
        // Right side is glued to the physical screen edge (no inset). Use
        // `frame.maxX`, not `visibleFrame.maxX`, so it hugs the true edge.
        let origin = NSPoint(
            x: screen.frame.maxX - size.width,
            y: visible.minY + Self.edgeInset
        )
        setFrameOrigin(origin)
    }
}

// MARK: - SwiftUI strip

private struct DockSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Sentinel key under which the revolver publishes its muzzle point into the
/// shared `SquareCenterKey` anchor dictionary — so the cannon layer can aim
/// the feed tracer, park the smoke, and float the toast all off one anchor.
private let dockMuzzleAnchorID = UUID()

struct SessionDockView: View {
    @EnvironmentObject var engine: ActivityEngine
    @EnvironmentObject var dock: DockState
    var onSizeChange: (CGSize) -> Void = { _ in }

    private static let square: CGFloat = 36
    private static let gap: CGFloat = 6
    private static let pad: CGFloat = 7
    /// Squares per row before wrapping up into a new row. Fixed (not balanced)
    /// so each tab keeps a stable position — muscle memory over symmetry.
    private static let perRow: Int = 6
    /// Transparent headroom reserved above the strip so the muzzle smoke + the
    /// card (and its upward stack of older cards) have room above the drawer.
    /// Constant — see the body comment on why it must never toggle.
    private static let deckHeadroom: CGFloat = 120

    // MARK: Cannon / toast state
    //
    // When a session crosses a notify threshold the engine posts
    // `.agentTabSessionEvent`. `fire(_:)` reserves headroom above the strip
    // (so the panel grows upward), launches a tracer from the firing
    // square, and pops the toast card on impact.

    /// The notification STACK — newest at index 0 (the front). A burst stacks
    /// (newest in front, older slides back + dims) instead of overriding; each
    /// card auto-dismisses after a few seconds.
    @State private var toasts: [DockToast] = []
    /// In-flight tracers (usually one). Removed once they reach the card.
    @State private var shots: [CannonShot] = []
    /// How many cards show before the rest collapse into a "+N" chip.
    private static let maxStack = 3
    /// Bumped on every notification to make the revolver FIRE (cylinder click
    /// + muzzle flash). The gun is now the single muzzle every toast comes out
    /// of, so this — not the in-flight count — is the authoritative "fire".
    @State private var revolverFire = 0
    /// Bumped when input arrives (the working count rises) → a magma comet rises
    /// from the bottom up to the middle of the left bar (loading the chamber).
    @State private var inputPulse = 0
    /// Bumped when a session FINISHES (.success) → a magma comet leaves the middle
    /// of the left bar, up over the top, and out the end (firing the round).
    @State private var shootPulse = 0

    /// Matches the notch shooter's `shootDelay`: the gun "poses" this long
    /// before the gunshot sound + bullet fire, so the dock shell launches on
    /// the same beat and the two stay in sync.
    private static let shootDelay: TimeInterval = 0.5

    private var sessions: [Session] {
        // Positional order — by Zellij tab number — so a square's position is
        // stable and mirrors the terminal tab bar's muscle memory. Urgency is
        // surfaced by colour/glow, NOT by moving things around (which broke
        // "I just know where it is").
        return engine.displaySessions
            .map { (session: $0, key: tabOrder($0)) }
            .sorted { $0.key < $1.key }
            .map(\.session)
    }

    /// (major, minor) sort key from the Zellij tab label: "6.1" → (6, 1),
    /// "4" → (4, 0). Sessions without a numeric label sort to the end.
    private func tabOrder(_ session: Session) -> (Int, Int) {
        let parts = engine.displayLabel(for: session).split(separator: ".")
        let major = parts.first.flatMap { Int($0) } ?? Int.max
        let minor = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return (major, minor)
    }

    /// Count of agents actively WORKING (input has been sent, still running).
    /// A rise in this means new input arrived → drives the "loading" comet.
    private func workingCount(_ sessions: [Session]) -> Int {
        sessions.reduce(into: 0) { n, s in
            switch s.activity {
            case .thinking, .tool, .initState: n += 1
            default: break
            }
        }
    }

    /// Cheap identity/order token for the layout animation. Hashes the session
    /// ids without allocating an intermediate `[UUID]` every body evaluation
    /// (the old `sessions.map(\.id)` minted a fresh array each render).
    private func layoutToken(_ sessions: [Session]) -> Int {
        var hasher = Hasher()
        for s in sessions { hasher.combine(s.id) }
        return hasher.finalize()
    }

    var body: some View {
        let sessions = self.sessions
        // The muzzle deck. Below: the strip (chevron · revolver · squares),
        // right-glued. Above: headroom the smoke + card erupt into. The panel
        // is bottom-anchored, so reserving headroom grows the window UPWARD.
        VStack(alignment: .trailing, spacing: 0) {
            // Reserve the headroom UNCONDITIONALLY, in BOTH states. Toggling it
            // per-toast (the old collapsed path inserted the card into the flow
            // only when a toast existed) resized the dock window every time a
            // notification came and went — a DockSizeKey → resize() → re-anchor
            // feedback loop that made the drawer jitter. The space is transparent,
            // so a constant window size is free. A touch wider than the card so it
            // never clips against the right-glued edge when the strip is narrow
            // (collapsed, or only a few sessions).
            Color.clear.frame(width: DockToastCard.width + 28, height: Self.deckHeadroom)
            strip(sessions)
        }
        // FX layer (non-interactive): the muzzle smoke + the tracer that feeds
        // the gun from the finishing square. Both aim at the revolver muzzle,
        // published into the same anchor dict under `dockMuzzleAnchorID`.
        .overlayPreferenceValue(SquareCenterKey.self) { centers in
            GeometryReader { geo in
                let muzzle = dock.collapsed ? nil : centers[dockMuzzleAnchorID].map { geo[$0] }
                ZStack {
                    // Smoke rises from the GUN — the spent round's exhaust
                    // collects at the muzzle for the whole notification.
                    if let front = toasts.first, let m = muzzle {
                        SmokePuff(origin: m, restartKey: front.id)
                            .id(front.id)
                    }
                    // The gun fires the round toward the notification's anchor.
                    ForEach(shots) { shot in
                        if let m = muzzle {
                            CannonProjectile(
                                start: m,
                                target: cardLanding(panelWidth: geo.size.width),
                                accent: shot.accent
                            )
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
        // Card layer (interactive): the toast is pulled in from the right edge
        // and rests just above the drawer. Its own overlay so it stays tappable.
        .overlay {
            GeometryReader { geo in
                if !toasts.isEmpty {
                    notificationStack(panelWidth: geo.size.width)
                }
            }
        }
        .fixedSize()
        .background(
            GeometryReader { g in
                Color.clear.preference(key: DockSizeKey.self, value: g.size)
            }
        )
        .onPreferenceChange(DockSizeKey.self) { onSizeChange($0) }
        .onReceive(NotificationCenter.default.publisher(for: .agentTabSessionEvent)) { note in
            if let payload = note.object as? DockEventPayload { fire(payload) }
        }
        // Input arriving = the count of WORKING agents rising → fire the "loading"
        // comet up from the bottom to the chamber (middle of the left bar).
        .onChange(of: workingCount(sessions)) { old, new in
            if new > old { inputPulse += 1 }
        }
        .animation(.easeOut(duration: 0.18), value: layoutToken(sessions))
        .animation(.easeOut(duration: 0.20), value: dock.collapsed)
    }

    /// The notification anchor — pinned to the panel's right edge (glued to the
    /// screen edge), so the card hugs the right and never drifts with session count.
    private func cardAnchorX(panelWidth: CGFloat) -> CGFloat {
        panelWidth - DockToastCard.width / 2 - 12
    }
    private func cardAnchorY() -> CGFloat {
        // Rest the FRONT card just above the drawer's top edge. The strip always
        // begins at the bottom of the fixed headroom, so this lands correctly
        // whether the drawer is one row or two. Older cards stack UP from here.
        Self.deckHeadroom - DockToastCard.height / 2 - 3
    }

    /// Where the tracer should land — the front card's resting centre. The gun
    /// fires a tracer from the muzzle up to this anchor as the card pulls in.
    private func cardLanding(panelWidth: CGFloat) -> CGPoint {
        CGPoint(x: cardAnchorX(panelWidth: panelWidth), y: cardAnchorY())
    }

    /// The notification stack: newest in front; older cards slide back (up),
    /// shrink and dim. Beyond `maxStack`, a "+N" chip rides the back.
    @ViewBuilder
    private func notificationStack(panelWidth: CGFloat) -> some View {
        ZStack {
            ForEach(Array(toasts.prefix(Self.maxStack).enumerated()), id: \.element.id) { idx, t in
                let depth = CGFloat(idx)
                DockToastCard(toast: t, onTap: { tapToast(t) })
                    .scaleEffect(1 - depth * 0.05, anchor: .top)
                    .offset(y: -depth * 7)
                    .opacity(1 - Double(idx) * 0.30)
                    .allowsHitTesting(idx == 0)
                    .zIndex(Double(Self.maxStack - idx))
                    // Pulled in from the right screen edge (a drawer-pull), then
                    // fades out on dismiss.
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity))
            }
            if toasts.count > Self.maxStack {
                Text("+\(toasts.count - Self.maxStack)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.black.opacity(0.65)))
                    .offset(y: -CGFloat(Self.maxStack) * 7 - 5)
                    .zIndex(100)
            }
        }
        .position(x: cardAnchorX(panelWidth: panelWidth), y: cardAnchorY())
    }

    /// The strip itself — the always-present horizontal handle + squares,
    /// inside the rounded black container with its three-sided border.
    private func strip(_ sessions: [Session]) -> some View {
        // Loaded rounds = agents in flight (working, or waiting on you).
        let inFlight = sessions.reduce(into: 0) { n, s in
            switch s.activity {
            case .thinking, .tool, .initState, .waiting: n += 1
            default: break
            }
        }
        let needsYou = sessions.contains { $0.activity == .waiting }
        // The revolver scales with the number of square rows so it never looks
        // dwarfed by a tall two-row magazine: its frame tracks the grid height.
        let rows = dock.collapsed
            ? 1
            : max(1, Int(ceil(Double(sessions.count) / Double(Self.perRow))))
        let gridH = CGFloat(rows) * Self.square + CGFloat(rows - 1) * Self.gap
        let revSize = (gridH * 0.95 + 22) * 0.85   // 15% smaller than the grid-tracked size
        let revolver = RevolverCylinder(inFlight: inFlight, needsYou: needsYou,
                                        firePulse: revolverFire, size: revSize)
        // No chevron in either state (⌃⌥⌘V toggles). Collapsed shows just the
        // revolver; expanded adds the squares.
        return HStack(spacing: Self.gap) {
            revolver
            if !dock.collapsed {
                grid(sessions)
            }
        }
        .padding(.vertical, Self.pad)
        // Tighter horizontal padding when collapsed so the handle hugs the
        // chevron (smaller footprint, chevron reads centered).
        .padding(.horizontal, dock.collapsed ? 5 : Self.pad)
        .background(
            containerShape
                .fill(Color.black.opacity(0.85))
                // Warm ember wash — the interior reads as coals glowing inside a
                // dark furnace rather than a cold black box, tying it to the magma
                // frame. Rises from the bottom (heat rising) and brightens with the
                // load, like the river. STATIC (no clock) — costs nothing at rest.
                .overlay(
                    containerShape
                        .fill(LinearGradient(
                            colors: [Magma.ember.opacity(0.18 * (0.5 + 0.5 * DockMagma.heat(active: inFlight))),
                                     Magma.deep.opacity(0.07 * (0.5 + 0.5 * DockMagma.heat(active: inFlight))),
                                     .clear],
                            startPoint: .bottom, endPoint: .top))
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                )
                .overlay(
                    // Border on TOP + LEFT + BOTTOM only (right is glued to the
                    // screen edge). Cold gray at rest; when work starts the molten
                    // frame connects in from the two ends and meets in the middle
                    // (the river's merge), retracting when the last agent quiets.
                    ForgeBorder(active: inFlight)
                )
                // Magma comets riding the same border path: input LOADS the chamber
                // (bottom-right → middle of the left bar), a finish FIRES it out
                // (middle of the left bar → over the top → end). The input comet is
                // synced to the merge curve so it rides the river's bottom front.
                .overlay(BorderComet(start: 1.0, end: 0.5, trigger: inputPulse,
                                     animation: .easeInOut(duration: 0.7)))
                .overlay(BorderComet(start: 0.5, end: 0.0, trigger: shootPulse))
                // Muzzle spark pop when the shoot comet fires out the top-right.
                .overlay(MuzzleSparks(trigger: shootPulse))
        )
        // Room for the flare "horns" (vertical) AND the border's left-corner
        // bloom (leading) to extend beyond the box without the content-sized,
        // right-glued panel clipping them — otherwise the glow gets sliced by a
        // straight window edge and the rounded corners read as 90° turns.
        .padding(.vertical, 8)
        .padding(.leading, 9)
    }


    // MARK: Cannon firing

    /// Handle one notify event. Holds for `shootDelay` so the shell launches
    /// on the same beat as the notch gunshot, then fires the cannon — unless a
    /// newer event has superseded this one in the meantime.
    private func fire(_ payload: DockEventPayload) {
        // Each event fires its own cannon into the stack — no superseding guard,
        // so a burst stacks instead of overriding.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shootDelay) {
            launchCannon(payload)
        }
    }

    /// Reserve the card slot, launch a tracer from the firing square, land the
    /// card on impact, then auto-dismiss.
    private func launchCannon(_ payload: DockEventPayload) {
        let accent = Self.accent(for: payload.variant)

        let next = DockToast(
            sessionId: payload.sessionId,
            taskId: payload.taskId,
            project: payload.projectName,
            message: payload.message,
            headline: Self.headline(for: payload.variant),
            accent: accent
        )
        // Click the revolver (cylinder turn + flash) as the round chambers, and
        // pull the new card in from the right onto the FRONT of the stack (older
        // ones slide back). A hard cap guards memory.
        revolverFire += 1
        // A FINISH fires the "shoot" comet up over the top and out the end.
        if payload.variant == .success { shootPulse += 1 }
        withAnimation(.spring(response: 0.40, dampingFraction: 0.78)) {
            toasts.insert(next, at: 0)
            if toasts.count > 8 { toasts.removeLast() }
        }

        if !dock.collapsed {
            // The finishing square fires a tracer into the muzzle; the smoke
            // billows from the gun as the card pulls in.
            let shot = CannonShot(sessionId: payload.sessionId, accent: accent)
            shots = [shot]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                shots.removeAll { $0.id == shot.id }
            }
        }

        // Auto-dismiss this card after a few seconds (oldest clears first).
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
            withAnimation(.easeOut(duration: 0.3)) {
                toasts.removeAll { $0.id == next.id }
            }
        }
    }

    /// Card tap — jump to the originating terminal tab and dismiss, mirroring
    /// the old toast's tap-through behaviour (plus the notch peek request).
    private func tapToast(_ t: DockToast) {
        NotificationCenter.default.post(name: .agentTabRequestPeek, object: nil)
        if let s = engine.displaySessions.first(where: { $0.id == t.sessionId }) {
            engine.focus(s)
        }
        withAnimation(.easeOut(duration: 0.2)) {
            toasts.removeAll { $0.id == t.id }
        }
    }

    static func accent(for v: DockToastVariant) -> Color {
        switch v {
        case .attention: return Theme.Neon.amber
        case .success:   return Theme.Neon.green
        case .urgent:    return Theme.Neon.pink
        }
    }

    /// Themed status line for the shell card — short, naturally-capitalised
    /// phrasing (not all-caps, not all-lowercase).
    static func headline(for v: DockToastVariant) -> String {
        switch v {
        case .attention: return "Needs You"
        case .success:   return "Finished"
        case .urgent:    return "Still Hot"
        }
    }

    /// Container outline. The dock is glued to the right screen edge in
    /// both states, so its right corners are always square — only the left
    /// corners are rounded.
    private var containerShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 14,
            bottomLeadingRadius: 14,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    /// Sessions laid out left-to-right, wrapping into stacked rows. Row 0 (the
    /// first, fully-filled row) sits at the TOP; new sessions overflow onto
    /// fresh rows BELOW it, filling each row from the LEFT (a partial last row
    /// sits under the first column, not flush to the right edge).
    @ViewBuilder
    private func grid(_ sessions: [Session]) -> some View {
        if sessions.isEmpty {
            emptySlot
        } else {
            let rows = stride(from: 0, to: sessions.count, by: Self.perRow).map {
                Array(sessions[$0 ..< min($0 + Self.perRow, sessions.count)])
            }
            VStack(alignment: .leading, spacing: Self.gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: Self.gap) {
                        ForEach(row) { session in
                            SessionSquare(
                                size: Self.square,
                                initials: Self.initials(for: session, engine: engine),
                                number: engine.displayLabel(for: session),
                                stateColor: Self.bodyColor(for: session),
                                identityColor: Self.identityColor(for: engine.displayName(for: session)),
                                name: engine.displayName(for: session),
                                activity: session.activity,
                                pulsing: session.activity == .waiting,
                                subdued: !Self.isLit(session),
                                onTap: { engine.focus(session) }
                            )
                            // Publish this square's centre so the cannon can
                            // launch a tracer from it on a notify event.
                            .anchorPreference(key: SquareCenterKey.self, value: .center) {
                                [session.id: $0]
                            }
                        }
                    }
                }
            }
        }
    }

    /// Placeholder shown when nothing is running, so the dock is always
    /// present at the corner (per spec) instead of vanishing.
    private var emptySlot: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(width: Self.square, height: Self.square)
            .overlay(
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 4, height: 4)
            )
    }

    // Two distinct, vivid greens for the dock so "just finished" vs
    // "done, sitting there" both read clearly green and never blur into
    // the dormant grays. Brighter + more saturated than the panel's
    // shared Activity greens (which the 0.22 square fill washed out).
    static let doneGreen = Color(red: 0x66 / 255.0, green: 0xF4 / 255.0, blue: 0x9E / 255.0)
    static let idleGreen = Color(red: 0x22 / 255.0, green: 0xC8 / 255.0, blue: 0x82 / 255.0)
    // "Working" is COOL STEEL resting in the forge — a muted slate-blue, not the
    // old icy neon. It deliberately CONTRASTS the warm frame + ember wash + brass
    // rounds (warm = heat/activity at the edges, cool = the calm work tiles), and
    // stays clearly distinct from amber "needs-you" and green "done".
    static let workingSteel = Color(red: 0.46, green: 0.60, blue: 0.78)

    static func color(for activity: Activity) -> Color {
        switch activity {
        case .thinking, .tool: return workingSteel
        case .waiting:         return Theme.Activity.waiting
        case .done:            return doneGreen
        case .initState:       return Theme.Activity.initState
        case .idle:            return idleGreen
        }
    }

    /// Neutral gray for long-untouched ("older finished") squares — the
    /// dock mirror of the panel's dormant row tint.
    static let dormantGray = Color(white: 0.58)

    /// A session that has aged out of "recently active" into OLDER FINISHED
    /// — done/idle past the recent window (or a stalled start). Urgent
    /// sessions never age out, matching the engine's predicate.
    static func isDormant(_ session: Session) -> Bool {
        if session.priority == .urgent { return false }
        let age = Date().timeIntervalSince(session.lastUpdate)
        switch session.activity {
        case .done, .idle: return age > ActivityEngine.recentFinishedWindow
        case .initState:   return true
        default:           return false
        }
    }

    /// Above-default priority (High/Urgent). Its color replaces GREEN as
    /// the finished-state color — so a finished important agent reads as
    /// violet/red instead of a generic green completion.
    static func isElevated(_ session: Session) -> Bool {
        session.priority.rawValue > Priority.default.rawValue
    }

    /// Body color for a square. While it's WORKING / WAITING / STARTING it
    /// always shows its activity-state color (you need to see what it's
    /// doing). Only once it's FINISHED does priority come into play: an
    /// elevated agent paints its priority color in place of green;
    /// everything else stays green, or gray once it goes dormant.
    static func bodyColor(for session: Session) -> Color {
        // High/Urgent always show their priority colour — a deliberate "this
        // matters" that stays visible in any state.
        if isElevated(session) { return session.priority.color }
        switch session.activity {
        case .waiting:
            return color(for: .waiting)               // amber — needs your input
        case .done:
            return isDormant(session) ? dormantGray : doneGreen   // green — just finished
        case .idle:
            return dormantGray                        // settled — nothing for you
        case .thinking, .tool, .initState:
            return workingSteel                       // cool steel — calm work tile
        }
    }

    /// "Lit" squares pull focus (full colour + a resting glow): they want you
    /// — waiting for input, or freshly finished — plus High/Urgent which stay
    /// lit in any state. Working / idle / dormant squares stay quiet so a
    /// glance lands only on what needs you.
    static func isLit(_ session: Session) -> Bool {
        if isElevated(session) { return true }
        switch session.activity {
        case .waiting: return true
        case .done:    return !isDormant(session)
        default:       return false
        }
    }

    /// 2-char token from the agent's name: initials of the first two
    /// word-segments (`mitar-booking` → `mb`), or the first two letters of
    /// a single-word name (`scratch` → `sc`). Falls back to the tab number.
    static func initials(for session: Session, engine: ActivityEngine) -> String {
        let name = engine.displayName(for: session)
        let segments = name.split { !$0.isLetter && !$0.isNumber }
        let token: String
        if segments.count >= 2 {
            token = String(segments[0].prefix(1) + segments[1].prefix(1))
        } else if let first = segments.first {
            token = String(first.prefix(2))
        } else {
            token = engine.displayLabel(for: session)
        }
        return token.isEmpty ? engine.displayLabel(for: session) : token.uppercased()
    }

    /// Stable, vivid identity color hashed from the agent's name — the
    /// same name always maps to the same hue, so a square's stripe color
    /// is a learnable "who" signal independent of its activity state.
    static func identityColor(for name: String) -> Color {
        var hash = 5381
        for byte in name.utf8 { hash = (hash &* 33) &+ Int(byte) }
        let hue = Double(((hash % 360) + 360) % 360) / 360.0
        return Color(hue: hue, saturation: 0.62, brightness: 0.95)
    }
}

/// The canonical magma palette — ONE source of truth for the app's lava look,
/// anchored on the notch river's signature stops. The notch river uses these
/// named colours directly; the dock heat ramp (`DockMagma`) re-bases its HOT
/// end on the same RGB, so the two read as the exact same molten material.
enum Magma {
    // Raw components are the source of truth (so both a SwiftUI `Color` and the
    // dock's interpolated ramp can be built from the identical numbers).
    static let deepRGB:  (r: Double, g: Double, b: Double) = (0.80, 0.09, 0.00) // deep-red base
    static let bodyRGB:  (r: Double, g: Double, b: Double) = (1.00, 0.40, 0.05) // hot-orange body
    static let goldRGB:  (r: Double, g: Double, b: Double) = (1.00, 0.66, 0.18) // gold bloom
    static let coreRGB:  (r: Double, g: Double, b: Double) = (1.00, 0.86, 0.50) // gold-white core
    static let whiteRGB: (r: Double, g: Double, b: Double) = (1.00, 0.95, 0.82) // white-hot
    static let emberRGB: (r: Double, g: Double, b: Double) = (1.00, 0.26, 0.04) // wide red-orange bloom

    static var deep:  Color { color(deepRGB) }
    static var body:  Color { color(bodyRGB) }
    static var gold:  Color { color(goldRGB) }
    static var core:  Color { color(coreRGB) }
    static var white: Color { color(whiteRGB) }
    static var ember: Color { color(emberRGB) }

    static func color(_ c: (r: Double, g: Double, b: Double)) -> Color {
        Color(red: c.r, green: c.g, blue: c.b)
    }
}

/// Shared magma "heat ramp" for the dock — maps the number of in-flight agents
/// to a colour from idle-ember up to white-hot, so the border, revolver and
/// squares all read the same load temperature.
enum DockMagma {
    // A real THERMAL ramp — cold metal heating up. Cold steel-blue when barely
    // loaded (a clean step from the gray idle, no muddy orange), then the HOT
    // end is the notch river's EXACT lava (gold → gold-white core → white-hot),
    // so the drawer and the river read as the same molten material.
    private static let stops: [(h: Double, r: Double, g: Double, b: Double)] = [
        (0.00, 0.30, 0.36, 0.46),                                          // cold steel-blue — the "cold" tail
        (0.42, 0.47, 0.50, 0.53),                                          // cool neutral bridge
        (0.64, Magma.goldRGB.r,  Magma.goldRGB.g,  Magma.goldRGB.b),       // gold (river-matched)
        (0.84, Magma.coreRGB.r,  Magma.coreRGB.g,  Magma.coreRGB.b),       // gold-white core (river-matched)
        (1.00, Magma.whiteRGB.r, Magma.whiteRGB.g, Magma.whiteRGB.b),      // white-hot (river-matched)
    ]

    /// In-flight count → heat 0…1 (ramps up fast, eases toward 1).
    static func heat(active: Int) -> Double {
        guard active > 0 else { return 0 }
        return min(1.0, 1.0 - pow(0.66, Double(active)))   // gentler — 1→.34, 2→.56, 3→.71, …
    }

    static func color(_ heat: Double) -> Color {
        let h = min(1, max(0, heat))
        var lo = stops[0], hi = stops[stops.count - 1]
        for i in 1 ..< stops.count where stops[i].h >= h {
            hi = stops[i]; lo = stops[i - 1]; break
        }
        let span = max(1e-6, hi.h - lo.h)
        let f = (h - lo.h) / span
        return Color(red: lo.r + (hi.r - lo.r) * f,
                     green: lo.g + (hi.g - lo.g) * f,
                     blue: lo.b + (hi.b - lo.b) * f)
    }
}

/// The dock's 3-sided border — the drawer's "river line". It carries the SAME
/// magma orange as the notch river so the two read identically; load shows as
/// glow intensity, NOT hue (the cold→white-hot ramp lives in the rounds + the
/// centre glow, not on the frame — that's what made the border pale to gold
/// under load and diverge from the river).
private struct ForgeBorder: View {
    let active: Int
    /// 0 = retracted (cold gray frame), 1 = fully connected (lit molten frame).
    /// Animated ONLY on the work-starts / work-ends transition — a one-shot
    /// "river" merge / unmerge, NOT a clock, so it's free at rest and while
    /// steady. Mirrors the notch river: the molten connects in from the two
    /// screen-edge ends and meets in the middle when work begins, and retracts
    /// back to the ends when the last agent goes quiet.
    @State private var merge: CGFloat = 0
    /// Pending retract, held so the border doesn't dissipate until the shoot
    /// comet has played out. Cancelled if work restarts during the hold.
    @State private var unmergeWork: DispatchWorkItem?
    /// ≈ the shoot comet's lifetime after the last agent quiets: the finish
    /// event's shootDelay (0.5) + the comet flight (~0.55), so the frame stays
    /// lit until the round has fired out the top.
    private static let dissipateDelay: Double = 1.1

    var body: some View {
        let line = DockEdgeBorder(radius: 14, inset: 0.75)
        return ZStack {
            // Cold base frame — always present; the molten covers it when lit.
            line.stroke(Color.white.opacity(0.5), lineWidth: 1.5)
            if merge >= 0.999 {
                // Fully connected → ONE continuous stroke, so there's no meeting
                // seam (two round caps butting at 0.5 left a dark-red dot).
                moltenSeg(line, from: 0, to: 1)
            } else {
                // Mid-transition → connect in from BOTH ends (param 0 = top-right
                // flare, param 1 = bottom-right flare) toward the centre (param
                // 0.5, the left edge), like the river merging from the sides.
                moltenSeg(line, from: 0, to: merge * 0.5)
                moltenSeg(line, from: 1 - merge * 0.5, to: 1)
            }
        }
        // Set the resting state without animating on first appear.
        .onAppear { merge = active > 0 ? 1 : 0 }
        // Work starts → connect in immediately (the river takes priority, and the
        // input comet rides its bottom front). Last agent goes quiet → HOLD, then
        // retract — so the dissipation only happens AFTER the shoot comet has
        // played out, never on top of it.
        .onChange(of: active > 0) { _, on in
            unmergeWork?.cancel()
            if on {
                withAnimation(.easeInOut(duration: 0.7)) { merge = 1 }
            } else {
                let work = DispatchWorkItem {
                    withAnimation(.easeInOut(duration: 0.7)) { merge = 0 }
                }
                unmergeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.dissipateDelay, execute: work)
            }
        }
    }

    /// One run of the molten frame over a trim range — the drawer's `moltenVein`:
    /// a wide deep-red base carrying the double bloom (ember + gold), the hot-
    /// orange body, and a thin gold-white core. Widths tuned so it reads ORANGE
    /// (not gold) at the dock's 1:1 scale. Always rendered (empty when the trim is
    /// zero-length) so the trim animates smoothly instead of popping in.
    @ViewBuilder
    private func moltenSeg(_ line: DockEdgeBorder, from: CGFloat, to: CGFloat) -> some View {
        let seg = line.trim(from: max(0, min(from, to)), to: max(from, to))
        ZStack {
            seg.stroke(Magma.deep, style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
                .shadow(color: Magma.ember.opacity(0.45), radius: 6)
                .shadow(color: Magma.gold.opacity(0.30), radius: 3)
            seg.stroke(Magma.body, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            seg.stroke(Magma.core, style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
                .blendMode(.plusLighter)
                .opacity(0.45)
        }
    }
}

/// A magma comet that streaks along the drawer's border — the dock's echo of the
/// notch's siphon comet. Border params: 0 = top-right end, 0.5 ≈ middle of the
/// left bar (by the revolver/chamber), 1 = bottom-right end. Travels `start`→`end`
/// once per `trigger` bump with a short trailing tail, then vanishes. One-shot,
/// no clock — free at rest.
private struct BorderComet: View {
    var start: CGFloat
    var end: CGFloat
    let trigger: Int
    /// The input comet uses the SAME curve/duration as the border merge so it
    /// rides exactly on the river's bottom front (synced, not competing).
    var animation: Animation = .easeOut(duration: 0.55)
    @State private var phase: CGFloat = 1   // 1 = finished / hidden

    var body: some View {
        let line = DockEdgeBorder(radius: 14, inset: 0.75)
        let head = start + (end - start) * phase
        let tailLen: CGFloat = 0.16
        let behind = head + (start >= end ? tailLen : -tailLen)   // tail trails toward `start`
        let from = max(0, min(head, behind))
        let to = min(1, max(head, behind))
        // Bright until it actually ARRIVES (so the input comet visibly reaches
        // the middle of the left bar before fading); quick fade over the last
        // sliver; fully hidden at rest.
        let vis: Double = phase >= 1 ? 0 : (phase < 0.92 ? 1 : max(0, Double(1 - phase) / 0.08))
        // ALWAYS rendered (no conditional view) so the TRIM animates and the
        // comet actually travels — a conditional `if` would animate the view's
        // insertion/removal (a fade) instead. Opacity hides it at rest.
        return ZStack {
            line.trim(from: from, to: to)            // warm halo
                .stroke(Magma.gold, style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                .shadow(color: Magma.ember.opacity(0.95), radius: 8)
                .shadow(color: Magma.gold.opacity(0.9), radius: 4)
                .blendMode(.plusLighter)
                .opacity(vis)
            line.trim(from: from, to: to)            // white-hot core — pops over the orange border
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .blendMode(.plusLighter)
                .opacity(vis)
        }
        .onChange(of: trigger) { _, _ in
            phase = 0
            withAnimation(animation) { phase = 1 }
        }
    }
}

/// A tiny one-shot spark pop at the muzzle (the top-right exit) fired when the
/// shoot comet reaches the end — the round leaving the barrel. Fans upward and
/// fades fast; no trailing sparks (the drawer stays calm). Event-driven, no clock.
private struct MuzzleSparks: View {
    let trigger: Int
    /// Fire when the comet arrives at the exit (≈ the shoot comet's flight time).
    var fireDelay: Double = 0.5
    @State private var phase: CGFloat = 1   // 1 = done / hidden

    // Fixed fan of sparks (angle° from +x, with +y up) spraying up-and-out.
    private static let sparks: [(angle: Double, dist: Double)] = [
        (58, 11), (80, 13), (100, 9), (120, 12), (90, 6),
    ]

    var body: some View {
        GeometryReader { geo in
            let origin = CGPoint(x: geo.size.width - 3, y: 3)   // top-right flare tip
            ForEach(Array(Self.sparks.enumerated()), id: \.offset) { _, s in
                let rad = s.angle * .pi / 180
                let d = s.dist * Double(phase)
                Circle()
                    .fill(Magma.white)
                    .frame(width: 2.2, height: 2.2)
                    .shadow(color: Magma.gold.opacity(0.9), radius: 2)
                    .blendMode(.plusLighter)
                    .position(x: origin.x + cos(rad) * d, y: origin.y - sin(rad) * d)
                    .opacity(phase >= 1 ? 0 : Double(1 - phase * phase))
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + fireDelay) {
                phase = 0
                withAnimation(.easeOut(duration: 0.4)) { phase = 1 }
            }
        }
    }
}

private struct SessionSquare: View {
    let size: CGFloat
    let initials: String      // 2-char name token, e.g. "mb"
    let number: String        // tab index, shown as a small subscript
    let stateColor: Color     // activity state — the part that changes
    let identityColor: Color  // stable "who" color — the part that doesn't
    let name: String          // full name, surfaced as a tooltip
    let activity: Activity    // current state — decides if the hop is delayed
    let pulsing: Bool
    /// Dormant (older-finished) squares stay quiet; everything else gets a
    /// stronger fill + border so the live greens/blues/ambers pop.
    let subdued: Bool
    let onTap: () -> Void

    /// Matches the notch gun + dock shell delay so the square's reaction
    /// (flash + hop) lands on the same beat as the shot it "fires", instead
    /// of jumping the instant the colour flips.
    private static let fireDelay: TimeInterval = 0.5
    /// Bullet-blue (matches the notch's start comet / bullets) for the
    /// "reloading" border sweep fired when the user sends input to a session.
    private static let reloadColor = Color(red: 0x66 / 255.0, green: 0xB5 / 255.0, blue: 0xFF / 255.0)

    @State private var hover = false
    /// Brief bright wash fired whenever the activity state changes.
    @State private var flash = false
    /// Vertical hop offset fired alongside the flash, drawing the eye to a
    /// change (0 = resting; negative = popped up).
    @State private var bounceY: CGFloat = 0
    /// "Reload" border sweep — a bullet-blue line traces once around the square
    /// when the user sends input (start). `reloadTrim` draws it on (0→1),
    /// `reloadOpacity` fades it out. One-shot via `withAnimation`, so it costs
    /// nothing at rest.
    @State private var reloadTrim: CGFloat = 0
    @State private var reloadOpacity: Double = 0

    var body: some View {
        // Dormant squares keep the quiet original treatment; live ones get
        // a heavier fill + border so their color reads strongly.
        // Wide gap between quiet (working/idle/dormant) and lit (needs-you /
        // done / elevated) so the glance lands on what matters.
        // Working squares get their OWN tier: a real blue fill (not the faint
        // 0.10 that made them blur into the dormant grays — the only tell used
        // to be the subtle border). Resting/dormant stay quiet; needs-you / done
        // / elevated stay fully lit.
        let working: Bool = {
            switch activity {
            case .thinking, .tool, .initState: return true
            default: return false
            }
        }()
        let strongEdge = working || !subdued   // full-weight border + a resting glow
        let fillOpacity: Double = working
            ? (hover ? 0.50 : 0.38)   // cool work tiles — present but calm, not shouting
            : (subdued ? (hover ? 0.22 : 0.10) : (hover ? 0.52 : 0.40))
        let borderOpacity: Double = working
            ? (hover ? 1.0 : 0.85)
            : (subdued ? (hover ? 0.70 : 0.34) : (hover ? 1.0 : 0.95))
        return Button(action: onTap) {
            VStack(spacing: 0) {
                // The tab NUMBER is the hero — it's your Zellij jump key. A
                // monospaced face (dispatch-board / stamped-serial) reads far
                // less toy-like than rounded; the tight dark emboss makes it look
                // pressed INTO the square instead of floating on it.
                numberView
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.55), radius: 0.5, y: 1)
                // Name token — a small stamped LABEL under the number.
                Text(initials)
                    .font(.system(size: size * 0.23, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.62))
                    .shadow(color: .black.opacity(0.45), radius: 0.5, y: 0.5)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(LinearGradient(
                        colors: [stateColor.opacity(fillOpacity * 1.35),
                                 stateColor.opacity(fillOpacity * 0.72)],
                        startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .stroke(stateColor.opacity(borderOpacity), lineWidth: strongEdge ? 1.0 : 0.8)
            )
            // Keycap shading — a bright lip along the TOP edge (fading down) and a
            // soft dark seat along the BOTTOM, so the square reads as a physical
            // key pressed into the panel rather than a flat chip.
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .stroke(LinearGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.0)],
                        startPoint: .top, endPoint: .center),
                        lineWidth: 1)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .stroke(LinearGradient(
                        colors: [.clear, .black.opacity(0.40)],
                        startPoint: .center, endPoint: .bottom),
                        lineWidth: 1)
                    .allowsHitTesting(false)
            )
            // State-change flash — a bright wash that decays away.
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(.white)
                    .opacity(flash ? 0.55 : 0)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            )
            // "Reload" sweep — a bullet-blue line draws around the square when
            // input is sent (start), following the gun/bullet theme.
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .inset(by: 1)
                    .trim(from: 0, to: reloadTrim)
                    .stroke(Self.reloadColor,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .opacity(reloadOpacity)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            )
            // Grounding shadow — the key sits ON the panel surface.
            .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
            // Lit squares carry a resting halo so they pop; quiet ones glow
            // only on hover.
            .shadow(
                color: stateColor.opacity(flash ? 0.9 : (strongEdge ? (hover ? 0.7 : 0.4) : (hover ? 0.3 : 0))),
                radius: flash ? 7 : (strongEdge ? 6 : 4)
            )
            .scaleEffect(hover ? 1.08 : 1.0)
            .offset(y: bounceY)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(name)
        .overlay(alignment: .topTrailing) {
            if pulsing { AttentionPulse(color: stateColor) }
        }
        .animation(.easeOut(duration: 0.12), value: hover)
        // When the activity (its color) flips, pop a flash and let it fade.
        .onChange(of: stateColor) { _, _ in
            switch activity {
            case .thinking, .tool, .initState:
                // Input sent → the session is "reloading". A bullet-blue line
                // sweeps once around the square (charging), following the
                // gun/bullet theme — no bounce, fires immediately.
                triggerReload()
            case .done, .waiting, .idle:
                // Finish / needs-input / settle → vertical bounce + flash.
                // Delayed to land with the shell on done/waiting; immediate
                // otherwise (idle has no shot to sync with).
                let delay: TimeInterval = (activity == .done || activity == .waiting) ? Self.fireDelay : 0
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    flash = true
                    withAnimation(.easeOut(duration: 0.6)) { flash = false }
                    // Snap UP, then a bouncy settle back to the floor.
                    withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { bounceY = -7 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.42)) { bounceY = 0 }
                    }
                }
            }
        }
    }

    /// The tab number as the hero. For a multi-pane tab ("6.1") the tab is big
    /// and the pane rides as a small superscript ("6¹") — compact, fits cleanly,
    /// and each pane still keeps its own square/state.
    @ViewBuilder
    private var numberView: some View {
        let hero = Font.system(size: size * 0.42, weight: .heavy, design: .monospaced)
        if let dot = number.firstIndex(of: ".") {
            let tab = String(number[..<dot])
            let pane = String(number[number.index(after: dot)...])
            HStack(alignment: .top, spacing: 0.5) {
                Text(tab).font(hero).monospacedDigit()
                Text(pane)
                    .font(.system(size: size * 0.26, weight: .heavy, design: .monospaced))
                    .monospacedDigit()
                    .opacity(0.85)
            }
        } else {
            Text(number).font(hero).monospacedDigit()
        }
    }

    /// Fire the one-shot "reload" sweep: a bullet-blue line traces around the
    /// square, then fades once it closes the loop.
    private func triggerReload() {
        reloadTrim = 0
        reloadOpacity = 1
        withAnimation(.easeInOut(duration: 0.5)) { reloadTrim = 1 }
        withAnimation(.easeOut(duration: 0.35).delay(0.5)) { reloadOpacity = 0 }
    }
}

/// Open border outline for the dock: traces the TOP, the rounded LEFT side
/// (top-left + bottom-left corners), and the BOTTOM — but NOT the right
/// edge, which is glued flush to the screen. `inset` pulls the path in by
/// half the line width so the whole stroke stays inside the panel bounds.
private struct DockEdgeBorder: Shape {
    var radius: CGFloat = 14
    var inset: CGFloat = 0.75
    /// Outward "flare" at the two screen-edge ends — like the macOS notch
    /// shoulders: the line curls out and meets the screen edge tangentially
    /// (vertical) instead of stopping in a flat 90° corner.
    var flare: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let r = max(0, radius - inset)
        let left = rect.minX + inset
        let right = rect.maxX
        let top = rect.minY + inset
        let bottom = rect.maxY - inset
        let f = flare

        var p = Path()
        // Top-right flare: start out on the screen edge ABOVE the body, then
        // curl down into the top edge (meets the screen tangent to vertical).
        p.move(to: CGPoint(x: right, y: top - f))
        p.addQuadCurve(to: CGPoint(x: right - f, y: top),
                       control: CGPoint(x: right, y: top))
        p.addArc(tangent1End: CGPoint(x: left, y: top),            // along top, round into…
                 tangent2End: CGPoint(x: left, y: bottom), radius: r)
        p.addArc(tangent1End: CGPoint(x: left, y: bottom),        // …down left, round into…
                 tangent2End: CGPoint(x: right - f, y: bottom), radius: r)
        p.addLine(to: CGPoint(x: right - f, y: bottom))            // …along bottom toward the edge
        // Bottom-right flare: curl out of the bottom edge and flare DOWN to the
        // screen edge (mirror of the top).
        p.addQuadCurve(to: CGPoint(x: right, y: bottom + f),
                       control: CGPoint(x: right, y: bottom))
        return p
    }
}

// MARK: - Cannon notification model + views

/// The toast card parked above the strip after a tracer lands.
private struct DockToast: Identifiable {
    let id = UUID()
    let sessionId: UUID
    let taskId: String
    let project: String
    let message: String
    let headline: String
    let accent: Color
}

/// A single in-flight tracer (square → card).
private struct CannonShot: Identifiable {
    let id = UUID()
    let sessionId: UUID
    let accent: Color
}

/// Collects every visible square's centre point, keyed by session id, so the
/// cannon layer can resolve where to launch a tracer from.
private struct SquareCenterKey: PreferenceKey {
    static var defaultValue: [UUID: Anchor<CGPoint>] = [:]
    static func reduce(value: inout [UUID: Anchor<CGPoint>],
                       nextValue: () -> [UUID: Anchor<CGPoint>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The notification card — a dispatch tag built from the SAME keycap material
/// as the dock squares so it reads as one machine. A shell-casing bullet on the
/// left, project · status in the middle, and the tab number as a real keycap
/// chip on the right — the hero, since it's your Zellij jump key.
private struct DockToastCard: View {
    static let width: CGFloat = 256
    static let height: CGFloat = 44
    private static let radius: CGFloat = 12

    /// The status icon (focus reticle), loaded once from Downloads.
    private static let bulletImage: NSImage? = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/focus.png")
        return NSImage(contentsOf: url)
    }()

    let toast: DockToast
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 9) {
                bullet
                // One line: project · status. Monospaced (dispatch-tag serial)
                // but normal case, so it sits next to the keycaps without shouting.
                HStack(spacing: 7) {
                    Text(toast.project)
                        .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("·")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                    Text(toast.headline)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(toast.accent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 6)
                tabChip
            }
            .padding(.leading, 8)
            .padding(.trailing, 7)
            .frame(width: Self.width, height: Self.height)
            // The card is a slice of the dock panel itself: a FLAT near-black body
            // + a neutral hairline edge. No body gradient, no accent halo — colour
            // lives ONLY inside (status text + the tab keycap), exactly like the
            // dock contains its colour inside the squares.
            .background(
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .fill(Color(white: 0.11))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.0)],
                                           startPoint: .top, endPoint: .center), lineWidth: 1)
                    .blendMode(.plusLighter)
            )
            .shadow(color: .black.opacity(0.55), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var bullet: some View {
        if let img = Self.bulletImage {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 24, height: 24)
        } else {
            Color.clear.frame(width: 24, height: 24)
        }
    }

    /// The tab number as a mini keycap chip — the hero, matching the dock
    /// squares: embossed mono digits with the pane as a small superscript, on
    /// the same accent-tinted keycap material (top bevel + seat + border + ground).
    private var tabChip: some View {
        let s: CGFloat = 30
        return numberView(size: s)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.55), radius: 0.5, y: 1)
            .frame(width: s, height: s)
            .background(
                RoundedRectangle(cornerRadius: s * 0.24, style: .continuous)
                    .fill(LinearGradient(
                        colors: [toast.accent.opacity(0.42), toast.accent.opacity(0.20)],
                        startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: s * 0.24, style: .continuous)
                    .stroke(toast.accent.opacity(0.75), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: s * 0.24, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.0)],
                                           startPoint: .top, endPoint: .center), lineWidth: 1)
                    .blendMode(.plusLighter)
            )
            .overlay(
                RoundedRectangle(cornerRadius: s * 0.24, style: .continuous)
                    .stroke(LinearGradient(colors: [.clear, .black.opacity(0.4)],
                                           startPoint: .center, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
    }

    /// Tab number, hero-sized. "6.2" → big "6" + small superscript "2".
    @ViewBuilder
    private func numberView(size: CGFloat) -> some View {
        let hero = Font.system(size: size * 0.46, weight: .heavy, design: .monospaced)
        if let dot = toast.taskId.firstIndex(of: ".") {
            let tab = String(toast.taskId[..<dot])
            let pane = String(toast.taskId[toast.taskId.index(after: dot)...])
            HStack(alignment: .top, spacing: 0.5) {
                Text(tab).font(hero).monospacedDigit()
                Text(pane)
                    .font(.system(size: size * 0.30, weight: .heavy, design: .monospaced))
                    .monospacedDigit()
                    .opacity(0.85)
            }
        } else {
            Text(toast.taskId).font(hero).monospacedDigit()
        }
    }
}

/// Muzzle smoke for the dock cannon — plays `smoke.gif` (already transparent)
/// rising from the firing square. Its bottom is pinned to the square so the
/// plume billows up into the reserved headroom; a short fade-in / end-fade
/// envelope ties its visibility to the notification's dwell.
private struct SmokePuff: View {
    let origin: CGPoint
    /// Changes per notification so the GIF player remounts and replays from
    /// frame 0 every time — without it the inner clock would stick on the
    /// last (dissipated) frame after the first finish.
    var restartKey: AnyHashable = 0
    /// On-screen footprint of the plume. Tall so the smoke has room to rise;
    /// the toast slot reserves matching headroom above the strip.
    var width: CGFloat = 72
    var height: CGFloat = 104
    /// Roughly the toast's dwell, so the last wisp fades as the card leaves.
    var lifetime: Double = 4.0

    @State private var startDate = Date()

    var body: some View {
        TimelineView(.animation) { ctx in
            let age = ctx.date.timeIntervalSince(startDate)
            let appear = min(1, age / 0.18)
            let fade = max(0, min(1, (lifetime - age) / 1.2))
            // The GIF's baked-in delays are 5fps (choppy); play its 106 frames
            // at a real rate, once through, so it flows and dissipates.
            KeyedGIFView(frames: ShootAsset.smoke, fps: 26, loop: false)
                .id(restartKey)   // remount → restart from frame 0 each finish
                .frame(width: width, height: height)
                .opacity(appear * fade)
                // Pin the plume's BASE to the muzzle; it extends upward.
                .position(x: origin.x, y: origin.y - height / 2 + 8)
        }
        .onAppear { startDate = Date() }
        .allowsHitTesting(false)
    }
}

/// A glowing tracer that arcs from a square up to the toast card on a quad
/// bezier, leaving a short comet tail. Self-timed via `TimelineView` so the
/// path is sampled every frame (a plain `.position` tween would cut the
/// corner of the arc). The parent removes it once it lands.
private struct CannonProjectile: View {
    let start: CGPoint
    let target: CGPoint
    let accent: Color

    @State private var startDate = Date()
    private let duration: Double = 0.36

    var body: some View {
        TimelineView(.animation) { ctx in
            let raw = ctx.date.timeIntervalSince(startDate) / duration
            let t = CGFloat(min(1, max(0, raw)))
            let head = point(at: t)
            let tail = point(at: max(0, t - 0.24))
            ZStack {
                // Comet tail — fades from nothing up to the bright head.
                Path { p in
                    p.move(to: tail)
                    p.addLine(to: head)
                }
                .stroke(
                    LinearGradient(
                        colors: [accent.opacity(0), accent],
                        startPoint: .top, endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .blendMode(.plusLighter)
                // Bright head with a white-hot core + colored glow.
                Circle()
                    .fill(accent)
                    .frame(width: 9, height: 9)
                    .overlay(
                        Circle().fill(.white).frame(width: 3.5, height: 3.5)
                            .blendMode(.plusLighter)
                    )
                    .shadow(color: accent, radius: 7)
                    .position(head)
            }
            .opacity(t >= 1 ? 0 : 1)
        }
        .onAppear { startDate = Date() }
    }

    /// Quadratic bezier from `start` to `target`, bowed upward so the tracer
    /// launches up and over rather than sliding in a straight line.
    private func point(at t: CGFloat) -> CGPoint {
        let control = CGPoint(
            x: (start.x + target.x) / 2,
            y: min(start.y, target.y) - 26
        )
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * start.x + 2 * mt * t * control.x + t * t * target.x,
            y: mt * mt * start.y + 2 * mt * t * control.y + t * t * target.y
        )
    }
}

// MARK: - Revolver cylinder (prototype)

/// The scalloped/fluted face of a revolver cylinder: a disc with a concave
/// notch bitten out of the edge between each chamber. Built as one big circle
/// plus N notch circles straddling the rim; fill with `FillStyle(eoFill: true)`
/// so the overlaps subtract, leaving the flutes.
private struct FlutedCylinder: Shape {
    var count: Int = 6
    var bodyR: CGFloat = 0.46          // outer (bump) radius, ratio of size
    var notchR: CGFloat = 0.17         // scallop radius
    var notchCenter: CGFloat = 0.52    // scallop centre distance (past the rim)

    func path(in rect: CGRect) -> Path {
        let d = min(rect.width, rect.height)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let R = d * bodyR, nR = d * notchR, nC = d * notchCenter
        var p = Path()
        p.addEllipse(in: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R))
        for i in 0 ..< count {
            // Notches sit BETWEEN chambers (half-step offset).
            let a: Double = (-90.0 + 360.0 / Double(count) * (Double(i) + 0.5)) * .pi / 180.0
            let nx = c.x + nC * CGFloat(cos(a))
            let ny = c.y + nC * CGFloat(sin(a))
            p.addEllipse(in: CGRect(x: nx - nR, y: ny - nR, width: 2 * nR, height: 2 * nR))
        }
        return p
    }
}

/// A face-on six-shooter that sits at the left of the dock. Loaded brass rounds
/// = agents in flight (capped at 6; "+N" rides the speedloader). A round LOADS
/// when an agent starts and FIRES (cylinder spins + muzzle flash, synced to the
/// dock shell) when one finishes — the dock squares stay the roster, this is the
/// theatrical action piece. One-shot animations + an energy-gated waiting pulse,
/// so it costs nothing at rest.
private struct RevolverCylinder: View {
    let inFlight: Int
    let needsYou: Bool
    /// Bumped by the parent on every notification. The gun FIRES on its change
    /// (cylinder click + muzzle flash) — decoupled from `inFlight` so a
    /// "needs input" toast (which doesn't spend a round) still fires the gun.
    var firePulse: Int = 0
    var size: CGFloat = 38

    /// Synced with the dock shell + notch gunshot so the spin lands on the beat.
    private static let fireDelay: TimeInterval = 0.5

    /// The cylinder silhouette — a black-on-transparent PNG (6 bores at ring
    /// 0.29, bore r 0.125). Loaded once; tinted to steel and the transparent
    /// bores let the brass rounds behind it show through. Loaded from Downloads
    /// like the other preview art.
    private static let cylinderImage: NSImage? = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads").appendingPathComponent("revolver-cylinder.png")
        return NSImage(contentsOf: url)
    }()

    @State private var loaded: [Bool] = Array(repeating: false, count: 6)
    @State private var angle: Double = 0
    @State private var flash = false
    @State private var overflow = 0
    @State private var spinGen = 0

    var body: some View {
        let d = size                 // overall frame — leaves a small margin for the muzzle flash
        let cylD = d * 0.80          // the cylinder image fills most of the frame (tight padding)
        let c = CGPoint(x: d / 2, y: d / 2)
        let ringR = cylD * 0.29      // bore-centre ring (measured from the PNG)
        let boreR = cylD * 0.122     // bore radius
        let heat = DockMagma.heat(active: inFlight)   // forge load → magma colour

        return Button(action: spin) {
            ZStack {
                // The cylinder image and its loaded rounds rotate together, so
                // the scalloped edge visibly turns on each spin / fire.
                ZStack {
                    // Brass rounds sit BEHIND the silhouette; the PNG's
                    // transparent bores let them show through when loaded.
                    ForEach(0 ..< 6, id: \.self) { i in
                        if loaded[i] {
                            ZStack {
                                // Hot-round magma glow — each chambered round
                                // burns the load colour.
                                Circle()
                                    .fill(DockMagma.color(heat))
                                    .frame(width: boreR * 2, height: boreR * 2)
                                    .blur(radius: boreR * 0.55)
                                    .opacity(0.45 + 0.55 * heat)
                                    .blendMode(.plusLighter)
                                brassRound(r: boreR)
                            }
                            .position(pos(i, center: c, r: ringR))
                        }
                    }
                    cylinderBody(d: cylD)
                }
                .frame(width: d, height: d)
                .rotationEffect(.degrees(angle))
                .shadow(color: DockMagma.color(heat).opacity(heat * 0.7), radius: cylD * 0.12 * heat)

                // Central heat glow — a STATIC core that brightens with the load
                // (no clock; renders once per count change).
                if heat > 0.01 {
                    Circle()
                        .fill(DockMagma.color(heat))
                        .frame(width: cylD * 0.20, height: cylD * 0.20)
                        .blur(radius: cylD * 0.07)
                        .opacity(heat * 0.7)
                        .blendMode(.plusLighter)
                        .position(c)
                }

                // Muzzle flash at the FIXED barrel (12 o'clock).
                muzzleFlash(d: cylD).position(x: c.x, y: c.y - ringR)

                // A live round waiting on YOU pulses amber at the barrel.
                if needsYou {
                    DecorativeTimeline(fps: 15) { ctx in
                        let p = 0.5 + 0.5 * sin(ctx.date.timeIntervalSinceReferenceDate * 4)
                        Circle()
                            .stroke(Theme.Neon.amber, lineWidth: 1.5)
                            .frame(width: boreR * 2.1, height: boreR * 2.1)
                            .opacity(0.45 + 0.55 * p)
                            .shadow(color: Theme.Neon.amber.opacity(p), radius: 3)
                    }
                    .position(x: c.x, y: c.y - ringR)
                }

                // Publish the muzzle point (12 o'clock) so the cannon layer can
                // aim the feed tracer, park the smoke, and float the card here.
                Color.clear
                    .frame(width: 1, height: 1)
                    .position(x: c.x, y: c.y - ringR)
                    .anchorPreference(key: SquareCenterKey.self, value: .center) {
                        [dockMuzzleAnchorID: $0]
                    }
            }
            .frame(width: d, height: d)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onChange(of: firePulse) { old, new in
            guard new != old, new > 0 else { return }
            fireOnce()
        }
        .overlay(alignment: .bottomTrailing) {
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: d * 0.22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 0.5)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .offset(x: 6, y: 3)
            }
        }
        .onAppear {
            loaded = (0 ..< 6).map { $0 < min(inFlight, 6) }
            overflow = max(0, inFlight - 6)
        }
        .onChange(of: inFlight) { old, new in
            overflow = max(0, new - 6)
            let oldT = min(old, 6), newT = min(new, 6)
            guard newT != oldT else { return }
            if newT > oldT {
                // Load — a round seats the instant you send input (no delay).
                withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
                    loaded = (0 ..< 6).map { $0 < newT }
                }
            } else {
                // Eject — keep the round chambered until the gun fires on the
                // beat, then empty it. The spin + muzzle flash come from
                // `firePulse` (fired for EVERY notification), so the eject and
                // the flash land together without double-driving the rotation.
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.fireDelay) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                        loaded = (0 ..< 6).map { $0 < newT }
                    }
                }
            }
        }
    }

    /// Fire the gun: click the cylinder one chamber forward and flash the
    /// muzzle. Driven by `firePulse`, so it runs once per notification —
    /// independent of whether a round was actually spent.
    private func fireOnce() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { angle += 60 }
        flash = true
        withAnimation(.easeOut(duration: 0.45)) { flash = false }
    }

    /// Flick the cylinder — a smooth exponential ease-out crawl PLUS the final
    /// mechanical tick, fused so there's no dead stop between them.
    ///
    /// The main sweep (easeOutExpo) whips out fast then creeps very slowly to
    /// JUST shy of the chamber, finishing its creep exactly when the sound's
    /// last "tick" plays — and right then the final 22° tick snaps it onto the
    /// chamber. Because the creep ends the instant the tick fires, the two read
    /// as one motion that clicks into place (not the old stop-then-jump). The
    /// generation token cancels a pending tick if you spam-spin.
    private func spin() {
        spinGen += 1
        let gen = spinGen
        let turns = Double(5 + Int.random(in: 0 ... 2))           // several full revolutions
        let landing = Double(Int.random(in: 0 ..< 6)) * 60        // land on a random chamber
        let click = 22.0                                          // the final tick, synced to the sound
        SoundFX.play(SoundFX.spin)
        // cubic-bezier(0.19, 1, 0.22, 1) == easeOutExpo — fast whip into a long
        // slow creep, landing just short of the chamber at t = 2.0s.
        withAnimation(.timingCurve(0.19, 1, 0.22, 1, duration: 2.0)) {
            angle += turns * 360 + landing - click
        }
        // …and the creep flows straight into the final tick (no pause): snap the
        // last 22° onto the chamber on the sound's tick.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard gen == spinGen else { return }
            withAnimation(.spring(response: 0.16, dampingFraction: 0.68)) {
                angle += click
            }
        }
    }

    /// Chamber `i` placed around the ring, 12 o'clock first.
    private func pos(_ i: Int, center: CGPoint, r: CGFloat) -> CGPoint {
        let a: Double = (-90.0 + 60.0 * Double(i)) * .pi / 180.0
        return CGPoint(x: center.x + r * CGFloat(cos(a)),
                       y: center.y + r * CGFloat(sin(a)))
    }

    /// The cylinder silhouette PNG, tinted to steel (template rendering keys off
    /// its alpha, so the transparent bores/scallops/centre stay open).
    @ViewBuilder
    private func cylinderBody(d: CGFloat) -> some View {
        if let img = Self.cylinderImage {
            Image(nsImage: img)
                .renderingMode(.template)
                .resizable()
                .frame(width: d, height: d)
                .foregroundStyle(LinearGradient(
                    colors: [Color(white: 0.62), Color(white: 0.24)],
                    startPoint: .top, endPoint: .bottom))
        } else {
            Circle().fill(Color(white: 0.3)).frame(width: d, height: d)
        }
    }

    /// A brass cartridge head, sized to fill a bore.
    private func brassRound(r: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(
                colors: [Color(red: 1.0, green: 0.87, blue: 0.50),
                         Color(red: 0.70, green: 0.48, blue: 0.15)],
                center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: r))
            .overlay(
                Circle().fill(Color(red: 0.26, green: 0.19, blue: 0.08))
                    .frame(width: r * 0.60, height: r * 0.60))   // primer
            .frame(width: r * 2, height: r * 2)
            .transition(.scale.combined(with: .opacity))
    }

    /// Burst at the barrel: a radial glow + eight white spikes, scaled by `flash`.
    private func muzzleFlash(d: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [.white, Color(red: 1, green: 0.82, blue: 0.35), .clear],
                    center: .center, startRadius: 0, endRadius: d * 0.28))
                .frame(width: d * 0.55, height: d * 0.55)
            ForEach(0 ..< 8, id: \.self) { k in
                Capsule().fill(.white)
                    .frame(width: 1.4, height: d * 0.30)
                    .offset(y: -d * 0.13)
                    .rotationEffect(.degrees(Double(k) * 45))
            }
        }
        .scaleEffect(flash ? 1 : 0.1)
        .opacity(flash ? 1 : 0)
        .blendMode(.plusLighter)
    }
}

private struct AttentionPulse: View {
    let color: Color

    var body: some View {
        DecorativeTimeline(fps: 15) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = 0.5 + 0.5 * sin(t * 4)
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .shadow(color: color, radius: 3 * phase)
                .opacity(0.55 + 0.45 * phase)
                .offset(x: 2, y: -2)
        }
    }
}

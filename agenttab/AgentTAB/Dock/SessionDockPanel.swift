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

struct SessionDockView: View {
    @EnvironmentObject var engine: ActivityEngine
    @EnvironmentObject var dock: DockState
    var onSizeChange: (CGSize) -> Void = { _ in }

    private static let square: CGFloat = 36
    private static let gap: CGFloat = 6
    private static let pad: CGFloat = 7
    /// Squares per row before wrapping up into a new row.
    private static let perRow: Int = 8

    // MARK: Cannon / toast state
    //
    // When a session crosses a notify threshold the engine posts
    // `.agentTabSessionEvent`. `fire(_:)` reserves headroom above the strip
    // (so the panel grows upward), launches a tracer from the firing
    // square, and pops the toast card on impact.

    /// The card currently parked above the strip (nil = none).
    @State private var toast: DockToast?
    /// Card visibility gate. Set true on tracer impact so the card "lands"
    /// rather than appearing instantly; the layout slot exists the whole
    /// time `toast != nil` so the tracer has somewhere to fly into.
    @State private var cardShown = false
    /// One-shot white wash on the card the moment the tracer lands.
    @State private var cardFlash = false
    /// In-flight tracers (usually one). Removed once they reach the card.
    @State private var shots: [CannonShot] = []
    /// Pending auto-dismiss, cancelled if a fresh event arrives first.
    @State private var dismissWork: DispatchWorkItem?
    /// Bumped on every event so a delayed launch can tell it's been
    /// superseded by a newer one during the pre-shot delay.
    @State private var fireGen = 0

    /// Matches the notch shooter's `shootDelay`: the gun "poses" this long
    /// before the gunshot sound + bullet fire, so the dock shell launches on
    /// the same beat and the two stay in sync.
    private static let shootDelay: TimeInterval = 0.5

    private var sessions: [Session] {
        // Order by urgency only (higher priority wins). Equal priorities keep
        // the engine's existing order — Swift's sort is stable — so squares
        // don't reshuffle on every activity tick the way a recency tiebreak
        // made them.
        engine.displaySessions.sorted { $0.priority.rawValue > $1.priority.rawValue }
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
        // The toast slot sits ABOVE the strip; both hug the trailing (screen)
        // edge. The panel is anchored bottom-right, so when the slot gains
        // height the window grows UPWARD — exactly where we want the toast.
        VStack(alignment: .trailing, spacing: 0) {
            toastLayer
            strip(sessions)
        }
        // Tracers are drawn over everything, flying from each square's centre
        // (resolved from its anchor preference) up into the toast slot. The
        // overlay never affects layout, so it can't grow the panel itself.
        .overlayPreferenceValue(SquareCenterKey.self) { centers in
            GeometryReader { geo in
                ZStack {
                    // Muzzle smoke — lingers at the firing square for the
                    // whole notification (the shell itself is gone in a
                    // blink), then dissipates. Driven off `toast` so it
                    // lives exactly as long as the notification.
                    if let toast, let anchor = centers[toast.sessionId] {
                        SmokePuff(origin: geo[anchor], restartKey: toast.id)
                            .id(toast.id)
                    }
                    ForEach(shots) { shot in
                        if let anchor = centers[shot.sessionId] {
                            CannonProjectile(
                                start: geo[anchor],
                                target: toastTarget(in: geo.size),
                                accent: shot.accent
                            )
                        }
                    }
                }
            }
            .allowsHitTesting(false)
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
        .animation(.easeOut(duration: 0.18), value: layoutToken(sessions))
        .animation(.easeOut(duration: 0.20), value: dock.collapsed)
    }

    /// The strip itself — the always-present horizontal handle + squares,
    /// inside the rounded black container with its three-sided border.
    private func strip(_ sessions: [Session]) -> some View {
        HStack(spacing: Self.gap) {
            chevron
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
                .overlay(
                    // Border on TOP + LEFT + BOTTOM only — the right side is
                    // glued to the screen edge, so it stays open. Soft light
                    // gray; the inset keeps the full stroke inside the
                    // content-sized panel bounds (an edge stroke would clip).
                    DockEdgeBorder(radius: 14, inset: 0.75)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                )
        )
    }

    /// TEMP: hide the card so the cannon tracer is visible on its own. The
    /// slot height is still reserved (clear placeholder) so the shell has
    /// somewhere to fly. Flip back to `true` to restore the popup.
    private static let showToastCard = false

    /// The notification card slot. While a toast exists the slot keeps its
    /// full height (so the tracer has room to fly into) even before the card
    /// is revealed — `cardShown` only drives the pop-in, not the layout.
    @ViewBuilder
    private var toastLayer: some View {
        if let toast {
            if Self.showToastCard {
                DockToastCard(toast: toast, flash: cardFlash, onTap: { tapToast(toast) })
                    .opacity(cardShown ? 1 : 0)
                    .scaleEffect(cardShown ? 1 : 0.7, anchor: .bottomTrailing)
                    .padding(.bottom, Self.gap)
            } else {
                // Reserve headroom for the smoke plume to rise into (the card
                // is hidden, so we don't need its footprint — just height).
                Color.clear
                    .frame(width: DockToastCard.width, height: 80)
            }
        }
    }

    /// Where a tracer should land: the centre of the (trailing-aligned) card.
    private func toastTarget(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width - DockToastCard.width / 2, y: DockToastCard.height / 2)
    }

    // MARK: Cannon firing

    /// Handle one notify event. Holds for `shootDelay` so the shell launches
    /// on the same beat as the notch gunshot, then fires the cannon — unless a
    /// newer event has superseded this one in the meantime.
    private func fire(_ payload: DockEventPayload) {
        dismissWork?.cancel()
        fireGen += 1
        let gen = fireGen
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shootDelay) {
            guard gen == fireGen else { return }
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
        cardShown = false
        cardFlash = false
        toast = next

        if !dock.collapsed {
            // Expanded: fire the cannon. The square's own state-change bounce
            // already supplies the recoil "kick"; this adds the projectile.
            let shot = CannonShot(sessionId: payload.sessionId, accent: accent)
            shots = [shot]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                guard toast?.id == next.id else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.52)) { cardShown = true }
                cardFlash = true
                withAnimation(.easeOut(duration: 0.5)) { cardFlash = false }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                shots.removeAll { $0.id == shot.id }
            }
        } else {
            // Collapsed: no squares to fire from — just present the card.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { cardShown = true }
        }

        let work = DispatchWorkItem {
            guard toast?.id == next.id else { return }
            withAnimation(.easeOut(duration: 0.25)) { cardShown = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                if toast?.id == next.id { toast = nil }
            }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2, execute: work)
    }

    /// Card tap — jump to the originating terminal tab and dismiss, mirroring
    /// the old toast's tap-through behaviour (plus the notch peek request).
    private func tapToast(_ t: DockToast) {
        NotificationCenter.default.post(name: .agentTabRequestPeek, object: nil)
        if let s = engine.displaySessions.first(where: { $0.id == t.sessionId }) {
            engine.focus(s)
        }
        dismissWork?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { cardShown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if toast?.id == t.id { toast = nil }
        }
    }

    static func accent(for v: DockToastVariant) -> Color {
        switch v {
        case .attention: return Theme.Neon.amber
        case .success:   return Theme.Neon.green
        case .urgent:    return Theme.Neon.pink
        }
    }

    static func headline(for v: DockToastVariant) -> String {
        switch v {
        case .attention: return "Needs input"
        case .success:   return "Task complete"
        case .urgent:    return "Still waiting"
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

    /// Far-left handle: collapses the dock to just itself (so you can reach
    /// whatever it was covering) or expands it back. Mirrors the ⌃⌥⌘V
    /// global shortcut.
    private var chevron: some View {
        Button {
            dock.toggle()
        } label: {
            Image(systemName: dock.collapsed ? "chevron.left" : "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: dock.collapsed ? 16 : Self.square * 0.5, height: Self.square)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(dock.collapsed ? "Expand sessions (⌃⌥⌘V)" : "Collapse sessions (⌃⌥⌘V)")
    }

    /// Sessions laid out left-to-right, wrapping into stacked rows. Row 0
    /// sits at the BOTTOM (closest to the corner); overflow grows upward.
    @ViewBuilder
    private func grid(_ sessions: [Session]) -> some View {
        if sessions.isEmpty {
            emptySlot
        } else {
            let rows = stride(from: 0, to: sessions.count, by: Self.perRow).map {
                Array(sessions[$0 ..< min($0 + Self.perRow, sessions.count)])
            }
            VStack(alignment: .trailing, spacing: Self.gap) {
                ForEach(Array(rows.enumerated().reversed()), id: \.offset) { _, row in
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
                                subdued: Self.isDormant(session) && !Self.isElevated(session),
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

    static func color(for activity: Activity) -> Color {
        switch activity {
        case .thinking, .tool: return Theme.Activity.tool
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
        switch session.activity {
        case .thinking, .tool, .waiting, .initState:
            return color(for: session.activity)
        case .done, .idle:
            // High/Urgent keep their priority color even when old.
            if isElevated(session) { return session.priority.color }
            // Everything else greys out once dormant.
            if isDormant(session) { return dormantGray }
            // Sidequest ("just for fun") finishes teal instead of green.
            if session.priority == .sidequest { return session.priority.color }
            return color(for: session.activity)
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
        let fillOpacity = subdued ? (hover ? 0.34 : 0.22) : (hover ? 0.46 : 0.34)
        let borderOpacity = subdued ? (hover ? 0.95 : 0.60) : (hover ? 1.0 : 0.88)
        return Button(action: onTap) {
            VStack(spacing: 1) {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(number)
                    .font(.system(size: size * 0.22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
                // Stable identity stripe — learnable "who" signal.
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(identityColor)
                    .frame(width: size * 0.46, height: size * 0.08)
                    .padding(.top, 1)
                    .shadow(color: identityColor.opacity(hover ? 0.8 : 0), radius: 3)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(stateColor.opacity(fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .stroke(stateColor.opacity(borderOpacity), lineWidth: subdued ? 0.8 : 1.0)
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
            .shadow(color: stateColor.opacity(flash ? 0.85 : (hover ? 0.55 : 0)), radius: flash ? 7 : 5)
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

    func path(in rect: CGRect) -> Path {
        let r = max(0, radius - inset)
        let left = rect.minX + inset
        let right = rect.maxX
        let top = rect.minY + inset
        let bottom = rect.maxY - inset

        var p = Path()
        p.move(to: CGPoint(x: right, y: top))                       // top-right (open)
        p.addArc(tangent1End: CGPoint(x: left, y: top),            // along top, round into…
                 tangent2End: CGPoint(x: left, y: bottom), radius: r)
        p.addArc(tangent1End: CGPoint(x: left, y: bottom),        // …down left, round into…
                 tangent2End: CGPoint(x: right, y: bottom), radius: r)
        p.addLine(to: CGPoint(x: right, y: bottom))                // …along bottom to the edge
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

/// The notification card. Compact pill — task chip + headline + subline —
/// styled to match the dock (near-black fill, accent edge + glow). Tapping it
/// jumps to the originating terminal tab.
private struct DockToastCard: View {
    static let width: CGFloat = 250
    static let height: CGFloat = 46

    let toast: DockToast
    let flash: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 9) {
                Text(toast.taskId)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(toast.accent.opacity(0.28))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(toast.accent.opacity(0.85), lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(toast.headline)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(toast.project) · \(toast.message)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(width: Self.width, height: Self.height)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(toast.accent.opacity(0.75), lineWidth: 1)
            )
            .overlay(
                // Impact wash fired the moment the tracer lands.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white)
                    .opacity(flash ? 0.4 : 0)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            )
            .shadow(color: toast.accent.opacity(0.35), radius: 10)
        }
        .buttonStyle(.plain)
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

/// Small breathing dot in the corner of a square that needs the user.
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

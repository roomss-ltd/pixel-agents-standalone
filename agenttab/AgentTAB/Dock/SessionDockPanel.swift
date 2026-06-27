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

    private var sessions: [Session] {
        // Default ordering: urgency first (higher priority wins), then
        // recency (most-recently-updated) as the tiebreak.
        engine.displaySessions.sorted { a, b in
            if a.priority != b.priority { return a.priority.rawValue > b.priority.rawValue }
            return a.lastUpdate > b.lastUpdate
        }
    }

    var body: some View {
        let sessions = self.sessions
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
        .fixedSize()
        .background(
            GeometryReader { g in
                Color.clear.preference(key: DockSizeKey.self, value: g.size)
            }
        )
        .onPreferenceChange(DockSizeKey.self) { onSizeChange($0) }
        .animation(.easeOut(duration: 0.18), value: sessions.map(\.id))
        .animation(.easeOut(duration: 0.20), value: dock.collapsed)
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
                                pulsing: session.activity == .waiting,
                                subdued: Self.isDormant(session) && !Self.isElevated(session),
                                onTap: { engine.focus(session) }
                            )
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
    let pulsing: Bool
    /// Dormant (older-finished) squares stay quiet; everything else gets a
    /// stronger fill + border so the live greens/blues/ambers pop.
    let subdued: Bool
    let onTap: () -> Void

    @State private var hover = false
    /// Brief bright wash fired whenever the activity state changes.
    @State private var flash = false
    /// Vertical hop offset fired alongside the flash, drawing the eye to a
    /// change (0 = resting; negative = popped up).
    @State private var bounceY: CGFloat = 0

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
            flash = true
            withAnimation(.easeOut(duration: 0.6)) { flash = false }
            // Vertical hop: snap UP, then a bouncy settle back to the floor
            // (the low-damping spring overshoots so it visibly bounces).
            withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { bounceY = -7 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.42)) { bounceY = 0 }
            }
        }
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

/// Small breathing dot in the corner of a square that needs the user.
private struct AttentionPulse: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { ctx in
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

// ActivityHistoryView — activity dashboard shown in place of the agent
// grid when the user taps the token counter. Three ranges sharing the
// same view: 7-day bar chart, 30-day dense bar variant, and a
// 119-day GitHub-style squares heatmap. Hand-rolled (no Charts
// dependency) so it matches the pitch-black neon theme exactly:
// daily token spend, agent count per day, and the projects worked
// on across the active range.

import SwiftUI

struct ActivityHistoryView: View {
    @ObservedObject var tracker: TokenTracker
    let onBack: () -> Void

    /// Active range slice of the tracker's 364-day history. The range
    /// pills in the header mutate this; defaults to 7 days.
    @State private var range: TokenTracker.HistoryRange = .week

    /// Day whose bar the cursor is currently over — drives the
    /// hover readout (token spend) above that column.
    @State private var hoveredDay: Date?

    /// Root names of project groups currently expanded to reveal
    /// their per-worktree breakdown. Single-worktree groups are
    /// never expandable so their root name never lives here.
    @State private var expandedGroups: Set<String> = []

    private var days: [DailyActivity] { tracker.days(for: range) }
    private var projectGroups: [ProjectGroup] { tracker.projectGroups(for: range) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            summaryStrip
            switch range {
            case .week:
                VStack(alignment: .leading, spacing: 6) {
                    barHoverChip
                    barChart(tracker.days(for: .week), dense: false)
                }
            case .month:
                VStack(alignment: .leading, spacing: 6) {
                    barHoverChip
                    barChart(tracker.days(for: .month), dense: true)
                }
            case .window:
                VStack(alignment: .leading, spacing: 6) {
                    barHoverChip
                    SquaresHistoryGrid(
                        days: tracker.days(for: .window),
                        hoveredDay: $hoveredDay
                    )
                }
            }
            projectsList
        }
        .animation(.easeOut(duration: 0.18), value: range)
    }

    /// Floating readout above the bar chart. The dense 30d columns are
    /// too narrow to fit a full token string in their top label, so
    /// this chip carries the authoritative value (date · tokens ·
    /// agents). Mirrors the squares grid's hover chip styling and
    /// reserves the same vertical slot when nothing is hovered.
    @ViewBuilder
    private var barHoverChip: some View {
        if let date = hoveredDay,
           let day = days.first(where: { $0.day == date }) {
            HStack(spacing: 6) {
                Text(chipDateLabel(day.day))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Neon.blue)
                Text("·").font(.system(size: 10)).foregroundStyle(Theme.textFaint)
                Text("\(TokenTracker.format(day.tokens)) tokens")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textStrong)
                if day.agentCount > 0 {
                    Text("·").font(.system(size: 10)).foregroundStyle(Theme.textFaint)
                    Text("\(day.agentCount) agent\(day.agentCount == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(height: 25, alignment: .leading)
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

    private func chipDateLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: d)
    }

    // MARK: - Header

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
            rangePill(.week,   label: "7d",  a11y: "Last 7 days")
            rangePill(.month,  label: "30d", a11y: "Last 30 days")
            rangePill(.window, icon: "square.grid.3x3.fill", a11y: "Last 52 weeks, squares view")
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
    private func rangePill(
        _ r: TokenTracker.HistoryRange,
        label: String? = nil,
        icon: String? = nil,
        a11y: String
    ) -> some View {
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
        .help(a11y)
        .accessibilityLabel(a11y)
    }

    // MARK: - Summary strip

    private var totalTokens: Int { days.reduce(0) { $0 + $1.tokens } }
    private var activeDays: Int { days.filter { $0.tokens > 0 }.count }

    private var summaryStrip: some View {
        HStack(spacing: 6) {
            summaryStat(value: TokenTracker.format(totalTokens), label: "tokens", accent: Theme.Neon.blue)
            dot
            summaryStat(value: "\(projectGroups.count)", label: projectGroups.count == 1 ? "project" : "projects", accent: Theme.Neon.green)
            dot
            summaryStat(value: "\(activeDays)", label: activeDays == 1 ? "active day" : "active days", accent: Theme.Neon.amber)
            Spacer()
        }
    }

    private func summaryStat(value: String, label: String, accent: Color) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 11.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(accent)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textFaint)
        }
    }

    private var dot: some View {
        Circle()
            .fill(Theme.textFaint.opacity(0.4))
            .frame(width: 2.5, height: 2.5)
    }

    // MARK: - Bar chart

    private func barChart(_ days: [DailyActivity], dense: Bool) -> some View {
        let maxTokens = max(days.map(\.tokens).max() ?? 1, 1)
        let staticTopFont: CGFloat = dense ? 7 : 8
        return HStack(alignment: .bottom, spacing: dense ? 3 : 6) {
            ForEach(days) { day in
                let hovered = hoveredDay == day.day
                let bottomText = dense ? bottomTick(for: day) : weekdayLabel(day.day)
                // True only on Sunday columns — the hairline anchors
                // the weekly rhythm, independent of whether today also
                // happens to carry a label.
                let isWeekStart = dense && Calendar.current.component(.weekday, from: day.day) == 1
                VStack(spacing: 4) {
                    // Top readout — hovering a column swaps the day's
                    // agent count for its exact token spend. Hover label
                    // stays at 8pt so the active column reads slightly
                    // larger than its dense-mode neighbours.
                    Text(topLabel(for: day, hovered: hovered))
                        .font(.system(size: hovered ? 8 : staticTopFont, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(hovered ? Theme.Neon.blue : Theme.textDim)
                        .lineLimit(1)
                        .modifier(DenseFixedSize(dense: dense))

                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                day.tokens > 0
                                    ? Theme.Neon.blue.opacity(
                                        hovered ? 1.0 : (isToday(day.day) ? 0.92 : 0.7)
                                      )
                                    : Color.white.opacity(hovered ? 0.12 : 0.06)
                            )
                            .frame(height: barHeight(day.tokens, max: maxTokens))

                        if isWeekStart {
                            Rectangle()
                                .fill(Theme.hairline)
                                .frame(height: 0.5)
                                .offset(y: 1)
                        }
                    }

                    Text(bottomText)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(
                            hovered || isToday(day.day) ? Theme.Neon.blue : Theme.textFaint
                        )
                        .lineLimit(1)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onHover { inside in
                    hoveredDay = inside ? day.day : (hoveredDay == day.day ? nil : hoveredDay)
                }
            }
        }
        .frame(height: 108)
        .padding(.vertical, 2)
        .animation(.easeOut(duration: 0.12), value: hoveredDay)
    }

    /// In 7d mode the top label is allowed to render at its natural
    /// width via `.fixedSize()` (columns are wide). In 30d/dense mode
    /// columns are too narrow to fit a full token string, so we let
    /// SwiftUI truncate via the default flexible width.
    private struct DenseFixedSize: ViewModifier {
        let dense: Bool
        func body(content: Content) -> some View {
            if dense {
                content
            } else {
                content.fixedSize()
            }
        }
    }

    /// Sparse bottom tick for the 30d/dense chart: day-of-month for
    /// today and the start of each Sunday-first week; a space for
    /// other days so column heights stay aligned. Sunday anchor
    /// matches the squares heatmap, keeping the two views aligned
    /// regardless of locale firstWeekday.
    private func bottomTick(for day: DailyActivity) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day.day) {
            return "\(cal.component(.day, from: day.day))"
        }
        if cal.component(.weekday, from: day.day) == 1 {
            return "\(cal.component(.day, from: day.day))"
        }
        return " "
    }

    /// Top-of-column text: token spend while hovered, otherwise the
    /// day's agent count (blank when nothing ran).
    private func topLabel(for day: DailyActivity, hovered: Bool) -> String {
        if hovered {
            return TokenTracker.format(day.tokens)
        }
        return day.agentCount > 0 ? "\(day.agentCount)" : " "
    }

    private func barHeight(_ tokens: Int, max: Int) -> CGFloat {
        let minH: CGFloat = 3
        let maxH: CGFloat = 80
        guard tokens > 0 else { return minH }
        return minH + (maxH - minH) * CGFloat(tokens) / CGFloat(max)
    }

    // MARK: - Projects list

    @ViewBuilder
    private var projectsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                dashLine
                Text("WORKED ON")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textDim)
                dashLine
            }

            if projectGroups.isEmpty {
                Text("No agent activity in this range.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(projectGroups) { group in
                            projectRow(group)
                        }
                    }
                }
                .frame(maxHeight: 132)
            }
        }
    }

    @ViewBuilder
    private func projectRow(_ group: ProjectGroup) -> some View {
        let isExpandable = group.worktrees.count > 1
        let expanded = expandedGroups.contains(group.rootName)
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                if isExpandable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 8)
                } else {
                    Circle()
                        .fill(Theme.Neon.blue)
                        .frame(width: 5, height: 5)
                        .frame(width: 8)
                }
                Text(group.rootName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textStrong)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(TokenTracker.format(group.tokens))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textDim)
                Text("·")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textFaint)
                Text("\(group.activeDays)d")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                guard isExpandable else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    if expanded {
                        expandedGroups.remove(group.rootName)
                    } else {
                        expandedGroups.insert(group.rootName)
                    }
                }
            }

            if isExpandable && expanded {
                VStack(spacing: 2) {
                    ForEach(group.worktrees) { worktree in
                        worktreeRow(worktree, rootName: group.rootName)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 0.5)
                )
        )
    }

    /// Indented sub-row inside an expanded group. Shows just the
    /// branch name (the "/feat-x" half of "repo/feat-x") and the
    /// per-worktree token + active-day count in a quieter style than
    /// the parent row.
    private func worktreeRow(_ worktree: ProjectSpend, rootName: String) -> some View {
        let branch: String = {
            if let slash = worktree.name.firstIndex(of: "/") {
                return String(worktree.name[worktree.name.index(after: slash)...])
            }
            return "main"
        }()
        return HStack(spacing: 6) {
            Text("└")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textFaint)
                .padding(.leading, 4)
            Text(branch)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Theme.textDim)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(TokenTracker.format(worktree.tokens))
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textFaint)
            Text("·")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textFaint)
            Text("\(worktree.activeDays)d")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.textFaint)
        }
    }

    private var dashLine: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Date helpers

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    /// Single-letter weekday — M T W T F S S.
    private func weekdayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f.string(from: date)
    }
}

struct SquaresHistoryGrid: View {
    let days: [DailyActivity]      // up to 364 entries, oldest first

    /// Owned by the parent — the hover chip above the grid reads from
    /// this same binding so squares share a chip with the bar charts.
    @Binding var hoveredDay: Date?

    /// Hard upper bound — matches the .window range (52 weeks).
    private let maxCols = 52
    private let rows = 7
    private let gap: CGFloat = 3
    /// The widest a cell is allowed to draw — drives both the per-cell
    /// clamp and the outer frame height so the slot lines up with the
    /// bar chart's vertical footprint (~109pt).
    private let maxCell: CGFloat = 13

    var body: some View {
        GeometryReader { geo in
            // Cell sizing: divide the available width by the full
            // 52-week budget, subtract the gap, and clamp into the
            // GitHub range. At narrow widths the cell floors at 8pt
            // so the grid stays legible.
            let cell = min(max((geo.size.width / CGFloat(maxCols)) - gap, 8), maxCell)
            // Then back-solve how many full columns actually fit.
            let cols = min(maxCols, max(1, Int(floor(geo.size.width / (cell + gap)))))
            grid(cell: cell, cols: cols)
        }
        .frame(height: CGFloat(rows) * maxCell + CGFloat(rows - 1) * gap)
    }

    // MARK: grid

    private func grid(cell: CGFloat, cols: Int) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todayRow = (cal.component(.weekday, from: today) - 1) % 7

        var byDate: [Date: DailyActivity] = [:]
        for d in days { byDate[d.day] = d }

        let maxTokens = max(days.map(\.tokens).max() ?? 1, 1)
        let firstColDay: Date = {
            let daysBack = (cols - 1) * 7 + todayRow
            return cal.date(byAdding: .day, value: -daysBack, to: today)!
        }()

        return HStack(spacing: gap) {
            ForEach(0 ..< cols, id: \.self) { c in
                VStack(spacing: gap) {
                    ForEach(0 ..< rows, id: \.self) { r in
                        cellView(
                            col: c, row: r, cell: cell,
                            firstDay: firstColDay,
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
                // White stroke stays visible against every fill tier —
                // a Theme.Neon.blue stroke disappears into a q4 fill,
                // which is exactly when today is busiest.
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isToday ? Color.white.opacity(0.95) : Color.clear, lineWidth: 1.2)
            )
            .frame(width: cell, height: cell)
            .contentShape(Rectangle())
            .onHover { inside in
                if isFuture { return }
                if inside {
                    hoveredDay = date
                } else if hoveredDay == date {
                    hoveredDay = nil
                }
            }
    }
}

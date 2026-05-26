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

    /// Active range slice of the tracker's 119-day history. The range
    /// pills in the header mutate this; defaults to 7 days.
    @State private var range: TokenTracker.HistoryRange = .week

    /// Day whose bar the cursor is currently over — drives the
    /// hover readout (token spend) above that column.
    @State private var hoveredDay: Date?

    private var days: [DailyActivity] { tracker.days(for: range) }
    private var projectsForRange: [ProjectSpend] { tracker.projects(for: range) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            summaryStrip
            switch range {
            case .week:
                barChart(tracker.days(for: .week), dense: false)
            case .month:
                barChart(tracker.days(for: .month), dense: true)
            case .window:
                SquaresHistoryGrid(days: tracker.days(for: .window))
            }
            projectsList
        }
        .animation(.easeOut(duration: 0.18), value: range)
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
            rangePill(.window, icon: "square.grid.3x3.fill", a11y: "Last 119 days, squares view")
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
            summaryStat(value: "\(projectsForRange.count)", label: projectsForRange.count == 1 ? "project" : "projects", accent: Theme.Neon.green)
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
                let isWeekTick = dense && bottomText.trimmingCharacters(in: .whitespaces).isEmpty == false
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

                        if isWeekTick {
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
    /// today and the start of each locale-defined week; a space for
    /// other days so column heights stay aligned.
    private func bottomTick(for day: DailyActivity) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day.day) {
            return "\(cal.component(.day, from: day.day))"
        }
        if cal.component(.weekday, from: day.day) == cal.firstWeekday {
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

            if projectsForRange.isEmpty {
                Text("No agent activity in this range.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(projectsForRange) { project in
                            projectRow(project)
                        }
                    }
                }
                .frame(maxHeight: 132)
            }
        }
    }

    private func projectRow(_ project: ProjectSpend) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.Neon.blue)
                .frame(width: 5, height: 5)
            Text(project.name)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.textStrong)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(TokenTracker.format(project.tokens))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textDim)
            Text("·")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textFaint)
            Text("\(project.activeDays)d")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 0.5)
                )
        )
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
                // Clamp to the same 34pt height baked into the outer
                // frame so the last row never clips when the panel is
                // slightly wider than expected.
                let cell = min(max(((geo.size.width - rowLabelWidth) / CGFloat(cols)) - gap, 12), 34)
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
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todayRow = (cal.component(.weekday, from: today) - 1) % 7

        var byDate: [Date: DailyActivity] = [:]
        for d in days { byDate[d.day] = d }

        let maxTokens = max(days.map(\.tokens).max() ?? 1, 1)
        let firstColMonday: Date = {
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

// ActivityHistoryView — weekly activity dashboard shown in place of the
// agent grid when the user taps the token counter. Hand-rolled bar
// chart (7 bars, no Charts dependency) so it matches the pitch-black
// neon theme exactly: daily token spend, agent count per day, and the
// projects worked on across the window.

import SwiftUI

struct ActivityHistoryView: View {
    let weekly: [DailyActivity]
    let projects: [ProjectSpend]
    let onBack: () -> Void

    /// Day whose bar the cursor is currently over — drives the
    /// hover readout (token spend) above that column.
    @State private var hoveredDay: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            summaryStrip
            barChart
            projectsList
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
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

            Text("Last 7 days")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(Theme.textStrong)
            Spacer()
        }
    }

    // MARK: - Summary strip

    private var totalTokens: Int { weekly.reduce(0) { $0 + $1.tokens } }
    private var activeDays: Int { weekly.filter { $0.tokens > 0 }.count }

    private var summaryStrip: some View {
        HStack(spacing: 6) {
            summaryStat(value: TokenTracker.format(totalTokens), label: "tokens", accent: Theme.Neon.blue)
            dot
            summaryStat(value: "\(projects.count)", label: projects.count == 1 ? "project" : "projects", accent: Theme.Neon.green)
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

    private var barChart: some View {
        let maxTokens = max(weekly.map(\.tokens).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(weekly) { day in
                let hovered = hoveredDay == day.day
                VStack(spacing: 4) {
                    // Top readout — hovering a column swaps the day's
                    // agent count for its exact token spend.
                    Text(topLabel(for: day, hovered: hovered))
                        .font(.system(size: 8, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(hovered ? Theme.Neon.blue : Theme.textDim)
                        .lineLimit(1)
                        .fixedSize()

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            day.tokens > 0
                                ? Theme.Neon.blue.opacity(
                                    hovered ? 1.0 : (isToday(day.day) ? 0.92 : 0.7)
                                  )
                                : Color.white.opacity(hovered ? 0.12 : 0.06)
                        )
                        .frame(height: barHeight(day.tokens, max: maxTokens))

                    Text(weekdayLabel(day.day))
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(
                            hovered || isToday(day.day) ? Theme.Neon.blue : Theme.textFaint
                        )
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

            if projects.isEmpty {
                Text("No agent activity in the last 7 days.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(projects) { project in
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

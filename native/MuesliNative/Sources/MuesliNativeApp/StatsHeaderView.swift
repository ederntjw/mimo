import SwiftUI
import MuesliCore

struct StatsHeaderView: View {
    let dictationStats: DictationStats
    let meetingStats: MeetingStats
    var showsMeetingStat = true
    var tracksInsightsFeatureTour = false
    var horizontalPadding: CGFloat = MuesliTheme.spacing24
    let onSelect: (InsightsSection) -> Void

    private struct Metric: Identifiable {
        let section: InsightsSection
        let value: String
        let label: String
        let accessibilityHint: String

        var id: InsightsSection { section }
    }

    private var metrics: [Metric] {
        var result = [
            Metric(
                section: .streak,
                value: "\(dictationStats.currentStreakDays)",
                label: "day streak",
                accessibilityHint: "Open streak insights"
            ),
            Metric(
                section: .words,
                value: formatWordCount(dictationStats.totalWords),
                label: "words dictated",
                accessibilityHint: "Open word activity insights"
            ),
            Metric(
                section: .pace,
                value: String(format: "%.0f", dictationStats.averageWPM),
                label: "words / min",
                accessibilityHint: "Open speaking pace insights"
            ),
        ]
        if showsMeetingStat {
            result.append(Metric(
                section: .meetings,
                value: "\(meetingStats.totalMeetings)",
                label: "meetings",
                accessibilityHint: "Open meeting insights"
            ))
        }
        return result
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                    if index > 0 {
                        Rectangle()
                            .fill(MuesliTheme.surfaceBorder)
                            .frame(width: 1, height: 30)
                            .padding(.horizontal, MuesliTheme.spacing8)
                    }
                    metricButton(metric)
                        .frame(minWidth: 110, maxWidth: .infinity)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110), spacing: MuesliTheme.spacing12)],
                alignment: .leading,
                spacing: MuesliTheme.spacing12
            ) {
                ForEach(metrics) { metric in
                    metricButton(metric)
                }
            }
        }
        .padding(.vertical, MuesliTheme.spacing16)
        .padding(.horizontal, horizontalPadding)
        .featureTourTarget(tracksInsightsFeatureTour ? .insightsEntry : nil)
    }

    private func metricButton(_ metric: Metric) -> some View {
        CompactStatButton(
            value: metric.value,
            label: metric.label,
            accessibilityHint: metric.accessibilityHint,
            action: { onSelect(metric.section) }
        )
    }

    private func formatWordCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}

private struct CompactStatButton: View {
    let value: String
    let label: String
    let accessibilityHint: String
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                Text(value)
                    .font(MuesliTheme.displayTitle(26))
                    .monospacedDigit()
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .contentTransition(.numericText())
                Text(label)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, MuesliTheme.spacing8)
            .background(isHovered ? MuesliTheme.backgroundHover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .contentShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        }
        .buttonStyle(InsightsStatButtonStyle(reduceMotion: reduceMotion))
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .help(accessibilityHint)
        .accessibilityLabel("\(value) \(label)")
        .accessibilityHint(accessibilityHint)
    }
}

private struct InsightsStatButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

import SwiftUI
import WidgetKit

/// Three rings for the day: focus minutes, right answers, resisted impulses.
struct TodayWidget: Widget {
    let kind = "MaToday"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MaProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName(tr("Today", "Heute"))
        .description(tr("Focus, learning and resisted impulses as three rings.",
                        "Fokus, Lernen und Impulse, denen du widerstanden hast, als drei Ringe."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayWidgetView: View {
    let entry: MaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .nightBackground(for: family)
            .widgetURL(MaLink.today.url)
    }

    @ViewBuilder
    private var content: some View {
        if family == .systemMedium {
            medium
        } else {
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Today", "Heute"))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Night.inkSoft)
            TripleRings(snapshot: entry.snapshot, size: 96, lineWidth: 9)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(summary))
    }

    private var medium: some View {
        let today = entry.snapshot.today
        let focusText: String = tr("\(today.focusMinutes) of \(MaSnapshot.focusGoal) min",
                                   "\(today.focusMinutes) von \(MaSnapshot.focusGoal) Min.")
        let learnText: String = tr("\(today.correct) of \(MaSnapshot.learnGoal) right",
                                   "\(today.correct) von \(MaSnapshot.learnGoal) richtig")
        let resistText: String = Self.impulses(today.resisted)
        return HStack(spacing: 18) {
            TripleRings(snapshot: entry.snapshot, size: 118, lineWidth: 11)
            VStack(alignment: .leading, spacing: 10) {
                // Each row opens the part of the app it talks about.
                Link(destination: MaLink.focus.url) {
                    legend(tint: Night.shu, title: tr("Focus", "Fokus"), value: focusText)
                }
                Link(destination: MaLink.learn.url) {
                    legend(tint: Night.ai, title: tr("Learning", "Lernen"), value: learnText)
                }
                Link(destination: MaLink.today.url) {
                    legend(tint: Night.matcha, title: tr("Resisted", "Widerstanden"), value: resistText)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func legend(tint: Color, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Night.inkSoft)
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Night.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let today = entry.snapshot.today
        return tr("Today: \(today.focusMinutes) minutes of focus, \(today.correct) right answers, \(Self.impulses(today.resisted)) resisted.",
                  "Heute: \(today.focusMinutes) Minuten Fokus, \(today.correct) richtige Antworten, \(Self.impulses(today.resisted)) widerstanden.")
    }

    static func impulses(_ count: Int) -> String {
        if count == 1 { return tr("1 impulse", "1 Impuls") }
        return tr("\(count) impulses", "\(count) Impulse")
    }
}

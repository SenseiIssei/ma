import SwiftUI
import WidgetKit

/// The running focus round at a glance, or a way in when none runs.
struct FocusWidget: Widget {
    let kind = "MaFocus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MaProvider()) { entry in
            FocusWidgetView(entry: entry)
        }
        .configurationDisplayName(tr("Focus", "Fokus"))
        .description(tr("Time left in the running round, or a quick way to start one.",
                        "Die Restzeit der laufenden Runde oder ein schneller Start."))
        .supportedFamilies([.systemSmall])
    }
}

struct FocusWidgetView: View {
    let entry: MaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .nightBackground(for: family)
            .widgetURL(MaLink.focus.url)
    }

    @ViewBuilder
    private var content: some View {
        if let session = entry.snapshot.focus {
            running(session)
        } else {
            idle
        }
    }

    private func running(_ session: WidgetFocusSession) -> some View {
        let tint: Color = Night.tint(isBreak: session.isBreak)
        let total: Int = max(1, entry.snapshot.settings.roundsUntilLongBreak)
        return VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(session.title)
            } icon: {
                Image(systemName: Night.symbol(isBreak: session.isBreak))
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .widgetAccentable()

            Spacer(minLength: 0)

            // Counts down on its own; the widget does not need a reload per second.
            Text(timerInterval: session.interval, countsDown: true)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Night.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            ProgressView(timerInterval: session.interval, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(tint)

            RoundDots(round: session.round, totalRounds: total, isBreak: session.isBreak, size: 6)
        }
    }

    private var idle: some View {
        let minutes: Int = entry.snapshot.settings.focusMinutes
        return VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "timer")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Night.shu)
                .widgetAccentable()
            Spacer(minLength: 0)
            Text(tr("Start focus", "Fokus starten"))
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Night.ink)
            Text(tr("\(minutes) quiet minutes", "\(minutes) ruhige Minuten"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Night.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

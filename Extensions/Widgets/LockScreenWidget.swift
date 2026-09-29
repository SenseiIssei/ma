import SwiftUI
import WidgetKit

/// Lock Screen widgets: a ring and a line. During a focus round both show
/// the countdown, otherwise today's progress.
struct LockScreenWidget: Widget {
    let kind = "MaGlance"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MaProvider()) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName(tr("Ma at a glance", "Ma auf einen Blick"))
        .description(tr("The focus countdown, or your day so far.",
                        "Der Fokus-Countdown oder dein bisheriger Tag."))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct LockScreenWidgetView: View {
    let entry: MaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let link: MaLink = entry.snapshot.focus == nil ? .today : .focus
        content
            .nightBackground(for: family)
            .widgetURL(link.url)
    }

    @ViewBuilder
    private var content: some View {
        if family == .accessoryRectangular {
            rectangular
        } else {
            circular
        }
    }

    // MARK: Circular

    @ViewBuilder
    private var circular: some View {
        if let session = entry.snapshot.focus {
            // Timer-driven, so the ring drains without timeline entries.
            ProgressView(timerInterval: session.interval, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: Night.symbol(isBreak: session.isBreak))
            }
            .progressViewStyle(.circular)
            .widgetAccentable()
        } else {
            let today = entry.snapshot.today
            let progress: Double = min(1, entry.snapshot.focusProgress)
            Gauge(value: progress) {
                Image(systemName: "timer")
            } currentValueLabel: {
                Text("\(today.focusMinutes)")
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityLabel(Text(tr("\(today.focusMinutes) minutes of focus today",
                                        "Heute \(today.focusMinutes) Minuten Fokus")))
        }
    }

    // MARK: Rectangular

    @ViewBuilder
    private var rectangular: some View {
        if let session = entry.snapshot.focus {
            let total: Int = max(1, entry.snapshot.settings.roundsUntilLongBreak)
            VStack(alignment: .leading, spacing: 1) {
                Label(session.title, systemImage: Night.symbol(isBreak: session.isBreak))
                    .font(.headline)
                    .widgetAccentable()
                Text(timerInterval: session.interval, countsDown: true)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text(tr("Round \(session.round) of \(total)", "Runde \(session.round) von \(total)"))
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let today = entry.snapshot.today
            VStack(alignment: .leading, spacing: 1) {
                Label(tr("Today", "Heute"), systemImage: "circle.circle")
                    .font(.headline)
                    .widgetAccentable()
                Text(tr("\(today.focusMinutes) min focus, \(today.correct) right",
                        "\(today.focusMinutes) Min. Fokus, \(today.correct) richtig"))
                    .font(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(tr("\(TodayWidgetView.impulses(today.resisted)) resisted",
                        "\(TodayWidgetView.impulses(today.resisted)) widerstanden"))
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

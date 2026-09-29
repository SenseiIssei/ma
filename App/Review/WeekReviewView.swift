import DeviceActivity
import FamilyControls
import SwiftUI

extension DeviceActivityReport.Context {
    /// The scene MaReport draws for this. Same raw value on both sides.
    static let week = Self("week")
}

/// The weekly look back: iOS Screen Time drawn by the report extension,
/// then Ma's own counters against the week before.
struct WeekReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var summary: WeekSummary
    @State private var filter: DeviceActivityFilter
    @State private var asking = false

    init(now: Date = Date()) {
        _summary = State(initialValue: WeekSummary(stats: SharedStore.stats, now: now))
        // Built once and kept in state: a new filter on every redraw would
        // make iOS ask the extension for the whole report again.
        _filter = State(initialValue: Self.lastSevenDays(now: now))
    }

    /// Today and the six days before, cut into one segment per day so the
    /// extension can draw a bar for each.
    static func lastSevenDays(now: Date, calendar: Calendar = .current) -> DeviceActivityFilter {
        let today: Date = calendar.startOfDay(for: now)
        let start: Date = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let end: Date = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let interval = DateInterval(start: start, end: end)
        // No devices means this iPhone only; empty sets mean every app.
        return DeviceActivityFilter(segment: .daily(during: interval), devices: nil,
                                    applications: [], categories: [], webDomains: [])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    summaryCard
                    numbers
                    highlights
                    screenTime
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.bottom, 40)
            }
            .background(AppBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Done", "Fertig")) { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Zen.shu)
                }
            }
        }
        .onAppear {
            // The extensions may have counted more since the sheet was built.
            summary = WeekSummary(stats: SharedStore.stats)
        }
    }

    // MARK: Header

    private var rangeText: String {
        let first: Date = summary.days.first?.date ?? Date()
        let last: Date = summary.days.last?.date ?? Date()
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(Loc.locale)
        return tr("\(first.formatted(style)) to \(last.formatted(style))",
                  "\(first.formatted(style)) bis \(last.formatted(style))")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Illustration(name: "IllustrationEvening", height: 190)
            VStack(alignment: .leading, spacing: 4) {
                Text(rangeText.uppercased(with: Loc.locale))
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Zen.inkSoft)
                Text(tr("Your week", "Deine Woche"))
                    .font(.display(34))
                    .foregroundStyle(Zen.ink)
            }
        }
        .padding(.top, 4)
    }

    private var summaryCard: some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(systemName: "moon.stars.fill", tint: Zen.shu, size: 44)
            Text(summary.sentence)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Zen.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .zenCard(padding: 20)
    }

    // MARK: Ma's numbers

    private var numbers: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "chart.bar.fill", title: tr("With Ma", "Mit Ma")) {
                Text(tr("vs. last week", "zur Vorwoche"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Zen.inkSoft)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(summary.metrics) { metric in
                    MetricCard(metric: metric)
                }
            }
        }
    }

    // MARK: Best day and streak

    private var highlights: some View {
        let best: ReviewDay? = summary.bestDay
        let bestTitle: String = best.map {
            $0.date.formatted(.dateTime.weekday(.wide).locale(Loc.locale))
        } ?? tr("Not yet", "Noch keiner")
        let bestDetail: String = best.map { Self.bestDetail($0) }
            ?? tr("Your best day will show up here.", "Hier erscheint dein bester Tag.")
        let streak = summary.streak
        let streakTitle: String = streak == 1 ? tr("1 day", "1 Tag") : tr("\(streak) days", "\(streak) Tage")
        let streakDetail: String = streak > 0
            ? tr("in a row with Ma", "in Folge mit Ma")
            : tr("starts with your next pause", "beginnt mit deiner nächsten Pause")

        return HStack(alignment: .top, spacing: 12) {
            HighlightCard(icon: "star.fill", tint: Zen.kin, label: tr("Best day", "Bester Tag"),
                          title: bestTitle, detail: bestDetail)
            HighlightCard(icon: "flame.fill", tint: Zen.matcha, label: tr("Streak", "Serie"),
                          title: streakTitle, detail: streakDetail)
        }
    }

    private static func bestDetail(_ day: ReviewDay) -> String {
        var parts: [String] = []
        if day.resisted > 0 { parts.append(tr("\(day.resisted) resisted", "\(day.resisted) widerstanden")) }
        if day.correct > 0 { parts.append(tr("\(day.correct) right", "\(day.correct) richtig")) }
        if day.rounds > 0 {
            parts.append(day.rounds == 1 ? tr("1 round", "1 Runde") : tr("\(day.rounds) rounds", "\(day.rounds) Runden"))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Screen Time

    private var screenTimeReady: Bool {
        BuildFlavor.screenTimeAvailable && model.authorization == .approved
    }

    private var screenTime: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "hourglass", title: tr("Screen time", "Bildschirmzeit"))
            if screenTimeReady {
                // A report cannot size itself to its content, so it gets a
                // fixed height that fits what WeekActivityView lays out.
                DeviceActivityReport(.week, filter: filter)
                    .frame(height: 700)
                Text(tr("These numbers come from iOS and stay on this iPhone. Ma itself never sees them.",
                        "Diese Zahlen kommen von iOS und bleiben auf diesem iPhone. Ma selbst sieht sie nie."))
                    .font(.system(size: 12))
                    .foregroundStyle(Zen.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                screenTimeMissing
            }
        }
    }

    private var screenTimeMissing: some View {
        let available = BuildFlavor.screenTimeAvailable
        let text: String = available
            ? tr("Allow Screen Time and Ma shows your week here: total time, every day and the apps that took the most.",
                 "Erlaube die Bildschirmzeit, dann zeigt Ma hier deine Woche: die Gesamtzeit, jeden Tag und die Apps, die am meisten Zeit bekommen haben.")
            : BuildFlavor.previewNote

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(systemName: "hourglass", tint: Zen.inkSoft, size: 44)
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if available {
                Button(tr("Allow Screen Time", "Bildschirmzeit erlauben")) {
                    Haptics.tap()
                    asking = true
                    Task {
                        await model.requestScreenTime()
                        asking = false
                    }
                }
                .buttonStyle(.primary)
                .disabled(asking)
            }
        }
        .zenCard(padding: 20)
    }
}

// MARK: - Cards

/// One of Ma's counters with the arrow against last week.
private struct MetricCard: View {
    let metric: WeekMetric

    private var icon: String {
        switch metric.kind {
        case .resisted: "hand.raised.fill"
        case .unlocks: "lock.open.fill"
        case .correct: "checkmark.bubble.fill"
        case .focusMinutes: "timer"
        case .rounds: "circle.dotted.circle"
        }
    }

    private var tint: Color {
        switch metric.kind {
        case .resisted: Zen.matcha
        case .unlocks: Zen.kin
        case .correct: Zen.ai
        case .focusMinutes, .rounds: Zen.shu
        }
    }

    private var label: String {
        switch metric.kind {
        case .resisted: tr("impulses resisted", "Impulse widerstanden")
        case .unlocks: tr("unlocks", "Freigaben")
        case .correct: tr("answers right", "richtige Antworten")
        case .focusMinutes: tr("focus", "Fokus")
        case .rounds: tr("focus rounds", "Fokusrunden")
        }
    }

    private func format(_ value: Int) -> String {
        metric.kind == .focusMinutes ? WeekSummary.minutesText(value) : "\(value)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(format(metric.current))
                .font(.display(24))
                .monospacedDigit()
                .foregroundStyle(Zen.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Zen.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            TrendBadge(metric: metric, format: format)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .zenCard(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

/// Arrow plus change. Green when it moved the good way, warm amber when not:
/// a weaker week is a nudge, never an alarm, so no red here.
private struct TrendBadge: View {
    let metric: WeekMetric
    let format: (Int) -> String

    var body: some View {
        let symbol: String
        switch metric.trend {
        case .up: symbol = "arrow.up"
        case .down: symbol = "arrow.down"
        case .same: symbol = "equal"
        }
        let color: Color = metric.improved ? Zen.matcha : (metric.worsened ? Zen.kin : Zen.inkFaint)
        let amount: String = metric.trend == .same
            ? tr("same", "gleich")
            : format(abs(metric.delta))
        let before: String = tr("last week \(format(metric.previous))", "Vorwoche \(format(metric.previous))")

        return VStack(alignment: .leading, spacing: 2) {
            Label(amount, systemImage: symbol)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .labelStyle(TightLabel())
            Text(before)
                .font(.system(size: 11))
                .foregroundStyle(Zen.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.top, 2)
    }
}

/// Icon and title closer together than the default label.
private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

private struct HighlightCard: View {
    let icon: String
    let tint: Color
    let label: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconBadge(systemName: icon, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Zen.inkSoft)
                Text(title)
                    .font(.display(19, weight: .semibold))
                    .foregroundStyle(Zen.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .zenCard(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

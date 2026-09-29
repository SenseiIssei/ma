import SwiftUI

/// The Balance tab: move a little, drink and eat with some care, and let
/// the evening wind down. One calm scrolling page, summary first.
struct BalanceView: View {
    @Environment(BalanceStore.self) private var balance
    @State private var routine: Routine?

    var body: some View {
        NavigationStack {
            // Ticks once a minute so "today" and the sleep phase follow the
            // clock while the tab stays open, also across midnight.
            TimelineView(.everyMinute) { context in
                content(now: context.date)
            }
            .background(AppBackground())
            .fullScreenCover(item: $routine) { routine in
                MovePlayerView(routine: routine)
                    .environment(balance)
            }
        }
    }

    private func content(now: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageTitle(title: tr("Balance", "Balance"),
                          subtitle: tr("Move a little, drink some water, sleep well. Small things that carry the day.",
                                       "Ein bisschen Bewegung, genug Wasser, guter Schlaf. Kleine Dinge, die den Tag tragen."),
                          icon: "leaf.fill")
                BalanceSummaryCard(now: now)
                MoveSection { routine = $0 }
                FoodSection(now: now)
                SleepSection(now: now)
                FriendsEntry()
            }
            .padding(.horizontal, Zen.gutter)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Summary

/// "Today in balance": three rings side by side, water, movement and the
/// evening routine.
struct BalanceSummaryCard: View {
    @Environment(BalanceStore.self) private var balance
    let now: Date

    var body: some View {
        let settings: BalanceSettings = balance.settings
        let today: BalanceDay = balance.today
        let tonight: BalanceDay = balance.tonight
        let total: Int = WindDownItem.allCases.count
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("Today in balance", "Heute im Gleichgewicht"))
                    .font(.display(20))
                    .foregroundStyle(Zen.ink)
                Spacer()
                if balance.dayInBalance {
                    Label(tr("All three", "Alle drei"), systemImage: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Zen.matcha)
                }
            }
            HStack(spacing: 12) {
                BalanceRing(progress: balance.waterProgress, tint: Zen.ai, icon: "drop.fill",
                            value: "\(today.water)/\(settings.waterTarget)",
                            label: tr("Glasses", "Gläser"))
                BalanceRing(progress: balance.moveProgress, tint: Zen.matcha, icon: "figure.walk",
                            value: "\(today.moveMinutes)/\(settings.moveGoalMinutes)",
                            label: tr("Minutes moved", "Min. Bewegung"))
                BalanceRing(progress: balance.windDownProgress, tint: Zen.shu, icon: "moon.stars.fill",
                            value: "\(tonight.windDown.count)/\(total)",
                            label: tr("Wind-down", "Runterfahren"))
            }
            Text(summaryLine)
                .font(.system(size: 14))
                .foregroundStyle(Zen.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .zenCard(padding: 20)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: balance.days)
    }

    /// One gentle nudge towards whatever is furthest behind.
    private var summaryLine: String {
        if balance.dayInBalance {
            return tr("A day in balance. Nothing left to chase.", "Ein Tag im Gleichgewicht. Nichts mehr zu jagen.")
        }
        let phase: SleepPlan.Phase = balance.settings.sleep.phase(at: now)
        if phase != .day && balance.windDownProgress < 1 {
            return tr("The evening is here. Tick off the wind-down below.", "Der Abend ist da. Hak unten das Runterfahren ab.")
        }
        let left: Int = WaterMath.remaining(glasses: balance.today.water, target: balance.settings.waterTarget)
        if balance.waterProgress <= balance.moveProgress && left > 0 {
            return tr("\(left) more \(left == 1 ? "glass" : "glasses") of water to go.", "Noch \(left) \(left == 1 ? "Glas" : "Gläser") Wasser.")
        }
        if balance.moveProgress < 1 {
            return tr("A short routine below fills the movement ring.", "Eine kurze Einheit unten füllt den Bewegungsring.")
        }
        return tr("Keep it gentle. The rest of the day is yours.", "Bleib sanft. Der Rest des Tages gehört dir.")
    }
}

struct BalanceRing: View {
    let progress: Double
    let tint: Color
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                ProgressRing(progress: progress, lineWidth: 9, tint: tint)
                Image(systemName: progress >= 1 ? "checkmark" : icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 82, height: 82)
            VStack(spacing: 2) {
                Text(value)
                    .font(.display(17))
                    .monospacedDigit()
                    .foregroundStyle(Zen.ink)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Zen.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

// MARK: - Shared bits

extension Routine {
    var tint: Color {
        switch id {
        case .morning: Zen.kin
        case .desk: Zen.ai
        case .sevenMinute: Zen.negative
        case .evening: Zen.shu
        }
    }
}

/// A small caption line under a section, like the safety note.
struct BalanceNote: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Zen.inkSoft)
    }
}

// MARK: - Friends

/// Doorway to friends circles: numbers only, never a feed.
struct FriendsEntry: View {
    var body: some View {
        NavigationLink {
            FriendsView()
        } label: {
            HStack(spacing: 14) {
                IconBadge(systemName: "person.2.fill", tint: Zen.ai)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Friends without a feed", "Freunde ohne Feed"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Zen.ink)
                    Text(tr("Keep each other going with streaks and weekly challenges. Only numbers are shared.",
                            "Motiviert euch mit Serien und Wochen-Challenges. Geteilt werden nur Zahlen."))
                        .font(.system(size: 14))
                        .foregroundStyle(Zen.inkSoft)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Zen.inkFaint)
            }
            .zenCard()
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

enum WatchRoute: Hashable {
    case breathe, focus
}

/// Today at a glance: the three rings, the streak and the two ways in.
struct HomeView: View {
    @Environment(WatchSession.self) private var session

    var body: some View {
        // Once a minute is enough for rings; it also catches midnight.
        TimelineView(.everyMinute) { context in
            content(at: context.date)
        }
        .navigationTitle("Ma")
        .containerBackground(Night.background, for: .navigation)
        .navigationDestination(for: WatchRoute.self) { route in
            switch route {
            case .breathe: BreatheView()
            case .focus: WatchFocusView()
            }
        }
    }

    private func content(at date: Date) -> some View {
        let stored: WatchSnapshot = session.snapshot ?? WatchSnapshot(day: WatchSnapshot.dayKey(date))
        let day: WatchSnapshot = stored.current(at: date)
        let streak: Int = stored.streak(at: date)
        let running: WatchFocus? = stored.runningFocus(at: date)
        return ScrollView {
            VStack(spacing: 10) {
                rings(day)
                legend(day)
                if streak > 0 {
                    streakLabel(streak)
                }
                NavigationLink(value: WatchRoute.breathe) {
                    Label(tr("Breathe", "Atmen"), systemImage: "wind")
                }
                .buttonStyle(NightButtonStyle(tint: Night.matcha, filled: true))
                NavigationLink(value: WatchRoute.focus) {
                    focusLabel(running)
                }
                .buttonStyle(NightButtonStyle(tint: Night.shu, filled: true))
                if session.snapshot == nil {
                    Text(tr("Open Ma on your iPhone once to see your day here.",
                            "Öffne Ma einmal auf deinem iPhone, dann steht dein Tag hier."))
                        .font(.footnote)
                        .foregroundStyle(Night.inkSoft)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: Rings

    private func rings(_ day: WatchSnapshot) -> some View {
        ZStack {
            NightRing(progress: day.focusProgress, tint: Night.shu)
                .frame(width: 96, height: 96)
            NightRing(progress: day.learnProgress, tint: Night.ai)
                .frame(width: 72, height: 72)
            NightRing(progress: day.resistProgress, tint: Night.matcha)
                .frame(width: 48, height: 48)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func legend(_ day: WatchSnapshot) -> some View {
        let focusText: String = tr("\(day.focusMinutes)/\(WatchSnapshot.focusGoal) min", "\(day.focusMinutes)/\(WatchSnapshot.focusGoal) Min.")
        let learnText: String = tr("\(day.correct)/\(day.dailyGoal) right", "\(day.correct)/\(day.dailyGoal) richtig")
        let resistText: String = tr("\(day.resisted) resisted", "\(day.resisted) widerstanden")
        return VStack(alignment: .leading, spacing: 3) {
            legendRow(tint: Night.shu, title: tr("Focus", "Fokus"), value: focusText)
            legendRow(tint: Night.ai, title: tr("Learning", "Lernen"), value: learnText)
            legendRow(tint: Night.matcha, title: tr("Impulses", "Impulse"), value: resistText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendRow(tint: Color, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(Night.inkSoft)
            Spacer(minLength: 4)
            Text(value)
                .foregroundStyle(Night.ink)
                .monospacedDigit()
        }
        .font(.footnote)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }

    private func streakLabel(_ streak: Int) -> some View {
        let text: String = streak == 1
            ? tr("1 day learning", "1 Tag am Lernen")
            : tr("\(streak) days learning", "\(streak) Tage am Lernen")
        return Label(text, systemImage: "flame.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Night.kin)
    }

    // MARK: Focus button

    @ViewBuilder
    private func focusLabel(_ running: WatchFocus?) -> some View {
        if let running {
            HStack(spacing: 6) {
                Image(systemName: running.isBreak ? "cup.and.saucer.fill" : "timer")
                Text(timerInterval: running.interval, countsDown: true)
                    .monospacedDigit()
            }
        } else {
            Label(tr("Focus", "Fokus"), systemImage: "timer")
        }
    }
}

import SwiftUI

/// The running pomodoro phase, or a Start button when there is none. The
/// watch only asks; the iPhone starts and stops the round because it owns
/// the Screen Time shields.
struct WatchFocusView: View {
    @Environment(WatchSession.self) private var session

    var body: some View {
        // Redraws at each phase end the snapshot predicts, so a finished
        // round turns into its break without waiting for the phone.
        TimelineView(.explicit(boundaries)) { context in
            content(at: context.date)
        }
        .navigationTitle(tr("Focus", "Fokus"))
        .containerBackground(Night.background, for: .navigation)
    }

    /// The next few phase ends, walked forward from the snapshot.
    private var boundaries: [Date] {
        var dates: [Date] = [Date()]
        guard let snapshot = session.snapshot else { return dates }
        var phase: WatchFocus? = snapshot.runningFocus(at: Date())
        for _ in 0..<6 {
            guard let current = phase else { break }
            dates.append(current.endsAt)
            phase = current.next(snapshot.settings)
        }
        return dates
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                if let snapshot = session.snapshot {
                    if let running = snapshot.runningFocus(at: date) {
                        runningView(running, settings: snapshot.settings)
                    } else {
                        idleView(snapshot.settings)
                    }
                } else {
                    neverSynced
                }
                if !session.reachable {
                    unreachableNote
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Running

    private func runningView(_ focus: WatchFocus, settings: WatchFocusSettings) -> some View {
        let tint: Color = focus.isBreak ? Night.matcha : Night.shu
        let stopping: Bool = session.pending == .stopFocus
        return VStack(spacing: 8) {
            Text(Self.title(of: focus.phase))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(tint)
            Text(timerInterval: focus.interval, countsDown: true)
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Night.ink)
                .multilineTextAlignment(.center)
            RoundDots(round: focus.round, total: settings.roundsUntilLongBreak, isBreak: focus.isBreak, tint: tint)
            Button {
                session.send(.stopFocus)
            } label: {
                Label(stopping ? tr("Ending...", "Wird beendet...") : tr("End", "Beenden"),
                      systemImage: "stop.fill")
            }
            .buttonStyle(NightButtonStyle(tint: Night.negative))
            .disabled(stopping)
        }
    }

    // MARK: Idle

    private func idleView(_ settings: WatchFocusSettings) -> some View {
        let starting: Bool = session.pending == .startFocus
        let length: String = tr("\(settings.focusMinutes) min focus, \(settings.shortBreakMinutes) min break",
                                "\(settings.focusMinutes) Min. Fokus, \(settings.shortBreakMinutes) Min. Pause")
        return VStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 28))
                .foregroundStyle(Night.shu)
            Text(tr("Ready for a round", "Bereit für eine Runde"))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Night.ink)
                .multilineTextAlignment(.center)
            Text(length)
                .font(.footnote)
                .foregroundStyle(Night.inkSoft)
                .multilineTextAlignment(.center)
            Button {
                session.send(.startFocus)
            } label: {
                Label(starting ? tr("Starting...", "Startet...") : tr("Start", "Starten"),
                      systemImage: "play.fill")
            }
            .buttonStyle(NightButtonStyle(tint: Night.shu, filled: true))
            .disabled(starting)
        }
    }

    // MARK: Notes

    private var neverSynced: some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone")
                .font(.system(size: 26))
                .foregroundStyle(Night.inkSoft)
            Text(tr("Open Ma on your iPhone once to connect.", "Öffne Ma einmal auf deinem iPhone, um zu verbinden."))
                .font(.footnote)
                .foregroundStyle(Night.inkSoft)
                .multilineTextAlignment(.center)
        }
    }

    /// Said plainly: without the phone nothing starts right now.
    private var unreachableNote: some View {
        let text: String = session.queued
            ? tr("iPhone not reachable. Your tap goes through once it is back nearby.",
                 "iPhone nicht erreichbar. Dein Tippen kommt an, sobald es wieder in der Nähe ist.")
            : tr("iPhone not reachable. Focus starts and ends on the iPhone.",
                 "iPhone nicht erreichbar. Fokus startet und endet auf dem iPhone.")
        return Label {
            Text(text)
        } icon: {
            Image(systemName: "iphone.slash")
        }
        .font(.footnote)
        .foregroundStyle(Night.kin)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Night.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    static func title(of phase: String) -> String {
        switch phase {
        case "shortBreak": return tr("Short break", "Kurze Pause")
        case "longBreak": return tr("Long break", "Lange Pause")
        default: return tr("Focus", "Fokus")
        }
    }
}

/// One dot per round until the long break. Finished rounds are full, the
/// running one is ringed.
struct RoundDots: View {
    let round: Int
    let total: Int
    let isBreak: Bool
    let tint: Color

    var body: some View {
        let count: Int = max(1, total)
        HStack(spacing: 6) {
            ForEach(1...count, id: \.self) { index in
                dot(index)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Round \(round) of \(count)", "Runde \(round) von \(count)"))
    }

    @ViewBuilder
    private func dot(_ index: Int) -> some View {
        // During a break the round it follows is already done.
        let done: Bool = index < round || (isBreak && index == round)
        let current: Bool = index == round && !isBreak
        if done {
            Circle().fill(tint).frame(width: 8, height: 8)
        } else if current {
            Circle().strokeBorder(tint, lineWidth: 2).frame(width: 8, height: 8)
        } else {
            Circle().fill(Night.line).frame(width: 8, height: 8)
        }
    }
}

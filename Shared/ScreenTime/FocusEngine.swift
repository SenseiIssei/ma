import Foundation

/// Pomodoro state machine. Lives in Shared because the monitor extension
/// has to move the timer on while the app is closed.
enum FocusEngine {
    static func start(round: Int = 1, now: Date = Date()) {
        let settings = SharedStore.focusSettings
        let session = FocusSession(
            phase: .focus,
            startedAt: now,
            duration: TimeInterval(settings.focusMinutes * 60),
            round: round
        )
        begin(session)
    }

    static func startBreak(after round: Int, now: Date = Date()) {
        let settings = SharedStore.focusSettings
        let long = round >= settings.roundsUntilLongBreak
        let session = FocusSession(
            phase: long ? .longBreak : .shortBreak,
            startedAt: now,
            duration: TimeInterval((long ? settings.longBreakMinutes : settings.shortBreakMinutes) * 60),
            round: round
        )
        begin(session)
    }

    static func stop() {
        SharedStore.focus = nil
        Scheduler.watchFocus(nil)
        Notifier.cancel(Notifier.focusID)
        ShieldEngine.apply()
    }

    /// Round the next focus block will carry once the current break is over.
    static var upcomingRound: Int {
        get { MaShared.read(Int.self, from: "focus-next.json") ?? 1 }
        set { MaShared.write(newValue, to: "focus-next.json") }
    }

    /// Moves any phase whose time is up to its successor. Safe to call from
    /// anywhere, as often as you like. Returns true if something changed.
    @discardableResult
    static func advanceIfDue(now: Date = Date()) -> Bool {
        guard var session = SharedStore.focus, now >= session.endsAt else { return false }
        let settings = SharedStore.focusSettings

        // A phone left in a drawer can skip several phases; walk them all.
        for _ in 0..<12 {
            switch session.phase {
            case .focus:
                let minutes = Int(session.duration / 60)
                SharedStore.updateToday {
                    $0.pomodoros += 1
                    $0.focusMinutes += minutes
                }
                let long = session.round >= settings.roundsUntilLongBreak
                session = FocusSession(
                    phase: long ? .longBreak : .shortBreak,
                    startedAt: session.endsAt,
                    duration: TimeInterval((long ? settings.longBreakMinutes : settings.shortBreakMinutes) * 60),
                    round: session.round
                )
            case .shortBreak, .longBreak:
                let nextRound = session.phase == .longBreak ? 1 : session.round + 1
                upcomingRound = nextRound
                guard settings.autoStartFocus else {
                    SharedStore.focus = nil
                    Scheduler.watchFocus(nil)
                    ShieldEngine.apply(now: now)
                    return true
                }
                session = FocusSession(
                    phase: .focus,
                    startedAt: session.endsAt,
                    duration: TimeInterval(settings.focusMinutes * 60),
                    round: nextRound
                )
            }
            if now < session.endsAt { break }
        }

        begin(session, now: now)
        return true
    }

    private static func begin(_ session: FocusSession, now: Date = Date()) {
        SharedStore.focus = session
        Scheduler.watchFocus(session)
        switch session.phase {
        case .focus:
            Notifier.schedule(
                id: Notifier.focusID,
                title: tr("集中 Round \(session.round) done", "集中 Runde \(session.round) geschafft"),
                body: tr("Stand up, look into the distance. Your break starts now.", "Steh kurz auf, schau in die Ferne. Die Pause beginnt."),
                at: session.endsAt
            )
        case .shortBreak, .longBreak:
            Notifier.schedule(
                id: Notifier.focusID,
                title: tr("休憩 Break is over", "休憩 Pause vorbei"),
                body: tr("Ready for the next round? Tap to carry on.", "Bereit für die nächste Runde? Tippe, um weiterzumachen."),
                at: session.endsAt
            )
        }
        ShieldEngine.apply(now: now)
    }
}

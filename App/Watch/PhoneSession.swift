import Foundation
import WatchConnectivity

/// The iPhone end of WatchConnectivity. Sends the watch a small snapshot of
/// the day as application context and takes its start and stop requests for
/// focus. The phone stays in charge because only it can raise the shields.
///
/// Threading: WCSession calls the delegate on a background queue. Every piece
/// of state here is touched on the main actor only; the delegate methods hop
/// there before reading or writing it.
final class PhoneSession: NSObject, WCSessionDelegate {
    static let shared = PhoneSession()

    /// Newest snapshot from AppModel, sent once the session allows it.
    private var latest: WatchSnapshot?
    /// Bytes of the last context that went out, to skip identical ones:
    /// reload() runs once a second on the focus screen.
    private var lastSent: Data?
    private var handler: (@MainActor (WatchCommand) -> Void)?
    /// Commands that arrived before AppModel attached its handler.
    private var waiting: [WatchCommand] = []
    private var activated = false

    private override init() {
        super.init()
    }

    // MARK: Called by AppModel

    /// Starts the session once and routes watch commands to `onCommand`.
    @MainActor
    func activate(onCommand: @escaping @MainActor (WatchCommand) -> Void) {
        handler = onCommand
        let queued: [WatchCommand] = waiting
        waiting = []
        for command in queued { onCommand(command) }

        guard !activated, WCSession.isSupported() else { return }
        activated = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Hands the newest state to the watch if it differs from what went out.
    @MainActor
    func push(_ snapshot: WatchSnapshot) {
        latest = snapshot
        flush()
    }

    // MARK: Sending

    @MainActor
    private func flush() {
        guard activated, let latest else { return }
        let session = WCSession.default
        // Without a paired watch that has Ma installed the call would throw.
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        guard let data = latest.encoded(), data != lastSent else { return }
        do {
            try session.updateApplicationContext([WatchSnapshot.contextKey: data])
            lastSent = data
        } catch {
            // Left unsent; the next reload() tries again.
        }
    }

    @MainActor
    private func deliver(_ command: WatchCommand) {
        guard let handler else {
            waiting.append(command)
            return
        }
        handler(command)
    }

    /// Reply to a command: whether it was understood plus the fresh snapshot,
    /// so the watch updates without waiting for the context to arrive.
    @MainActor
    private func reply(understood: Bool) -> [String: Any] {
        var reply: [String: Any] = ["ok": understood]
        if let data = latest?.encoded() {
            reply[WatchSnapshot.contextKey] = data
        }
        return reply
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            // A watch paired while Ma was closed gets the state right away.
            self.lastSent = nil
            self.flush()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switching to another watch deactivates the session; activate again
    /// so the new watch is served.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            // Ma just landed on the watch, or the watch changed: resend.
            self.lastSent = nil
            self.flush()
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let command: WatchCommand? = WatchCommand.parse(message, now: Date())
        Task { @MainActor in
            if let command { self.deliver(command) }
            replyHandler(self.reply(understood: command != nil))
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let command = WatchCommand.parse(message, now: Date()) else { return }
        Task { @MainActor in self.deliver(command) }
    }

    /// The fallback path: taps the watch queued while the phone was away.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let command = WatchCommand.parse(userInfo, now: Date()) else { return }
        Task { @MainActor in self.deliver(command) }
    }
}

// MARK: - AppModel side

extension AppModel {
    /// What the watch draws, built from the state reload() just read.
    func watchSnapshot() -> WatchSnapshot {
        let s: FocusSettings = focusSettings
        var settings = WatchFocusSettings()
        settings.focusMinutes = s.focusMinutes
        settings.shortBreakMinutes = s.shortBreakMinutes
        settings.longBreakMinutes = s.longBreakMinutes
        settings.roundsUntilLongBreak = s.roundsUntilLongBreak
        settings.autoStartFocus = s.autoStartFocus

        let profile: LearnerProfile = decks.profile
        var snapshot = WatchSnapshot(day: SharedStore.dayKey())
        snapshot.focusMinutes = today.focusMinutes
        snapshot.correct = today.correct
        snapshot.resisted = today.resisted
        snapshot.pomodoros = today.pomodoros
        snapshot.dailyGoal = max(1, profile.dailyGoal)
        snapshot.streakDays = profile.streakDays
        snapshot.lastLearnedDay = profile.lastLearnedDay
        snapshot.settings = settings
        snapshot.focus = focus.map { session in
            WatchFocus(
                id: session.id.uuidString,
                phase: session.phase.rawValue,
                startedAt: session.startedAt,
                duration: session.duration,
                round: session.round
            )
        }
        return snapshot
    }

    /// A start or stop from the watch. Both are guarded, so a double tap or
    /// a late delivery never restarts a running round or stops nothing.
    func handleWatch(_ command: WatchCommand) {
        // Settle phases the monitor moved on while the app slept first.
        reload()
        switch command {
        case .startFocus:
            guard focus == nil else { return }
            startFocus()
        case .stopFocus:
            guard let focus else { return }
            // Mindful release puts three questions in front of ending a
            // focus round early. The watch cannot ask them, so it may only
            // end breaks then; the round itself ends on the iPhone.
            if mindfulRelease && focus.phase == .focus { return }
            stopFocus()
        }
    }
}

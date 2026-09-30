import Foundation
import Observation
import WatchKit

/// Runs one breathing session: the clock, the haptic per phase and the
/// extended runtime session that keeps it all going when the wrist drops.
/// Timing is derived from the start date, so a pause in drawing never puts
/// the circle out of step with the clock.
@MainActor
@Observable
final class BreathRunner {
    private(set) var pattern: WatchBreathPattern = .calm
    private(set) var startedAt: Date?
    private(set) var length: Double = 0
    /// Seconds of the last finished session, for the done screen.
    private(set) var finishedSeconds: Int?

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var runtime: WKExtendedRuntimeSession?
    @ObservationIgnored private let runtimeDelegate = RuntimeDelegate()

    var isRunning: Bool { startedAt != nil }

    func start(_ pattern: WatchBreathPattern, minutes: Int) {
        stop(finished: false)
        self.pattern = pattern
        length = pattern.sessionLength(minutes: minutes)
        finishedSeconds = nil
        let now = Date()
        startedAt = now
        beginRuntime()
        runLoop(from: now)
    }

    /// Ends the session. `finished` marks a session that ran its full length.
    func stop(finished: Bool) {
        loop?.cancel()
        loop = nil
        if let startedAt {
            let seconds = Int(Date().timeIntervalSince(startedAt).rounded())
            finishedSeconds = finished ? Int(length.rounded()) : (seconds >= 10 ? seconds : nil)
        }
        startedAt = nil
        endRuntime()
    }

    func reset() {
        finishedSeconds = nil
    }

    // MARK: Haptics

    /// Sleeps until the next phase starts and taps the wrist then. Runs on
    /// its own, so the rhythm holds with the screen off.
    private func runLoop(from start: Date) {
        let pattern: WatchBreathPattern = self.pattern
        let length: Double = self.length
        loop = Task { @MainActor [weak self] in
            var lastTick = -1
            while !Task.isCancelled {
                let elapsed: Double = Date().timeIntervalSince(start)
                if elapsed >= length {
                    WKInterfaceDevice.current().play(.success)
                    self?.stop(finished: true)
                    return
                }
                let state: WatchBreathState = pattern.state(at: elapsed)
                if state.tick != lastTick {
                    lastTick = state.tick
                    Self.play(BreathCue.at(state.kind))
                }
                let toStep: Double = pattern.secondsToNextStep(at: elapsed)
                let toEnd: Double = length - elapsed
                // A hair past the boundary, so the next pass lands inside the
                // new step instead of on its edge.
                let wait: Double = max(0.05, min(toStep, toEnd) + 0.02)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    private static func play(_ cue: BreathCue) {
        let type: WKHapticType
        switch cue {
        case .start: type = .start
        case .stop: type = .stop
        case .click: type = .click
        }
        WKInterfaceDevice.current().play(type)
    }

    // MARK: Extended runtime

    /// A mindfulness session (WKBackgroundModes: mindfulness in Info.plist)
    /// keeps the app running and allowed to play haptics while the wrist is
    /// down. It must start while the app is in front, which a tap on Start is.
    private func beginRuntime() {
        endRuntime()
        let session = WKExtendedRuntimeSession()
        runtimeDelegate.onEnd = { [weak self] ended in
            // The system took the session away (time limit, another session
            // started). The circle keeps going while the app is open. Only
            // forget it if it is still ours: a restart invalidates the old
            // one, and its late callback must not drop the new one.
            guard let self, self.runtime === ended else { return }
            self.runtime = nil
        }
        session.delegate = runtimeDelegate
        session.start()
        runtime = session
    }

    private func endRuntime() {
        guard let runtime else { return }
        self.runtime = nil
        if runtime.state == .running || runtime.state == .scheduled {
            runtime.invalidate()
        }
    }
}

/// WKExtendedRuntimeSessionDelegate is called off the main actor; this
/// forwards the one thing BreathRunner cares about.
final class RuntimeDelegate: NSObject, WKExtendedRuntimeSessionDelegate {
    var onEnd: (@MainActor (WKExtendedRuntimeSession) -> Void)?

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        let onEnd = self.onEnd
        Task { @MainActor in onEnd?(extendedRuntimeSession) }
    }
}

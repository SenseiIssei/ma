import ActivityKit
import Foundation

/// The focus timer as a Live Activity. The app starts, updates and ends it
/// (see AppModel), the widget extension draws it on the Lock Screen and in
/// the Dynamic Island. Only plain strings, numbers and dates travel here:
/// the widget target cannot see FocusSession, because Models.swift imports
/// FamilyControls.
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// FocusPhase raw value: "focus", "shortBreak" or "longBreak".
        var phase: String
        /// Already translated by the app, so the island says what the app says.
        var title: String
        var startedAt: Date
        var endsAt: Date
        /// 1-based round inside the current set.
        var round: Int
        /// Rounds until the long break, drawn as dots.
        var totalRounds: Int

        var isBreak: Bool { phase != "focus" }

        /// Range for Text(timerInterval:) and ProgressView(timerInterval:).
        /// A closed range with lower > upper traps, so the end is clamped.
        var interval: ClosedRange<Date> {
            let end: Date = max(startedAt, endsAt)
            return startedAt...end
        }
    }

    // Nothing static on purpose: every piece of the focus round can change
    // between phases, so it all lives in ContentState.
}

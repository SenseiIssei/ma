import Foundation
import WidgetKit

// The real types (DayStats, FocusSession, FocusSettings) live in
// Shared/ScreenTime/Models.swift, which imports FamilyControls and
// ManagedSettings. A widget should not link Screen Time to read a handful of
// numbers, so these mirrors decode the same App Group JSON through MaShared
// and ignore every key they do not draw.

/// Mirror of DayStats in stats.json.
struct WidgetDayStats: Decodable {
    var resisted = 0
    var correct = 0
    var focusMinutes = 0
    var pomodoros = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        resisted = try c.decodeIfPresent(Int.self, forKey: .resisted) ?? 0
        correct = try c.decodeIfPresent(Int.self, forKey: .correct) ?? 0
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 0
        pomodoros = try c.decodeIfPresent(Int.self, forKey: .pomodoros) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case resisted, correct, focusMinutes, pomodoros
    }
}

/// Mirror of FocusSession in focus.json.
struct WidgetFocusSession: Decodable {
    /// FocusPhase raw value: "focus", "shortBreak" or "longBreak".
    var phase: String
    var startedAt: Date
    var duration: TimeInterval
    var round: Int

    var endsAt: Date { startedAt.addingTimeInterval(duration) }
    var isBreak: Bool { phase != "focus" }

    var title: String {
        switch phase {
        case "shortBreak": tr("Short break", "Kurze Pause")
        case "longBreak": tr("Long break", "Lange Pause")
        default: tr("Focus", "Fokus")
        }
    }

    /// Range for Text(timerInterval:). Clamped because an inverted closed
    /// range traps.
    var interval: ClosedRange<Date> {
        let end: Date = max(startedAt, endsAt)
        return startedAt...end
    }

    /// The phase that follows this one, or nil when Ma waits for a tap.
    /// Mirrors FocusEngine.advanceIfDue; keep the two in step.
    func next(_ settings: WidgetFocusSettings) -> WidgetFocusSession? {
        if phase == "focus" {
            let long: Bool = round >= settings.roundsUntilLongBreak
            let minutes: Int = long ? settings.longBreakMinutes : settings.shortBreakMinutes
            return WidgetFocusSession(
                phase: long ? "longBreak" : "shortBreak",
                startedAt: endsAt,
                duration: TimeInterval(minutes * 60),
                round: round
            )
        }
        guard settings.autoStartFocus else { return nil }
        let nextRound: Int = phase == "longBreak" ? 1 : round + 1
        return WidgetFocusSession(
            phase: "focus",
            startedAt: endsAt,
            duration: TimeInterval(settings.focusMinutes * 60),
            round: nextRound
        )
    }
}

/// Mirror of FocusSettings in focus-settings.json, without the app selection.
struct WidgetFocusSettings: Decodable {
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var roundsUntilLongBreak = 4
    var autoStartFocus = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WidgetFocusSettings()
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? d.focusMinutes
        shortBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? d.shortBreakMinutes
        longBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? d.longBreakMinutes
        roundsUntilLongBreak = try c.decodeIfPresent(Int.self, forKey: .roundsUntilLongBreak) ?? d.roundsUntilLongBreak
        autoStartFocus = try c.decodeIfPresent(Bool.self, forKey: .autoStartFocus) ?? d.autoStartFocus
    }

    private enum CodingKeys: String, CodingKey {
        case focusMinutes, shortBreakMinutes, longBreakMinutes, roundsUntilLongBreak, autoStartFocus
    }
}

/// Everything one widget face needs, read once per timeline.
struct MaSnapshot {
    /// Ring targets. The learning goal lives in the app's own documents,
    /// out of the widget's reach, so the widget uses the default of 20.
    static let focusGoal = 100
    static let learnGoal = 20
    static let resistGoal = 5

    var today = WidgetDayStats()
    /// The running phase at the entry's date, nil when idle.
    var focus: WidgetFocusSession?
    var settings = WidgetFocusSettings()

    var focusProgress: Double { Double(today.focusMinutes) / Double(Self.focusGoal) }
    var learnProgress: Double { Double(today.correct) / Double(Self.learnGoal) }
    var resistProgress: Double { Double(today.resisted) / Double(Self.resistGoal) }

    /// Shown in the gallery and while the real data loads.
    static var sample: MaSnapshot {
        var snapshot = MaSnapshot()
        snapshot.today.focusMinutes = 50
        snapshot.today.correct = 12
        snapshot.today.resisted = 3
        return snapshot
    }
}

enum WidgetStore {
    /// Same format as SharedStore.dayKey, which the widget cannot import.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func load(at date: Date) -> MaSnapshot {
        var snapshot = MaSnapshot()
        let stats: [String: WidgetDayStats] = MaShared.read([String: WidgetDayStats].self, from: "stats.json") ?? [:]
        snapshot.today = stats[dayKey(date)] ?? WidgetDayStats()
        snapshot.settings = MaShared.read(WidgetFocusSettings.self, from: "focus-settings.json") ?? WidgetFocusSettings()
        let stored: WidgetFocusSession? = MaShared.read(WidgetFocusSession.self, from: "focus.json")
        snapshot.focus = running(from: stored, settings: snapshot.settings, at: date)
        return snapshot
    }

    /// Walks past phases the monitor has not settled yet, the way
    /// FocusEngine.advanceIfDue would, so a late write never shows 0:00.
    static func running(from session: WidgetFocusSession?, settings: WidgetFocusSettings, at date: Date) -> WidgetFocusSession? {
        var current = session
        for _ in 0..<12 {
            guard let phase = current else { return nil }
            if date < phase.endsAt { return phase }
            current = phase.next(settings)
        }
        return nil
    }
}

struct MaEntry: TimelineEntry {
    let date: Date
    let snapshot: MaSnapshot
}

/// One provider for every Ma widget. Refreshes every 15 minutes and at the
/// end of a focus phase, and plans the following phase in advance so the
/// face flips on time even before WidgetKit gets round to reloading.
struct MaProvider: TimelineProvider {
    static let refreshInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> MaEntry {
        MaEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (MaEntry) -> Void) {
        let now = Date()
        let snapshot: MaSnapshot = context.isPreview ? .sample : WidgetStore.load(at: now)
        completion(MaEntry(date: now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MaEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetStore.load(at: now)
        var entries: [MaEntry] = [MaEntry(date: now, snapshot: snapshot)]
        var refresh: Date = now.addingTimeInterval(Self.refreshInterval)

        if let session = snapshot.focus {
            // The predicted next phase (or the idle face) takes over at the
            // end on its own; the reload a little later picks up what the
            // monitor really wrote, including the new focus minutes.
            var after = snapshot
            after.focus = session.next(snapshot.settings)
            entries.append(MaEntry(date: session.endsAt, snapshot: after))
            let settled: Date = session.endsAt.addingTimeInterval(30)
            refresh = min(refresh, settled)
        }

        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

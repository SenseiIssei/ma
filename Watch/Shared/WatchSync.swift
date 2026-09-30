import Foundation

// The one file both sides of WatchConnectivity compile: the iPhone app (Ma)
// and the watch app (MaWatch). Foundation only, no Screen Time, no UI, so the
// watch never links FamilyControls and the wire format lives in one place.

// MARK: - Snapshot

/// Everything the watch draws, sent by the iPhone as application context.
/// Small on purpose: the system keeps only the newest context and hands it
/// over whenever the watch wakes up.
struct WatchSnapshot: Codable, Equatable {
    /// Key of the encoded snapshot inside the application context and inside
    /// the reply to a command.
    static let contextKey = "snapshot"
    /// Ring targets that are not settings in the app. Focus follows the
    /// brief (100 minutes), resisting follows the widgets (5).
    static let focusGoal = 100
    static let resistGoal = 5

    /// Day key (yyyy-MM-dd) the numbers below belong to.
    var day: String
    var focusMinutes = 0
    var correct = 0
    var resisted = 0
    var pomodoros = 0
    /// Right answers per day the person aims for (LearnerProfile.dailyGoal).
    var dailyGoal = 20
    /// Raw streak plus the day it was last extended, so the watch can tell on
    /// its own whether the streak still holds after midnight.
    var streakDays = 0
    var lastLearnedDay: String?
    var focus: WatchFocus?
    var settings = WatchFocusSettings()

    init(day: String) {
        self.day = day
    }

    // Tolerant decoding: a watch on an older build still reads a newer phone.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 0
        correct = try c.decodeIfPresent(Int.self, forKey: .correct) ?? 0
        resisted = try c.decodeIfPresent(Int.self, forKey: .resisted) ?? 0
        pomodoros = try c.decodeIfPresent(Int.self, forKey: .pomodoros) ?? 0
        dailyGoal = try c.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? 20
        streakDays = try c.decodeIfPresent(Int.self, forKey: .streakDays) ?? 0
        lastLearnedDay = try c.decodeIfPresent(String.self, forKey: .lastLearnedDay)
        focus = try c.decodeIfPresent(WatchFocus.self, forKey: .focus)
        settings = try c.decodeIfPresent(WatchFocusSettings.self, forKey: .settings) ?? WatchFocusSettings()
    }

    /// Same format as SharedStore.dayKey on the phone.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The snapshot as it reads at `date`. After midnight the day numbers of
    /// yesterday are not today's, so they drop to zero until the phone sends
    /// fresh ones. Goals, streak and focus stay.
    func current(at date: Date, calendar: Calendar = .current) -> WatchSnapshot {
        let today: String = Self.dayKey(date, calendar: calendar)
        guard day != today else { return self }
        var copy = self
        copy.day = today
        copy.focusMinutes = 0
        copy.correct = 0
        copy.resisted = 0
        copy.pomodoros = 0
        return copy
    }

    /// Learning streak at `date`: it only breaks once a whole day is missed,
    /// the same rule as DeckStore.currentStreak.
    func streak(at date: Date, calendar: Calendar = .current) -> Int {
        guard let last = lastLearnedDay else { return 0 }
        let today: String = Self.dayKey(date, calendar: calendar)
        let start: Date = calendar.startOfDay(for: date)
        let before: Date = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        let yesterday: String = Self.dayKey(before, calendar: calendar)
        return last == today || last == yesterday ? streakDays : 0
    }

    // Ring fractions, not clamped: a ring past 1 is drawn full.
    var focusProgress: Double { Double(focusMinutes) / Double(Self.focusGoal) }
    var learnProgress: Double { Double(correct) / Double(max(1, dailyGoal)) }
    var resistProgress: Double { Double(resisted) / Double(Self.resistGoal) }

    /// The focus phase running at `date`, walking past phases the phone has
    /// not reported yet (it may be asleep in a pocket). Nil when idle.
    func runningFocus(at date: Date) -> WatchFocus? {
        var current: WatchFocus? = focus
        for _ in 0..<12 {
            guard let phase = current else { return nil }
            if date < phase.endsAt { return phase }
            current = phase.next(settings)
        }
        return nil
    }

    // MARK: Wire format

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        // Stable key order, so equal snapshots encode to equal bytes and the
        // phone can skip a context that did not change.
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    func encoded() -> Data? {
        try? Self.encoder().encode(self)
    }

    static func decoded(from data: Data) -> WatchSnapshot? {
        try? decoder().decode(WatchSnapshot.self, from: data)
    }

    /// Application context or command reply carrying a snapshot.
    static func from(_ dictionary: [String: Any]) -> WatchSnapshot? {
        guard let data = dictionary[contextKey] as? Data else { return nil }
        return decoded(from: data)
    }
}

// MARK: - Focus

/// Mirror of FocusSession. The phase is the FocusPhase raw value:
/// "focus", "shortBreak" or "longBreak".
struct WatchFocus: Codable, Equatable {
    var id: String
    var phase: String
    var startedAt: Date
    var duration: TimeInterval
    /// 1-based position inside the current set of rounds.
    var round: Int

    var endsAt: Date { startedAt.addingTimeInterval(duration) }
    var isBreak: Bool { phase != "focus" }

    /// Range for Text(timerInterval:). Clamped because an inverted closed
    /// range traps.
    var interval: ClosedRange<Date> {
        let end: Date = max(startedAt, endsAt)
        return startedAt...end
    }

    /// The phase after this one, or nil when Ma waits for a tap. Mirrors
    /// FocusEngine.advanceIfDue and WidgetFocusSession.next; keep them in step.
    func next(_ settings: WatchFocusSettings) -> WatchFocus? {
        if phase == "focus" {
            let long: Bool = round >= settings.roundsUntilLongBreak
            let minutes: Int = long ? settings.longBreakMinutes : settings.shortBreakMinutes
            return WatchFocus(
                id: id + "+",
                phase: long ? "longBreak" : "shortBreak",
                startedAt: endsAt,
                duration: TimeInterval(minutes * 60),
                round: round
            )
        }
        guard settings.autoStartFocus else { return nil }
        let nextRound: Int = phase == "longBreak" ? 1 : round + 1
        return WatchFocus(
            id: id + "+",
            phase: "focus",
            startedAt: endsAt,
            duration: TimeInterval(settings.focusMinutes * 60),
            round: nextRound
        )
    }
}

/// Mirror of FocusSettings without the app selection.
struct WatchFocusSettings: Codable, Equatable {
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var roundsUntilLongBreak = 4
    var autoStartFocus = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WatchFocusSettings()
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? d.focusMinutes
        shortBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? d.shortBreakMinutes
        longBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? d.longBreakMinutes
        roundsUntilLongBreak = try c.decodeIfPresent(Int.self, forKey: .roundsUntilLongBreak) ?? d.roundsUntilLongBreak
        autoStartFocus = try c.decodeIfPresent(Bool.self, forKey: .autoStartFocus) ?? d.autoStartFocus
    }
}

// MARK: - Commands

/// What the watch may ask of the phone. The phone owns the Screen Time
/// shields, so the watch never starts or stops focus on its own.
enum WatchCommand: String, Codable {
    case startFocus, stopFocus

    static let commandKey = "cmd"
    static let sentAtKey = "at"
    /// A queued tap older than this is ignored: starting a round an hour
    /// after the tap would surprise more than help.
    static let maxAge: TimeInterval = 10 * 60

    func message(at date: Date) -> [String: Any] {
        [Self.commandKey: rawValue, Self.sentAtKey: date.timeIntervalSince1970]
    }

    /// Reads a message or user info dictionary. Nil when it is not a
    /// command, or a stale one.
    static func parse(_ message: [String: Any], now: Date) -> WatchCommand? {
        guard let raw = message[commandKey] as? String,
              let command = WatchCommand(rawValue: raw) else { return nil }
        if let sent = message[sentAtKey] as? Double {
            let age: TimeInterval = now.timeIntervalSince1970 - sent
            if age > maxAge { return nil }
        }
        return command
    }

    /// True once `snapshot` shows the command took effect.
    func isSatisfied(by snapshot: WatchSnapshot?, at date: Date) -> Bool {
        let running: Bool = snapshot?.runningFocus(at: date) != nil
        switch self {
        case .startFocus: return running
        case .stopFocus: return !running
        }
    }
}

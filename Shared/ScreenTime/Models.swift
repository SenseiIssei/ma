import Foundation
import FamilyControls
import ManagedSettings

// MARK: - Rules

/// A time window in minutes after midnight. `start > end` wraps past midnight,
/// so 22:00 to 07:00 is one window that belongs to the evening it starts on.
struct RuleSchedule: Codable, Hashable {
    var startMinute: Int = 9 * 60
    var endMinute: Int = 17 * 60
    /// Calendar weekdays, 1 = Sunday through 7 = Saturday.
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]

    var wrapsMidnight: Bool { startMinute > endMinute }

    /// No day picked reads as every day rather than never.
    var effectiveWeekdays: Set<Int> { weekdays.isEmpty ? Set(1...7) : weekdays }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let weekday = c.weekday ?? 1
        let weekdays = effectiveWeekdays
        if startMinute == endMinute { return weekdays.contains(weekday) }
        if !wrapsMidnight {
            return weekdays.contains(weekday) && minute >= startMinute && minute < endMinute
        }
        if minute >= startMinute { return weekdays.contains(weekday) }
        if minute < endMinute { return weekdays.contains(weekday == 1 ? 7 : weekday - 1) }
        return false
    }

    static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    var label: String {
        let days: String
        if weekdays == Set(1...7) || weekdays.isEmpty {
            days = tr("daily", "täglich")
        } else if weekdays == Set([2, 3, 4, 5, 6]) {
            days = tr("Mon to Fri", "Mo bis Fr")
        } else if weekdays == Set([1, 7]) {
            days = tr("weekends", "am Wochenende")
        } else {
            days = [2, 3, 4, 5, 6, 7, 1].filter { weekdays.contains($0) }.map { Self.dayName($0) }.joined(separator: ", ")
        }
        return tr("\(Self.clock(startMinute)) to \(Self.clock(endMinute)), \(days)",
                  "\(Self.clock(startMinute)) bis \(Self.clock(endMinute)), \(days)")
    }

    /// Two-letter weekday, 1 = Sunday.
    static func dayName(_ weekday: Int) -> String {
        let en = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        let de = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        let index = (weekday - 1 + 7) % 7
        return Loc.isGerman ? de[index] : en[index]
    }
}

struct BlockRule: Codable, Identifiable {
    /// Used for rules saved before icons existed, and for new ones.
    static let defaultIcon = "shield.lefthalf.filled"
    /// Rising friction stops here, so a bad day never asks for twenty answers.
    static let maxQuestions = 10

    var id = UUID()
    var name: String = tr("Social media", "Soziale Medien")
    /// SF Symbol name shown on the card.
    var icon: String = BlockRule.defaultIcon
    var selection = FamilyActivitySelection()
    var isEnabled = true
    /// nil means the rule holds all day, every day.
    var schedule: RuleSchedule?
    var unlockMinutes = 5
    var questionsRequired = 1
    /// false turns the rule into a wall: the shield offers no way through.
    var allowsUnlock = true
    /// Unlocks allowed per calendar day. nil means no limit. Once spent, the
    /// rule is a wall until midnight.
    var dailyUnlockLimit: Int?
    /// Every unlock today costs one more right answer than the last.
    var risingFriction = false
    /// Seconds the gate waits before the first question. 0 means no wait.
    var waitSeconds = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BlockRule()
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? d.id
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
        // Older files carry a `kanji` instead; it is simply not read any more.
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? Self.defaultIcon
        selection = try c.decodeIfPresent(FamilyActivitySelection.self, forKey: .selection) ?? d.selection
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        schedule = try c.decodeIfPresent(RuleSchedule.self, forKey: .schedule)
        unlockMinutes = try c.decodeIfPresent(Int.self, forKey: .unlockMinutes) ?? d.unlockMinutes
        questionsRequired = try c.decodeIfPresent(Int.self, forKey: .questionsRequired) ?? d.questionsRequired
        allowsUnlock = try c.decodeIfPresent(Bool.self, forKey: .allowsUnlock) ?? d.allowsUnlock
        dailyUnlockLimit = try c.decodeIfPresent(Int.self, forKey: .dailyUnlockLimit)
        risingFriction = try c.decodeIfPresent(Bool.self, forKey: .risingFriction) ?? d.risingFriction
        waitSeconds = try c.decodeIfPresent(Int.self, forKey: .waitSeconds) ?? d.waitSeconds
    }

    func isActive(at date: Date) -> Bool {
        guard isEnabled else { return false }
        guard let schedule else { return true }
        return schedule.contains(date)
    }

    var itemCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    var isEmpty: Bool { itemCount == 0 }

    /// Right answers the next unlock costs, given how many unlocks this rule
    /// already gave today. With rising friction the first costs the base
    /// number, every further one a single answer more.
    func questionsNeeded(unlocksToday used: Int) -> Int {
        let base = max(1, questionsRequired)
        guard risingFriction else { return base }
        return min(Self.maxQuestions, base + max(0, used))
    }

    /// Unlocks still left today, or nil without a daily limit.
    func unlocksLeft(usedToday used: Int) -> Int? {
        guard let limit = dailyUnlockLimit else { return nil }
        return max(0, limit - max(0, used))
    }

    /// True once the daily budget is used up: a wall until midnight.
    func budgetSpent(usedToday used: Int) -> Bool {
        unlocksLeft(usedToday: used) == 0
    }
}

// MARK: - Unlocks

/// A time-boxed hole punched into every active rule.
struct UnlockGrant: Codable, Identifiable {
    var id = UUID()
    var applications: Set<ApplicationToken> = []
    var webDomains: Set<WebDomainToken> = []
    var categories: Set<ActivityCategoryToken> = []
    var createdAt = Date()
    var expiresAt: Date

    var remaining: TimeInterval { max(0, expiresAt.timeIntervalSinceNow) }
}

/// Written by the shield's action extension when someone asks to pass,
/// picked up by the app when it opens.
struct PendingUnlock: Codable, Identifiable {
    var id = UUID()
    var application: ApplicationToken?
    var webDomain: WebDomainToken?
    var category: ActivityCategoryToken?
    var displayName: String?
    var createdAt = Date()

    /// A request older than this is stale: the person has moved on.
    var isFresh: Bool { Date().timeIntervalSince(createdAt) < 10 * 60 }
}

/// Maps opaque tokens to the names the shield saw, so the app can say
/// "Instagram" instead of "diese App".
struct TokenName: Codable {
    var application: ApplicationToken?
    var webDomain: WebDomainToken?
    var name: String
}

// MARK: - Focus (Pomodoro)

enum FocusPhase: String, Codable {
    case focus, shortBreak, longBreak

    var kanji: String {
        switch self {
        case .focus: "集中"
        case .shortBreak: "休憩"
        case .longBreak: "長休"
        }
    }

    var title: String {
        switch self {
        case .focus: tr("Focus", "Fokus")
        case .shortBreak: tr("Short break", "Kurze Pause")
        case .longBreak: tr("Long break", "Lange Pause")
        }
    }
}

struct FocusSession: Codable {
    var id = UUID()
    var phase: FocusPhase
    var startedAt: Date
    var duration: TimeInterval
    /// 1-based position inside the current set of rounds.
    var round: Int

    var endsAt: Date { startedAt.addingTimeInterval(duration) }
    var remaining: TimeInterval { max(0, endsAt.timeIntervalSinceNow) }
    var progress: Double { duration > 0 ? min(1, 1 - remaining / duration) : 1 }
    var isOver: Bool { Date() >= endsAt }
}

struct FocusSettings: Codable {
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var roundsUntilLongBreak = 4
    var autoStartFocus = false
    /// When empty, focus borrows every app from every rule.
    var selection = FamilyActivitySelection()
    /// Strict: during focus the shield offers no quiz, only patience.
    var strict = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FocusSettings()
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? d.focusMinutes
        shortBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? d.shortBreakMinutes
        longBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? d.longBreakMinutes
        roundsUntilLongBreak = try c.decodeIfPresent(Int.self, forKey: .roundsUntilLongBreak) ?? d.roundsUntilLongBreak
        autoStartFocus = try c.decodeIfPresent(Bool.self, forKey: .autoStartFocus) ?? d.autoStartFocus
        selection = try c.decodeIfPresent(FamilyActivitySelection.self, forKey: .selection) ?? d.selection
        strict = try c.decodeIfPresent(Bool.self, forKey: .strict) ?? d.strict
    }
}

// MARK: - Stats

struct DayStats: Codable {
    var shieldsSeen = 0
    var resisted = 0
    var unlocks = 0
    var correct = 0
    var wrong = 0
    var focusMinutes = 0
    var pomodoros = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shieldsSeen = try c.decodeIfPresent(Int.self, forKey: .shieldsSeen) ?? 0
        resisted = try c.decodeIfPresent(Int.self, forKey: .resisted) ?? 0
        unlocks = try c.decodeIfPresent(Int.self, forKey: .unlocks) ?? 0
        correct = try c.decodeIfPresent(Int.self, forKey: .correct) ?? 0
        wrong = try c.decodeIfPresent(Int.self, forKey: .wrong) ?? 0
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 0
        pomodoros = try c.decodeIfPresent(Int.self, forKey: .pomodoros) ?? 0
    }
}

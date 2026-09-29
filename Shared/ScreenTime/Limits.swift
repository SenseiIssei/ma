import Foundation
import FamilyControls
import ManagedSettings

// MARK: - Daily unlock ledger

/// How many unlocks each rule gave on one calendar day. Stored as a single
/// small file that resets itself when the day changes, so the shield (which
/// runs in its own process) and the app always agree on the count.
struct UnlockLedger: Codable, Equatable {
    var day: String
    /// Rule id (uuidString) to unlocks on `day`.
    var counts: [String: Int] = [:]

    init(day: String, counts: [String: Int] = [:]) {
        self.day = day
        self.counts = counts
    }

    /// Unlocks for `rule` on `day`. A ledger from another day counts as empty.
    func count(for rule: UUID, on day: String) -> Int {
        guard day == self.day else { return 0 }
        return counts[rule.uuidString] ?? 0
    }

    /// Adds one unlock to each rule. A new day starts a fresh ledger.
    mutating func record(_ rules: [UUID], on day: String) {
        if day != self.day {
            self.day = day
            counts = [:]
        }
        for id in Set(rules) {
            counts[id.uuidString, default: 0] += 1
        }
    }
}

// MARK: - Lockdown

/// "Lock everything now": every app from every boundary and the focus list,
/// for a fixed time, with no way through. The tokens are copied at the start
/// so editing a boundary during the lockdown cannot loosen it.
struct LockdownState: Codable {
    var startedAt: Date
    var until: Date
    var applications: Set<ApplicationToken> = []
    var categories: Set<ActivityCategoryToken> = []
    var webDomains: Set<WebDomainToken> = []

    init(startedAt: Date, until: Date) {
        self.startedAt = startedAt
        self.until = until
    }

    func isActive(at now: Date = Date()) -> Bool { now < until }

    func remaining(at now: Date = Date()) -> TimeInterval { max(0, until.timeIntervalSince(now)) }

    var duration: TimeInterval { max(1, until.timeIntervalSince(startedAt)) }

    func progress(at now: Date = Date()) -> Double {
        min(1, max(0, now.timeIntervalSince(startedAt) / duration))
    }

    /// Right answers it takes to end a lockdown early. Deliberately many.
    static let answersToEnd = 5

    /// Hour a lockdown "until tomorrow morning" ends.
    static let morningHour = 7

    /// The next morning at 07:00 that lies at least an hour ahead. At 06:30
    /// that is tomorrow, not in thirty minutes: "until morning" should mean a
    /// night, not a coffee break.
    static func nextMorning(after now: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = morningHour
        components.minute = 0
        components.second = 0
        let todayMorning = calendar.date(from: components) ?? now
        if todayMorning.timeIntervalSince(now) >= 3600 { return todayMorning }
        return calendar.date(byAdding: .day, value: 1, to: todayMorning) ?? now.addingTimeInterval(86_400)
    }

    /// Minutes from `now` to the next morning, for `startLockdown(minutes:)`.
    static func minutesUntilMorning(from now: Date = Date(), calendar: Calendar = .current) -> Int {
        let seconds = nextMorning(after: now, calendar: calendar).timeIntervalSince(now)
        return max(1, Int((seconds / 60).rounded(.up)))
    }
}

/// The durations offered for a lockdown.
enum LockdownOption: String, CaseIterable, Identifiable {
    case halfHour, oneHour, twoHours, fourHours, untilMorning

    var id: String { rawValue }

    func minutes(from now: Date = Date()) -> Int {
        switch self {
        case .halfHour: 30
        case .oneHour: 60
        case .twoHours: 120
        case .fourHours: 240
        case .untilMorning: LockdownState.minutesUntilMorning(from: now)
        }
    }

    var title: String {
        switch self {
        case .halfHour: tr("30 min.", "30 Min.")
        case .oneHour: tr("1 hour", "1 Stunde")
        case .twoHours: tr("2 hours", "2 Stunden")
        case .fourHours: tr("4 hours", "4 Stunden")
        case .untilMorning: tr("Until tomorrow morning", "Bis morgen früh")
        }
    }
}

// MARK: - Templates

/// Starting points for a new boundary. Each sets a name, an icon and a time
/// window; the apps are always picked by the person, because Screen Time
/// only hands out tokens through Apple's own picker.
enum RuleTemplate: String, CaseIterable, Identifiable {
    case socialMedia, morningCalm, deepWork, night

    var id: String { rawValue }

    var name: String {
        switch self {
        case .socialMedia: tr("Social media", "Soziale Medien")
        case .morningCalm: tr("Morning calm", "Ruhiger Morgen")
        case .deepWork: tr("Deep work", "Konzentriert arbeiten")
        case .night: tr("Night", "Nacht")
        }
    }

    var icon: String {
        switch self {
        case .socialMedia: "bubble.left.and.bubble.right.fill"
        case .morningCalm: "sunrise.fill"
        case .deepWork: "laptopcomputer"
        case .night: "moon.stars.fill"
        }
    }

    var schedule: RuleSchedule? {
        switch self {
        case .socialMedia:
            return nil
        case .morningCalm:
            return RuleSchedule(startMinute: 6 * 60, endMinute: 9 * 60, weekdays: Set(1...7))
        case .deepWork:
            return RuleSchedule(startMinute: 9 * 60, endMinute: 17 * 60, weekdays: [2, 3, 4, 5, 6])
        case .night:
            return RuleSchedule(startMinute: 22 * 60, endMinute: 7 * 60, weekdays: Set(1...7))
        }
    }

    var summary: String {
        switch self {
        case .socialMedia: tr("Always on", "Immer an")
        case .morningCalm: tr("06:00 to 09:00, daily", "06:00 bis 09:00, täglich")
        case .deepWork: tr("Mon to Fri, 09:00 to 17:00", "Mo bis Fr, 09:00 bis 17:00")
        case .night: tr("22:00 to 07:00, daily", "22:00 bis 07:00, täglich")
        }
    }

    var blurb: String {
        switch self {
        case .socialMedia: tr("The feeds that pull at you, all day.", "Die Feeds, die an dir ziehen, den ganzen Tag.")
        case .morningCalm: tr("Start the day before the phone does.", "Starte in den Tag, bevor es das Handy tut.")
        case .deepWork: tr("Working hours belong to the work.", "Die Arbeitszeit gehört der Arbeit.")
        case .night: tr("Evenings and nights without the scroll.", "Abende und Nächte ohne Scrollen.")
        }
    }

    func makeRule() -> BlockRule {
        var rule = BlockRule()
        rule.name = name
        rule.icon = icon
        rule.schedule = schedule
        return rule
    }
}

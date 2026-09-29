import Foundation

// Pure data and rules for the "improve your day" features. Foundation only,
// so the logic can be tested without SwiftUI.

// MARK: - Day keys

enum DayKey {
    /// Same format as `SharedStore.dayKey`, kept here so this file has no
    /// dependency on the Screen Time code.
    static func of(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The day `offset` days before `date`. Goes through the calendar, not
    /// 86 400 seconds, so a daylight saving switch never skips a day.
    static func of(daysBefore offset: Int, _ date: Date = Date(), calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: date)
        let day = calendar.date(byAdding: .day, value: -offset, to: start) ?? start
        return of(day, calendar: calendar)
    }
}

// MARK: - Time of day

enum DayPhase: Equatable {
    case morning, day, evening

    /// Morning runs from 04:00 to 11:00, the evening from 18:00 until the
    /// small hours, so a late night still counts as the evening before.
    static func at(hour: Int) -> DayPhase {
        switch hour {
        case 4..<11: .morning
        case 11..<18: .day
        default: .evening
        }
    }

    static func now(_ date: Date = Date(), calendar: Calendar = .current) -> DayPhase {
        at(hour: calendar.component(.hour, from: date))
    }

    var illustration: String {
        switch self {
        case .morning: "IllustrationMorning"
        case .day: "IllustrationDay"
        case .evening: "IllustrationEvening"
        }
    }

    var greeting: String {
        switch self {
        case .morning: tr("Good morning", "Guten Morgen")
        case .day: tr("Hello", "Hallo")
        case .evening: tr("Good evening", "Guten Abend")
        }
    }
}

// MARK: - Mood and journal

/// Five steps from heavy to bright. Stored as the raw value.
enum Mood: Int, Codable, CaseIterable, Identifiable {
    case low = 1, meh, okay, good, great

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .low: tr("Heavy", "Schwer")
        case .meh: tr("Meh", "Naja")
        case .okay: tr("Okay", "Okay")
        case .good: tr("Good", "Gut")
        case .great: tr("Great", "Super")
        }
    }

    /// -1 for a frown, +1 for a full smile; drives the drawn mouth.
    var curve: Double { Double(rawValue - 3) / 2 }
}

struct MorningCheckIn: Codable, Equatable {
    var mood: Mood
    var intention: String
    var at = Date()
}

struct EveningReflection: Codable, Equatable {
    var wentWell: String
    var learned: String
    var letGo: String
    var at = Date()

    var isEmpty: Bool {
        [wentWell, learned, letGo].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct DayEntry: Codable, Equatable {
    var morning: MorningCheckIn?
    var evening: EveningReflection?
}

// MARK: - Habits

struct Habit: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var symbol: String
    /// 1 means a simple check; more means a counter, like 8 glasses.
    var target: Int = 1
    /// Day key to count for that day.
    var log: [String: Int] = [:]

    var isCounter: Bool { target > 1 }

    func count(on key: String) -> Int { log[key] ?? 0 }

    func isDone(on key: String) -> Bool { count(on: key) >= max(1, target) }

    func progress(on key: String) -> Double {
        Double(min(count(on: key), max(1, target))) / Double(max(1, target))
    }

    /// Days in a row the habit was completed. An unfinished today does not
    /// break it yet; the streak only ends once a whole day is missed.
    func streak(asOf date: Date = Date(), calendar: Calendar = .current) -> Int {
        var offset = isDone(on: DayKey.of(date, calendar: calendar)) ? 0 : 1
        var days = 0
        while isDone(on: DayKey.of(daysBefore: offset, date, calendar: calendar)) {
            days += 1
            offset += 1
        }
        return days
    }

    /// A tap adds one. A simple habit toggles; a full counter starts over,
    /// so an accidental tap is always one more tap away from being undone.
    mutating func tap(on key: String) {
        let current = count(on: key)
        let next = current >= max(1, target) ? 0 : current + 1
        log[key] = next == 0 ? nil : next
    }

    mutating func decrement(on key: String) {
        let next = max(0, count(on: key) - 1)
        log[key] = next == 0 ? nil : next
    }

    /// A year of history is enough for any streak worth showing.
    mutating func trimLog(keeping days: Int = 400) {
        guard log.count > days else { return }
        for key in log.keys.sorted().prefix(log.count - days) { log.removeValue(forKey: key) }
    }

    static var defaults: [Habit] {
        [
            Habit(title: tr("Water", "Wasser"), symbol: "drop.fill", target: 8),
            Habit(title: tr("Move", "Bewegung"), symbol: "figure.walk"),
            Habit(title: tr("Read", "Lesen"), symbol: "book.fill"),
            Habit(title: tr("No phone in bed", "Kein Handy im Bett"), symbol: "bed.double.fill"),
        ]
    }

    /// The small set offered in the picker. Plain, recognisable symbols.
    static let symbols: [String] = [
        "drop.fill", "figure.walk", "book.fill", "bed.double.fill",
        "leaf.fill", "sun.max.fill", "moon.fill", "heart.fill",
        "dumbbell.fill", "fork.knife", "cup.and.saucer.fill", "pencil.line",
        "brain.head.profile", "music.note", "figure.mind.and.body", "phone.down.fill",
    ]
}

// MARK: - Breathing

enum BreathKind: Equatable {
    case inhale, holdFull, exhale, holdEmpty

    var label: String {
        switch self {
        case .inhale: tr("Breathe in", "Einatmen")
        case .holdFull, .holdEmpty: tr("Hold", "Halten")
        case .exhale: tr("Breathe out", "Ausatmen")
        }
    }
}

struct BreathStep: Equatable {
    var kind: BreathKind
    var seconds: Double
}

struct BreathPattern: Identifiable, Equatable {
    let id: String
    let steps: [BreathStep]

    var cycle: Double { steps.reduce(0) { $0 + $1.seconds } }

    var title: String {
        switch id {
        case "box": tr("Box", "Box")
        case "478": "4-7-8"
        default: tr("Calm", "Ruhe")
        }
    }

    var rhythm: String {
        steps.map { String(Int($0.seconds)) }.joined(separator: "-")
    }

    var summary: String {
        switch id {
        case "box": tr("Even and steady. Good before focus.", "Gleichmäßig und ruhig. Gut vor dem Fokus.")
        case "478": tr("A long out-breath. Good before sleep.", "Langes Ausatmen. Gut vor dem Schlafen.")
        default: tr("Out longer than in. Settles you quickly.", "Länger aus als ein. Beruhigt schnell.")
        }
    }

    static let box = BreathPattern(id: "box", steps: [
        BreathStep(kind: .inhale, seconds: 4), BreathStep(kind: .holdFull, seconds: 4),
        BreathStep(kind: .exhale, seconds: 4), BreathStep(kind: .holdEmpty, seconds: 4),
    ])
    static let fourSevenEight = BreathPattern(id: "478", steps: [
        BreathStep(kind: .inhale, seconds: 4), BreathStep(kind: .holdFull, seconds: 7),
        BreathStep(kind: .exhale, seconds: 8),
    ])
    static let calm = BreathPattern(id: "calm", steps: [
        BreathStep(kind: .inhale, seconds: 4), BreathStep(kind: .exhale, seconds: 6),
    ])
    static let all: [BreathPattern] = [.box, .fourSevenEight, .calm]

    /// A session always ends on a finished out-breath, never halfway in.
    func sessionLength(minutes: Int) -> Double {
        let wanted = Double(max(1, minutes)) * 60
        return (wanted / cycle).rounded(.up) * cycle
    }

    func state(at elapsed: Double) -> BreathState {
        let t = max(0, elapsed)
        let cycleIndex = Int(t / cycle)
        var inCycle = t - Double(cycleIndex) * cycle
        for (index, step) in steps.enumerated() {
            if inCycle < step.seconds || index == steps.count - 1 {
                let into = min(inCycle, step.seconds)
                return BreathState(cycle: cycleIndex, stepIndex: index, kind: step.kind,
                                   elapsedInStep: into, stepSeconds: step.seconds)
            }
            inCycle -= step.seconds
        }
        return BreathState(cycle: cycleIndex, stepIndex: 0, kind: .inhale, elapsedInStep: 0, stepSeconds: 1)
    }
}

struct BreathState: Equatable {
    var cycle: Int
    var stepIndex: Int
    var kind: BreathKind
    var elapsedInStep: Double
    var stepSeconds: Double

    /// Changes on every phase switch, the trigger for haptics.
    var tick: Int { cycle * 16 + stepIndex }

    var secondsLeft: Int { max(1, Int((stepSeconds - elapsedInStep).rounded(.up))) }

    /// How open the circle is, 0 empty to 1 full, eased so it breathes.
    var openness: Double {
        let p = stepSeconds > 0 ? min(1, max(0, elapsedInStep / stepSeconds)) : 1
        let eased = 0.5 - cos(p * Double.pi) / 2
        switch kind {
        case .inhale: return eased
        case .holdFull: return 1
        case .exhale: return 1 - eased
        case .holdEmpty: return 0
        }
    }
}

struct BreathStats: Codable, Equatable {
    var sessions = 0
    var seconds = 0
    /// Day key to sessions that day.
    var byDay: [String: Int] = [:]

    var minutes: Int { seconds / 60 }

    mutating func record(seconds length: Int, on key: String) {
        sessions += 1
        seconds += max(0, length)
        byDay[key, default: 0] += 1
        if byDay.count > 400 {
            for k in byDay.keys.sorted().prefix(byDay.count - 400) { byDay.removeValue(forKey: k) }
        }
    }
}

import Foundation

// The numbers behind the weekly review. Foundation only and free of any
// store access, so the comparison math can be tested with plain swiftc.

/// Sums of Ma's own counters over seven days.
struct WeekTotals: Equatable {
    var resisted = 0
    var unlocks = 0
    var correct = 0
    var focusMinutes = 0
    var rounds = 0

    init() {}

    init(_ days: [DayStats]) {
        for day in days {
            resisted += day.resisted
            unlocks += day.unlocks
            correct += day.correct
            focusMinutes += day.focusMinutes
            rounds += day.pomodoros
        }
    }

    /// Nothing happened at all. Unlocks alone still count as something.
    var isEmpty: Bool {
        resisted == 0 && unlocks == 0 && correct == 0 && focusMinutes == 0 && rounds == 0
    }

    func value(of kind: WeekMetric.Kind) -> Int {
        switch kind {
        case .resisted: resisted
        case .unlocks: unlocks
        case .correct: correct
        case .focusMinutes: focusMinutes
        case .rounds: rounds
        }
    }
}

/// One counter, this week against the week before.
struct WeekMetric: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case resisted, unlocks, correct, focusMinutes, rounds
    }

    enum Trend: Equatable {
        case up, down, same
    }

    let kind: Kind
    let current: Int
    let previous: Int

    var id: String { kind.rawValue }
    var delta: Int { current - previous }

    var trend: Trend {
        if delta > 0 { return .up }
        if delta < 0 { return .down }
        return .same
    }

    /// Fewer unlocks is the good direction; every other counter should grow.
    var higherIsBetter: Bool { kind != .unlocks }

    var improved: Bool { higherIsBetter ? delta > 0 : delta < 0 }
    var worsened: Bool { higherIsBetter ? delta < 0 : delta > 0 }

    /// Whole percent change, nil when last week was zero: there is no base
    /// to compare against, and "infinitely better" helps nobody.
    var percentChange: Int? {
        guard previous > 0 else { return nil }
        let ratio: Double = Double(delta) / Double(previous)
        return Int((ratio * 100).rounded())
    }
}

/// One of the seven days under review.
struct ReviewDay: Equatable {
    let date: Date
    let key: String
    let resisted: Int
    let correct: Int
    let rounds: Int

    /// What makes a good day in Ma: impulses let pass, right answers and
    /// finished focus rounds, each worth the same.
    var score: Int { resisted + correct + rounds }
}

struct WeekSummary {
    /// This week, oldest first, the last entry is today.
    let days: [ReviewDay]
    let current: WeekTotals
    let previous: WeekTotals
    /// nil while every day of the week is still empty.
    let bestDay: ReviewDay?
    /// Days in a row with any activity, ending today or yesterday.
    let streak: Int
    let metrics: [WeekMetric]

    init(stats: [String: DayStats], now: Date = Date(), calendar: Calendar = .current) {
        let thisWeek: [(Date, String, DayStats)] = (0..<7).reversed().map { offset in
            Self.day(offset, before: now, in: stats, calendar: calendar)
        }
        let lastWeek: [DayStats] = (7..<14).map { offset in
            Self.day(offset, before: now, in: stats, calendar: calendar).2
        }

        // Built as locals first: a closure may not touch self before every
        // stored property is set.
        let reviewDays: [ReviewDay] = thisWeek.map { date, key, day in
            ReviewDay(date: date, key: key, resisted: day.resisted, correct: day.correct, rounds: day.pomodoros)
        }
        let thisTotals = WeekTotals(thisWeek.map { $0.2 })
        let lastTotals = WeekTotals(lastWeek)

        days = reviewDays
        current = thisTotals
        previous = lastTotals
        bestDay = Self.best(of: reviewDays)
        streak = Self.streak(in: stats, now: now, calendar: calendar)
        metrics = WeekMetric.Kind.allCases.map { kind in
            WeekMetric(kind: kind, current: thisTotals.value(of: kind), previous: lastTotals.value(of: kind))
        }
    }

    /// How many of the counters moved in the good direction.
    var improvedCount: Int { metrics.filter(\.improved).count }

    // MARK: Pieces

    private static func day(_ offset: Int, before now: Date, in stats: [String: DayStats], calendar: Calendar) -> (Date, String, DayStats) {
        let start: Date = calendar.startOfDay(for: now)
        let date: Date = calendar.date(byAdding: .day, value: -offset, to: start) ?? start
        let key: String = DayKey.of(date, calendar: calendar)
        return (date, key, stats[key] ?? DayStats())
    }

    /// The highest score wins; on a tie the later day, because it is the
    /// fresher memory.
    static func best(of days: [ReviewDay]) -> ReviewDay? {
        var best: ReviewDay?
        for day in days where day.score > 0 {
            if let current = best, current.score > day.score { continue }
            best = day
        }
        return best
    }

    /// Like the learning streak, a day only breaks it once it is over: an
    /// empty today still leaves yesterday's run standing.
    static func streak(in stats: [String: DayStats], now: Date, calendar: Calendar) -> Int {
        func active(_ offset: Int) -> Bool {
            let start: Date = calendar.startOfDay(for: now)
            let date: Date = calendar.date(byAdding: .day, value: -offset, to: start) ?? start
            guard let day = stats[DayKey.of(date, calendar: calendar)] else { return false }
            let sum: Int = day.resisted + day.correct + day.pomodoros + day.focusMinutes
            return sum > 0
        }
        var offset = active(0) ? 0 : 1
        var count = 0
        // The store keeps about 400 days; looking further is pointless.
        while offset < 400 && active(offset) {
            count += 1
            offset += 1
        }
        return count
    }

    // MARK: Words

    /// Two or three plain sentences made from the numbers. No model, just
    /// rules, so the same week always reads the same.
    var sentence: String {
        Self.sentence(current: current, previous: previous, improved: improvedCount,
                      of: metrics.count, streak: streak)
    }

    static func sentence(current: WeekTotals, previous: WeekTotals, improved: Int, of total: Int, streak: Int) -> String {
        if current.isEmpty {
            return previous.isEmpty
                ? tr("A quiet start. Your first pause will show up here.",
                     "Ein ruhiger Anfang. Deine erste Pause taucht hier auf.")
                : tr("A quiet week with Ma. The next pause can start today.",
                     "Eine stille Woche mit Ma. Die nächste Pause kann heute beginnen.")
        }

        var parts: [String] = [lead(current)]
        if streak >= 3 {
            parts.append(tr("\(streak) days in a row with Ma.", "\(streak) Tage in Folge mit Ma."))
        }
        parts.append(comparison(previous: previous, improved: improved, of: total))
        return parts.joined(separator: " ")
    }

    /// The main clause names the strongest thing that happened, the second
    /// half adds one more, so the sentence never becomes a list.
    private static func lead(_ week: WeekTotals) -> String {
        let focus: String = minutesText(week.focusMinutes)
        if week.resisted > 0 {
            let impulses: String = count(week.resisted, "impulse", "impulses", "Impuls", "Impulse")
            if week.focusMinutes > 0 {
                return tr("You let \(impulses) pass and focused for \(focus).",
                          "Du hast \(impulses) ziehen lassen und \(focus) fokussiert gearbeitet.")
            }
            if week.correct > 0 {
                let answers: String = count(week.correct, "question", "questions", "Frage", "Fragen")
                return tr("You let \(impulses) pass and answered \(answers) right.",
                          "Du hast \(impulses) ziehen lassen und \(answers) richtig beantwortet.")
            }
            return tr("You let \(impulses) pass.", "Du hast \(impulses) ziehen lassen.")
        }
        if week.correct > 0 {
            let answers: String = count(week.correct, "question", "questions", "Frage", "Fragen")
            if week.focusMinutes > 0 {
                return tr("You answered \(answers) right and focused for \(focus).",
                          "Du hast \(answers) richtig beantwortet und \(focus) fokussiert gearbeitet.")
            }
            return tr("You answered \(answers) right.", "Du hast \(answers) richtig beantwortet.")
        }
        if week.focusMinutes > 0 {
            return tr("You focused for \(focus).", "Du hast \(focus) fokussiert gearbeitet.")
        }
        // Only unlocks this week: still honest, still kind.
        return tr("You came through the pause every time this week.",
                  "Diese Woche bist du jedes Mal durch die Pause gegangen.")
    }

    private static func comparison(previous: WeekTotals, improved: Int, of total: Int) -> String {
        if previous.isEmpty {
            return tr("A good first week to build on.", "Ein guter Anfang, auf dem du aufbauen kannst.")
        }
        if improved >= 3 {
            return tr("Better than last week in \(improved) of \(total) areas. Keep it up.",
                      "In \(improved) von \(total) Bereichen besser als letzte Woche. Weiter so.")
        }
        if improved >= 1 {
            return tr("Better than last week in \(improved) of \(total) areas, step by step.",
                      "In \(improved) von \(total) Bereichen besser als letzte Woche, Schritt für Schritt.")
        }
        return tr("A softer week than the last. Every pause still counts.",
                  "Eine ruhigere Woche als die letzte. Jede Pause zählt trotzdem.")
    }

    // MARK: Formatting

    /// "3 h 20 min" or "3 Std. 20 Min.", minutes only below an hour.
    static func minutesText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return tr("\(rest) min", "\(rest) Min.") }
        if rest == 0 { return tr("\(hours) h", "\(hours) Std.") }
        return tr("\(hours) h \(rest) min", "\(hours) Std. \(rest) Min.")
    }

    /// "1 impulse", "12 impulses" and the German forms.
    static func count(_ n: Int, _ oneEN: String, _ manyEN: String, _ oneDE: String, _ manyDE: String) -> String {
        n == 1 ? tr("1 \(oneEN)", "1 \(oneDE)") : tr("\(n) \(manyEN)", "\(n) \(manyDE)")
    }
}

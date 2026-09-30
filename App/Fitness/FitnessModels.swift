import Foundation

// Pure data and rules for the fitness goal: weigh-ins, workouts from a
// Garmin feed or typed in by hand, the weekly burn a weight goal needs,
// experience points, levels, quests and badges. Foundation only, so every
// rule here can be tested without SwiftUI or a phone.

// MARK: - Activities

enum ActivityKind: String, Codable, CaseIterable, Identifiable {
    case strength, cycling, running, walking, swimming, hiking, hiit, yoga, other

    var id: String { rawValue }

    /// Garmin's activity type as the feed spells it: "strength training",
    /// "indoor cycling", "lap swimming", "trail running".
    static func from(garmin type: String) -> ActivityKind {
        let t: String = type.lowercased()
        if t.contains("strength") || t.contains("weight") { return .strength }
        if t.contains("cycl") || t.contains("bik") || t.contains("ride") { return .cycling }
        if t.contains("run") { return .running }
        if t.contains("swim") { return .swimming }
        if t.contains("hik") { return .hiking }
        if t.contains("walk") { return .walking }
        if t.contains("hiit") || t.contains("cardio") || t.contains("interval") { return .hiit }
        if t.contains("yoga") || t.contains("pilates") || t.contains("stretch") { return .yoga }
        return .other
    }

    var title: String {
        switch self {
        case .strength: tr("Strength", "Kraft")
        case .cycling: tr("Cycling", "Radfahren")
        case .running: tr("Running", "Laufen")
        case .walking: tr("Walking", "Gehen")
        case .swimming: tr("Swimming", "Schwimmen")
        case .hiking: tr("Hiking", "Wandern")
        case .hiit: tr("HIIT", "HIIT")
        case .yoga: tr("Yoga", "Yoga")
        case .other: tr("Workout", "Training")
        }
    }

    var symbol: String {
        switch self {
        case .strength: "figure.strengthtraining.traditional"
        case .cycling: "figure.outdoor.cycle"
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .swimming: "figure.pool.swim"
        case .hiking: "figure.hiking"
        case .hiit: "figure.highintensity.intervaltraining"
        case .yoga: "figure.yoga"
        case .other: "figure.mixed.cardio"
        }
    }

    /// Typical effort from the Compendium of Physical Activities, used
    /// until the feed has enough of your own sessions to go by.
    var met: Double {
        switch self {
        case .strength: 5.0
        case .cycling: 7.5
        case .running: 9.8
        case .walking: 3.8
        case .swimming: 7.0
        case .hiking: 6.0
        case .hiit: 8.0
        case .yoga: 3.0
        case .other: 5.0
        }
    }

    /// What the goal screen offers as favourites for the weekly plan.
    static let plannable: [ActivityKind] = [.strength, .cycling, .running, .walking, .swimming, .hiit]
}

// MARK: - Records

struct FitnessWorkout: Codable, Identifiable, Equatable {
    enum Source: String, Codable { case garmin, manual }

    let id: String
    var kind: ActivityKind
    /// The activity type as it came in, "strength training" or "Cycling".
    var name: String
    /// Day key, yyyy-MM-dd.
    var date: String
    var minutes: Int
    var km: Double?
    var calories: Int
    var averageHeartRate: Int?
    var source: Source
}

/// One day of watch totals. Only the days the feed reported while Ma was
/// open are known; the feed itself carries just the latest one.
struct FitnessDay: Codable, Equatable {
    var steps = 0
    var stepGoal = 0
    var activeCalories = 0
    var moderateMinutes = 0
    var vigorousMinutes = 0

    /// Minutes the way WHO and Garmin count them: vigorous ones double.
    var intensityMinutes: Int { moderateMinutes + 2 * vigorousMinutes }
    var stepGoalMet: Bool { stepGoal > 0 && steps >= stepGoal }
}

struct WeightEntry: Codable, Equatable, Identifiable {
    /// Day key; one weigh-in per day, a second one replaces the first.
    var date: String
    var kg: Double

    var id: String { date }
}

struct FitnessGoal: Codable, Equatable {
    var startKg: Double
    var goalKg: Double
    var heightCm: Double?
    /// 0.1 to 1.0 kg a week.
    var kgPerWeek: Double
    /// Day key the plan began.
    var startDate: String
    /// Workout calories of a normal week before the plan. The plan asks for
    /// this plus the deficit, so what you already did keeps your weight
    /// where it is and only the extra takes it down.
    var baselineWeeklyKcal: Double
    var favorites: [ActivityKind]

    var toLose: Double { max(0, startKg - goalKg) }

    init(startKg: Double, goalKg: Double, heightCm: Double?, kgPerWeek: Double,
         startDate: String, baselineWeeklyKcal: Double, favorites: [ActivityKind]) {
        self.startKg = startKg
        self.goalKg = goalKg
        self.heightCm = heightCm
        self.kgPerWeek = kgPerWeek
        self.startDate = startDate
        self.baselineWeeklyKcal = baselineWeeklyKcal
        self.favorites = favorites
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startKg = try c.decode(Double.self, forKey: .startKg)
        goalKg = try c.decode(Double.self, forKey: .goalKg)
        heightCm = try? c.decodeIfPresent(Double.self, forKey: .heightCm)
        kgPerWeek = FitnessMath.clampPace((try? c.decodeIfPresent(Double.self, forKey: .kgPerWeek)) ?? 0.25)
        startDate = (try? c.decodeIfPresent(String.self, forKey: .startDate)) ?? FitnessDate.key(Date())
        baselineWeeklyKcal = (try? c.decodeIfPresent(Double.self, forKey: .baselineWeeklyKcal)) ?? 0
        // An activity a later version drops must not lose the whole goal.
        let raw: [String] = (try? c.decodeIfPresent([String].self, forKey: .favorites)) ?? []
        favorites = raw.compactMap(ActivityKind.init(rawValue:))
    }
}

struct FitnessSettings: Codable, Equatable {
    /// A URL that returns the Garmin snapshot JSON (see docs/FITNESS.md).
    var feedURL = ""
    /// Highest level the person has already been congratulated on.
    var seenLevel = 0
    var seenBadges: Set<String> = []
    /// Garmin workouts the person removed; the next sync must not bring
    /// them back.
    var hiddenWorkouts: Set<String> = []
    var lastSync: Date?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        feedURL = (try? c.decodeIfPresent(String.self, forKey: .feedURL)) ?? ""
        seenLevel = (try? c.decodeIfPresent(Int.self, forKey: .seenLevel)) ?? 0
        seenBadges = (try? c.decodeIfPresent(Set<String>.self, forKey: .seenBadges)) ?? []
        hiddenWorkouts = (try? c.decodeIfPresent(Set<String>.self, forKey: .hiddenWorkouts)) ?? []
        lastSync = try? c.decodeIfPresent(Date.self, forKey: .lastSync)
    }
}

// MARK: - Days and weeks

enum FitnessDate {
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Noon of the day, so time zone shifts never tip it into a neighbour.
    static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts: [Int] = key.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// Weeks start on Monday, whatever the region says.
    static func mondayCalendar(_ calendar: Calendar) -> Calendar {
        var c = calendar
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    static func weekStart(_ date: Date, calendar: Calendar = .current) -> Date {
        let c = mondayCalendar(calendar)
        return c.dateInterval(of: .weekOfYear, for: date)?.start ?? c.startOfDay(for: date)
    }

    static func weekKey(_ date: Date, calendar: Calendar = .current) -> String {
        key(weekStart(date, calendar: calendar), calendar: calendar)
    }

    /// Days left in the week including today, 7 on a Monday, 1 on a Sunday.
    static func daysLeftInWeek(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = mondayCalendar(calendar)
        let start: Date = weekStart(date, calendar: calendar)
        let passed: Int = c.dateComponents([.day], from: start, to: c.startOfDay(for: date)).day ?? 0
        return max(1, 7 - passed)
    }
}

struct FitnessWeek: Equatable {
    /// Day key of the Monday.
    let key: String
    let workouts: [FitnessWorkout]

    var kcal: Int { workouts.reduce(0) { $0 + $1.calories } }
    var minutes: Int { workouts.reduce(0) { $0 + $1.minutes } }
    var sessions: Int { workouts.count }
    var kinds: Set<ActivityKind> { Set(workouts.map(\.kind)) }
    var longest: Int { workouts.map(\.minutes).max() ?? 0 }
}

// MARK: - The math

enum FitnessMath {
    /// Energy in a kilogram of body fat, the usual rule of thumb.
    static let kcalPerKg: Double = 7700
    static let paceRange: ClosedRange<Double> = 0.1...1.0
    static let paceChoices: [Double] = [0.25, 0.5, 0.75]

    static func extraWeeklyKcal(kgPerWeek: Double) -> Double {
        clampPace(kgPerWeek) * kcalPerKg
    }

    static func clampPace(_ kgPerWeek: Double) -> Double {
        min(paceRange.upperBound, max(paceRange.lowerBound, kgPerWeek))
    }

    static func weeklyTarget(_ goal: FitnessGoal) -> Double {
        goal.baselineWeeklyKcal + extraWeeklyKcal(kgPerWeek: goal.kgPerWeek)
    }

    static func weeksToGoal(kgLeft: Double, kgPerWeek: Double) -> Double {
        max(0, kgLeft) / clampPace(kgPerWeek)
    }

    static func bmi(kg: Double, heightCm: Double?) -> Double? {
        guard let heightCm, heightCm > 80 else { return nil }
        let m: Double = heightCm / 100
        return kg / (m * m)
    }

    /// The lowest weight inside the healthy BMI range for this height.
    static func healthyMinimumKg(heightCm: Double?) -> Double? {
        guard let heightCm, heightCm > 80 else { return nil }
        let m: Double = heightCm / 100
        return (18.5 * m * m * 10).rounded(.up) / 10
    }

    /// Calories a minute of this activity burns for you. Your own sessions
    /// win once there are two of at least ten minutes; before that the
    /// textbook value for your weight stands in.
    static func kcalPerMinute(_ kind: ActivityKind, weightKg: Double, history: [FitnessWorkout]) -> Double {
        let own: [FitnessWorkout] = history.filter { $0.kind == kind && $0.minutes >= 10 && $0.calories > 0 }
        if own.count >= 2 {
            let kcal: Double = Double(own.reduce(0) { $0 + $1.calories })
            let minutes: Double = Double(own.reduce(0) { $0 + $1.minutes })
            return kcal / minutes
        }
        return estimatedKcalPerMinute(kind, weightKg: weightKg)
    }

    static func estimatedKcalPerMinute(_ kind: ActivityKind, weightKg: Double) -> Double {
        kind.met * 3.5 * max(30, weightKg) / 200
    }

    static func hasOwnRate(_ kind: ActivityKind, history: [FitnessWorkout]) -> Bool {
        history.filter { $0.kind == kind && $0.minutes >= 10 && $0.calories > 0 }.count >= 2
    }

    /// Minutes for a number of calories, rounded up to five.
    static func minutes(forKcal kcal: Double, perMinute: Double) -> Int {
        guard kcal > 0, perMinute > 0 else { return 0 }
        return Int((kcal / perMinute / 5).rounded(.up)) * 5
    }

    /// Average workout calories a week over the `weeks` whole weeks before
    /// `date`. That is the week the plan builds on.
    static func baseline(_ workouts: [FitnessWorkout], before date: Date, weeks: Int = 4,
                         calendar: Calendar = .current) -> Double {
        let end: Date = FitnessDate.weekStart(date, calendar: calendar)
        guard weeks > 0, let start = calendar.date(byAdding: .day, value: -7 * weeks, to: end) else { return 0 }
        let from: String = FitnessDate.key(start, calendar: calendar)
        let to: String = FitnessDate.key(end, calendar: calendar)
        let kcal: Int = workouts.filter { $0.date >= from && $0.date < to }.reduce(0) { $0 + $1.calories }
        return Double(kcal) / Double(weeks)
    }

    /// Smoothed weight: each weigh-in moves the trend a third of the way,
    /// so one salty dinner or a glass of water does not look like progress
    /// or failure. Returns one point per weigh-in, oldest first.
    static func trend(_ entries: [WeightEntry], smoothing: Double = 1.0 / 3.0) -> [WeightEntry] {
        let sorted: [WeightEntry] = entries.sorted { $0.date < $1.date }
        guard let first = sorted.first else { return [] }
        var value: Double = first.kg
        return sorted.map { entry in
            value += (entry.kg - value) * smoothing
            return WeightEntry(date: entry.date, kg: (value * 10).rounded() / 10)
        }
    }

    static func weeks(_ workouts: [FitnessWorkout], calendar: Calendar = .current) -> [String: FitnessWeek] {
        var grouped: [String: [FitnessWorkout]] = [:]
        for workout in workouts {
            guard let day = FitnessDate.date(workout.date, calendar: calendar) else { continue }
            grouped[FitnessDate.weekKey(day, calendar: calendar), default: []].append(workout)
        }
        return grouped.reduce(into: [:]) { $0[$1.key] = FitnessWeek(key: $1.key, workouts: $1.value) }
    }

    /// The Monday keys from the plan's first week up to and including the
    /// week of `date`.
    static func planWeeks(from start: String, to date: Date, calendar: Calendar = .current) -> [String] {
        guard let startDay = FitnessDate.date(start, calendar: calendar) else { return [] }
        var monday: Date = FitnessDate.weekStart(startDay, calendar: calendar)
        let last: Date = FitnessDate.weekStart(date, calendar: calendar)
        var keys: [String] = []
        while monday <= last && keys.count < 520 {
            keys.append(FitnessDate.key(monday, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 7, to: monday) else { break }
            monday = FitnessDate.weekStart(next, calendar: calendar)
        }
        return keys
    }
}

// MARK: - Planning

struct PlanSession: Identifiable, Equatable {
    /// 0 is today (or Monday for a template week).
    let dayOffset: Int
    let kind: ActivityKind
    let minutes: Int
    let kcal: Int

    var id: String { "\(dayOffset)-\(kind.rawValue)" }
}

enum FitnessPlanner {
    /// A comfortable session burns about this much; more is split up.
    static let sessionKcal: Double = 500
    static let maxMinutes = 120

    /// Spreads the calories still missing this week over the days left,
    /// taking the favourite activities in turn. A session never runs past
    /// two hours; if that is not enough, the week simply cannot hold it and
    /// the screen says so instead of asking for more.
    static func sessions(remainingKcal: Double, daysLeft: Int, favorites: [ActivityKind],
                         rate: (ActivityKind) -> Double) -> [PlanSession] {
        guard remainingKcal > 1, daysLeft > 0 else { return [] }
        let kinds: [ActivityKind] = favorites.isEmpty ? [.walking] : favorites
        // With four or more days to go, one of them stays a rest day.
        let open: Int = daysLeft >= 4 ? daysLeft - 1 : daysLeft
        let count: Int = min(open, max(1, Int((remainingKcal / sessionKcal).rounded(.up))))
        let each: Double = remainingKcal / Double(count)
        return (0..<count).map { index in
            let kind: ActivityKind = kinds[index % kinds.count]
            let perMinute: Double = rate(kind)
            let minutes: Int = min(maxMinutes, FitnessMath.minutes(forKcal: each, perMinute: perMinute))
            let offset: Int = count == 1 ? 0 : index * (daysLeft - 1) / (count - 1)
            return PlanSession(dayOffset: offset, kind: kind, minutes: minutes,
                               kcal: Int((Double(minutes) * perMinute).rounded()))
        }
    }

    /// Minutes a whole week of the target takes with the favourites.
    static func weeklyMinutes(targetKcal: Double, favorites: [ActivityKind], rate: (ActivityKind) -> Double) -> Int {
        let kinds: [ActivityKind] = favorites.isEmpty ? [.walking] : favorites
        let average: Double = kinds.map(rate).reduce(0, +) / Double(kinds.count)
        return FitnessMath.minutes(forKcal: targetKcal, perMinute: average)
    }
}

// MARK: - Experience and levels

enum FitnessXP {
    static let weighIn = 10
    static let stepGoal = 15

    /// A workout is worth a tenth of its calories plus half its minutes,
    /// so both long easy rides and short hard ones count.
    static func workout(_ workout: FitnessWorkout) -> Int {
        max(5, workout.calories / 10 + workout.minutes / 2)
    }

    /// Three points per thousand steps up to 30,000, plus a bonus for the
    /// watch's own step goal.
    static func day(_ day: FitnessDay) -> Int {
        min(day.steps, 30_000) / 1000 * 3 + (day.stepGoalMet ? stepGoal : 0)
    }

    /// Experience needed to reach a level: 0, 100, 300, 600, 1000...
    static func threshold(_ level: Int) -> Int {
        let l: Int = max(1, level)
        return 50 * l * (l - 1)
    }

    static func level(for xp: Int) -> Int {
        var level = 1
        while threshold(level + 1) <= xp && level < 999 { level += 1 }
        return level
    }

    struct Progress: Equatable {
        let level: Int
        let into: Int
        let span: Int

        var fraction: Double { span > 0 ? Double(into) / Double(span) : 0 }
        var left: Int { max(0, span - into) }
    }

    static func progress(_ xp: Int) -> Progress {
        let level: Int = level(for: xp)
        let floor: Int = threshold(level)
        return Progress(level: level, into: xp - floor, span: threshold(level + 1) - floor)
    }

    static func title(_ level: Int) -> String {
        switch level {
        case ..<5: tr("Warming up", "Aufwärmen")
        case 5..<10: tr("On the move", "In Bewegung")
        case 10..<15: tr("Regular", "Stammgast")
        case 15..<20: tr("Athlete", "Sportskanone")
        case 20..<30: tr("Relentless", "Unermüdlich")
        default: tr("Legend", "Legende")
        }
    }
}

// MARK: - Quests

struct FitnessQuest: Identifiable, Equatable {
    enum Kind: String { case burn, sessions, long, weighIns, steps, variety }

    let kind: Kind
    let title: String
    let detail: String
    let symbol: String
    let progress: Int
    let target: Int
    let reward: Int

    var id: String { kind.rawValue }
    var done: Bool { progress >= target }
    var fraction: Double { target > 0 ? min(1, Double(progress) / Double(target)) : 0 }
}

enum FitnessQuests {
    /// Three quests a week: the burn the goal needs, the number of
    /// sessions the plan suggests, and one that changes from week to week.
    static func week(_ week: FitnessWeek, target: Double, plannedSessions: Int,
                     weighIns: Int, stepGoalDays: Int, weekIndex: Int) -> [FitnessQuest] {
        let targetKcal: Int = Int(target.rounded())
        let sessions: Int = min(6, max(2, plannedSessions))
        let burn = FitnessQuest(kind: .burn,
                                title: tr("Weekly burn", "Wochenziel"),
                                detail: tr("\(targetKcal.formatted()) kcal in workouts", "\(targetKcal.formatted()) kcal im Training"),
                                symbol: "flame.fill", progress: week.kcal, target: max(1, targetKcal), reward: 150)
        let count = FitnessQuest(kind: .sessions,
                                 title: tr("Show up", "Dranbleiben"),
                                 detail: tr("\(sessions) workouts this week", "\(sessions) Einheiten diese Woche"),
                                 symbol: "checkmark.circle.fill", progress: week.sessions, target: sessions, reward: 75)
        let rotating: FitnessQuest
        switch ((weekIndex % 4) + 4) % 4 {
        case 0:
            rotating = FitnessQuest(kind: .long,
                                    title: tr("The long one", "Die Lange"),
                                    detail: tr("One session of an hour or more", "Eine Einheit ab einer Stunde"),
                                    symbol: "hourglass", progress: week.longest, target: 60, reward: 50)
        case 1:
            rotating = FitnessQuest(kind: .weighIns,
                                    title: tr("Check in", "Kurz wiegen"),
                                    detail: tr("Weigh yourself twice this week", "Wieg dich zweimal diese Woche"),
                                    symbol: "scalemass.fill", progress: weighIns, target: 2, reward: 50)
        case 2:
            rotating = FitnessQuest(kind: .steps,
                                    title: tr("Step it up", "Schritt für Schritt"),
                                    detail: tr("Reach your step goal on 4 days", "An 4 Tagen dein Schrittziel"),
                                    symbol: "shoeprints.fill", progress: stepGoalDays, target: 4, reward: 50)
        default:
            rotating = FitnessQuest(kind: .variety,
                                    title: tr("Mix it up", "Abwechslung"),
                                    detail: tr("Two different kinds of workout", "Zwei verschiedene Trainingsarten"),
                                    symbol: "shuffle", progress: week.kinds.count, target: 2, reward: 50)
        }
        return [burn, count, rotating]
    }
}

// MARK: - Badges

struct FitnessBadge: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let earned: Bool
}

enum FitnessBadges {
    struct Input {
        var workouts: [FitnessWorkout]
        var days: [FitnessDay]
        var bestWeekKcal: Int
        var targetWeeksInARow: Int
        var lostKg: Double
        var goal: FitnessGoal?
    }

    static func all(_ input: Input) -> [FitnessBadge] {
        let count: Int = input.workouts.count
        let longestKm: Double = input.workouts.compactMap(\.km).max() ?? 0
        let biggest: Int = input.workouts.map(\.calories).max() ?? 0
        let bestSteps: Int = input.days.map(\.steps).max() ?? 0
        let toLose: Double = input.goal?.toLose ?? 0
        return [
            FitnessBadge(id: "first", title: tr("First step", "Erster Schritt"),
                         detail: tr("Log your first workout", "Dein erstes Training"),
                         symbol: "figure.walk", earned: count >= 1),
            FitnessBadge(id: "ten", title: tr("Ten", "Zehn"),
                         detail: tr("10 workouts", "10 Einheiten"),
                         symbol: "10.circle.fill", earned: count >= 10),
            FitnessBadge(id: "fifty", title: tr("Fifty", "Fünfzig"),
                         detail: tr("50 workouts", "50 Einheiten"),
                         symbol: "50.circle.fill", earned: count >= 50),
            FitnessBadge(id: "km10", title: tr("Ten kilometres", "Zehn Kilometer"),
                         detail: tr("10 km in one session", "10 km in einer Einheit"),
                         symbol: "point.topleft.down.to.point.bottomright.curvepath", earned: longestKm >= 10),
            FitnessBadge(id: "km30", title: tr("Long haul", "Langstrecke"),
                         detail: tr("30 km in one session", "30 km in einer Einheit"),
                         symbol: "road.lanes", earned: longestKm >= 30),
            FitnessBadge(id: "burn500", title: tr("Furnace", "Brennofen"),
                         detail: tr("500 kcal in one session", "500 kcal in einer Einheit"),
                         symbol: "flame.fill", earned: biggest >= 500),
            FitnessBadge(id: "week3000", title: tr("Big week", "Starke Woche"),
                         detail: tr("3,000 kcal in one week", "3.000 kcal in einer Woche"),
                         symbol: "calendar.badge.checkmark", earned: input.bestWeekKcal >= 3000),
            FitnessBadge(id: "steps10k", title: tr("Ten thousand", "Zehntausend"),
                         detail: tr("10,000 steps in a day", "10.000 Schritte an einem Tag"),
                         symbol: "shoeprints.fill", earned: bestSteps >= 10_000),
            FitnessBadge(id: "streak3", title: tr("Three in a row", "Drei am Stück"),
                         detail: tr("Weekly burn three weeks running", "Wochenziel drei Wochen hintereinander"),
                         symbol: "bolt.heart.fill", earned: input.targetWeeksInARow >= 3),
            FitnessBadge(id: "kg1", title: tr("First kilo", "Erstes Kilo"),
                         detail: tr("1 kg down on the trend", "1 kg weniger im Trend"),
                         symbol: "arrow.down.circle.fill", earned: input.lostKg >= 1),
            FitnessBadge(id: "kg5", title: tr("Five down", "Fünf weniger"),
                         detail: tr("5 kg down on the trend", "5 kg weniger im Trend"),
                         symbol: "arrow.down.to.line.circle.fill", earned: input.lostKg >= 5),
            FitnessBadge(id: "halfway", title: tr("Halfway", "Halbzeit"),
                         detail: tr("Half of your goal", "Die Hälfte deines Ziels"),
                         symbol: "circle.lefthalf.filled", earned: toLose > 0 && input.lostKg >= toLose / 2),
            FitnessBadge(id: "goal", title: tr("Made it", "Geschafft"),
                         detail: tr("Reach your goal weight", "Zielgewicht erreicht"),
                         symbol: "trophy.fill", earned: toLose > 0 && input.lostKg >= toLose),
        ]
    }
}

// MARK: - Garmin feed

/// The snapshot senseiissei.dev's Garmin sync publishes. Every field is
/// optional so a feed from another script only needs what it has.
struct GarminFeed: Decodable {
    struct Totals: Decodable {
        var date: String
        var steps: Int?
        var stepGoal: Int?
        var activeCalories: Int?
        var moderateIntensityMinutes: Int?
        var vigorousIntensityMinutes: Int?

        var day: FitnessDay {
            FitnessDay(steps: steps ?? 0, stepGoal: stepGoal ?? 0, activeCalories: activeCalories ?? 0,
                       moderateMinutes: moderateIntensityMinutes ?? 0, vigorousMinutes: vigorousIntensityMinutes ?? 0)
        }
    }

    struct Workout: Decodable {
        var id: String
        var type: String?
        var date: String
        var minutes: Double?
        var km: Double?
        var calories: Double?
        var averageHeartRate: Double?

        private enum CodingKeys: String, CodingKey {
            case id, type, date, minutes, km, calories, averageHeartRate
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let text = try? c.decode(String.self, forKey: .id) {
                id = text
            } else {
                id = String(try c.decode(Int64.self, forKey: .id))
            }
            type = try c.decodeIfPresent(String.self, forKey: .type)
            date = try c.decode(String.self, forKey: .date)
            minutes = try? c.decodeIfPresent(Double.self, forKey: .minutes)
            km = try? c.decodeIfPresent(Double.self, forKey: .km)
            calories = try? c.decodeIfPresent(Double.self, forKey: .calories)
            averageHeartRate = try? c.decodeIfPresent(Double.self, forKey: .averageHeartRate)
        }

        var record: FitnessWorkout {
            let name: String = type ?? "workout"
            return FitnessWorkout(id: "garmin-\(id)", kind: ActivityKind.from(garmin: name), name: name,
                                  date: String(date.prefix(10)),
                                  minutes: Int((minutes ?? 0).rounded()),
                                  km: km, calories: Int((calories ?? 0).rounded()),
                                  averageHeartRate: averageHeartRate.map { Int($0.rounded()) },
                                  source: .garmin)
        }
    }

    var latest: Totals?
    /// Optional history of daily totals, for feeds that keep more than today.
    var activity: [Totals]?
    var workouts: [Workout]?
}

// MARK: - Everything the screens show, in one pass

struct FitnessReport {
    var xp = 0
    var progress = FitnessXP.progress(0)
    var week = FitnessWeek(key: "", workouts: [])
    /// Workout calories a week the goal needs, nil without a goal.
    var target: Double?
    var remaining: Double = 0
    /// Sessions for the rest of this week.
    var plan: [PlanSession] = []
    /// A whole week that reaches the target, Monday first.
    var template: [PlanSession] = []
    var weeklyMinutes = 0
    var quests: [FitnessQuest] = []
    var badges: [FitnessBadge] = []
    var trend: [WeightEntry] = []
    var currentKg: Double?
    var lostKg: Double = 0
    var kgLeft: Double?
    var eta: Date?
    /// What the workouts above the old baseline are worth so far, in kg.
    var exerciseKg: Double = 0
    var weeksInARow = 0
    /// The last eight weeks, oldest first, empty ones included.
    var history: [FitnessWeek] = []

    var weekFraction: Double {
        guard let target, target > 0 else { return 0 }
        return min(1, Double(week.kcal) / target)
    }

    var goalFraction: Double {
        guard let kgLeft, lostKg + kgLeft > 0 else { return 0 }
        return min(1, lostKg / (lostKg + kgLeft))
    }

    static func make(goal: FitnessGoal?, workouts: [FitnessWorkout], days: [String: FitnessDay],
                     weights: [WeightEntry], now: Date = Date(), calendar: Calendar = .current) -> FitnessReport {
        var report = FitnessReport()
        report.trend = FitnessMath.trend(weights)
        report.currentKg = report.trend.last?.kg ?? goal?.startKg
        let weightForRates: Double = report.currentKg ?? 75
        let rate: (ActivityKind) -> Double = { kind in
            FitnessMath.kcalPerMinute(kind, weightKg: weightForRates, history: workouts)
        }

        let weeks: [String: FitnessWeek] = FitnessMath.weeks(workouts, calendar: calendar)
        let thisKey: String = FitnessDate.weekKey(now, calendar: calendar)
        report.week = weeks[thisKey] ?? FitnessWeek(key: thisKey, workouts: [])
        let monday: Date = FitnessDate.weekStart(now, calendar: calendar)
        report.history = (0..<8).reversed().compactMap { back -> FitnessWeek? in
            guard let start = calendar.date(byAdding: .day, value: -7 * back, to: monday) else { return nil }
            let key: String = FitnessDate.weekKey(start, calendar: calendar)
            return weeks[key] ?? FitnessWeek(key: key, workouts: [])
        }

        var questXP = 0
        var bestRun = 0
        if let goal {
            let target: Double = FitnessMath.weeklyTarget(goal)
            report.target = target
            report.remaining = max(0, target - Double(report.week.kcal))
            report.plan = FitnessPlanner.sessions(remainingKcal: report.remaining,
                                                  daysLeft: FitnessDate.daysLeftInWeek(now, calendar: calendar),
                                                  favorites: goal.favorites, rate: rate)
            report.template = FitnessPlanner.sessions(remainingKcal: target, daysLeft: 7,
                                                      favorites: goal.favorites, rate: rate)
            report.weeklyMinutes = FitnessPlanner.weeklyMinutes(targetKcal: target, favorites: goal.favorites, rate: rate)

            let weighInDays: Set<String> = Set(weights.map(\.date))
            var met: [Bool] = []
            var run = 0
            for (index, key) in FitnessMath.planWeeks(from: goal.startDate, to: now, calendar: calendar).enumerated() {
                let week: FitnessWeek = weeks[key] ?? FitnessWeek(key: key, workouts: [])
                let dayKeys: [String] = (0..<7).compactMap { offset in
                    guard let start = FitnessDate.date(key, calendar: calendar),
                          let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
                    return FitnessDate.key(day, calendar: calendar)
                }
                let quests: [FitnessQuest] = FitnessQuests.week(
                    week, target: target, plannedSessions: report.template.count,
                    weighIns: dayKeys.filter { weighInDays.contains($0) }.count,
                    stepGoalDays: dayKeys.filter { days[$0]?.stepGoalMet == true }.count,
                    weekIndex: index)
                questXP += quests.filter(\.done).reduce(0) { $0 + $1.reward }
                if key == thisKey { report.quests = quests }
                let reached: Bool = Double(week.kcal) >= target
                met.append(reached)
                run = reached ? run + 1 : 0
                bestRun = max(bestRun, run)
                report.exerciseKg += max(0, Double(week.kcal) - goal.baselineWeeklyKcal) / FitnessMath.kcalPerKg
            }
            // The running week does not break the streak before it is over.
            var streak = 0
            for (index, reached) in met.enumerated().reversed() {
                if reached { streak += 1 } else if index == met.count - 1 { continue } else { break }
            }
            report.weeksInARow = streak

            if let current = report.currentKg {
                report.lostKg = max(0, goal.startKg - current)
                let left: Double = max(0, current - goal.goalKg)
                report.kgLeft = left
                let weeksLeft: Double = FitnessMath.weeksToGoal(kgLeft: left, kgPerWeek: goal.kgPerWeek)
                report.eta = calendar.date(byAdding: .day, value: Int((weeksLeft * 7).rounded(.up)), to: now)
            }
        } else if let first = report.trend.first, let last = report.trend.last {
            report.lostKg = max(0, first.kg - last.kg)
        }

        report.xp = workouts.reduce(0) { $0 + FitnessXP.workout($1) }
            + days.values.reduce(0) { $0 + FitnessXP.day($1) }
            + weights.count * FitnessXP.weighIn
            + questXP
        report.progress = FitnessXP.progress(report.xp)
        report.badges = FitnessBadges.all(FitnessBadges.Input(
            workouts: workouts, days: Array(days.values),
            bestWeekKcal: weeks.values.map(\.kcal).max() ?? 0,
            targetWeeksInARow: bestRun, lostKg: report.lostKg, goal: goal))
        return report
    }
}

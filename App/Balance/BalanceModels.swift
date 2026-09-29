import Foundation

// Pure data and rules for the Balance tab: movement routines, water, meals
// and sleep. Foundation only, so every rule here can be tested without
// SwiftUI or a phone.

// MARK: - Movement

/// One movement in a routine. Not called Exercise: that name belongs to
/// the learning engine.
struct BodyMove: Equatable {
    let name: String
    let howTo: String
    let symbol: String
    /// One side first, the other after half the time. The player says so.
    var switchesSides = false
}

struct RoutineStep: Equatable {
    enum Kind: Equatable { case prepare, work, rest }

    let kind: Kind
    let exercise: BodyMove
    let seconds: Double

    var title: String {
        switch kind {
        case .prepare: tr("Get ready", "Mach dich bereit")
        case .rest: tr("Rest", "Pause")
        case .work: exercise.name
        }
    }
}

enum RoutineID: String, CaseIterable {
    case morning, desk, sevenMinute, evening
}

struct Routine: Identifiable, Equatable {
    let id: RoutineID
    let title: String
    let blurb: String
    let symbol: String
    let illustration: String
    /// The length people know the routine by. The real total adds a few
    /// seconds to get ready, and for the classic workout the short rests.
    let nominalMinutes: Int
    let steps: [RoutineStep]

    var durations: [Double] { steps.map(\.seconds) }
    var totalSeconds: Double { steps.reduce(0) { $0 + $1.seconds } }
    var workSeconds: Double { steps.filter { $0.kind == .work }.reduce(0) { $0 + $1.seconds } }
    var exerciseCount: Int { steps.filter { $0.kind == .work }.count }

    /// The next step that is an actual exercise, for the "next up" preview.
    func nextWork(after index: Int) -> RoutineStep? {
        guard index + 1 < steps.count else { return nil }
        return steps[(index + 1)...].first { $0.kind == .work }
    }

    /// Five quiet seconds before the first move, then one move after another.
    static func flow(_ moves: [(BodyMove, Double)], prepare: Double = 5) -> [RoutineStep] {
        let first: BodyMove = moves.first?.0 ?? BodyMove(name: "", howTo: "", symbol: "figure.stand")
        var steps: [RoutineStep] = [RoutineStep(kind: .prepare, exercise: first, seconds: prepare)]
        for (exercise, seconds) in moves {
            steps.append(RoutineStep(kind: .work, exercise: exercise, seconds: seconds))
        }
        return steps
    }

    /// Work and rest in turn. No rest after the last move: then it is over.
    static func intervals(_ moves: [BodyMove], work: Double, rest: Double, prepare: Double = 5) -> [RoutineStep] {
        guard let first = moves.first else { return [] }
        var steps: [RoutineStep] = [RoutineStep(kind: .prepare, exercise: first, seconds: prepare)]
        for (index, exercise) in moves.enumerated() {
            steps.append(RoutineStep(kind: .work, exercise: exercise, seconds: work))
            if index + 1 < moves.count {
                steps.append(RoutineStep(kind: .rest, exercise: moves[index + 1], seconds: rest))
            }
        }
        return steps
    }

    static var all: [Routine] { [.morning, .desk, .sevenMinute, .evening] }

    static func with(id: RoutineID) -> Routine {
        switch id {
        case .morning: .morning
        case .desk: .desk
        case .sevenMinute: .sevenMinute
        case .evening: .evening
        }
    }
}

// MARK: Routine catalogue

extension Routine {
    static var morning: Routine {
        let moves: [(BodyMove, Double)] = [
            (BodyMove(name: tr("Neck rolls", "Nackenkreisen"),
                      howTo: tr("Slow half circles from shoulder to shoulder.", "Langsame Halbkreise von Schulter zu Schulter."),
                      symbol: "figure.mind.and.body"), 40),
            (BodyMove(name: tr("Shoulder circles", "Schulterkreisen"),
                      howTo: tr("Big circles backwards, then forwards.", "Große Kreise nach hinten, dann nach vorn."),
                      symbol: "figure.arms.open"), 40),
            (BodyMove(name: tr("Arm swings", "Armschwünge"),
                      howTo: tr("Hug yourself, then open your arms wide.", "Umarm dich selbst, dann öffne die Arme weit."),
                      symbol: "figure.cross.training"), 40),
            (BodyMove(name: tr("Cat and cow", "Katze und Kuh"),
                      howTo: tr("On all fours, round your back, then let it sink.", "Im Vierfüßlerstand den Rücken runden, dann sinken lassen."),
                      symbol: "figure.yoga"), 40),
            (BodyMove(name: tr("Hip circles", "Hüftkreisen"),
                      howTo: tr("Hands on your hips, slow circles both ways.", "Hände an die Hüften, langsame Kreise in beide Richtungen."),
                      symbol: "figure.taichi"), 40),
            (BodyMove(name: tr("Lunge with a twist", "Ausfallschritt mit Drehung"),
                      howTo: tr("Step forward and turn your chest over the front knee.", "Schritt nach vorn, Oberkörper über das vordere Knie drehen."),
                      symbol: "figure.flexibility", switchesSides: true), 40),
            (BodyMove(name: tr("Squat to stand", "Aus der Hocke hoch"),
                      howTo: tr("Sink into a deep squat, then roll up slowly.", "Geh tief in die Hocke und roll dich langsam hoch."),
                      symbol: "figure.strengthtraining.functional"), 40),
            (BodyMove(name: tr("Side bends", "Seitbeugen"),
                      howTo: tr("One arm overhead, lean to the side, take turns.", "Einen Arm über den Kopf, zur Seite neigen, im Wechsel."),
                      symbol: "figure.cooldown"), 40),
            (BodyMove(name: tr("Reach and breathe", "Strecken und atmen"),
                      howTo: tr("Reach up as you breathe in, let your arms float down as you breathe out.", "Streck dich beim Einatmen, lass die Arme beim Ausatmen sinken."),
                      symbol: "figure.stand"), 40),
        ]
        return Routine(id: .morning,
                       title: tr("Morning mobility", "Morgen-Mobilität"),
                       blurb: tr("Wake up the joints, gently.", "Weckt die Gelenke, ganz sanft."),
                       symbol: "sunrise.fill", illustration: "IllustrationMorning",
                       nominalMinutes: 6, steps: flow(moves))
    }

    static var desk: Routine {
        let moves: [(BodyMove, Double)] = [
            (BodyMove(name: tr("Stand and reach", "Aufstehen und strecken"),
                      howTo: tr("Stand up, lace your fingers and reach for the ceiling.", "Steh auf, verschränk die Finger und streck dich zur Decke."),
                      symbol: "figure.stand"), 30),
            (BodyMove(name: tr("Neck release", "Nacken lockern"),
                      howTo: tr("Tilt your ear towards your shoulder and breathe.", "Neig das Ohr zur Schulter und atme ruhig."),
                      symbol: "figure.mind.and.body", switchesSides: true), 30),
            (BodyMove(name: tr("Chest opener", "Brust öffnen"),
                      howTo: tr("Hands behind your back, shoulder blades together, chest up.", "Hände hinter den Rücken, Schulterblätter zusammen, Brust heben."),
                      symbol: "figure.arms.open"), 30),
            (BodyMove(name: tr("Wrist circles", "Handgelenke kreisen"),
                      howTo: tr("Circle your wrists, then stretch your fingers back gently.", "Kreis die Handgelenke und zieh die Finger sanft zurück."),
                      symbol: "hand.raised.fill"), 30),
            (BodyMove(name: tr("Seated twist", "Drehung im Sitzen"),
                      howTo: tr("Sit tall and turn from the middle of your back.", "Sitz aufrecht und dreh dich aus der Mitte des Rückens."),
                      symbol: "figure.flexibility", switchesSides: true), 30),
            (BodyMove(name: tr("Calf raises", "Wadenheben"),
                      howTo: tr("Rise onto your toes and lower slowly.", "Geh auf die Zehenspitzen und senk dich langsam ab."),
                      symbol: "figure.step.training"), 30),
            (BodyMove(name: tr("March on the spot", "Auf der Stelle gehen"),
                      howTo: tr("Lift your knees, swing your arms, keep it easy.", "Knie heben, Arme mitschwingen, ganz locker."),
                      symbol: "figure.walk"), 30),
            (BodyMove(name: tr("Look into the distance", "In die Ferne schauen"),
                      howTo: tr("Look out of a window or across the room and let your eyes rest.", "Schau aus dem Fenster oder quer durch den Raum und lass die Augen ruhen."),
                      symbol: "eye"), 30),
        ]
        return Routine(id: .desk,
                       title: tr("Desk break", "Schreibtisch-Pause"),
                       blurb: tr("Undo an hour of sitting.", "Macht eine Stunde Sitzen wieder gut."),
                       symbol: "chair.lounge.fill", illustration: "IllustrationFocus",
                       nominalMinutes: 4, steps: flow(moves))
    }

    /// The classic twelve, 30 seconds each with 10 seconds between.
    static var sevenMinute: Routine {
        let moves: [BodyMove] = [
            BodyMove(name: tr("Jumping jacks", "Hampelmann"),
                     howTo: tr("Jump your feet apart as your arms go up, then back.", "Spring in die Grätsche, Arme nach oben, und zurück."),
                     symbol: "figure.mixed.cardio"),
            BodyMove(name: tr("Wall sit", "Wandsitzen"),
                     howTo: tr("Back against a wall, knees at a right angle, hold.", "Rücken an die Wand, Knie im rechten Winkel, halten."),
                     symbol: "figure.strengthtraining.functional"),
            BodyMove(name: tr("Push-ups", "Liegestütze"),
                     howTo: tr("Body in one line, lower your chest, push up. Knees down is fine.", "Körper in einer Linie, Brust absenken, hochdrücken. Auf den Knien ist völlig okay."),
                     symbol: "figure.strengthtraining.traditional"),
            BodyMove(name: tr("Crunches", "Crunches"),
                     howTo: tr("On your back, knees bent, lift your shoulders a little.", "Auf dem Rücken, Knie angewinkelt, Schultern leicht anheben."),
                     symbol: "figure.core.training"),
            BodyMove(name: tr("Step-ups", "Step-ups"),
                     howTo: tr("Step onto a sturdy chair or stair, take turns with your legs.", "Steig auf einen stabilen Stuhl oder eine Stufe, Beine im Wechsel."),
                     symbol: "figure.step.training"),
            BodyMove(name: tr("Squats", "Kniebeugen"),
                     howTo: tr("Feet hip-wide, sit back as if onto a chair, stand up.", "Füße hüftbreit, setz dich nach hinten wie auf einen Stuhl, wieder hoch."),
                     symbol: "figure.strengthtraining.functional"),
            BodyMove(name: tr("Triceps dips", "Trizeps-Dips"),
                     howTo: tr("Hands on a chair behind you, bend and straighten your arms.", "Hände hinter dir auf einem Stuhl, Arme beugen und strecken."),
                     symbol: "figure.strengthtraining.traditional"),
            BodyMove(name: tr("Plank", "Unterarmstütz"),
                     howTo: tr("On your forearms, body straight, breathe calmly.", "Auf den Unterarmen, Körper gerade, ruhig atmen."),
                     symbol: "figure.core.training"),
            BodyMove(name: tr("High knees", "Kniehebelauf"),
                     howTo: tr("Run on the spot and bring your knees up high.", "Lauf auf der Stelle und zieh die Knie hoch."),
                     symbol: "figure.run"),
            BodyMove(name: tr("Lunges", "Ausfallschritte"),
                     howTo: tr("Step forward, lower the back knee, take turns with your legs.", "Schritt nach vorn, hinteres Knie absenken, Beine im Wechsel."),
                     symbol: "figure.cross.training"),
            BodyMove(name: tr("Push-up and rotation", "Liegestütz mit Drehung"),
                     howTo: tr("After each push-up, turn and lift one arm to the sky.", "Nach jedem Liegestütz aufdrehen und einen Arm zum Himmel strecken."),
                     symbol: "figure.highintensity.intervaltraining"),
            BodyMove(name: tr("Side plank", "Seitstütz"),
                     howTo: tr("On one forearm, hips up, body in a line.", "Auf einem Unterarm, Hüfte hoch, Körper in einer Linie."),
                     symbol: "figure.pilates", switchesSides: true),
        ]
        return Routine(id: .sevenMinute,
                       title: tr("7-minute workout", "7-Minuten-Workout"),
                       blurb: tr("The classic twelve. Short and honest.", "Die klassischen zwölf. Kurz und ehrlich."),
                       symbol: "flame.fill", illustration: "IllustrationHabits",
                       nominalMinutes: 7, steps: intervals(moves, work: 30, rest: 10))
    }

    static var evening: Routine {
        let catCow = BodyMove(name: tr("Slow cat and cow", "Langsam Katze und Kuh"),
                              howTo: tr("On all fours, move with your breath, no hurry.", "Im Vierfüßlerstand mit dem Atem bewegen, ohne Eile."),
                              symbol: "figure.yoga")
        let moves: [(BodyMove, Double)] = [
            (BodyMove(name: tr("Child's pose", "Kindhaltung"),
                      howTo: tr("Knees wide, sit back on your heels, arms long, breathe into your back.", "Knie weit, Po zu den Fersen, Arme lang, atme in den Rücken."),
                      symbol: "figure.yoga"), 60),
            (catCow, 45),
            (BodyMove(name: tr("Lying twist", "Liegende Drehung"),
                      howTo: tr("On your back, let both knees sink to one side, look the other way.", "Auf dem Rücken beide Knie zu einer Seite sinken lassen, Blick zur anderen."),
                      symbol: "figure.pilates", switchesSides: true), 90),
            (BodyMove(name: tr("Figure four", "Liegende Taube"),
                      howTo: tr("On your back, one ankle over the other knee, draw it gently towards you.", "Auf dem Rücken, einen Knöchel aufs andere Knie, sanft zu dir ziehen."),
                      symbol: "figure.flexibility", switchesSides: true), 90),
            (BodyMove(name: tr("Seated forward fold", "Vorbeuge im Sitzen"),
                      howTo: tr("Legs long, fold forward from the hips, never force it.", "Beine lang, aus der Hüfte nach vorn, nie mit Gewalt."),
                      symbol: "figure.flexibility"), 60),
            (BodyMove(name: tr("Butterfly", "Schmetterling"),
                      howTo: tr("Soles together, let your knees fall open, sit tall.", "Fußsohlen zusammen, Knie fallen lassen, aufrecht sitzen."),
                      symbol: "figure.mind.and.body"), 45),
            (BodyMove(name: tr("Legs up the wall", "Beine an die Wand"),
                      howTo: tr("Lie down, rest your legs against a wall, breathe slowly.", "Leg dich hin, Beine an die Wand, langsam atmen."),
                      symbol: "moon.stars.fill"), 90),
        ]
        return Routine(id: .evening,
                       title: tr("Evening stretch", "Abend-Dehnen"),
                       blurb: tr("Slow holds that tell the body the day is done.", "Ruhige Haltungen, die dem Körper sagen: Der Tag ist vorbei."),
                       symbol: "moon.stars.fill", illustration: "IllustrationEvening",
                       nominalMinutes: 8, steps: flow(moves))
    }
}

// MARK: Routine clock

/// Where a running routine stands. Time is kept as "banked seconds plus
/// the time since the last resume", so pausing, skipping and a trip to the
/// background all come out right without a ticking counter.
struct RoutineClock: Equatable {
    let durations: [Double]
    private(set) var index = 0
    private(set) var isFinished: Bool
    /// Seconds spent in the current step before the last resume.
    private(set) var bankedInStep: Double = 0
    /// Seconds spent in steps that are already behind.
    private(set) var bankedBefore: Double = 0
    /// Nil while paused or not started.
    private(set) var runningSince: Date?

    init(durations: [Double]) {
        self.durations = durations
        isFinished = durations.isEmpty
    }

    var isRunning: Bool { runningSince != nil }

    var stepSeconds: Double { durations.indices.contains(index) ? durations[index] : 0 }

    func elapsedInStep(at now: Date) -> Double {
        let running: Double = runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return min(stepSeconds, bankedInStep + running)
    }

    func remainingInStep(at now: Date) -> Double {
        max(0, stepSeconds - elapsedInStep(at: now))
    }

    func stepProgress(at now: Date) -> Double {
        stepSeconds > 0 ? elapsedInStep(at: now) / stepSeconds : 1
    }

    /// Everything actually spent, pauses left out. This is what counts as
    /// active time.
    func spent(at now: Date) -> Double {
        isFinished ? bankedBefore : bankedBefore + elapsedInStep(at: now)
    }

    func totalProgress(at now: Date) -> Double {
        let total: Double = durations.reduce(0, +)
        guard total > 0 else { return 1 }
        let before: Double = durations.prefix(index).reduce(0, +)
        let inStep: Double = isFinished ? 0 : elapsedInStep(at: now)
        return isFinished ? 1 : min(1, (before + inStep) / total)
    }

    mutating func start(at now: Date) {
        guard !isFinished, runningSince == nil else { return }
        runningSince = now
    }

    mutating func pause(at now: Date) {
        guard let since = runningSince else { return }
        bankedInStep += max(0, now.timeIntervalSince(since))
        runningSince = nil
    }

    /// Moves on past every step whose time is up. Returns true when the step
    /// changed, so the caller knows to speak and buzz. A long stay in the
    /// background may cross several steps at once; they all count.
    @discardableResult
    mutating func sync(at now: Date) -> Bool {
        guard !isFinished, let since = runningSince else { return false }
        var inStep: Double = bankedInStep + max(0, now.timeIntervalSince(since))
        var changed = false
        while inStep >= stepSeconds {
            inStep -= stepSeconds
            bankedBefore += stepSeconds
            changed = true
            if index + 1 >= durations.count {
                finish()
                return true
            }
            index += 1
        }
        // Re-anchor on the current step so the arithmetic never drifts.
        bankedInStep = 0
        runningSince = now.addingTimeInterval(-inStep)
        return changed
    }

    /// Skipping keeps the seconds already spent in the step, nothing more.
    mutating func skip(at now: Date) {
        sync(at: now)
        guard !isFinished else { return }
        bankedBefore += elapsedInStep(at: now)
        bankedInStep = 0
        if index + 1 >= durations.count {
            finish()
            return
        }
        index += 1
        if runningSince != nil { runningSince = now }
    }

    private mutating func finish() {
        isFinished = true
        runningSince = nil
        bankedInStep = 0
    }

    /// True in the tick where the step passes its midpoint: the moment to
    /// switch sides.
    static func crossedHalf(stepSeconds: Double, from previous: Double, to current: Double) -> Bool {
        let half: Double = stepSeconds / 2
        return previous < half && current >= half
    }
}

// MARK: - Water

enum WaterMath {
    static let glassMilliliters = 250
    static let targetRange: ClosedRange<Int> = 4...16
    static let defaultTarget = 8
    /// A ceiling for mistaken taps, far above any sensible day.
    static let maxGlasses = 30

    static func liters(glasses: Int) -> Double {
        Double(glasses * glassMilliliters) / 1000
    }

    static func clampTarget(_ target: Int) -> Int {
        min(targetRange.upperBound, max(targetRange.lowerBound, target))
    }

    static func progress(glasses: Int, target: Int) -> Double {
        let goal: Int = max(1, target)
        return min(1, Double(max(0, glasses)) / Double(goal))
    }

    static func remaining(glasses: Int, target: Int) -> Int {
        max(0, target - glasses)
    }

    static func added(to glasses: Int) -> Int { min(maxGlasses, glasses + 1) }
    static func removed(from glasses: Int) -> Int { max(0, glasses - 1) }
}

// MARK: - Meals

enum Meal: String, CaseIterable, Codable, Identifiable {
    case breakfast, lunch, dinner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: tr("Breakfast", "Frühstück")
        case .lunch: tr("Lunch", "Mittagessen")
        case .dinner: tr("Dinner", "Abendessen")
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.fill"
        }
    }
}

/// A quick honest look at a meal. No calories, no grams: only what was on
/// the plate, as a mirror, not a score.
enum MealTag: String, CaseIterable, Codable, Identifiable {
    case vegetables, protein, wholeGrains, sugarFree

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vegetables: tr("Vegetables", "Gemüse")
        case .protein: tr("Protein", "Eiweiß")
        case .wholeGrains: tr("Whole grains", "Vollkorn")
        case .sugarFree: tr("No added sugar", "Ohne Zucker")
        }
    }

    var symbol: String {
        switch self {
        case .vegetables: "carrot.fill"
        case .protein: "fish.fill"
        case .wholeGrains: "leaf.fill"
        case .sugarFree: "checkmark.seal.fill"
        }
    }
}

struct MealEntry: Codable, Equatable {
    var eaten = false
    var tags: Set<MealTag> = []

    init(eaten: Bool = false, tags: Set<MealTag> = []) {
        self.eaten = eaten
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eaten = (try? c.decodeIfPresent(Bool.self, forKey: .eaten)) ?? false
        tags = (try? c.decodeIfPresent(Set<MealTag>.self, forKey: .tags)) ?? []
    }
}

// MARK: - Sleep

enum WindDownItem: String, CaseIterable, Codable, Identifiable {
    case phoneAway, dimLights, breathe, readPage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phoneAway: tr("Phone away from the bed", "Handy weg vom Bett")
        case .dimLights: tr("Dim the lights", "Licht dimmen")
        case .breathe: tr("A few slow breaths", "Ein paar ruhige Atemzüge")
        case .readPage: tr("Read a page", "Eine Seite lesen")
        }
    }

    var symbol: String {
        switch self {
        case .phoneAway: "iphone.slash"
        case .dimLights: "lamp.desk.fill"
        case .breathe: "wind"
        case .readPage: "book.fill"
        }
    }
}

/// Bedtime, wake time and the wind-down before bed, in minutes after
/// midnight. Every calculation goes round the clock, so a bedtime after
/// midnight or a wake time before it both work.
struct SleepPlan: Codable, Equatable {
    var bedtime = 23 * 60
    var wake = 7 * 60
    var windDown = 30

    static let windDownChoices = [15, 30, 45, 60]

    enum Phase: Equatable { case day, windDown, night }

    init(bedtime: Int = 23 * 60, wake: Int = 7 * 60, windDown: Int = 30) {
        self.bedtime = SleepPlan.normalized(bedtime)
        self.wake = SleepPlan.normalized(wake)
        self.windDown = windDown
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bedtime = SleepPlan.normalized((try? c.decodeIfPresent(Int.self, forKey: .bedtime)) ?? 23 * 60)
        wake = SleepPlan.normalized((try? c.decodeIfPresent(Int.self, forKey: .wake)) ?? 7 * 60)
        windDown = (try? c.decodeIfPresent(Int.self, forKey: .windDown)) ?? 30
    }

    static func normalized(_ minute: Int) -> Int {
        ((minute % 1440) + 1440) % 1440
    }

    /// Minutes from one clock time forward to the next, across midnight.
    static func span(from start: Int, to end: Int) -> Int {
        normalized(end - start)
    }

    /// True when `minute` lies in [start, end), a window that may wrap.
    static func contains(_ minute: Int, from start: Int, to end: Int) -> Bool {
        let m = normalized(minute)
        let s = normalized(start)
        let e = normalized(end)
        if s == e { return false }
        return s < e ? (m >= s && m < e) : (m >= s || m < e)
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Time in bed the plan allows: bedtime to the alarm.
    var opportunity: Int { SleepPlan.span(from: bedtime, to: wake) }

    var windDownStart: Int { SleepPlan.normalized(bedtime - windDown) }

    func phase(at date: Date, calendar: Calendar = .current) -> Phase {
        let now: Int = SleepPlan.minuteOfDay(date, calendar: calendar)
        if SleepPlan.contains(now, from: bedtime, to: wake) { return .night }
        if SleepPlan.contains(now, from: windDownStart, to: bedtime) { return .windDown }
        return .day
    }

    /// Minutes until the next alarm, counted from `date`.
    func minutesUntilWake(from date: Date, calendar: Calendar = .current) -> Int {
        SleepPlan.span(from: SleepPlan.minuteOfDay(date, calendar: calendar), to: wake)
    }

    static func clock(_ minute: Int) -> String {
        let m = normalized(minute)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// "7 h 30 min" or "8 h".
    static func durationText(_ minutes: Int) -> String {
        let hours: Int = max(0, minutes) / 60
        let rest: Int = max(0, minutes) % 60
        if rest == 0 { return tr("\(hours) h", "\(hours) Std.") }
        if hours == 0 { return tr("\(rest) min", "\(rest) Min.") }
        return tr("\(hours) h \(rest) min", "\(hours) Std. \(rest) Min.")
    }
}

/// The evening a wind-down belongs to. Ticking the list at half past
/// midnight still counts for the night that began the day before, the
/// same small-hours rule the Today tab uses for the evening.
enum BalanceNight {
    static let cutoffHour = 4

    static func date(for now: Date, calendar: Calendar = .current) -> Date {
        let hour: Int = calendar.component(.hour, from: now)
        guard hour < cutoffHour else { return now }
        return calendar.date(byAdding: .day, value: -1, to: now) ?? now
    }
}

// MARK: - Days

/// One day of balance. Every field decodes on its own, so a file written
/// by an older version never loses the whole day.
struct BalanceDay: Codable, Equatable {
    var water = 0
    /// The water target that day, so changing it later leaves history alone.
    var waterGoal: Int?
    var moveSessions = 0
    var moveSeconds = 0
    var meals: [String: MealEntry] = [:]
    var windDown: Set<WindDownItem> = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        water = (try? c.decodeIfPresent(Int.self, forKey: .water)) ?? 0
        waterGoal = try? c.decodeIfPresent(Int.self, forKey: .waterGoal)
        moveSessions = (try? c.decodeIfPresent(Int.self, forKey: .moveSessions)) ?? 0
        moveSeconds = (try? c.decodeIfPresent(Int.self, forKey: .moveSeconds)) ?? 0
        meals = (try? c.decodeIfPresent([String: MealEntry].self, forKey: .meals)) ?? [:]
        windDown = (try? c.decodeIfPresent(Set<WindDownItem>.self, forKey: .windDown)) ?? []
    }

    var moveMinutes: Int { moveSeconds / 60 }

    func meal(_ meal: Meal) -> MealEntry { meals[meal.rawValue] ?? MealEntry() }

    var hadVegetables: Bool { meals.values.contains { $0.tags.contains(.vegetables) } }

    func waterMet(defaultTarget: Int) -> Bool {
        water >= max(1, waterGoal ?? defaultTarget)
    }

    var windDownProgress: Double {
        Double(windDown.count) / Double(WindDownItem.allCases.count)
    }
}

struct BalanceSettings: Codable, Equatable {
    var waterTarget = WaterMath.defaultTarget
    var moveGoalMinutes = 10
    var voice = true
    var sleep = SleepPlan()
    var reminder = false

    static let moveGoalChoices = [5, 10, 20, 30]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        waterTarget = WaterMath.clampTarget((try? c.decodeIfPresent(Int.self, forKey: .waterTarget)) ?? WaterMath.defaultTarget)
        moveGoalMinutes = (try? c.decodeIfPresent(Int.self, forKey: .moveGoalMinutes)) ?? 10
        voice = (try? c.decodeIfPresent(Bool.self, forKey: .voice)) ?? true
        sleep = (try? c.decodeIfPresent(SleepPlan.self, forKey: .sleep)) ?? SleepPlan()
        reminder = (try? c.decodeIfPresent(Bool.self, forKey: .reminder)) ?? false
    }
}

// MARK: - Streaks and weeks

enum BalanceStreak {
    /// Days in a row that pass `isDone`. An unfinished today does not break
    /// the streak yet, it ends once a whole day is missed. Same rule as the
    /// habits on the Today tab.
    static func count(asOf date: Date = Date(), calendar: Calendar = .current,
                      key: (Date) -> String, isDone: (String) -> Bool) -> Int {
        let start: Date = calendar.startOfDay(for: date)
        var offset = isDone(key(start)) ? 0 : 1
        var days = 0
        while days < 1000 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: start), isDone(key(day)) else { break }
            days += 1
            offset += 1
        }
        return days
    }

    /// The last `count` days, oldest first, as dates at the start of each day.
    static func lastDays(_ count: Int, asOf date: Date = Date(), calendar: Calendar = .current) -> [Date] {
        let start: Date = calendar.startOfDay(for: date)
        return (0..<max(0, count)).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: start) }
    }
}

// MARK: - Nutrition tips

struct NutritionTip: Equatable {
    let title: String
    let text: String
    let symbol: String

    /// Well established basics, nothing medical. One a day, in turn.
    static var all: [NutritionTip] {
        [
            NutritionTip(title: tr("Water first", "Erst mal Wasser"),
                         text: tr("Keep a glass within reach. Thirst often feels like hunger or tiredness.", "Stell dir ein Glas in Reichweite. Durst fühlt sich oft wie Hunger oder Müdigkeit an."),
                         symbol: "drop.fill"),
            NutritionTip(title: tr("Half the plate", "Der halbe Teller"),
                         text: tr("Fill half your plate with vegetables and fruit.", "Füll die Hälfte deines Tellers mit Gemüse und Obst."),
                         symbol: "carrot.fill"),
            NutritionTip(title: tr("Whole grains", "Vollkorn"),
                         text: tr("Whole grain bread, oats and brown rice keep you full for longer than white flour.", "Vollkornbrot, Haferflocken und Naturreis halten länger satt als Weißmehl."),
                         symbol: "leaf.fill"),
            NutritionTip(title: tr("Mind the drinks", "Achte aufs Trinken"),
                         text: tr("Sugary drinks add up fast. Water or unsweetened tea do the job.", "Zuckrige Getränke läppern sich schnell. Wasser oder ungesüßter Tee tun es auch."),
                         symbol: "cup.and.saucer.fill"),
            NutritionTip(title: tr("Eat slowly", "Iss langsam"),
                         text: tr("Feeling full takes a little while to arrive. Put the fork down between bites.", "Das Sattgefühl braucht eine Weile. Leg die Gabel zwischen den Bissen ab."),
                         symbol: "tortoise.fill"),
            NutritionTip(title: tr("No screen at the table", "Kein Bildschirm am Tisch"),
                         text: tr("Eating without a feed makes it easier to notice when you have had enough.", "Ohne Feed merkst du leichter, wann du genug hast."),
                         symbol: "iphone.slash"),
            NutritionTip(title: tr("Colour on the plate", "Farbe auf dem Teller"),
                         text: tr("Different colours bring different nutrients. Try one more colour today.", "Verschiedene Farben bringen verschiedene Nährstoffe. Probier heute eine Farbe mehr."),
                         symbol: "paintpalette.fill"),
            NutritionTip(title: tr("Pulses", "Hülsenfrüchte"),
                         text: tr("Beans, lentils and chickpeas bring protein and fibre. A few times a week is a good start.", "Bohnen, Linsen und Kichererbsen bringen Eiweiß und Ballaststoffe. Ein paar Mal pro Woche ist ein guter Anfang."),
                         symbol: "leaf.circle.fill"),
            NutritionTip(title: tr("Whole fruit", "Ganzes Obst"),
                         text: tr("A piece of fruit fills you more than its juice, because the fibre stays in.", "Ein Stück Obst macht satter als sein Saft, weil die Ballaststoffe drin bleiben."),
                         symbol: "basket.fill"),
            NutritionTip(title: tr("A handful of nuts", "Eine Handvoll Nüsse"),
                         text: tr("A small handful of unsalted nuts is a good snack.", "Eine kleine Handvoll ungesalzener Nüsse ist ein guter Snack."),
                         symbol: "hand.raised.fill"),
            NutritionTip(title: tr("Go easy on salt", "Sparsam mit Salz"),
                         text: tr("Taste before you salt. Herbs and spices bring flavour too.", "Erst probieren, dann salzen. Kräuter und Gewürze bringen auch Geschmack."),
                         symbol: "sparkles"),
            NutritionTip(title: tr("Cook now and then", "Öfter selbst kochen"),
                         text: tr("When you cook, you know what is in it. Simple is enough.", "Wenn du kochst, weißt du, was drin ist. Einfach reicht völlig."),
                         symbol: "frying.pan.fill"),
        ]
    }

    /// Day number since a fixed point, so the tip turns over at midnight and
    /// is the same all day long.
    static func index(for date: Date, offset: Int = 0, count: Int, calendar: Calendar = .current) -> Int {
        guard count > 0 else { return 0 }
        let origin: Date = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 0)
        let from: Date = calendar.startOfDay(for: origin)
        let to: Date = calendar.startOfDay(for: date)
        let day: Int = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        return ((day + offset) % count + count) % count
    }
}

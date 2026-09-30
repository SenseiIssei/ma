import Charts
import SwiftUI

// MARK: - Formatting

enum FitnessFormat {
    static func kg(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(Loc.locale)) + " kg"
    }

    static func number(_ value: Int) -> String {
        value.formatted(.number.locale(Loc.locale))
    }

    static func kcal(_ value: Int) -> String {
        number(value) + " kcal"
    }

    static func kcal(_ value: Double) -> String {
        kcal(Int(value.rounded()))
    }

    /// "4 h 20 min" or "45 min".
    static func duration(_ minutes: Int) -> String {
        let h: Int = minutes / 60
        let m: Int = minutes % 60
        if h == 0 { return tr("\(m) min", "\(m) Min.") }
        if m == 0 { return tr("\(h) h", "\(h) Std.") }
        return tr("\(h) h \(m) min", "\(h) Std. \(m) Min.")
    }

    static func weekday(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().weekday(.wide).locale(Loc.locale))
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().day().month(.abbreviated).locale(Loc.locale))
    }

    static func monthYear(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().month(.wide).year().locale(Loc.locale))
    }

    /// Relative to today for the plan: Today, Tomorrow, then the weekday.
    static func planDay(_ offset: Int, from date: Date = Date()) -> String {
        switch offset {
        case 0: return tr("Today", "Heute")
        case 1: return tr("Tomorrow", "Morgen")
        default:
            let day: Date = Calendar.current.date(byAdding: .day, value: offset, to: date) ?? date
            return weekday(day)
        }
    }
}

// MARK: - Section on the Balance hub

struct FitnessSection: View {
    @Environment(FitnessStore.self) private var fitness
    @State private var setup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "flame.fill", title: tr("Fitness goal", "Fitnessziel")) {
                if fitness.syncing {
                    ProgressView().controlSize(.small)
                }
            }
            if fitness.goal == nil {
                intro
            } else {
                NavigationLink {
                    FitnessView()
                } label: {
                    FitnessOverviewCard()
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $setup) {
            FitnessGoalSheet()
                .environment(fitness)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(systemName: "scalemass.fill", tint: Zen.kin, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Lose weight by moving", "Abnehmen durch Bewegung"))
                        .scaledFont(size: 17, weight: .semibold)
                        .foregroundStyle(Zen.ink)
                    Text(tr("Enter your weight and a goal. Ma works out how much sport a week gets you there, plans the week and levels you up with every workout your Garmin records.",
                            "Gib dein Gewicht und ein Ziel ein. Ma rechnet aus, wie viel Sport pro Woche dich dahin bringt, plant die Woche und lässt dich mit jedem Training aufsteigen, das deine Garmin aufzeichnet."))
                        .scaledFont(size: 14)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if fitness.report.xp > 0 {
                HStack(spacing: 12) {
                    LevelRing(progress: fitness.report.progress, size: 56)
                    Text(tr("Your workouts already count: level \(fitness.report.progress.level).",
                            "Deine Trainings zählen schon: Level \(fitness.report.progress.level)."))
                        .scaledFont(size: 14, weight: .medium)
                        .foregroundStyle(Zen.ink)
                }
            }
            Button(tr("Set a goal", "Ziel festlegen")) { setup = true }
                .buttonStyle(.primary)
        }
        .zenCard()
    }
}

/// Level, this week's burn and the weight in one glance.
struct FitnessOverviewCard: View {
    @Environment(FitnessStore.self) private var fitness

    var body: some View {
        let report: FitnessReport = fitness.report
        let target: Int = Int((report.target ?? 0).rounded())
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                LevelRing(progress: report.progress, size: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text(FitnessXP.title(report.progress.level))
                        .displayFont(19)
                        .foregroundStyle(Zen.ink)
                    Text(tr("\(FitnessFormat.number(report.progress.left)) XP to level \(report.progress.level + 1)",
                            "Noch \(FitnessFormat.number(report.progress.left)) XP bis Level \(report.progress.level + 1)"))
                        .scaledFont(size: 13, weight: .medium)
                        .foregroundStyle(Zen.inkSoft)
                    if report.weeksInARow > 1 {
                        Label(tr("\(report.weeksInARow) weeks in a row", "\(report.weeksInARow) Wochen am Stück"),
                              systemImage: "bolt.heart.fill")
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(Zen.kin)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Zen.inkFaint)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tr("This week", "Diese Woche"))
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(Zen.inkSoft)
                    Spacer()
                    Text("\(FitnessFormat.number(report.week.kcal)) / \(FitnessFormat.kcal(target))")
                        .scaledFont(size: 13, weight: .semibold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(Zen.ink)
                }
                InkProgress(value: report.weekFraction, color: report.weekFraction >= 1 ? Zen.matcha : Zen.kin, height: 8)
                    .accessibilityMeter(tr("This week", "Diese Woche"),
                                        value: tr("\(report.week.kcal) of \(target) kcal", "\(report.week.kcal) von \(target) kcal"))
                Text(nextLine(report))
                    .scaledFont(size: 14)
                    .foregroundStyle(Zen.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let current = report.currentKg, let goal = fitness.goal {
                Divider().overlay(Zen.line)
                HStack(spacing: 10) {
                    Image(systemName: "scalemass.fill")
                        .foregroundStyle(Zen.ai)
                        .accessibilityHidden(true)
                    Text("\(FitnessFormat.kg(current))  →  \(FitnessFormat.kg(goal.goalKg))")
                        .scaledFont(size: 15, weight: .semibold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(Zen.ink)
                    Spacer(minLength: 0)
                    if let left = report.kgLeft {
                        Text(left <= 0 ? tr("Goal reached", "Ziel erreicht") : tr("\(FitnessFormat.kg(left)) to go", "noch \(FitnessFormat.kg(left))"))
                            .scaledFont(size: 13, weight: .medium)
                            .foregroundStyle(left <= 0 ? Zen.matcha : Zen.inkSoft)
                    }
                }
            }
        }
        .zenCard()
    }

    private func nextLine(_ report: FitnessReport) -> String {
        if report.weekFraction >= 1 {
            return tr("Weekly burn done. Everything else this week is a bonus.",
                      "Wochenziel geschafft. Alles Weitere diese Woche ist Bonus.")
        }
        guard let next = report.plan.first else {
            return tr("Sync your watch or log a workout to fill the week.",
                      "Synchronisier deine Uhr oder trag ein Training ein.")
        }
        let day: String = FitnessFormat.planDay(next.dayOffset)
        return tr("\(day): \(FitnessFormat.duration(next.minutes)) \(next.kind.title.lowercased()), about \(FitnessFormat.kcal(next.kcal))",
                  "\(day): \(FitnessFormat.duration(next.minutes)) \(next.kind.title), etwa \(FitnessFormat.kcal(next.kcal))")
    }
}

struct LevelRing: View {
    let progress: FitnessXP.Progress
    var size: CGFloat = 86

    var body: some View {
        ZStack {
            ProgressRing(progress: progress.fraction, lineWidth: max(5, size * 0.1), tint: Zen.kin)
            VStack(spacing: -2) {
                if size >= 70 {
                    Text(tr("LEVEL", "LEVEL"))
                        .font(.system(size: size * 0.12, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(Zen.inkSoft)
                }
                Text("\(progress.level)")
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Zen.ink)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(size * 0.14)
        }
        .frame(width: size, height: size)
        .accessibilityMeter(tr("Level \(progress.level)", "Level \(progress.level)"),
                            value: tr("\(progress.into) of \(progress.span) XP", "\(progress.into) von \(progress.span) XP"))
    }
}

// MARK: - Detail

struct FitnessView: View {
    @Environment(FitnessStore.self) private var fitness
    @Environment(AccountStore.self) private var accounts
    @State private var editGoal = false
    @State private var logWeight = false
    @State private var addWorkout = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                FitnessLevelCard()
                FitnessWeekCard()
                FitnessQuestsCard()
                FitnessWeightCard { logWeight = true }
                FitnessHistoryCard()
                FitnessBadgesCard()
                if accounts.has("daily") {
                    DailyLessonsCard()
                }
                FitnessWorkoutsCard { addWorkout = true }
                FitnessFeedCard()
                FitnessHowCard()
                Button(tr("Change goal", "Ziel ändern")) { editGoal = true }
                    .buttonStyle(.quiet)
                BalanceNote(icon: "heart.text.square",
                            text: tr("Numbers from a watch are estimates. Ask a doctor before a big change in training, and stop if anything hurts.",
                                     "Zahlen von einer Uhr sind Schätzungen. Sprich vor einer großen Umstellung mit einer Ärztin oder einem Arzt und hör auf, wenn etwas wehtut."))
            }
            .padding(.horizontal, Zen.gutter)
            .padding(.bottom, 40)
        }
        .refreshable { await fitness.refresh(force: true) }
        .background(AppBackground())
        .navigationTitle(tr("Fitness goal", "Fitnessziel"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { logWeight = true } label: {
                        Label(tr("Log weight", "Gewicht eintragen"), systemImage: "scalemass")
                    }
                    Button { addWorkout = true } label: {
                        Label(tr("Add workout", "Training eintragen"), systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .accessibilityLabel(tr("Add", "Hinzufügen"))
                }
            }
        }
        .sheet(isPresented: $editGoal) {
            FitnessGoalSheet(editing: true).environment(fitness)
        }
        .sheet(isPresented: $logWeight) {
            WeightSheet().environment(fitness)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $addWorkout) {
            ManualWorkoutSheet().environment(fitness)
        }
        .task { await fitness.refresh() }
    }
}

struct FitnessLevelCard: View {
    @Environment(FitnessStore.self) private var fitness

    var body: some View {
        let report: FitnessReport = fitness.report
        let progress: FitnessXP.Progress = report.progress
        let perWorkout: Int = max(40, typicalWorkoutXP)
        let workoutsToGo: Int = Int((Double(progress.left) / Double(perWorkout)).rounded(.up))
        return VStack(spacing: 14) {
            LevelRing(progress: progress, size: 132)
                .dynamicTypeSize(...denseTypeLimit)
            Text(FitnessXP.title(progress.level))
                .displayFont(24)
                .foregroundStyle(Zen.ink)
            Text(tr("\(FitnessFormat.number(report.xp)) XP · \(FitnessFormat.number(progress.left)) to the next level, about \(workoutsToGo) \(workoutsToGo == 1 ? "workout" : "workouts")",
                    "\(FitnessFormat.number(report.xp)) XP · noch \(FitnessFormat.number(progress.left)) bis zum nächsten Level, etwa \(workoutsToGo) \(workoutsToGo == 1 ? "Training" : "Trainings")"))
                .scaledFont(size: 14)
                .foregroundStyle(Zen.inkSoft)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                StatTile(icon: "flame.fill", value: FitnessFormat.number(report.week.kcal),
                         label: tr("kcal this week", "kcal diese Woche"), tint: Zen.kin)
                StatTile(icon: "timer", value: FitnessFormat.number(report.week.minutes),
                         label: tr("Minutes this week", "Minuten diese Woche"), tint: Zen.ai)
                StatTile(icon: "bolt.heart.fill", value: "\(report.weeksInARow)",
                         label: tr("Weeks on target", "Wochen im Ziel"), tint: Zen.matcha)
            }
        }
        .frame(maxWidth: .infinity)
        .zenCard(padding: 20)
        .padding(.top, 8)
    }

    /// What a normal session of yours is worth, for the "about n workouts".
    private var typicalWorkoutXP: Int {
        let recent: [FitnessWorkout] = Array(fitness.workouts.prefix(10))
        guard !recent.isEmpty else { return 60 }
        return recent.reduce(0) { $0 + FitnessXP.workout($1) } / recent.count
    }
}

struct FitnessWeekCard: View {
    @Environment(FitnessStore.self) private var fitness

    var body: some View {
        let report: FitnessReport = fitness.report
        let target: Double = report.target ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "calendar", title: tr("Your week", "Deine Woche"))
            HStack(spacing: 16) {
                ZStack {
                    ProgressRing(progress: report.weekFraction, lineWidth: 11,
                                 tint: report.weekFraction >= 1 ? Zen.matcha : Zen.kin)
                    VStack(spacing: 0) {
                        Text(report.weekFraction.formatted(.percent.precision(.fractionLength(0)).locale(Loc.locale)))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Zen.ink)
                    }
                }
                .frame(width: 88, height: 88)
                .accessibilityMeter(tr("Weekly burn", "Wochenziel"),
                                    value: tr("\(report.week.kcal) of \(Int(target)) kcal", "\(report.week.kcal) von \(Int(target)) kcal"))
                VStack(alignment: .leading, spacing: 4) {
                    Text(FitnessFormat.kcal(report.week.kcal))
                        .displayFont(22)
                        .monospacedDigit()
                        .foregroundStyle(Zen.ink)
                    Text(tr("of \(FitnessFormat.kcal(target)) in workouts", "von \(FitnessFormat.kcal(target)) im Training"))
                        .scaledFont(size: 14)
                        .foregroundStyle(Zen.inkSoft)
                    if report.remaining > 0 {
                        Text(tr("\(FitnessFormat.kcal(report.remaining)) left", "noch \(FitnessFormat.kcal(report.remaining))"))
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundStyle(Zen.kin)
                    }
                }
            }

            if report.plan.isEmpty {
                Label(report.weekFraction >= 1
                      ? tr("Done for this week. Rest counts too.", "Diese Woche geschafft. Pause zählt auch.")
                      : tr("Nothing planned yet.", "Noch nichts geplant."),
                      systemImage: "checkmark.seal.fill")
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Zen.matcha)
            } else {
                VStack(spacing: 10) {
                    ForEach(report.plan) { session in
                        PlanRow(day: FitnessFormat.planDay(session.dayOffset), session: session)
                    }
                }
                if planShortfall(report) > 50 {
                    BalanceNote(icon: "exclamationmark.triangle",
                                text: tr("Even two hours a day would not close this week. That is fine: take what you can, the goal date moves a little.",
                                         "Selbst zwei Stunden am Tag würden diese Woche nicht schließen. Kein Problem: mach, was geht, das Zieldatum verschiebt sich ein wenig."))
                }
            }
        }
        .zenCard()
    }

    private func planShortfall(_ report: FitnessReport) -> Double {
        report.remaining - Double(report.plan.reduce(0) { $0 + $1.kcal })
    }
}

struct PlanRow: View {
    let day: String
    let session: PlanSession

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: session.kind.symbol, tint: Zen.kin, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(day)
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(Zen.inkSoft)
                Text("\(session.kind.title) · \(FitnessFormat.duration(session.minutes))")
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(Zen.ink)
            }
            Spacer(minLength: 0)
            Text(FitnessFormat.kcal(session.kcal))
                .scaledFont(size: 13, weight: .semibold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(Zen.inkSoft)
        }
        .accessibilityElement(children: .combine)
    }
}

struct FitnessQuestsCard: View {
    @Environment(FitnessStore.self) private var fitness

    var body: some View {
        let quests: [FitnessQuest] = fitness.report.quests
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "scroll.fill", title: tr("Weekly quests", "Wochenquests"))
            ForEach(quests) { quest in
                HStack(spacing: 12) {
                    IconBadge(systemName: quest.done ? "checkmark" : quest.symbol,
                              tint: quest.done ? Zen.matcha : Zen.shu, size: 40, filled: quest.done)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(quest.title)
                                .scaledFont(size: 16, weight: .semibold)
                                .foregroundStyle(Zen.ink)
                            Spacer()
                            Text("+\(quest.reward) XP")
                                .scaledFont(size: 12, weight: .bold, design: .rounded)
                                .foregroundStyle(quest.done ? Zen.matcha : Zen.kin)
                        }
                        Text(quest.detail)
                            .scaledFont(size: 13)
                            .foregroundStyle(Zen.inkSoft)
                        InkProgress(value: quest.fraction, color: quest.done ? Zen.matcha : Zen.shu, height: 5)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(quest.title), \(quest.detail)")
                .accessibilityValue(quest.done ? tr("Done", "Erledigt") : "\(quest.progress) / \(quest.target)")
            }
            Text(tr("New quests every Monday.", "Neue Quests jeden Montag."))
                .scaledFont(size: 12)
                .foregroundStyle(Zen.inkFaint)
        }
        .zenCard()
    }
}

struct FitnessWeightCard: View {
    @Environment(FitnessStore.self) private var fitness
    let log: () -> Void

    var body: some View {
        let report: FitnessReport = fitness.report
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "scalemass.fill", title: tr("Weight", "Gewicht")) {
                Button(tr("Log", "Eintragen"), action: log)
                    .scaledFont(size: 15, weight: .semibold)
            }
            if let goal = fitness.goal, let current = report.currentKg {
                HStack(spacing: 12) {
                    StatTile(icon: "scalemass", value: FitnessFormat.kg(current),
                             label: tr("Trend", "Trend"), tint: Zen.ai)
                    StatTile(icon: "arrow.down", value: FitnessFormat.kg(report.lostKg),
                             label: tr("Down so far", "Bisher weniger"), tint: Zen.matcha)
                    StatTile(icon: "flag.checkered", value: FitnessFormat.kg(goal.goalKg),
                             label: tr("Goal", "Ziel"), tint: Zen.kin)
                }
                InkProgress(value: report.goalFraction, color: Zen.matcha, height: 8)
                    .accessibilityMeter(tr("Progress to goal", "Fortschritt zum Ziel"),
                                        value: report.goalFraction.formatted(.percent.precision(.fractionLength(0))))
                if report.trend.count >= 2 {
                    chart(report: report, goal: goal)
                }
                Text(etaLine(report: report, goal: goal))
                    .scaledFont(size: 14)
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(tr("Weigh yourself in the morning, before breakfast. The trend line smooths out water and salt, so one day never decides anything.",
                    "Wieg dich morgens vor dem Frühstück. Die Trendlinie glättet Wasser und Salz, ein einzelner Tag entscheidet also nichts."))
                .scaledFont(size: 12)
                .foregroundStyle(Zen.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .zenCard()
    }

    private func etaLine(report: FitnessReport, goal: FitnessGoal) -> String {
        if let left = report.kgLeft, left <= 0 {
            return tr("You reached your goal. Keep moving to stay there, or set a new one.",
                      "Du hast dein Ziel erreicht. Bleib in Bewegung, um es zu halten, oder setz ein neues.")
        }
        var line: String = ""
        if let eta = report.eta {
            line = tr("At \(FitnessFormat.kg(goal.kgPerWeek)) a week you get there around \(FitnessFormat.monthYear(eta)).",
                      "Mit \(FitnessFormat.kg(goal.kgPerWeek)) pro Woche bist du etwa im \(FitnessFormat.monthYear(eta)) da.")
        }
        if report.exerciseKg >= 0.1 {
            line += " " + tr("Your extra workouts so far are worth about \(FitnessFormat.kg(report.exerciseKg)).",
                             "Deine zusätzlichen Trainings bisher entsprechen etwa \(FitnessFormat.kg(report.exerciseKg)).")
        }
        return line
    }

    private func chart(report: FitnessReport, goal: FitnessGoal) -> some View {
        let raw: [WeightEntry] = Array(fitness.weights.suffix(60))
        let trend: [WeightEntry] = Array(report.trend.suffix(60))
        let values: [Double] = raw.map(\.kg) + [goal.goalKg]
        let low: Double = (values.min() ?? 0) - 1
        let high: Double = (values.max() ?? 1) + 1
        return Chart {
            ForEach(raw) { entry in
                if let day = FitnessDate.date(entry.date) {
                    PointMark(x: .value("Day", day), y: .value("kg", entry.kg))
                        .foregroundStyle(Zen.inkFaint)
                        .symbolSize(18)
                }
            }
            ForEach(trend) { entry in
                if let day = FitnessDate.date(entry.date) {
                    LineMark(x: .value("Day", day), y: .value("Trend", entry.kg))
                        .foregroundStyle(Zen.ai)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                }
            }
            RuleMark(y: .value("Goal", goal.goalKg))
                .foregroundStyle(Zen.matcha.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartYScale(domain: low...high)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .frame(height: 170)
        .accessibilityLabel(tr("Weight trend", "Gewichtsverlauf"))
    }
}

struct FitnessHistoryCard: View {
    @Environment(FitnessStore.self) private var fitness

    var body: some View {
        let report: FitnessReport = fitness.report
        let target: Double = report.target ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "chart.bar.fill", title: tr("Last eight weeks", "Letzte acht Wochen"))
            Chart {
                ForEach(report.history, id: \.key) { week in
                    if let day = FitnessDate.date(week.key) {
                        BarMark(x: .value("Week", day, unit: .weekOfYear), y: .value("kcal", week.kcal))
                            .foregroundStyle(Double(week.kcal) >= target && target > 0 ? Zen.matcha : Zen.kin)
                            .cornerRadius(5)
                    }
                }
                if target > 0 {
                    RuleMark(y: .value("Target", target))
                        .foregroundStyle(Zen.inkSoft)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 160)
            .accessibilityLabel(tr("Workout calories per week", "Trainingskalorien pro Woche"))
            Text(tr("Dashed line: your weekly burn. Green weeks reached it.",
                    "Gestrichelt: dein Wochenziel. Grüne Wochen haben es erreicht."))
                .scaledFont(size: 12)
                .foregroundStyle(Zen.inkFaint)
        }
        .zenCard()
    }
}

struct FitnessBadgesCard: View {
    @Environment(FitnessStore.self) private var fitness

    var body: some View {
        let badges: [FitnessBadge] = fitness.report.badges
        let earned: Int = badges.filter(\.earned).count
        let columns: [GridItem] = [GridItem(.adaptive(minimum: 96), spacing: 12)]
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "rosette", title: tr("Badges", "Abzeichen")) {
                Text("\(earned)/\(badges.count)")
                    .scaledFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundStyle(Zen.inkSoft)
            }
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(badges) { badge in
                    VStack(spacing: 6) {
                        IconBadge(systemName: badge.earned ? badge.symbol : "lock.fill",
                                  tint: badge.earned ? Zen.kin : Zen.inkFaint, size: 52, filled: badge.earned)
                        Text(badge.title)
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(badge.earned ? Zen.ink : Zen.inkSoft)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        Text(badge.detail)
                            .scaledFont(size: 11)
                            .foregroundStyle(Zen.inkFaint)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(badge.title), \(badge.detail)")
                    .accessibilityValue(badge.earned ? tr("Earned", "Verdient") : tr("Not yet", "Noch nicht"))
                }
            }
        }
        .zenCard()
    }
}

struct FitnessWorkoutsCard: View {
    @Environment(FitnessStore.self) private var fitness
    let add: () -> Void

    var body: some View {
        let recent: [FitnessWorkout] = Array(fitness.workouts.prefix(12))
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "list.bullet", title: tr("Workouts", "Trainings")) {
                Button(tr("Add", "Eintragen"), action: add)
                    .scaledFont(size: 15, weight: .semibold)
            }
            if recent.isEmpty {
                Text(tr("Nothing yet. Connect your Garmin feed below or add a workout by hand.",
                        "Noch nichts. Verbinde unten deinen Garmin-Feed oder trag ein Training von Hand ein."))
                    .scaledFont(size: 14)
                    .foregroundStyle(Zen.inkSoft)
            }
            ForEach(recent) { workout in
                WorkoutRow(workout: workout)
                    .contextMenu {
                        Button(role: .destructive) {
                            fitness.remove(workout)
                        } label: {
                            Label(tr("Remove", "Entfernen"), systemImage: "trash")
                        }
                    }
            }
        }
        .zenCard()
    }
}

struct WorkoutRow: View {
    let workout: FitnessWorkout

    var body: some View {
        let day: Date = FitnessDate.date(workout.date) ?? Date()
        var detail: String = "\(FitnessFormat.shortDate(day)) · \(FitnessFormat.duration(workout.minutes))"
        if let km = workout.km, km > 0 {
            detail += " · " + km.formatted(.number.precision(.fractionLength(1)).locale(Loc.locale)) + " km"
        }
        return HStack(spacing: 12) {
            IconBadge(systemName: workout.kind.symbol, tint: workout.source == .garmin ? Zen.ai : Zen.shu, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.kind.title)
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(Zen.ink)
                Text(detail)
                    .scaledFont(size: 13)
                    .foregroundStyle(Zen.inkSoft)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(FitnessFormat.kcal(workout.calories))
                    .scaledFont(size: 14, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(Zen.ink)
                Text("+\(FitnessXP.workout(workout)) XP")
                    .scaledFont(size: 12, weight: .bold, design: .rounded)
                    .foregroundStyle(Zen.kin)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct FitnessFeedCard: View {
    @Environment(FitnessStore.self) private var fitness
    @State private var text = ""
    @State private var probing = false
    @State private var probe: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "applewatch.radiowaves.left.and.right", title: tr("Garmin feed", "Garmin-Feed"))
            Text(tr("Paste the address of your Garmin snapshot, for example the one your own website publishes. Ma reads workouts, steps and active calories from it every time you open the app.",
                    "Füge die Adresse deines Garmin-Schnappschusses ein, etwa den, den deine eigene Website veröffentlicht. Ma liest daraus Trainings, Schritte und aktive Kalorien, jedes Mal wenn du die App öffnest."))
                .scaledFont(size: 14)
                .foregroundStyle(Zen.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            TextField("https://…/api/public/garmin", text: $text)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .scaledFont(size: 15)
                .padding(12)
                .background(Zen.sand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onSubmit(save)
            HStack(spacing: 10) {
                Button(tr("Save and sync", "Sichern und laden"), action: save)
                    .buttonStyle(InkButtonStyle(kind: .shu, fullWidth: false))
                    .disabled(probing)
                if probing { ProgressView() }
            }
            if let probe {
                Text(probe)
                    .scaledFont(size: 13, weight: .medium)
                    .foregroundStyle(Zen.inkSoft)
            } else if let error = fitness.syncError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .scaledFont(size: 13, weight: .medium)
                    .foregroundStyle(Zen.negative)
            } else if let last = fitness.settings.lastSync {
                Label(tr("Synced \(last.formatted(.relative(presentation: .named).locale(Loc.locale)))",
                         "Geladen \(last.formatted(.relative(presentation: .named).locale(Loc.locale)))"),
                      systemImage: "checkmark.circle")
                    .scaledFont(size: 13, weight: .medium)
                    .foregroundStyle(Zen.matcha)
            }
            if let latest = fitness.latestDay {
                HStack(spacing: 12) {
                    StatTile(icon: "shoeprints.fill", value: FitnessFormat.number(latest.day.steps),
                             label: tr("Steps", "Schritte"), tint: Zen.matcha)
                    StatTile(icon: "flame", value: FitnessFormat.number(latest.day.activeCalories),
                             label: tr("Active kcal", "Aktive kcal"), tint: Zen.kin)
                    StatTile(icon: "heart.fill", value: FitnessFormat.number(latest.day.intensityMinutes),
                             label: tr("Intensity min", "Intensitätsmin."), tint: Zen.negative)
                }
            }
        }
        .zenCard()
        .onAppear { text = fitness.settings.feedURL }
    }

    private func save() {
        let value: String = text
        probing = true
        probe = nil
        Task {
            let result: Result<Int, FitnessStore.FeedError> = await FitnessStore.probe(value)
            switch result {
            case .success(let count):
                fitness.setFeedURL(value)
                await fitness.refresh(force: true)
                probe = tr("Connected: \(count) workouts in the feed.", "Verbunden: \(count) Trainings im Feed.")
                Haptics.success()
            case .failure(let error):
                probe = error.message
                Haptics.warning()
            }
            probing = false
        }
    }
}

struct FitnessHowCard: View {
    @Environment(FitnessStore.self) private var fitness

    var body: some View {
        let goal: FitnessGoal? = fitness.goal
        let extra: Double = FitnessMath.extraWeeklyKcal(kgPerWeek: goal?.kgPerWeek ?? 0.25)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "function", title: tr("How Ma calculates", "So rechnet Ma"))
            howLine("1", tr("A kilo of body fat holds about 7,700 kcal. Losing \(FitnessFormat.kg(goal?.kgPerWeek ?? 0.25)) a week without eating differently means burning \(FitnessFormat.kcal(extra)) more a week.",
                            "Ein Kilo Körperfett speichert etwa 7.700 kcal. \(FitnessFormat.kg(goal?.kgPerWeek ?? 0.25)) pro Woche ohne andere Ernährung heißt: \(FitnessFormat.kcal(extra)) mehr pro Woche verbrennen."))
            howLine("2", tr("On top of your usual week: \(FitnessFormat.kcal(goal?.baselineWeeklyKcal ?? 0)) of workouts, the average of the four weeks before your start. What you already did keeps your weight where it is.",
                            "Dazu kommt deine übliche Woche: \(FitnessFormat.kcal(goal?.baselineWeeklyKcal ?? 0)) Training, der Schnitt der vier Wochen vor dem Start. Was du schon gemacht hast, hält dein Gewicht, wo es ist."))
            howLine("3", tr("Minutes come from your own Garmin sessions once there are two of a kind, otherwise from textbook values for your weight.",
                            "Die Minuten kommen aus deinen eigenen Garmin-Einheiten, sobald es zwei derselben Art gibt, sonst aus Richtwerten für dein Gewicht."))
            howLine("4", tr("Food is not part of the plan yet. Changing it later makes the same goal much lighter.",
                            "Ernährung ist noch nicht Teil des Plans. Kommt sie später dazu, wird dasselbe Ziel deutlich leichter."))
        }
        .zenCard()
    }

    private func howLine(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .scaledFont(size: 12, weight: .bold, design: .rounded)
                .foregroundStyle(Zen.shu)
                .frame(width: 22, height: 22)
                .background(Zen.shu.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .scaledFont(size: 14)
                .foregroundStyle(Zen.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

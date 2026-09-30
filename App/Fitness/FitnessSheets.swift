import SwiftUI

// MARK: - Goal

/// Weight now, weight wanted, pace and favourite sports. Shows live what
/// the choice costs in minutes a week before anything is saved.
struct FitnessGoalSheet: View {
    var editing = false
    @Environment(FitnessStore.self) private var fitness
    @Environment(\.dismiss) private var dismiss
    @State private var currentKg: Double = 80
    @State private var goalKg: Double = 75
    @State private var heightCm: Double?
    @State private var pace: Double = 0.25
    @State private var favorites: Set<ActivityKind> = []
    @State private var baseline: Double = 0
    @State private var loaded = false
    @State private var confirmEnd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    weightCard
                    paceCard
                    favoritesCard
                    baselineCard
                    previewCard
                    Button(editing ? tr("Save", "Sichern") : tr("Start plan", "Plan starten"), action: save)
                        .buttonStyle(.primary)
                        .disabled(!valid)
                        .opacity(valid ? 1 : 0.5)
                    if editing {
                        Button {
                            confirmEnd = true
                        } label: {
                            Text(tr("End goal", "Ziel beenden"))
                                .foregroundStyle(Zen.negative)
                        }
                        .buttonStyle(.quiet)
                    }
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle(editing ? tr("Change goal", "Ziel ändern") : tr("Fitness goal", "Fitnessziel"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Abbrechen")) { dismiss() }
                }
            }
            .confirmationDialog(tr("End this goal?", "Dieses Ziel beenden?"), isPresented: $confirmEnd, titleVisibility: .visible) {
                Button(tr("End goal", "Ziel beenden"), role: .destructive) {
                    fitness.endGoal()
                    dismiss()
                }
            } message: {
                Text(tr("Workouts, weigh-ins and your level stay.", "Trainings, Gewichte und dein Level bleiben."))
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let goal = fitness.goal {
            currentKg = fitness.report.currentKg ?? goal.startKg
            goalKg = goal.goalKg
            heightCm = goal.heightCm
            pace = goal.kgPerWeek
            favorites = Set(goal.favorites)
            baseline = goal.baselineWeeklyKcal
        } else {
            currentKg = fitness.report.currentKg ?? 80
            goalKg = max(40, (currentKg - 5).rounded())
            baseline = fitness.currentBaseline.rounded()
            // Start from what the watch says you actually do.
            let counts: [ActivityKind: Int] = fitness.workouts.reduce(into: [:]) { $0[$1.kind, default: 0] += 1 }
            let top: [ActivityKind] = counts.sorted { $0.value > $1.value }.map(\.key)
                .filter { ActivityKind.plannable.contains($0) }
            favorites = Set(top.prefix(2))
            if favorites.isEmpty { favorites = [.walking, .cycling] }
        }
    }

    private var orderedFavorites: [ActivityKind] {
        ActivityKind.plannable.filter { favorites.contains($0) }
    }

    private var valid: Bool {
        currentKg >= 30 && currentKg <= 400 && goalKg >= 30 && goalKg < currentKg && !favorites.isEmpty
    }

    private func save() {
        guard valid else { return }
        if editing {
            fitness.updateGoal(goalKg: goalKg, heightCm: heightCm, kgPerWeek: pace,
                               favorites: orderedFavorites, baseline: baseline)
            if abs(currentKg - (fitness.report.currentKg ?? currentKg)) >= 0.05 {
                fitness.logWeight(currentKg)
            }
        } else {
            fitness.startGoal(currentKg: currentKg, goalKg: goalKg, heightCm: heightCm, kgPerWeek: pace,
                              favorites: orderedFavorites, baseline: baseline)
        }
        Haptics.success()
        dismiss()
    }

    // MARK: Cards

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            numberRow(tr("Weight today", "Gewicht heute"), value: $currentKg, unit: "kg")
            numberRow(tr("Goal weight", "Zielgewicht"), value: $goalKg, unit: "kg")
            optionalRow(tr("Height (optional)", "Größe (optional)"), value: $heightCm, unit: "cm")
            if let minimum = FitnessMath.healthyMinimumKg(heightCm: heightCm), goalKg < minimum {
                BalanceNote(icon: "exclamationmark.triangle",
                            text: tr("That goal is below a healthy weight for your height (about \(FitnessFormat.kg(minimum))). Please talk to a doctor first.",
                                     "Das Ziel liegt unter einem gesunden Gewicht für deine Größe (etwa \(FitnessFormat.kg(minimum))). Sprich bitte vorher mit einer Ärztin oder einem Arzt."))
            }
        }
        .zenCard()
    }

    private func numberRow(_ title: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(title)
                .scaledFont(size: 16, weight: .semibold)
                .foregroundStyle(Zen.ink)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .scaledFont(size: 17, weight: .semibold, design: .rounded)
                .frame(width: 90)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(Zen.sand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(unit)
                .scaledFont(size: 15)
                .foregroundStyle(Zen.inkSoft)
                .frame(width: 30, alignment: .leading)
        }
    }

    private func optionalRow(_ title: String, value: Binding<Double?>, unit: String) -> some View {
        HStack {
            Text(title)
                .scaledFont(size: 16, weight: .semibold)
                .foregroundStyle(Zen.ink)
            Spacer()
            TextField("–", value: value, format: .number.precision(.fractionLength(0)))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .scaledFont(size: 17, weight: .semibold, design: .rounded)
                .frame(width: 90)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(Zen.sand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(unit)
                .scaledFont(size: 15)
                .foregroundStyle(Zen.inkSoft)
                .frame(width: 30, alignment: .leading)
        }
    }

    private var paceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Pace", "Tempo"))
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Zen.inkSoft)
            HStack(spacing: 8) {
                ForEach(FitnessMath.paceChoices, id: \.self) { choice in
                    Chip(title: FitnessFormat.kg(choice), selected: abs(pace - choice) < 0.001) { pace = choice }
                }
            }
            Stepper(value: $pace, in: FitnessMath.paceRange, step: 0.05) {
                Text(tr("\(FitnessFormat.kg(pace)) a week", "\(FitnessFormat.kg(pace)) pro Woche"))
                    .scaledFont(size: 16, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(Zen.ink)
            }
            Text(tr("0.25 kg is gentle and easy to keep up. Without changing food, every extra 0.25 kg a week costs about 1,925 kcal of sport.",
                    "0,25 kg ist sanft und gut durchzuhalten. Ohne andere Ernährung kostet jede weiteren 0,25 kg pro Woche etwa 1.925 kcal Sport."))
                .scaledFont(size: 13)
                .foregroundStyle(Zen.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .zenCard()
    }

    private var favoritesCard: some View {
        let columns: [GridItem] = [GridItem(.adaptive(minimum: 100), spacing: 10)]
        return VStack(alignment: .leading, spacing: 12) {
            Text(tr("What you like to do", "Was du gern machst"))
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Zen.inkSoft)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ActivityKind.plannable) { kind in
                    let on: Bool = favorites.contains(kind)
                    Button {
                        Haptics.tap()
                        if on { favorites.remove(kind) } else { favorites.insert(kind) }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 22, weight: .semibold))
                            Text(kind.title)
                                .scaledFont(size: 13, weight: .semibold)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if fitness.hasOwnRate(kind) {
                                Text(tr("your data", "deine Daten"))
                                    .scaledFont(size: 10, weight: .bold)
                                    .foregroundStyle(on ? Color.white.opacity(0.85) : Zen.ai)
                            }
                        }
                        .foregroundStyle(on ? Color.white : Zen.ink)
                        .frame(maxWidth: .infinity, minHeight: 78)
                        .background(on ? AnyShapeStyle(Zen.shu) : AnyShapeStyle(Zen.sand),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text(tr("The weekly plan takes these in turn.", "Der Wochenplan wechselt zwischen diesen ab."))
                .scaledFont(size: 13)
                .foregroundStyle(Zen.inkSoft)
        }
        .zenCard()
    }

    private var baselineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Your usual week", "Deine übliche Woche"))
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Zen.inkSoft)
            Stepper(value: $baseline, in: 0...10_000, step: 100) {
                Text(tr("\(FitnessFormat.kcal(baseline)) of workouts", "\(FitnessFormat.kcal(baseline)) Training"))
                    .scaledFont(size: 16, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(Zen.ink)
            }
            Text(tr("What a normal week burned before this plan, taken from the last four weeks of your feed. If your weight was steady, this is what keeps it steady; the plan adds the extra on top.",
                    "Was eine normale Woche vor dem Plan verbrannt hat, aus den letzten vier Wochen deines Feeds. War dein Gewicht stabil, hält genau das es stabil; der Plan legt das Extra obendrauf."))
                .scaledFont(size: 13)
                .foregroundStyle(Zen.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .zenCard()
    }

    private var previewCard: some View {
        let extra: Double = FitnessMath.extraWeeklyKcal(kgPerWeek: pace)
        let target: Double = baseline + extra
        let kinds: [ActivityKind] = orderedFavorites
        let minutes: Int = FitnessPlanner.weeklyMinutes(targetKcal: target, favorites: kinds, rate: fitness.rate)
        let extraMinutes: Int = FitnessPlanner.weeklyMinutes(targetKcal: extra, favorites: kinds, rate: fitness.rate)
        let weeks: Double = FitnessMath.weeksToGoal(kgLeft: currentKg - goalKg, kgPerWeek: pace)
        let eta: Date = Calendar.current.date(byAdding: .day, value: Int((weeks * 7).rounded(.up)), to: Date()) ?? Date()
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "sparkles", title: tr("Your plan", "Dein Plan"))
            HStack(spacing: 12) {
                StatTile(icon: "flame.fill", value: FitnessFormat.number(Int(target.rounded())),
                         label: tr("kcal a week", "kcal pro Woche"), tint: Zen.kin)
                StatTile(icon: "timer", value: FitnessFormat.duration(minutes),
                         label: tr("Sport a week", "Sport pro Woche"), tint: Zen.ai)
                StatTile(icon: "flag.checkered", value: valid ? FitnessFormat.shortDate(eta) : "–",
                         label: valid ? FitnessFormat.monthYear(eta) : tr("Goal date", "Zieldatum"), tint: Zen.matcha)
            }
            Text(tr("That is \(FitnessFormat.duration(extraMinutes)) more than your usual week, spread over the days you choose.",
                    "Das sind \(FitnessFormat.duration(extraMinutes)) mehr als deine übliche Woche, verteilt auf die Tage, die du wählst."))
                .scaledFont(size: 14)
                .foregroundStyle(Zen.ink)
                .fixedSize(horizontal: false, vertical: true)
            if minutes > 600 {
                BalanceNote(icon: "exclamationmark.triangle",
                            text: tr("More than ten hours a week is a lot to keep up. A slower pace is kinder, and adding food to the plan later makes it much lighter.",
                                     "Mehr als zehn Stunden pro Woche sind viel zum Durchhalten. Ein langsameres Tempo ist freundlicher, und Ernährung im Plan macht es später deutlich leichter."))
            }
        }
        .zenCard()
    }
}

// MARK: - Weight

struct WeightSheet: View {
    @Environment(FitnessStore.self) private var fitness
    @Environment(\.dismiss) private var dismiss
    @State private var kg: Double = 80
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 14) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            TextField("0", value: $kg, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .frame(maxWidth: 180)
                            Text("kg")
                                .scaledFont(size: 20, weight: .semibold)
                                .foregroundStyle(Zen.inkSoft)
                        }
                        HStack(spacing: 10) {
                            nudge(-0.1, "minus")
                            nudge(0.1, "plus")
                        }
                        DatePicker(tr("Day", "Tag"), selection: $date, in: ...Date(), displayedComponents: .date)
                            .scaledFont(size: 15)
                    }
                    .frame(maxWidth: .infinity)
                    .zenCard()

                    Button(tr("Save", "Sichern")) {
                        fitness.logWeight(kg, on: date)
                        Haptics.success()
                        dismiss()
                    }
                    .buttonStyle(.primary)
                    .disabled(kg < 25 || kg > 400)

                    let recent: [WeightEntry] = Array(fitness.weights.suffix(5).reversed())
                    if !recent.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(recent) { entry in
                                HStack {
                                    Text(FitnessFormat.shortDate(FitnessDate.date(entry.date) ?? Date()))
                                        .scaledFont(size: 15)
                                        .foregroundStyle(Zen.inkSoft)
                                    Spacer()
                                    Text(FitnessFormat.kg(entry.kg))
                                        .scaledFont(size: 15, weight: .semibold, design: .rounded)
                                        .foregroundStyle(Zen.ink)
                                    Button {
                                        fitness.removeWeight(entry)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(Zen.inkFaint)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(tr("Delete", "Löschen"))
                                }
                            }
                        }
                        .zenCard()
                    }
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.vertical, 12)
            }
            .background(AppBackground())
            .navigationTitle(tr("Log weight", "Gewicht eintragen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Abbrechen")) { dismiss() }
                }
            }
        }
        .onAppear {
            kg = fitness.weights.last?.kg ?? fitness.goal?.startKg ?? 80
        }
    }

    private func nudge(_ step: Double, _ symbol: String) -> some View {
        Button {
            Haptics.tap()
            kg = ((kg + step) * 10).rounded() / 10
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 52, height: 40)
                .background(Zen.sand, in: Capsule())
                .foregroundStyle(Zen.ink)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(step > 0 ? tr("Plus 100 grams", "Plus 100 Gramm") : tr("Minus 100 grams", "Minus 100 Gramm"))
    }
}

// MARK: - Manual workout

struct ManualWorkoutSheet: View {
    @Environment(FitnessStore.self) private var fitness
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ActivityKind = .walking
    @State private var minutes = 30
    @State private var calories: Int?
    @State private var km: Double?
    @State private var date = Date()

    var body: some View {
        let estimate: Int = Int((Double(minutes) * fitness.rate(kind)).rounded())
        let kcal: Int = calories ?? estimate
        let preview = FitnessWorkout(id: "preview", kind: kind, name: kind.title, date: "", minutes: minutes,
                                     km: km, calories: kcal, averageHeartRate: nil, source: .manual)
        let columns: [GridItem] = [GridItem(.adaptive(minimum: 76), spacing: 10)]
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(ActivityKind.allCases) { option in
                            let on: Bool = option == kind
                            Button {
                                Haptics.tap()
                                kind = option
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: option.symbol)
                                        .font(.system(size: 20, weight: .semibold))
                                    Text(option.title)
                                        .scaledFont(size: 11, weight: .semibold)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .foregroundStyle(on ? Color.white : Zen.ink)
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .background(on ? AnyShapeStyle(Zen.shu) : AnyShapeStyle(Zen.sand),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .zenCard()

                    VStack(alignment: .leading, spacing: 14) {
                        Stepper(value: $minutes, in: 5...600, step: 5) {
                            Text(FitnessFormat.duration(minutes))
                                .scaledFont(size: 17, weight: .semibold)
                                .monospacedDigit()
                                .foregroundStyle(Zen.ink)
                        }
                        HStack {
                            Text(tr("Calories", "Kalorien"))
                                .scaledFont(size: 15, weight: .semibold)
                                .foregroundStyle(Zen.ink)
                            Spacer()
                            TextField(tr("about \(estimate)", "etwa \(estimate)"), value: $calories, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                                .padding(8)
                                .background(Zen.sand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        HStack {
                            Text(tr("Distance (km)", "Strecke (km)"))
                                .scaledFont(size: 15, weight: .semibold)
                                .foregroundStyle(Zen.ink)
                            Spacer()
                            TextField(tr("optional", "optional"), value: $km, format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                                .padding(8)
                                .background(Zen.sand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        DatePicker(tr("Day", "Tag"), selection: $date, in: ...Date(), displayedComponents: .date)
                    }
                    .scaledFont(size: 15)
                    .zenCard()

                    Text(tr("\(FitnessFormat.kcal(kcal)) · +\(FitnessXP.workout(preview)) XP",
                            "\(FitnessFormat.kcal(kcal)) · +\(FitnessXP.workout(preview)) XP"))
                        .scaledFont(size: 15, weight: .semibold, design: .rounded)
                        .foregroundStyle(Zen.kin)
                        .frame(maxWidth: .infinity)

                    Button(tr("Add workout", "Training eintragen")) {
                        fitness.addManual(kind: kind, minutes: minutes, calories: calories, km: km, date: date)
                        Haptics.success()
                        dismiss()
                    }
                    .buttonStyle(.primary)
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle(tr("Add workout", "Training eintragen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Abbrechen")) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Level up

struct LevelUpView: View {
    let celebration: FitnessCelebration
    let done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let progress = FitnessXP.Progress(level: celebration.level, into: 1, span: 1)
        return ZStack {
            AppBackground()
            VStack(spacing: 22) {
                Spacer(minLength: 20)
                ZStack {
                    Circle()
                        .fill(Zen.kin.opacity(0.16))
                        .frame(width: 230, height: 230)
                        .scaleEffect(shown ? 1 : 0.6)
                        .blur(radius: 12)
                    LevelRing(progress: progress, size: 170)
                        .scaleEffect(shown ? 1 : 0.7)
                        .opacity(shown ? 1 : 0)
                }
                .dynamicTypeSize(...denseTypeLimit)
                VStack(spacing: 8) {
                    Text(headline)
                        .displayFont(30)
                        .foregroundStyle(Zen.ink)
                        .multilineTextAlignment(.center)
                    Text(FitnessXP.title(celebration.level))
                        .scaledFont(size: 17, weight: .semibold, design: .rounded)
                        .foregroundStyle(Zen.kin)
                    Text(subline)
                        .scaledFont(size: 15)
                        .foregroundStyle(Zen.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)

                if CompanionID.hasChosen {
                    companionLine
                }

                if !celebration.badges.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(celebration.badges.count == 1 ? tr("New badge", "Neues Abzeichen") : tr("New badges", "Neue Abzeichen"))
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(Zen.inkSoft)
                        ForEach(celebration.badges.prefix(4)) { badge in
                            HStack(spacing: 12) {
                                IconBadge(systemName: badge.symbol, tint: Zen.kin, size: 40, filled: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(badge.title)
                                        .scaledFont(size: 16, weight: .semibold)
                                        .foregroundStyle(Zen.ink)
                                    Text(badge.detail)
                                        .scaledFont(size: 13)
                                        .foregroundStyle(Zen.inkSoft)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .zenCard()
                    .padding(.horizontal, Zen.gutter)
                }
                Spacer(minLength: 10)
                Button(tr("Keep going", "Weiter so"), action: done)
                    .buttonStyle(.primary)
                    .padding(.horizontal, Zen.gutter)
                    .padding(.bottom, 20)
            }
        }
        .onAppear {
            Haptics.success()
            if reduceMotion {
                shown = true
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { shown = true }
            }
        }
    }

    private var companionLine: some View {
        let who: CompanionID = CompanionID.current
        let text: String = who == .nyx
            ? tr("Told you. Level \(celebration.level) suits you.", "Hab ich doch gesagt. Level \(celebration.level) steht dir.")
            : tr("[Level Up] Level \(celebration.level). Keep hunting.", "[Level Up] Level \(celebration.level). Weiter jagen.")
        return HStack(alignment: .center, spacing: 12) {
            CompanionAvatar(companion: who, mood: .proud, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(who.name.uppercased())
                    .scaledFont(size: 11, weight: .heavy, design: .rounded)
                    .tracking(1.5)
                    .foregroundStyle(Zen.ai)
                Text(text)
                    .scaledFont(size: 15, weight: .medium)
                    .foregroundStyle(Zen.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(CompanionStyle.window.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(CompanionStyle.glow(0.6), lineWidth: 1))
        .padding(.horizontal, Zen.gutter)
    }

    private var headline: String {
        if celebration.first { return tr("You start at level \(celebration.level)", "Du startest auf Level \(celebration.level)") }
        if celebration.levelUp { return tr("Level \(celebration.level)", "Level \(celebration.level)") }
        return tr("Well earned", "Verdient")
    }

    private var subline: String {
        if celebration.first {
            return tr("The workouts your watch already recorded count. Every new one takes you further.",
                      "Die Trainings, die deine Uhr schon aufgezeichnet hat, zählen mit. Jedes neue bringt dich weiter.")
        }
        if celebration.levelUp {
            return tr("Another level, earned by showing up. Keep the pace that feels right.",
                      "Wieder ein Level, verdient durchs Dranbleiben. Bleib bei dem Tempo, das sich gut anfühlt.")
        }
        return tr("A new badge for your collection.", "Ein neues Abzeichen für deine Sammlung.")
    }
}

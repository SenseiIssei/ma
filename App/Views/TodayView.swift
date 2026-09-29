import FamilyControls
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(DayStore.self) private var day
    @State private var showSettings = false
    @State private var lesson: QuizSession?
    @State private var journal: JournalSheet?
    @State private var breathing = false
    @State private var newHabit: Habit?
    @State private var askLockdown = false
    @State private var askEndLockdown = false
    @State private var showWeekReview = false

    enum JournalSheet: String, Identifiable {
        case morning, evening
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            // Ticks once a minute so the greeting, the illustration and the
            // check-in invitation follow the clock while the screen is open.
            TimelineView(.everyMinute) { context in
                content(now: context.date)
            }
            .background(AppBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Zen.ink)
                    }
                    .accessibilityLabel(tr("Settings", "Einstellungen"))
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(item: $journal) { sheet in
                switch sheet {
                case .morning: MorningCheckInView().environment(day)
                case .evening: EveningReflectionView().environment(day)
                }
            }
            .sheet(item: $newHabit) { habit in
                HabitEditor(habit: habit).environment(day)
            }
            .sheet(isPresented: $showWeekReview) {
                WeekReviewView()
                    .environment(model)
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(item: $lesson) { session in
                LessonScreen(session: session) { lesson = nil }
            }
            .fullScreenCover(isPresented: $breathing) {
                BreathingView().environment(day)
            }
            .confirmationDialog(tr("Lock everything", "Alles sperren"), isPresented: $askLockdown, titleVisibility: .visible) {
                ForEach([30, 60, 120], id: \.self) { minutes in
                    Button(Self.durationText(minutes)) {
                        Haptics.success()
                        model.startLockdown(minutes: minutes)
                    }
                }
                Button(tr("Cancel", "Abbrechen"), role: .cancel) {}
            } message: {
                Text(tr("Every app in your boundaries closes right away, whatever the time window says.", "Alle Apps aus deinen Grenzen sind sofort zu, egal was das Zeitfenster sagt."))
            }
            .confirmationDialog(tr("End the lockdown?", "Sperre beenden?"), isPresented: $askEndLockdown, titleVisibility: .visible) {
                Button(tr("Answer questions", "Fragen beantworten")) {
                    model.endLockdown()
                }
                Button(tr("Keep it", "Weiter sperren"), role: .cancel) {}
            } message: {
                Text(tr("Ending early takes five right answers.", "Früher beenden kostet fünf richtige Antworten."))
            }
        }
    }

    private func content(now: Date) -> some View {
        let phase = DayPhase.now(now)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(phase: phase, now: now)
                hero(phase: phase)
                checkIn(phase: phase)
                intention(phase: phase)
                dayScore
                stats
                habits
                actions(now: now)
                if !model.grants.isEmpty { openNow }
                boundaries
                week(now: now)
                weekReviewEntry
            }
            .padding(.horizontal, Zen.gutter)
            .padding(.bottom, 40)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: day.habits)
        }
    }

    // MARK: Header

    private func header(phase: DayPhase, now: Date) -> some View {
        let date = now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Loc.locale))
        return VStack(alignment: .leading, spacing: 4) {
            Text(date.uppercased(with: Loc.locale))
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Zen.inkSoft)
            Text(phase.greeting)
                .font(.display(34))
                .foregroundStyle(Zen.ink)
        }
        .padding(.top, 4)
    }

    private func hero(phase: DayPhase) -> some View {
        let streak = model.decks.currentStreak
        return Illustration(name: phase.illustration, height: 170)
            .overlay(alignment: .bottomLeading) {
                if streak > 0 {
                    Label(tr("\(streak) \(streak == 1 ? "day" : "days") learning", "\(streak) \(streak == 1 ? "Tag" : "Tage") am Lernen"), systemImage: "flame.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Zen.ink)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(12)
                }
            }
    }

    // MARK: Morning and evening

    @ViewBuilder
    private func checkIn(phase: DayPhase) -> some View {
        if phase == .morning && day.today.morning == nil {
            invite(icon: "sun.horizon.fill", tint: Zen.kin,
                   title: tr("Start your day", "Starte in den Tag"),
                   text: tr("How do you feel, and what matters today?", "Wie geht es dir, und was zählt heute?"),
                   button: tr("Check in", "Einchecken")) { journal = .morning }
        } else if phase == .evening && day.today.evening == nil {
            invite(icon: "moon.stars.fill", tint: Zen.shu,
                   title: tr("Close the day", "Schließ den Tag ab"),
                   text: tr("Three short questions before you rest.", "Drei kurze Fragen, bevor du zur Ruhe kommst."),
                   button: tr("Reflect", "Zurückblicken")) { journal = .evening }
        }
    }

    private func invite(icon: String, tint: Color, title: String, text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(systemName: icon, tint: tint, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.display(20))
                        .foregroundStyle(Zen.ink)
                    Text(text)
                        .font(.system(size: 15))
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(button) {
                Haptics.tap()
                action()
            }
            .buttonStyle(.primary)
        }
        .zenCard(padding: 20)
    }

    @ViewBuilder
    private func intention(phase: DayPhase) -> some View {
        let entry = day.today
        if let morning = entry.morning {
            Button {
                journal = .morning
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    MoodFace(mood: morning.mood, size: 46)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Today's intention", "Vorsatz für heute"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Zen.inkSoft)
                        Text(day.intention ?? tr("No intention, just being here.", "Kein Vorsatz, einfach da sein."))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(day.intention == nil ? Zen.inkSoft : Zen.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Zen.inkFaint)
                }
                .zenCard()
            }
            .buttonStyle(.plain)
        } else if phase != .morning {
            compactRow(icon: "scope", tint: Zen.shu, title: tr("Set an intention for today", "Setz dir einen Vorsatz für heute")) {
                journal = .morning
            }
        }
        if entry.evening != nil {
            compactRow(icon: "checkmark.seal.fill", tint: Zen.matcha, title: tr("Day reflected. Rest well.", "Tag reflektiert. Ruh dich gut aus.")) {
                journal = .evening
            }
        }
    }

    private func compactRow(icon: String, tint: Color, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBadge(systemName: icon, tint: tint, size: 34)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Zen.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Zen.inkFaint)
            }
            .zenCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: Day score

    private var focusGoal: Int {
        max(1, model.focusSettings.focusMinutes * max(1, model.focusSettings.roundsUntilLongBreak))
    }

    private var learnGoal: Int { max(1, model.decks.profile.dailyGoal) }

    private var dayScore: some View {
        let focus: Double = Double(model.today.focusMinutes) / Double(focusGoal)
        let learn: Double = Double(model.today.correct) / Double(learnGoal)
        let habitsOn = !day.habits.isEmpty
        let habitShare: Double = day.habitProgress
        let parts: [Double] = habitsOn ? [focus, learn, habitShare] : [focus, learn]
        let score: Double = parts.map { min(1, $0) }.reduce(0, +) / Double(parts.count)
        let percent = Int((score * 100).rounded())
        let habitValue = habitsOn ? "\(day.habitsDoneToday) / \(day.habits.count)" : tr("none yet", "noch keine")

        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "circle.circle", title: tr("Your day", "Dein Tag")) {
                Text(tr("\(percent)%", "\(percent) %"))
                    .font(.display(17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Zen.shu)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 22) {
                ZStack {
                    ProgressRing(progress: focus, lineWidth: 12, tint: Zen.shu)
                        .frame(width: 140, height: 140)
                    ProgressRing(progress: learn, lineWidth: 12, tint: Zen.ai)
                        .frame(width: 108, height: 108)
                    ProgressRing(progress: habitShare, lineWidth: 12, tint: Zen.matcha)
                        .frame(width: 76, height: 76)
                }
                .animation(.spring(response: 0.8, dampingFraction: 0.85), value: score)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 14) {
                    ringLegend(tint: Zen.shu, title: tr("Focus", "Fokus"),
                               value: tr("\(model.today.focusMinutes) of \(focusGoal) min", "\(model.today.focusMinutes) von \(focusGoal) Min."))
                    ringLegend(tint: Zen.ai, title: tr("Learning", "Lernen"),
                               value: tr("\(model.today.correct) of \(learnGoal) right", "\(model.today.correct) von \(learnGoal) richtig"))
                    ringLegend(tint: Zen.matcha, title: tr("Habits", "Gewohnheiten"), value: habitValue)
                }
                Spacer(minLength: 0)
            }
            .zenCard(padding: 20)
        }
    }

    private func ringLegend(tint: Color, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(tint).frame(width: 10, height: 10).padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Zen.inkSoft)
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Zen.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Stats

    private var stats: some View {
        let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
            StatTile(icon: "hand.raised.fill", value: "\(model.today.resisted)", label: tr("resisted", "widerstanden"), tint: Zen.matcha)
            StatTile(icon: "checkmark.bubble.fill", value: "\(model.today.correct)", label: tr("answers right", "Fragen richtig"), tint: Zen.ai)
            StatTile(icon: "timer", value: "\(model.today.focusMinutes)", label: tr("min. focus", "Min. Fokus"), tint: Zen.shu)
            StatTile(icon: "shield.lefthalf.filled", value: "\(model.today.shieldsSeen)", label: tr("stopped", "aufgehalten"), tint: Zen.kin)
        }
        .zenCard(padding: 20)
    }

    // MARK: Habits

    @ViewBuilder
    private var habits: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "checklist", title: tr("Habits", "Gewohnheiten")) {
                if !day.habits.isEmpty {
                    NavigationLink {
                        HabitsView()
                    } label: {
                        Text(tr("Edit", "Bearbeiten"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Zen.shu)
                    }
                }
            }
            if day.habits.isEmpty {
                if day.habitsOffered {
                    compactRow(icon: "plus", tint: Zen.shu, title: tr("Add a small daily habit", "Eine kleine tägliche Gewohnheit anlegen")) {
                        newHabit = Habit(title: "", symbol: Habit.symbols[4])
                    }
                } else {
                    HabitStarterCard {
                        newHabit = Habit(title: "", symbol: Habit.symbols[4])
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(day.habits.enumerated()), id: \.element.id) { index, habit in
                        if index > 0 {
                            Divider().overlay(Zen.line).padding(.leading, 60)
                        }
                        HabitRow(habit: habit)
                            .padding(.vertical, 10)
                    }
                }
                .zenCard(padding: 16)
            }
        }
    }

    // MARK: Actions

    private func actions(now: Date) -> some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let lockedUntil: Date? = model.lockdownUntil.flatMap { $0 > now ? $0 : nil }
        let focusText = model.focus == nil
            ? tr("\(model.focusSettings.focusMinutes) minutes", "\(model.focusSettings.focusMinutes) Minuten")
            : tr("running", "läuft")
        let breathText = day.breathSessionsToday > 0
            ? tr("\(day.breathSessionsToday) today", "\(day.breathSessionsToday) heute")
            : tr("1 to 5 minutes", "1 bis 5 Minuten")
        let lockText = lockedUntil.map {
            tr("Locked until \($0.formatted(date: .omitted, time: .shortened))", "Gesperrt bis \($0.formatted(date: .omitted, time: .shortened))")
        } ?? tr("Everything, now", "Alles, sofort")

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "bolt.fill", title: tr("Now", "Jetzt"))
            LazyVGrid(columns: columns, spacing: 12) {
                ActionTile(icon: "timer", title: tr("Focus", "Fokus"), subtitle: focusText, tint: Zen.shu) {
                    if model.focus == nil { model.startFocus() }
                    model.tab = .focus
                }
                ActionTile(icon: "graduationcap.fill", title: tr("Lesson", "Lektion"), subtitle: tr("8 exercises", "8 Übungen"), tint: Zen.ai) {
                    lesson = QuizSession(mode: .lesson(count: 8), store: model.decks)
                }
                ActionTile(icon: "wind", title: tr("Breathe", "Atmen"), subtitle: breathText, tint: Zen.matcha) {
                    breathing = true
                }
                ActionTile(icon: lockedUntil == nil ? "lock.shield.fill" : "lock.fill",
                           title: tr("Lock all", "Alles zu"), subtitle: lockText,
                           tint: lockedUntil == nil ? Zen.kin : Zen.negative) {
                    if lockedUntil == nil { askLockdown = true } else { askEndLockdown = true }
                }
            }
        }
    }

    private static func durationText(_ minutes: Int) -> String {
        if minutes < 60 { return tr("\(minutes) minutes", "\(minutes) Minuten") }
        let hours = minutes / 60
        return hours == 1 ? tr("1 hour", "1 Stunde") : tr("\(hours) hours", "\(hours) Stunden")
    }

    // MARK: Open unlocks

    private var openNow: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "lock.open.fill", title: tr("Open right now", "Gerade offen"))
            VStack(spacing: 0) {
                ForEach(Array(model.grants.enumerated()), id: \.element.id) { index, grant in
                    if index > 0 {
                        Divider().overlay(Zen.line).padding(.leading, 52)
                    }
                    GrantRow(grant: grant) { model.revoke(grant) }
                        .padding(.vertical, 10)
                }
            }
            .zenCard(padding: 16)
        }
    }

    // MARK: Boundaries

    private var boundaries: some View {
        let active = model.rules.filter { model.isShielding($0) }
        let approved = model.authorization == .approved
        let title: String
        let detail: String
        if !approved {
            title = tr("Screen Time not allowed", "Bildschirmzeit nicht erlaubt")
            detail = BuildFlavor.screenTimeAvailable
                ? tr("Without this permission Ma cannot block anything.", "Ohne diese Erlaubnis kann Ma nichts sperren.")
                : BuildFlavor.previewNote
        } else if model.rules.isEmpty {
            title = tr("No boundary yet", "Noch keine Grenze")
            detail = tr("Under Boundaries, choose what pulls at you too often.", "Leg unter Grenzen fest, was dich zu oft zieht.")
        } else {
            title = tr("\(active.count) of \(model.rules.count) on watch", "\(active.count) von \(model.rules.count) wachen gerade")
            detail = active.isEmpty ? tr("Everything is open right now.", "Gerade ist alles offen.") : active.map(\.name).joined(separator: ", ")
        }
        let tint: Color = approved ? (active.isEmpty ? Zen.inkSoft : Zen.shu) : Zen.negative

        return Button {
            model.tab = .rules
        } label: {
            HStack(alignment: .center, spacing: 14) {
                IconBadge(systemName: approved ? "shield.lefthalf.filled" : "exclamationmark.shield.fill", tint: tint, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(approved ? Zen.ink : Zen.negative)
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(Zen.inkSoft)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Zen.inkFaint)
            }
            .zenCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: Week

    private func week(now: Date) -> some View {
        let values: [Int] = model.week.map { $0.resisted + $0.correct }
        let peak: Int = max(1, values.max() ?? 1)
        let moods: [Mood?] = day.weekMoods
        let count = values.count

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "chart.bar.fill", title: tr("This week", "Diese Woche"))
            VStack(spacing: 12) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(0..<count, id: \.self) { index in
                        let isToday = index == count - 1
                        let height: CGFloat = max(6, 84 * CGFloat(values[index]) / CGFloat(peak))
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isToday ? AnyShapeStyle(Zen.accentGradient) : AnyShapeStyle(Zen.shu.opacity(0.28)))
                            .frame(height: height)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 84, alignment: .bottom)
                HStack(spacing: 10) {
                    ForEach(0..<count, id: \.self) { index in
                        let slot = moods.count - count + index
                        let mood: Mood? = moods.indices.contains(slot) ? moods[slot] : nil
                        VStack(spacing: 6) {
                            moodDot(mood)
                            Text(weekdayLetter(daysBefore: count - 1 - index, now: now))
                                .font(.system(size: 11, weight: index == count - 1 ? .bold : .medium))
                                .foregroundStyle(index == count - 1 ? Zen.ink : Zen.inkSoft)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .zenCard(padding: 20)
            .animation(.spring(response: 0.6, dampingFraction: 0.85), value: values)
            Text(tr("Bars: impulses resisted plus right answers. Dots: your morning mood.", "Balken: widerstandene Impulse plus richtige Antworten. Punkte: deine Stimmung am Morgen."))
                .font(.system(size: 12))
                .foregroundStyle(Zen.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Door to the weekly review. The teaser number is this week's resisted
    /// impulses, the one count that is always worth seeing grow.
    private var weekReviewEntry: some View {
        let resisted: Int = model.week.reduce(0) { $0 + $1.resisted }
        let impulses: String = WeekSummary.count(resisted, "impulse", "impulses", "Impuls", "Impulse")
        let detail: String = resisted > 0
            ? tr("\(impulses) resisted so far. Screen time, focus and how it compares with last week.",
                 "\(impulses) bisher widerstanden. Bildschirmzeit, Fokus und der Vergleich zur Vorwoche.")
            : tr("Screen time, focus and how it compares with last week.",
                 "Bildschirmzeit, Fokus und der Vergleich zur Vorwoche.")

        return Button {
            Haptics.tap()
            showWeekReview = true
        } label: {
            HStack(alignment: .center, spacing: 14) {
                IconBadge(systemName: "calendar.badge.clock", tint: Zen.shu, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Your week", "Deine Woche"))
                        .font(.display(19, weight: .semibold))
                        .foregroundStyle(Zen.ink)
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(Zen.inkSoft)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Zen.inkFaint)
            }
            .zenCard(padding: 18)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func moodDot(_ mood: Mood?) -> some View {
        if let mood {
            Circle()
                .fill(mood.tint)
                .frame(width: 10, height: 10)
                .accessibilityLabel(mood.title)
        } else {
            Circle()
                .strokeBorder(Zen.inkFaint.opacity(0.6), lineWidth: 1.5)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
        }
    }

    private func weekdayLetter(daysBefore offset: Int, now: Date) -> String {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
        return RuleSchedule.dayName(calendar.component(.weekday, from: date))
    }
}

// MARK: - Components

struct ActionTile: View {
    let icon: String
    let title: String
    let subtitle: String
    var tint: Color = Zen.shu
    let action: () -> Void

    init(icon: String, title: String, subtitle: String, tint: Color = Zen.shu, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.action = action
    }

    /// Old signature. The kanji is ignored.
    init(kanji: String, title: String, subtitle: String, action: @escaping () -> Void) {
        self.init(icon: "sparkles", title: title, subtitle: subtitle, action: action)
    }

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                IconBadge(systemName: icon, tint: tint, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.display(18, weight: .semibold))
                        .foregroundStyle(Zen.ink)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Zen.inkSoft)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .zenCard(padding: 16)
        }
        .buttonStyle(ActionTilePress())
    }
}

private struct ActionTilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GrantRow: View {
    let grant: UnlockGrant
    let revoke: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let token = grant.applications.first {
                    Label(token).labelStyle(.iconOnly)
                } else if let web = grant.webDomains.first {
                    Label(web).labelStyle(.iconOnly)
                } else {
                    Image(systemName: "square.grid.2x2.fill").foregroundStyle(Zen.inkSoft)
                }
            }
            .frame(width: 36, height: 36)
            .background(Zen.sand, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                if let token = grant.applications.first {
                    Label(token).labelStyle(.titleOnly)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Zen.ink)
                } else {
                    Text(tr("Unlock", "Freigabe"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Zen.ink)
                }
                Text(tr("open until \(grant.expiresAt.formatted(date: .omitted, time: .shortened))", "offen bis \(grant.expiresAt.formatted(date: .omitted, time: .shortened))"))
                    .font(.system(size: 13))
                    .foregroundStyle(Zen.inkSoft)
            }
            Spacer()
            Button {
                Haptics.tap()
                revoke()
            } label: {
                Label(tr("Lock", "Sperren"), systemImage: "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Zen.shu)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .background(Zen.shu.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Step numbers in setup guides. Once kanji numerals, now plain digits; the
/// name stays so the guides keep compiling.
enum KanjiDate {
    static func number(_ n: Int) -> String { "\(n)" }
}

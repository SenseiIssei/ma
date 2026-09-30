import SwiftUI

// MARK: - Row

/// One habit for today. The whole row is the button: a tap checks it off or
/// counts one up, a long press offers one less.
struct HabitRow: View {
    @Environment(DayStore.self) private var day
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let habit: Habit

    var body: some View {
        let key = day.todayKey
        let done = habit.isDone(on: key)
        let streak = habit.streak()
        let tapAnimation: Animation = reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.75)
        Button {
            let wasDone = done
            withAnimation(tapAnimation) { day.tap(habit) }
            let nowDone = day.habits.first(where: { $0.id == habit.id })?.isDone(on: key) ?? false
            if nowDone && !wasDone { Haptics.success() } else { Haptics.tap() }
        } label: {
            HStack(spacing: 14) {
                HabitMark(habit: habit, key: key)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.title)
                        .scaledFont(size: 17, weight: .semibold)
                        .foregroundStyle(Zen.ink)
                        .strikethrough(done && !habit.isCounter, color: Zen.inkFaint)
                    detail(key: key, streak: streak)
                }
                Spacer(minLength: 8)
                trailing(done: done, key: key)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if habit.count(on: key) > 0 {
                Button {
                    withAnimation { day.decrement(habit) }
                } label: {
                    Label(tr("One less", "Einmal weniger"), systemImage: "minus.circle")
                }
            }
        }
        .accessibilityValue(habit.isCounter
            ? tr("\(habit.count(on: key)) of \(habit.target)", "\(habit.count(on: key)) von \(habit.target)")
            : (done ? tr("done", "erledigt") : tr("open", "offen")))
    }

    @ViewBuilder
    private func detail(key: String, streak: Int) -> some View {
        HStack(spacing: 10) {
            if habit.isCounter {
                Text(tr("\(habit.count(on: key)) of \(habit.target)", "\(habit.count(on: key)) von \(habit.target)"))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            if streak > 0 {
                Label(tr("\(streak) \(streak == 1 ? "day" : "days")", "\(streak) \(streak == 1 ? "Tag" : "Tage")"), systemImage: "flame.fill")
                    .labelStyle(StreakLabelStyle())
            } else if !habit.isCounter {
                Text(tr("Tap when done", "Tippen, wenn erledigt"))
            }
        }
        .scaledFont(size: 13, weight: .medium)
        .foregroundStyle(Zen.inkSoft)
    }

    @ViewBuilder
    private func trailing(done: Bool, key: String) -> some View {
        if habit.isCounter && !done {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Zen.shu)
                .frame(width: 34, height: 34)
                .background(Zen.shu.opacity(0.12), in: Circle())
        } else {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .scaledFont(size: 26, weight: .regular)
                .foregroundStyle(done ? Zen.matcha : Zen.inkFaint)
                .contentTransition(.symbolEffect(.replace))
        }
    }
}

private struct StreakLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.foregroundStyle(Zen.kin)
            configuration.title
        }
    }
}

/// The habit's symbol inside a small ring that fills over the day.
struct HabitMark: View {
    let habit: Habit
    let key: String
    var size: CGFloat = 46

    var body: some View {
        let progress = habit.progress(on: key)
        let done = habit.isDone(on: key)
        let tint: Color = done ? Zen.matcha : Zen.shu
        ZStack {
            ProgressRing(progress: progress, lineWidth: 4, tint: tint)
            Image(systemName: habit.symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
    }
}

// MARK: - Starter offer

/// Shown once, before the first habit exists.
struct HabitStarterCard: View {
    @Environment(DayStore.self) private var day
    var onCustom: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                Image("IllustrationHabits")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Small habits", "Kleine Gewohnheiten"))
                        .displayFont(20)
                        .foregroundStyle(Zen.ink)
                    Text(tr("A few tiny things, every day. Start with these or make your own.", "Ein paar kleine Dinge, jeden Tag. Fang mit diesen an oder leg eigene an."))
                        .scaledFont(size: 14)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            FlowChips(items: Habit.defaults)
            HStack(spacing: 10) {
                Button(tr("Add these", "Übernehmen")) {
                    Haptics.success()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { day.adoptDefaults() }
                }
                .buttonStyle(InkButtonStyle(kind: .shu))
                Button(tr("My own", "Eigene")) {
                    onCustom()
                }
                .buttonStyle(.quiet)
            }
        }
        .zenCard(padding: 20)
    }
}

private struct FlowChips: View {
    let items: [Habit]

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items) { habit in
                HStack(spacing: 8) {
                    Image(systemName: habit.symbol)
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(Zen.shu)
                        .accessibilityHidden(true)
                    Text(habit.title)
                        .scaledFont(size: 14, weight: .medium)
                        .foregroundStyle(Zen.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Zen.sand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

// MARK: - Manage

/// Add, edit, reorder and delete habits.
struct HabitsView: View {
    @Environment(DayStore.self) private var day
    @State private var editing: Habit?

    var body: some View {
        List {
            if day.habits.isEmpty {
                Section {
                    VStack(spacing: 14) {
                        Image("IllustrationEmpty")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 140)
                            .accessibilityHidden(true)
                        Text(tr("No habits yet", "Noch keine Gewohnheiten"))
                            .displayFont(20)
                            .foregroundStyle(Zen.ink)
                        Button(tr("Add the starter set", "Startset übernehmen")) {
                            withAnimation { day.adoptDefaults() }
                        }
                        .buttonStyle(InkButtonStyle(kind: .quiet, fullWidth: false))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Zen.card)
                }
            } else {
                Section {
                    ForEach(day.habits) { habit in
                        Button {
                            editing = habit
                        } label: {
                            HStack(spacing: 14) {
                                IconBadge(systemName: habit.symbol, tint: Zen.shu, size: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(habit.title)
                                        .scaledFont(size: 17, weight: .semibold)
                                        .foregroundStyle(Zen.ink)
                                    Text(HabitEditor.targetText(habit.target))
                                        .scaledFont(size: 13)
                                        .foregroundStyle(Zen.inkSoft)
                                }
                                Spacer()
                                let streak = habit.streak()
                                if streak > 0 {
                                    Label("\(streak)", systemImage: "flame.fill")
                                        .scaledFont(size: 14, weight: .semibold)
                                        .foregroundStyle(Zen.kin)
                                        .accessibilityLabel(tr("\(streak) \(streak == 1 ? "day" : "days") in a row", "\(streak) \(streak == 1 ? "Tag" : "Tage") am Stück"))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Zen.card)
                    }
                    .onDelete { day.delete(at: $0) }
                    .onMove { day.move(from: $0, to: $1) }
                } footer: {
                    Text(tr("Drag to reorder, swipe to delete.", "Ziehen zum Sortieren, wischen zum Löschen."))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(tr("Habits", "Gewohnheiten"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = Habit(title: "", symbol: Habit.symbols[4])
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(tr("New habit", "Neue Gewohnheit"))
            }
            if !day.habits.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .sheet(item: $editing) { habit in
            HabitEditor(habit: habit).environment(day)
        }
    }
}

struct HabitEditor: View {
    @Environment(DayStore.self) private var day
    @Environment(\.dismiss) private var dismiss
    @State private var habit: Habit

    init(habit: Habit) {
        _habit = State(initialValue: habit)
    }

    private var isNew: Bool { !day.habits.contains { $0.id == habit.id } }
    private var trimmedTitle: String { habit.title.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func targetText(_ target: Int) -> String {
        target <= 1
            ? tr("Once a day", "Einmal am Tag")
            : tr("\(target) times a day", "\(target)-mal am Tag")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Spacer()
                        IconBadge(systemName: habit.symbol, tint: Zen.shu, size: 72, filled: true)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: habit.symbol)
                        Spacer()
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(tr("Name", "Name"))
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(Zen.inkSoft)
                        TextField(tr("e.g. Stretch", "z. B. Dehnen"), text: $habit.title)
                            .scaledFont(size: 17)
                            .padding(14)
                            .background(Zen.sand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .zenCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Text(tr("Symbol", "Symbol"))
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(Zen.inkSoft)
                        symbolGrid
                    }
                    .zenCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text(tr("Daily target", "Tagesziel"))
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(Zen.inkSoft)
                        Stepper(value: $habit.target, in: 1...20) {
                            Text(Self.targetText(habit.target))
                                .scaledFont(size: 17, weight: .semibold)
                                .foregroundStyle(Zen.ink)
                                .monospacedDigit()
                        }
                        Text(tr("More than once turns it into a counter, like glasses of water.", "Mehr als einmal macht daraus einen Zähler, etwa für Gläser Wasser."))
                            .scaledFont(size: 13)
                            .foregroundStyle(Zen.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .zenCard()

                    Button(isNew ? tr("Add habit", "Hinzufügen") : tr("Save", "Sichern")) {
                        var saved = habit
                        saved.title = trimmedTitle
                        day.save(saved)
                        Haptics.success()
                        dismiss()
                    }
                    .buttonStyle(.primary)
                    .disabled(trimmedTitle.isEmpty)
                    .opacity(trimmedTitle.isEmpty ? 0.5 : 1)

                    if !isNew {
                        Button(role: .destructive) {
                            day.delete(habit)
                            dismiss()
                        } label: {
                            Text(tr("Delete habit", "Gewohnheit löschen"))
                                .foregroundStyle(Zen.negative)
                        }
                        .buttonStyle(.quiet)
                    }
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle(isNew ? tr("New habit", "Neue Gewohnheit") : tr("Edit habit", "Gewohnheit bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Abbrechen")) { dismiss() }
                }
            }
        }
    }

    private var symbolGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Habit.symbols, id: \.self) { symbol in
                let isOn: Bool = habit.symbol == symbol
                Button {
                    Haptics.tap()
                    habit.symbol = symbol
                } label: {
                    IconBadge(systemName: symbol, tint: isOn ? Zen.shu : Zen.inkSoft, size: 52, filled: isOn)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(spokenSymbolName(symbol))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

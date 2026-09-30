import FamilyControls
import SwiftUI

struct RuleEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State var rule: BlockRule
    let isNew: Bool
    @State private var showPicker = false
    @State private var confirmDelete = false

    private let iconChoices = [
        "shield.lefthalf.filled", "bubble.left.and.bubble.right.fill", "play.rectangle.fill", "gamecontroller.fill",
        "cart.fill", "newspaper.fill", "sunrise.fill", "laptopcomputer", "moon.stars.fill", "book.fill",
        "figure.walk", "leaf.fill",
    ]
    private let minuteChoices = [1, 3, 5, 10, 15, 30]
    private let iconColumns = [GridItem(.adaptive(minimum: 44), spacing: 10)]
    private let chipColumns = [GridItem(.adaptive(minimum: 56), spacing: 8)]
    /// Waiting period the gate enforces when the switch is on.
    private let waitDefault = 10

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                whatSection
                whenSection
                wayThroughSection
                limitsSection
                if !isNew { deleteSection }
            }
            .tint(Zen.shu)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(isNew ? tr("New boundary", "Neue Grenze") : rule.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Save", "Sichern")) {
                        Haptics.success()
                        model.save(rule)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .familyActivityPicker(isPresented: $showPicker, selection: $rule.selection)
            .confirmationDialog(tr("Delete this boundary?", "Diese Grenze löschen?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(tr("Delete", "Löschen"), role: .destructive) {
                    model.delete(rule)
                    dismiss()
                }
            }
            .onAppear {
                // A fresh boundary from a template goes straight to the apps.
                if isNew && rule.isEmpty { showPicker = true }
            }
        }
    }

    // MARK: Sections

    private var nameSection: some View {
        Section {
            HStack(spacing: 12) {
                IconBadge(systemName: rule.icon, filled: true)
                TextField(tr("Name", "Name"), text: $rule.name)
                    .displayFont(20, weight: .semibold)
            }
            LazyVGrid(columns: iconColumns, spacing: 10) {
                ForEach(iconChoices, id: \.self) { icon in
                    Button {
                        Haptics.tap()
                        rule.icon = icon
                    } label: {
                        IconBadge(systemName: icon, tint: rule.icon == icon ? Zen.shu : Zen.inkSoft, size: 40, filled: rule.icon == icon)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(spokenSymbolName(icon))
                    .accessibilityAddTraits(rule.icon == icon ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(tr("Boundary", "Grenze"))
        }
    }

    private var whatSection: some View {
        Section {
            Button {
                showPicker = true
            } label: {
                HStack {
                    Text(rule.isEmpty ? tr("Choose apps and websites", "Apps und Websites auswählen") : tr("Change selection", "Auswahl ändern"))
                        .foregroundStyle(Zen.ink)
                    Spacer()
                    Text("\(rule.itemCount)")
                        .foregroundStyle(Zen.inkSoft)
                        .monospacedDigit()
                }
            }
            if !rule.selection.applicationTokens.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(rule.selection.applicationTokens), id: \.self) { token in
                            Label(token).labelStyle(.iconOnly).frame(width: 34, height: 34)
                        }
                    }
                }
            }
        } header: {
            Text(tr("What", "Was"))
        } footer: {
            Text(tr("Tip: put the Instagram app inside the boundary, but not instagram.com. Then you use Instagram in the browser, where the Reels filter works.", "Tipp: Nimm die Instagram-App in die Grenze, aber nicht instagram.com. Dann nutzt du Instagram im Browser, wo der Reels-Filter wirkt."))
        }
    }

    private var whenSection: some View {
        Section {
            Picker(tr("When", "Wann"), selection: Binding(
                get: { rule.schedule != nil },
                set: { rule.schedule = $0 ? (rule.schedule ?? RuleSchedule()) : nil }
            )) {
                Text(tr("Always", "Immer")).tag(false)
                Text(tr("Time window", "Zeitfenster")).tag(true)
            }
            .pickerStyle(.segmented)

            if let schedule = rule.schedule {
                DatePicker(tr("From", "Von"), selection: timeBinding(\.startMinute), displayedComponents: .hourAndMinute)
                DatePicker(tr("Until", "Bis"), selection: timeBinding(\.endMinute), displayedComponents: .hourAndMinute)
                HStack(spacing: 6) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                        dayButton(day, on: schedule.weekdays.contains(day))
                    }
                }
            }
        } header: {
            Text(tr("When", "Wann"))
        } footer: {
            if let schedule = rule.schedule, schedule.wrapsMidnight {
                Text(tr("Runs past midnight: from \(RuleSchedule.clock(schedule.startMinute)) in the evening to \(RuleSchedule.clock(schedule.endMinute)) the next morning.", "Läuft über Mitternacht: von \(RuleSchedule.clock(schedule.startMinute)) am Abend bis \(RuleSchedule.clock(schedule.endMinute)) am nächsten Morgen."))
            }
        }
    }

    private func dayButton(_ day: Int, on: Bool) -> some View {
        Button {
            Haptics.tap()
            if on { rule.schedule?.weekdays.remove(day) } else { rule.schedule?.weekdays.insert(day) }
        } label: {
            Text(RuleSchedule.dayName(day))
                .scaledFont(size: 13, weight: .semibold)
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(on ? Color.white : Zen.ink)
                .background(on ? Zen.shu : Zen.sand, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var wayThroughSection: some View {
        Section {
            Toggle(tr("Unlock with questions", "Mit Fragen entsperrbar"), isOn: $rule.allowsUnlock)
            if rule.allowsUnlock {
                Stepper(value: $rule.questionsRequired, in: 1...5) {
                    HStack {
                        Text(tr("Right answers", "Richtige Antworten"))
                        Spacer()
                        Text("\(rule.questionsRequired)").foregroundStyle(Zen.inkSoft).monospacedDigit()
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("Then open for", "Danach offen für"))
                    LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                        ForEach(minuteChoices, id: \.self) { minutes in
                            Chip(title: tr("\(minutes) min.", "\(minutes) Min."), selected: rule.unlockMinutes == minutes) {
                                rule.unlockMinutes = minutes
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text(tr("Way through", "Ausweg"))
        } footer: {
            Text(rule.allowsUnlock
                 ? tr("The shield offers \"Answer a question\". Answer right and you may go in for the chosen time.", "Auf dem Sperrbildschirm gibt es \"Frage beantworten\". Wer richtig antwortet, darf für die gewählte Zeit hinein.")
                 : tr("No way through: the shield only offers the way back. You can still switch the boundary off here, unless a lockdown is running.", "Kein Ausweg: Der Sperrbildschirm bietet nur den Rückweg. Ausschalten kannst du die Grenze trotzdem hier, außer während einer Sperre."))
        }
    }

    @ViewBuilder
    private var limitsSection: some View {
        if rule.allowsUnlock {
            Section {
                Toggle(tr("Daily limit", "Tageslimit"), isOn: Binding(
                    get: { rule.dailyUnlockLimit != nil },
                    set: { rule.dailyUnlockLimit = $0 ? (rule.dailyUnlockLimit ?? 3) : nil }
                ))
                if let limit = rule.dailyUnlockLimit {
                    Stepper(value: Binding(
                        get: { limit },
                        set: { rule.dailyUnlockLimit = $0 }
                    ), in: 1...20) {
                        HStack {
                            Text(tr("Unlocks per day", "Freigaben pro Tag"))
                            Spacer()
                            Text("\(limit)").foregroundStyle(Zen.inkSoft).monospacedDigit()
                        }
                    }
                }
                Toggle(isOn: $rule.risingFriction) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Rising friction", "Steigende Hürde"))
                        Text(risingExample)
                            .scaledFont(size: 13)
                            .foregroundStyle(Zen.inkSoft)
                    }
                }
                Toggle(isOn: Binding(
                    get: { rule.waitSeconds > 0 },
                    set: { rule.waitSeconds = $0 ? waitDefault : 0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Wait before the questions", "Warten vor den Fragen"))
                        Text(tr("A \(waitDefault) second countdown that cannot be skipped.", "Ein Countdown von \(waitDefault) Sekunden, den du nicht überspringen kannst."))
                            .scaledFont(size: 13)
                            .foregroundStyle(Zen.inkSoft)
                    }
                }
            } header: {
                Text(tr("Friction", "Hürden"))
            } footer: {
                Text(rule.dailyUnlockLimit == nil
                     ? tr("Friction makes each unlock a little harder than the last, so the fifth one really is a decision.", "Hürden machen jede Freigabe etwas schwerer als die letzte, damit die fünfte wirklich eine Entscheidung ist.")
                     : tr("Once the daily unlocks are used, the shield becomes a wall until midnight.", "Sind die Freigaben des Tages verbraucht, wird der Sperrbildschirm bis Mitternacht zur Wand."))
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(tr("Delete boundary", "Grenze löschen"), role: .destructive) {
                confirmDelete = true
            }
            .disabled(model.isLockedDown)
        } footer: {
            if model.isLockedDown {
                Text(tr("A lockdown is running. You can delete boundaries again once it is over.", "Gerade läuft eine Sperre. Löschen kannst du Grenzen wieder, wenn sie vorbei ist."))
            }
        }
    }

    // MARK: Helpers

    private var risingExample: String {
        // Shown before the switch is on too, so preview the rising version.
        var preview = rule
        preview.risingFriction = true
        let steps = (0..<3).map { preview.questionsNeeded(unlocksToday: $0) }
        let list = steps.map(String.init).joined(separator: ", ")
        return tr("Each unlock today costs one question more: \(list) and so on.", "Jede Freigabe heute kostet eine Frage mehr: \(list) und so weiter.")
    }

    private func timeBinding(_ keyPath: WritableKeyPath<RuleSchedule, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minute = rule.schedule?[keyPath: keyPath] ?? 0
                return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                rule.schedule?[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}

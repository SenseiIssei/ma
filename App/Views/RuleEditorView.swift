import FamilyControls
import SwiftUI

struct RuleEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State var rule: BlockRule
    let isNew: Bool
    @State private var showPicker = false
    @State private var confirmDelete = false

    private let kanjiChoices = ["結", "門", "静", "守", "間", "禅", "止", "心", "夜", "朝"]
    private let minuteChoices = [1, 3, 5, 10, 15, 30]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(tr("Name", "Name"), text: $rule.name)
                        .font(.mincho(20, weight: .semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(kanjiChoices, id: \.self) { kanji in
                                Button {
                                    Haptics.tap()
                                    rule.kanji = kanji
                                } label: {
                                    Hanko(text: kanji, size: 38, color: rule.kanji == kanji ? Zen.shu : Zen.inkFaint)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text(tr("Boundary", "Grenze"))
                }

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
                                let on = schedule.weekdays.contains(day)
                                Button {
                                    Haptics.tap()
                                    if on { rule.schedule?.weekdays.remove(day) } else { rule.schedule?.weekdays.insert(day) }
                                } label: {
                                    Text(dayName(day))
                                        .font(.system(size: 13, weight: .semibold))
                                        .frame(maxWidth: .infinity, minHeight: 34)
                                        .foregroundStyle(on ? Zen.paper : Zen.ink)
                                        .background(on ? Zen.ink : Zen.card, in: Circle())
                                }
                                .buttonStyle(.plain)
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

                Section {
                    Toggle(tr("Unlock with questions", "Mit Fragen entsperrbar"), isOn: $rule.allowsUnlock)
                        .tint(Zen.shu)
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
                            HStack(spacing: 8) {
                                ForEach(minuteChoices, id: \.self) { minutes in
                                    Chip(title: "\(minutes)", selected: rule.unlockMinutes == minutes) {
                                        rule.unlockMinutes = minutes
                                    }
                                }
                                Text(tr("min.", "Min.")).foregroundStyle(Zen.inkSoft)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text(tr("Way through", "Ausweg"))
                } footer: {
                    Text(rule.allowsUnlock
                         ? tr("The shield offers \"Answer a question\". Answer right and you may go in for the chosen time.", "Auf dem Sperrbildschirm gibt es \"Frage beantworten\". Wer richtig antwortet, darf für die gewählte Zeit hinein.")
                         : tr("No way through: the shield only offers the way back. You can still switch the boundary off here at any time.", "Kein Ausweg: Der Sperrbildschirm bietet nur den Rückweg. Ausschalten kannst du die Grenze trotzdem jederzeit hier."))
                }

                if !isNew {
                    Section {
                        Button(tr("Delete boundary", "Grenze löschen"), role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(WashiBackground())
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
        }
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

    private func dayName(_ day: Int) -> String {
        RuleSchedule.dayName(day)
    }
}

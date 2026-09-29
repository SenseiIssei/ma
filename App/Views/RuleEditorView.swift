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
                    TextField("Name", text: $rule.name)
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
                    Text("Grenze")
                }

                Section {
                    Button {
                        showPicker = true
                    } label: {
                        HStack {
                            Text(rule.isEmpty ? "Apps und Websites auswählen" : "Auswahl ändern")
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
                    Text("Was")
                } footer: {
                    Text("Tipp: Nimm die Instagram-App in die Grenze, aber nicht instagram.com. Dann nutzt du Instagram im Browser, wo der Reels-Filter wirkt.")
                }

                Section {
                    Picker("Wann", selection: Binding(
                        get: { rule.schedule != nil },
                        set: { rule.schedule = $0 ? (rule.schedule ?? RuleSchedule()) : nil }
                    )) {
                        Text("Immer").tag(false)
                        Text("Zeitfenster").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if let schedule = rule.schedule {
                        DatePicker("Von", selection: timeBinding(\.startMinute), displayedComponents: .hourAndMinute)
                        DatePicker("Bis", selection: timeBinding(\.endMinute), displayedComponents: .hourAndMinute)
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
                    Text("Wann")
                } footer: {
                    if let schedule = rule.schedule, schedule.wrapsMidnight {
                        Text("Läuft über Mitternacht: von \(RuleSchedule.clock(schedule.startMinute)) am Abend bis \(RuleSchedule.clock(schedule.endMinute)) am nächsten Morgen.")
                    }
                }

                Section {
                    Toggle("Mit Fragen entsperrbar", isOn: $rule.allowsUnlock)
                        .tint(Zen.shu)
                    if rule.allowsUnlock {
                        Stepper(value: $rule.questionsRequired, in: 1...5) {
                            HStack {
                                Text("Richtige Antworten")
                                Spacer()
                                Text("\(rule.questionsRequired)").foregroundStyle(Zen.inkSoft).monospacedDigit()
                            }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Danach offen für")
                            HStack(spacing: 8) {
                                ForEach(minuteChoices, id: \.self) { minutes in
                                    Chip(title: "\(minutes)", selected: rule.unlockMinutes == minutes) {
                                        rule.unlockMinutes = minutes
                                    }
                                }
                                Text("Min.").foregroundStyle(Zen.inkSoft)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Ausweg")
                } footer: {
                    Text(rule.allowsUnlock
                         ? "Auf dem Sperrbildschirm gibt es \"Frage beantworten\". Wer richtig antwortet, darf für die gewählte Zeit hinein."
                         : "Kein Ausweg: Der Sperrbildschirm bietet nur den Rückweg. Ausschalten kannst du die Grenze trotzdem jederzeit hier.")
                }

                if !isNew {
                    Section {
                        Button("Grenze löschen", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(WashiBackground())
            .navigationTitle(isNew ? "Neue Grenze" : rule.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        Haptics.success()
                        model.save(rule)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .familyActivityPicker(isPresented: $showPicker, selection: $rule.selection)
            .confirmationDialog("Diese Grenze löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
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
        ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"][(day - 1) % 7]
    }
}

import FamilyControls
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    statusRow("Bildschirmzeit", ok: model.authorization == .approved) {
                        Task { await model.requestScreenTime() }
                    }
                    statusRow("Mitteilungen", ok: model.notificationsAllowed) {
                        Task { await model.requestNotifications() }
                    }
                } header: {
                    Text("Erlaubnisse")
                } footer: {
                    Text("Ohne Mitteilungen kann der Sperrbildschirm dich nicht zu deiner Frage schicken.")
                }

                Section {
                    Toggle("Achtsames Aufheben", isOn: $model.mindfulRelease)
                        .tint(Zen.shu)
                } footer: {
                    Text("Aufheben geht immer. Mit diesem Schalter kostet das Ausschalten einer Grenze oder das Abbrechen einer Fokusrunde aber drei richtige Antworten. So bleibt es eine Entscheidung und wird kein Reflex.")
                }

                Section {
                    Stepper(value: Binding(
                        get: { model.decks.profile.dailyGoal },
                        set: { model.decks.profile.dailyGoal = $0 }
                    ), in: 5...100, step: 5) {
                        HStack {
                            Text("Tagesziel")
                            Spacer()
                            Text("\(model.decks.profile.dailyGoal) Antworten")
                                .foregroundStyle(Zen.inkSoft)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Lernen")
                }

                Section {
                    NavigationLink("Reels-Filter für Safari") { FilterView() }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
                    Link("Quellcode auf GitHub", destination: URL(string: "https://github.com/SenseiIssei/ma")!)
                    Text("Ma speichert nichts außerhalb deines iPhones. Keine Konten, keine Analyse, kein Server.")
                        .font(.system(size: 14))
                        .foregroundStyle(Zen.inkSoft)
                } header: {
                    Text("Über Ma")
                }

                Section {
                    Button("Alle Sperren aufheben und zurücksetzen", role: .destructive) {
                        confirmReset = true
                    }
                } footer: {
                    Text("Löscht Grenzen, Freigaben und den Fokus-Timer. Deine Lernfortschritte bleiben.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(WashiBackground())
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .confirmationDialog("Wirklich alles zurücksetzen?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Zurücksetzen", role: .destructive) {
                    model.resetEverything()
                }
            }
        }
    }

    private func statusRow(_ title: String, ok: Bool, request: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if ok {
                Label("erlaubt", systemImage: "checkmark.seal.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Zen.matcha)
                    .font(.system(size: 14, weight: .medium))
            } else {
                Button("Erlauben", action: request)
                    .foregroundStyle(Zen.shu)
            }
        }
    }
}

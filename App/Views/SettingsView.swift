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
                    statusRow(tr("Screen Time", "Bildschirmzeit"), ok: model.authorization == .approved) {
                        Task { await model.requestScreenTime() }
                    }
                    statusRow(tr("Notifications", "Mitteilungen"), ok: model.notificationsAllowed) {
                        Task { await model.requestNotifications() }
                    }
                } header: {
                    Text(tr("Permissions", "Erlaubnisse"))
                } footer: {
                    Text(tr("Without notifications the shield cannot send you to your question.", "Ohne Mitteilungen kann der Sperrbildschirm dich nicht zu deiner Frage schicken."))
                }

                Section {
                    Toggle(tr("Mindful release", "Achtsames Aufheben"), isOn: $model.mindfulRelease)
                        .tint(Zen.shu)
                } footer: {
                    Text(tr("Releasing always works. With this switch, turning a boundary off or ending a focus round early costs three right answers. That keeps it a decision instead of a reflex.", "Aufheben geht immer. Mit diesem Schalter kostet das Ausschalten einer Grenze oder das Abbrechen einer Fokusrunde aber drei richtige Antworten. So bleibt es eine Entscheidung und wird kein Reflex."))
                }

                Section {
                    Stepper(value: Binding(
                        get: { model.decks.profile.dailyGoal },
                        set: { model.decks.profile.dailyGoal = $0 }
                    ), in: 5...100, step: 5) {
                        HStack {
                            Text(tr("Daily goal", "Tagesziel"))
                            Spacer()
                            Text(tr("\(model.decks.profile.dailyGoal) answers", "\(model.decks.profile.dailyGoal) Antworten"))
                                .foregroundStyle(Zen.inkSoft)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text(tr("Learning", "Lernen"))
                }

                Section {
                    NavigationLink(tr("Reels filter for Safari", "Reels-Filter für Safari")) { FilterView() }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
                    Link(tr("Source code on GitHub", "Quellcode auf GitHub"), destination: URL(string: "https://github.com/SenseiIssei/ma")!)
                    Text(tr("Ma stores nothing outside your iPhone. No accounts, no analytics, no server.", "Ma speichert nichts außerhalb deines iPhones. Keine Konten, keine Analyse, kein Server."))
                        .font(.system(size: 14))
                        .foregroundStyle(Zen.inkSoft)
                } header: {
                    Text(tr("About Ma", "Über Ma"))
                }

                Section {
                    Button(tr("Lift all blocks and reset", "Alle Sperren aufheben und zurücksetzen"), role: .destructive) {
                        confirmReset = true
                    }
                } footer: {
                    Text(tr("Deletes boundaries, unlocks and the focus timer. Your learning progress stays.", "Löscht Grenzen, Freigaben und den Fokus-Timer. Deine Lernfortschritte bleiben."))
                }
            }
            .scrollContentBackground(.hidden)
            .background(WashiBackground())
            .navigationTitle(tr("Settings", "Einstellungen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Fertig")) { dismiss() }
                }
            }
            .confirmationDialog(tr("Really reset everything?", "Wirklich alles zurücksetzen?"), isPresented: $confirmReset, titleVisibility: .visible) {
                Button(tr("Reset", "Zurücksetzen"), role: .destructive) {
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
                Label(tr("allowed", "erlaubt"), systemImage: "checkmark.seal.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Zen.matcha)
                    .font(.system(size: 14, weight: .medium))
            } else {
                Button(tr("Allow", "Erlauben"), action: request)
                    .foregroundStyle(Zen.shu)
            }
        }
    }
}

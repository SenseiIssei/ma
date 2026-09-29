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
                    if BuildFlavor.screenTimeAvailable {
                        statusRow(icon: "hourglass", title: tr("Screen Time", "Bildschirmzeit"), ok: model.authorization == .approved) {
                            Task { await model.requestScreenTime() }
                        }
                    }
                    statusRow(icon: "bell.badge.fill", title: tr("Notifications", "Mitteilungen"), ok: model.notificationsAllowed) {
                        Task { await model.requestNotifications() }
                    }
                } header: {
                    FormHeader(icon: "checkmark.shield.fill", title: tr("Permissions", "Erlaubnisse"))
                } footer: {
                    Text(BuildFlavor.screenTimeAvailable
                         ? tr("Without notifications the shield cannot send you to your question.", "Ohne Mitteilungen kann der Sperrbildschirm dich nicht zu deiner Frage schicken.")
                         : BuildFlavor.previewNote)
                }

                Section {
                    Toggle(tr("Mindful release", "Achtsames Aufheben"), isOn: $model.mindfulRelease)
                } header: {
                    FormHeader(icon: "shield.lefthalf.filled", title: tr("Blocking", "Sperren"))
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
                    FormHeader(icon: "book.fill", title: tr("Learning", "Lernen"))
                }

                Section {
                    NavigationLink {
                        FilterView()
                    } label: {
                        Label(tr("Reels filter for Safari", "Reels-Filter für Safari"), systemImage: "safari.fill")
                    }
                } header: {
                    FormHeader(icon: "square.stack.3d.up.fill", title: tr("More ways", "Weitere Wege"))
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
                    Link(destination: URL(string: "https://github.com/SenseiIssei/ma")!) {
                        Label(tr("Source code on GitHub", "Quellcode auf GitHub"), systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Text(tr("Ma stores nothing outside your iPhone. No accounts, no analytics, no server.", "Ma speichert nichts außerhalb deines iPhones. Keine Konten, keine Analyse, kein Server."))
                        .font(.system(size: 14))
                        .foregroundStyle(Zen.inkSoft)
                } header: {
                    FormHeader(icon: "info.circle.fill", title: tr("About Ma", "Über Ma"))
                }

                Section {
                    Button(tr("Lift all blocks and reset", "Alle Sperren aufheben und zurücksetzen"), role: .destructive) {
                        confirmReset = true
                    }
                    .disabled(model.isLockedDown)
                } footer: {
                    Text(model.isLockedDown
                         ? tr("A lockdown is running. Resetting waits until it is over.", "Gerade läuft eine Sperre. Zurücksetzen geht erst, wenn sie vorbei ist.")
                         : tr("Deletes boundaries, unlocks and the focus timer. Your learning progress stays.", "Löscht Grenzen, Freigaben und den Fokus-Timer. Deine Lernfortschritte bleiben."))
                }
            }
            .tint(Zen.shu)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(tr("Settings", "Einstellungen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Fertig")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog(tr("Really reset everything?", "Wirklich alles zurücksetzen?"), isPresented: $confirmReset, titleVisibility: .visible) {
                Button(tr("Reset", "Zurücksetzen"), role: .destructive) {
                    model.resetEverything()
                }
            }
        }
    }

    private func statusRow(icon: String, title: String, ok: Bool, request: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, tint: ok ? Zen.matcha : Zen.inkSoft, size: 32)
            Text(title)
            Spacer()
            if ok {
                Label(tr("allowed", "erlaubt"), systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Zen.matcha)
                    .font(.system(size: 14, weight: .medium))
            } else {
                Button(tr("Allow", "Erlauben"), action: request)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Zen.shu)
            }
        }
    }
}

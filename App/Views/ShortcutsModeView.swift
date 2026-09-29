import SwiftUI

/// Setup and settings for the Shortcuts mode: one automation in the
/// Shortcuts app runs "Ma Pause" whenever a chosen app opens. iOS does not
/// let an app create automations itself, so this screen walks through the
/// one manual step and then shows whether it is working.
struct ShortcutsModeView: View {
    @Environment(AppModel.self) private var model
    private let minuteChoices = [1, 3, 5, 10, 15, 30]
    private let chipColumns = [GridItem(.adaptive(minimum: 72), spacing: 8)]

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        IconBadge(systemName: "bolt.fill", tint: model.shortcutLastRun == nil ? Zen.inkSoft : Zen.shu)
                        Text(tr("Shortcuts mode", "Kurzbefehle-Modus"))
                            .font(.display(20))
                            .foregroundStyle(Zen.ink)
                    }
                    Text(tr("Works without Screen Time: a Shortcuts automation starts Ma whenever one of your apps opens. If you have an open pass, Ma stays invisible and the app opens as usual.",
                            "Funktioniert ohne Bildschirmzeit: Eine Kurzbefehle-Automation startet Ma, sobald eine deiner Apps geöffnet wird. Läuft gerade eine Freigabe, bleibt Ma unsichtbar und die App öffnet ganz normal."))
                        .foregroundStyle(Zen.inkSoft)
                    statusLine
                }
                .font(.system(size: 15))
                .padding(.vertical, 4)
            } header: {
                FormHeader(icon: "questionmark.circle.fill", title: tr("How it works", "So funktioniert es"))
            }

            Section {
                VStack(alignment: .leading, spacing: 14) {
                    StepRow(number: 1, text: tr("Open the Shortcuts app and go to the Automation tab.", "Öffne die App Kurzbefehle und geh zum Tab Automation."))
                    StepRow(number: 2, text: tr("Tap +, then choose \"App\".", "Tippe auf +, dann auf \"App\"."))
                    StepRow(number: 3, text: tr("Tap \"Choose\" and tick every app that pulls at you: Instagram, YouTube, X, TikTok and so on. One automation covers all of them.", "Tippe auf \"Auswählen\" und hake alle Apps an, die dich ziehen: Instagram, YouTube, X, TikTok und so weiter. Eine Automation reicht für alle."))
                    StepRow(number: 4, text: tr("Leave \"Is Opened\" ticked and choose \"Run Immediately\". Switch \"Notify When Run\" off.", "Lass \"Wird geöffnet\" angehakt und wähle \"Sofort ausführen\". Schalte \"Bei Ausführung mitteilen\" aus."))
                    StepRow(number: 5, text: tr("Tap Next, search for \"Ma Pause\" and pick it. Done.", "Tippe auf Weiter, such nach \"Ma Pause\" und wähle es aus. Fertig."))
                }
                .padding(.vertical, 4)

                Button {
                    if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                } label: {
                    Label(tr("Open Shortcuts", "Kurzbefehle öffnen"), systemImage: "arrow.up.forward.app")
                }
            } header: {
                FormHeader(icon: "list.number", title: tr("Set up once", "Einmal einrichten"))
            } footer: {
                Text(tr("Apple does not allow any app to create automations on its own, so this one step is yours. After that Ma handles everything.",
                        "Apple erlaubt keiner App, Automationen selbst anzulegen, deshalb ist dieser eine Schritt deiner. Danach erledigt Ma alles."))
            }

            Section {
                Stepper(value: $model.shortcutSettings.questions, in: 1...5) {
                    HStack {
                        Text(tr("Right answers", "Richtige Antworten"))
                        Spacer()
                        Text("\(model.shortcutSettings.questions)").foregroundStyle(Zen.inkSoft).monospacedDigit()
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("Then open for", "Danach offen für"))
                    LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                        ForEach(minuteChoices, id: \.self) { minutes in
                            Chip(title: tr("\(minutes) min.", "\(minutes) Min."), selected: model.shortcutSettings.minutes == minutes) {
                                model.shortcutSettings.minutes = minutes
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                FormHeader(icon: "hand.raised.fill", title: tr("The gate", "Die Schranke"))
            } footer: {
                Text(tr("A pass opens all guarded apps for that time. During a strict focus round or a lockdown the gate only shows the time left.",
                        "Eine Freigabe öffnet alle geschützten Apps für diese Zeit. Während einer strengen Fokusrunde oder einer Sperre zeigt die Schranke nur die Restzeit."))
            }

            if let until = model.shortcutPassUntil {
                Section {
                    HStack {
                        Text(tr("Open until \(BlockingFormat.time(until))", "Offen bis \(BlockingFormat.time(until))"))
                        Spacer()
                        Button(tr("Lock", "Sperren")) { model.closeShortcutPass() }
                            .fontWeight(.semibold)
                            .foregroundStyle(Zen.shu)
                    }
                } header: {
                    FormHeader(icon: "lock.open.fill", title: tr("Pass", "Freigabe"))
                }
            }

            Section {
                Button {
                    model.gate = .shortcut(GuardedApp.any.rawValue)
                } label: {
                    Label(tr("Try the gate now", "Schranke jetzt ausprobieren"), systemImage: "play.circle.fill")
                }
            }
        }
        .tint(Zen.shu)
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(tr("Shortcuts mode", "Kurzbefehle-Modus"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.shortcutSettings.questions) { _, _ in model.saveShortcutSettings() }
        .onChange(of: model.shortcutSettings.minutes) { _, _ in model.saveShortcutSettings() }
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Image(systemName: model.shortcutLastRun == nil ? "circle.dashed" : "checkmark.circle.fill")
                .foregroundStyle(model.shortcutLastRun == nil ? Zen.inkFaint : Zen.matcha)
            if let last = model.shortcutLastRun {
                Text(tr("Last run: \(last.formatted(date: .abbreviated, time: .shortened))", "Zuletzt ausgeführt: \(last.formatted(date: .abbreviated, time: .shortened))"))
                    .foregroundStyle(Zen.matcha)
            } else {
                Text(tr("Not run yet. Set up the automation below.", "Noch nie ausgeführt. Richte unten die Automation ein."))
                    .foregroundStyle(Zen.inkSoft)
            }
        }
        .font(.system(size: 14, weight: .medium))
    }
}

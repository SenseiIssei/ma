import SwiftUI

/// Setup and settings for the Shortcuts mode: one automation in the
/// Shortcuts app runs "Ma Pause" whenever a chosen app opens. iOS does not
/// let an app create automations itself, so this screen walks through the
/// one manual step and then shows whether it is working.
struct ShortcutsModeView: View {
    @Environment(AppModel.self) private var model
    private let minuteChoices = [1, 3, 5, 10, 15, 30]

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("Works without Screen Time: a Shortcuts automation starts Ma whenever one of your apps opens. If you have an open pass, Ma stays invisible and the app opens as usual.",
                            "Funktioniert ohne Bildschirmzeit: Eine Kurzbefehle-Automation startet Ma, sobald eine deiner Apps geöffnet wird. Läuft gerade eine Freigabe, bleibt Ma unsichtbar und die App öffnet ganz normal."))
                    statusLine
                }
                .font(.system(size: 15))
                .padding(.vertical, 4)
            } header: {
                Text(tr("How it works", "So funktioniert es"))
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    step(1, tr("Open the Shortcuts app and go to the Automation tab.", "Öffne die App Kurzbefehle und geh zum Tab Automation."))
                    step(2, tr("Tap +, then choose \"App\".", "Tippe auf +, dann auf \"App\"."))
                    step(3, tr("Tap \"Choose\" and tick every app that pulls at you: Instagram, YouTube, X, TikTok and so on. One automation covers all of them.", "Tippe auf \"Auswählen\" und hake alle Apps an, die dich ziehen: Instagram, YouTube, X, TikTok und so weiter. Eine Automation reicht für alle."))
                    step(4, tr("Leave \"Is Opened\" ticked and choose \"Run Immediately\". Switch \"Notify When Run\" off.", "Lass \"Wird geöffnet\" angehakt und wähle \"Sofort ausführen\". Schalte \"Bei Ausführung mitteilen\" aus."))
                    step(5, tr("Tap Next, search for \"Ma Pause\" and pick it. Done.", "Tippe auf Weiter, such nach \"Ma Pause\" und wähle es aus. Fertig."))
                }
                .font(.system(size: 15))
                .padding(.vertical, 4)

                Button {
                    if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                } label: {
                    Label(tr("Open Shortcuts", "Kurzbefehle öffnen"), systemImage: "arrow.up.forward.app")
                }
            } header: {
                Text(tr("Set up once", "Einmal einrichten"))
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
                    FlowLayout(spacing: 8) {
                        ForEach(minuteChoices, id: \.self) { minutes in
                            Chip(title: tr("\(minutes) min.", "\(minutes) Min."), selected: model.shortcutSettings.minutes == minutes) {
                                model.shortcutSettings.minutes = minutes
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(tr("The gate", "Die Schranke"))
            } footer: {
                Text(tr("A pass opens all guarded apps for that time. During a strict focus round the gate only shows the time left.",
                        "Eine Freigabe öffnet alle geschützten Apps für diese Zeit. Während einer strengen Fokusrunde zeigt die Schranke nur die Restzeit."))
            }

            if let until = model.shortcutPassUntil {
                Section {
                    HStack {
                        Text(tr("Open until \(until.formatted(date: .omitted, time: .shortened))", "Offen bis \(until.formatted(date: .omitted, time: .shortened))"))
                        Spacer()
                        Button(tr("Lock", "Sperren")) { model.closeShortcutPass() }
                            .foregroundStyle(Zen.shu)
                    }
                } header: {
                    Text(tr("Pass", "Freigabe"))
                }
            }

            Section {
                Button(tr("Try the gate now", "Schranke jetzt ausprobieren")) {
                    model.gate = .shortcut(GuardedApp.any.rawValue)
                }
            }
        }
        .tint(Zen.shu)
        .scrollContentBackground(.hidden)
        .background(WashiBackground())
        .navigationTitle(tr("Shortcuts mode", "Kurzbefehle-Modus"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.shortcutSettings.questions) { _, _ in model.saveShortcutSettings() }
        .onChange(of: model.shortcutSettings.minutes) { _, _ in model.saveShortcutSettings() }
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Image(systemName: model.shortcutLastRun == nil ? "circle.dashed" : "checkmark.seal.fill")
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

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(KanjiDate.number(number))
                .font(.kanji(15, bold: true))
                .foregroundStyle(Zen.shu)
                .frame(width: 22)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

import FamilyControls
import SwiftUI

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: BlockRule?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageTitle(
                        kanji: "結界",
                        title: tr("Boundaries", "Grenzen"),
                        subtitle: tr("In a temple, the kekkai is the line between the quiet grounds and everyday life. Here you draw yours.", "Ein Kekkai ist im Tempel die Linie, die den stillen Bereich vom Alltag trennt. Hier ziehst du deine.")
                    )

                    if model.authorization != .approved {
                        permissionCard
                    }

                    Button {
                        model.showShortcutsSetup = true
                    } label: {
                        HStack(spacing: 14) {
                            Hanko(text: "門", size: 40, color: model.shortcutLastRun == nil ? Zen.inkFaint : Zen.shu)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tr("Shortcuts mode", "Kurzbefehle-Modus"))
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Zen.ink)
                                Text(model.shortcutLastRun == nil
                                     ? tr("Pause before any app, without Screen Time. Set up once.", "Pause vor jeder App, ohne Bildschirmzeit. Einmal einrichten.")
                                     : tr("Active. One automation guards your apps.", "Aktiv. Eine Automation bewacht deine Apps."))
                                    .font(.system(size: 14))
                                    .foregroundStyle(Zen.inkSoft)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(Zen.inkFaint)
                        }
                        .zenCard()
                    }
                    .buttonStyle(.plain)

                    // Screen Time boundaries need Apple's approval. Without it the
                    // picker cannot open, so the preview only offers Shortcuts mode.
                    if BuildFlavor.screenTimeAvailable {
                    VStack(spacing: 12) {
                        ForEach(model.rules) { rule in
                            RuleCard(rule: rule, shielding: model.isShielding(rule)) {
                                editing = rule
                            } toggle: { on in
                                model.setEnabled(rule, on)
                            }
                        }
                        Button {
                            var rule = BlockRule()
                            rule.name = model.rules.isEmpty ? tr("Social media", "Soziale Medien") : tr("New boundary", "Neue Grenze")
                            editing = rule
                        } label: {
                            Label(tr("Draw a new boundary", "Neue Grenze ziehen"), systemImage: "plus")
                        }
                        .buttonStyle(.quiet)
                    }
                    }

                    if !model.grants.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(kanji: "開", title: tr("Open right now", "Gerade offen"))
                            VStack(spacing: 10) {
                                ForEach(model.grants) { grant in
                                    GrantRow(grant: grant) { model.revoke(grant) }
                                }
                            }
                            .zenCard()
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(kanji: "濾", title: tr("In the browser", "Im Browser"))
                        NavigationLink {
                            FilterView()
                        } label: {
                            HStack(spacing: 14) {
                                Hanko(text: "濾", size: 40, color: Zen.ai)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tr("Reels filter for Safari", "Reels-Filter für Safari"))
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(Zen.ink)
                                    Text(tr("Instagram without Reels, YouTube without Shorts, LinkedIn without the feed.", "Instagram ohne Reels, YouTube ohne Shorts, LinkedIn ohne Feed."))
                                        .font(.system(size: 14))
                                        .foregroundStyle(Zen.inkSoft)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").foregroundStyle(Zen.inkFaint)
                            }
                            .zenCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.bottom, 40)
            }
            .background(WashiBackground())
            .navigationDestination(isPresented: Binding(
                get: { model.showShortcutsSetup },
                set: { model.showShortcutsSetup = $0 }
            )) {
                ShortcutsModeView()
            }
            .sheet(item: $editing) { rule in
                RuleEditorView(rule: rule, isNew: !model.rules.contains { $0.id == rule.id })
            }
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !BuildFlavor.screenTimeAvailable {
                Text(BuildFlavor.previewNote)
                    .font(.system(size: 15))
                    .foregroundStyle(Zen.ink)
            } else {
                Text(tr("Ma needs Screen Time access, otherwise every boundary stays on paper.", "Ma braucht Zugriff auf Bildschirmzeit, sonst bleiben alle Grenzen nur auf dem Papier."))
                    .font(.system(size: 15))
                    .foregroundStyle(Zen.ink)
                Button(tr("Allow access", "Zugriff erlauben")) {
                    Task { await model.requestScreenTime() }
                }
                .buttonStyle(.shu)
            }
        }
        .zenCard()
    }
}

struct RuleCard: View {
    let rule: BlockRule
    let shielding: Bool
    let edit: () -> Void
    let toggle: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Hanko(text: rule.kanji, size: 44, color: rule.isEnabled ? Zen.shu : Zen.inkFaint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.name)
                        .font(.mincho(21, weight: .semibold))
                        .foregroundStyle(Zen.ink)
                    Text(summary)
                        .font(.system(size: 14))
                        .foregroundStyle(Zen.inkSoft)
                    Text(status)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(shielding ? Zen.shu : Zen.inkFaint)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(get: { rule.isEnabled }, set: toggle))
                    .labelsHidden()
                    .tint(Zen.shu)
            }
            if !rule.selection.applicationTokens.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(rule.selection.applicationTokens.prefix(7)), id: \.self) { token in
                        Label(token)
                            .labelStyle(.iconOnly)
                            .frame(width: 30, height: 30)
                    }
                    if rule.selection.applicationTokens.count > 7 {
                        Text("+\(rule.selection.applicationTokens.count - 7)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Zen.inkSoft)
                    }
                }
            }
        }
        .zenCard()
        .contentShape(Rectangle())
        .onTapGesture(perform: edit)
    }

    private var summary: String {
        var parts: [String] = []
        let apps = rule.selection.applicationTokens.count
        let cats = rule.selection.categoryTokens.count
        let webs = rule.selection.webDomainTokens.count
        if apps > 0 { parts.append(tr("\(apps) \(apps == 1 ? "app" : "apps")", "\(apps) \(apps == 1 ? "App" : "Apps")")) }
        if cats > 0 { parts.append(tr("\(cats) \(cats == 1 ? "category" : "categories")", "\(cats) \(cats == 1 ? "Kategorie" : "Kategorien")")) }
        if webs > 0 { parts.append(tr("\(webs) \(webs == 1 ? "website" : "websites")", "\(webs) \(webs == 1 ? "Website" : "Websites")")) }
        if parts.isEmpty { parts.append(tr("Nothing chosen yet", "Noch nichts ausgewählt")) }
        parts.append(rule.schedule?.label ?? tr("always", "immer"))
        return parts.joined(separator: " · ")
    }

    private var status: String {
        if !rule.isEnabled { return tr("switched off", "ausgeschaltet") }
        if rule.isEmpty { return tr("empty", "leer") }
        if !shielding { return tr("resting until the next window", "ruht bis zum nächsten Zeitfenster") }
        if !rule.allowsUnlock { return tr("on watch, no way through", "wacht, ohne Ausweg") }
        let q = rule.questionsRequired == 1
            ? tr("1 question", "1 Frage")
            : tr("\(rule.questionsRequired) questions", "\(rule.questionsRequired) Fragen")
        return tr("on watch · \(q) for \(rule.unlockMinutes) min.", "wacht · \(q) für \(rule.unlockMinutes) Min.")
    }
}

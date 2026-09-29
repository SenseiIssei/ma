import FamilyControls
import SwiftUI

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: BlockRule?
    @State private var showTemplates = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ScreenHeader(
                        title: tr("Boundaries", "Grenzen"),
                        subtitle: tr("Decide once what should wait. Ma holds the line when you would rather not.", "Leg einmal fest, was warten soll. Ma hält die Linie, wenn du es gerade nicht willst.")
                    )

                    LockdownCard()

                    if model.authorization != .approved {
                        permissionCard
                    }

                    // Screen Time boundaries need Apple's approval. Without it the
                    // picker cannot open, so the preview only offers Shortcuts mode.
                    if BuildFlavor.screenTimeAvailable {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(icon: "shield.lefthalf.filled", title: tr("Your boundaries", "Deine Grenzen"))
                            if model.rules.isEmpty {
                                emptyState
                            }
                            ForEach(model.rules) { rule in
                                RuleCard(
                                    rule: rule,
                                    shielding: model.isShielding(rule),
                                    unlocksToday: model.unlocksToday(rule),
                                    locked: model.isLockedDown
                                ) {
                                    editing = rule
                                } toggle: { on in
                                    model.setEnabled(rule, on)
                                }
                            }
                            Button {
                                showTemplates = true
                            } label: {
                                Label(tr("New boundary", "Neue Grenze"), systemImage: "plus")
                            }
                            .buttonStyle(.quiet)
                        }
                    }

                    if !model.grants.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(icon: "lock.open.fill", title: tr("Open right now", "Gerade offen"))
                            VStack(spacing: 12) {
                                ForEach(model.grants) { grant in
                                    OpenGrantRow(grant: grant) { model.revoke(grant) }
                                }
                            }
                            .zenCard()
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(icon: "square.stack.3d.up.fill", title: tr("More ways", "Weitere Wege"))
                        Button {
                            model.showShortcutsSetup = true
                        } label: {
                            LinkCard(
                                icon: "bolt.fill",
                                tint: model.shortcutLastRun == nil ? Zen.inkSoft : Zen.shu,
                                title: tr("Shortcuts mode", "Kurzbefehle-Modus"),
                                subtitle: model.shortcutLastRun == nil
                                    ? tr("Pause before any app, without Screen Time. Set up once.", "Pause vor jeder App, ohne Bildschirmzeit. Einmal einrichten.")
                                    : tr("Active. One automation guards your apps.", "Aktiv. Eine Automation bewacht deine Apps.")
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            FilterView()
                        } label: {
                            LinkCard(
                                icon: "safari.fill",
                                tint: Zen.ai,
                                title: tr("Reels filter for Safari", "Reels-Filter für Safari"),
                                subtitle: tr("Instagram without Reels, YouTube without Shorts, LinkedIn without the feed.", "Instagram ohne Reels, YouTube ohne Shorts, LinkedIn ohne Feed.")
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.bottom, 40)
            }
            .background(AppBackground())
            .navigationDestination(isPresented: Binding(
                get: { model.showShortcutsSetup },
                set: { model.showShortcutsSetup = $0 }
            )) {
                ShortcutsModeView()
            }
            .sheet(isPresented: $showTemplates) {
                TemplatePickerView(isFirst: model.rules.isEmpty) { rule in
                    showTemplates = false
                    // Let the first sheet go before the editor comes up.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        editing = rule
                    }
                }
            }
            .sheet(item: $editing) { rule in
                RuleEditorView(rule: rule, isNew: !model.rules.contains { $0.id == rule.id })
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Illustration(name: "IllustrationBlock", height: 150)
            Text(tr("No boundary yet. Start with a template: social media, a calm morning, deep work or the night.", "Noch keine Grenze. Fang mit einer Vorlage an: soziale Medien, ruhiger Morgen, konzentrierte Arbeit oder die Nacht."))
                .font(.system(size: 15))
                .foregroundStyle(Zen.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .zenCard()
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconBadge(systemName: "hourglass", tint: Zen.kin)
                Text(tr("Screen Time", "Bildschirmzeit"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Zen.ink)
            }
            if !BuildFlavor.screenTimeAvailable {
                Text(BuildFlavor.previewNote)
                    .font(.system(size: 15))
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(tr("Ma needs Screen Time access, otherwise every boundary stays on paper.", "Ma braucht Zugriff auf Bildschirmzeit, sonst bleiben alle Grenzen nur auf dem Papier."))
                    .font(.system(size: 15))
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr("Allow access", "Zugriff erlauben")) {
                    Task { await model.requestScreenTime() }
                }
                .buttonStyle(.primary)
            }
        }
        .zenCard()
    }
}

struct RuleCard: View {
    let rule: BlockRule
    let shielding: Bool
    var unlocksToday = 0
    /// A lockdown is running: the switch cannot be turned off.
    var locked = false
    let edit: () -> Void
    let toggle: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(systemName: rule.icon, tint: rule.isEnabled ? Zen.shu : Zen.inkFaint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.name)
                        .font(.display(19, weight: .semibold))
                        .foregroundStyle(Zen.ink)
                    Text(summary)
                        .font(.system(size: 14))
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(get: { rule.isEnabled }, set: toggle))
                    .labelsHidden()
                    .tint(Zen.shu)
                    .disabled(locked && rule.isEnabled)
            }
            HStack(spacing: 8) {
                statusPill
                if let pill = budgetPill { pill }
                if rule.risingFriction && rule.allowsUnlock {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Zen.kin)
                        .accessibilityLabel(tr("Rising friction", "Steigende Hürde"))
                }
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

    private var statusPill: some View {
        let active = shielding && rule.isEnabled && !rule.isEmpty
        let tint: Color = active ? Zen.shu : Zen.inkSoft
        return Text(status)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private var budgetPill: Text? {
        guard rule.allowsUnlock, let limit = rule.dailyUnlockLimit else { return nil }
        let left = rule.unlocksLeft(usedToday: unlocksToday) ?? 0
        let tint: Color = left == 0 ? Zen.negative : Zen.inkSoft
        return Text(tr("\(unlocksToday) of \(limit) today", "\(unlocksToday) von \(limit) heute"))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
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
        return parts.joined(separator: ", ")
    }

    private var status: String {
        if !rule.isEnabled { return tr("Off", "Aus") }
        if rule.isEmpty { return tr("Empty", "Leer") }
        if !shielding { return tr("Resting", "Ruht") }
        if !rule.allowsUnlock { return tr("Active, no way through", "Aktiv, ohne Ausweg") }
        if rule.budgetSpent(usedToday: unlocksToday) { return tr("Active, closed for today", "Aktiv, heute zu") }
        let q = rule.questionsNeeded(unlocksToday: unlocksToday)
        let questions = q == 1 ? tr("1 question", "1 Frage") : tr("\(q) questions", "\(q) Fragen")
        return tr("Active, \(questions) for \(rule.unlockMinutes) min.", "Aktiv, \(questions) für \(rule.unlockMinutes) Min.")
    }
}

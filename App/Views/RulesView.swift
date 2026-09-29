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
                        title: "Grenzen",
                        subtitle: "Ein Kekkai ist im Tempel die Linie, die den stillen Bereich vom Alltag trennt. Hier ziehst du deine."
                    )

                    if model.authorization != .approved {
                        permissionCard
                    }

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
                            rule.name = model.rules.isEmpty ? "Soziale Medien" : "Neue Grenze"
                            editing = rule
                        } label: {
                            Label("Neue Grenze ziehen", systemImage: "plus")
                        }
                        .buttonStyle(.quiet)
                    }

                    if !model.grants.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(kanji: "開", title: "Gerade offen")
                            VStack(spacing: 10) {
                                ForEach(model.grants) { grant in
                                    GrantRow(grant: grant) { model.revoke(grant) }
                                }
                            }
                            .zenCard()
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(kanji: "濾", title: "Im Browser")
                        NavigationLink {
                            FilterView()
                        } label: {
                            HStack(spacing: 14) {
                                Hanko(text: "濾", size: 40, color: Zen.ai)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Reels-Filter für Safari")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(Zen.ink)
                                    Text("Instagram ohne Reels, YouTube ohne Shorts, LinkedIn ohne Feed.")
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
            .sheet(item: $editing) { rule in
                RuleEditorView(rule: rule, isNew: !model.rules.contains { $0.id == rule.id })
            }
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ma braucht Zugriff auf Bildschirmzeit, sonst bleiben alle Grenzen nur auf dem Papier.")
                .font(.system(size: 15))
                .foregroundStyle(Zen.ink)
            Button("Zugriff erlauben") {
                Task { await model.requestScreenTime() }
            }
            .buttonStyle(.shu)
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
        if apps > 0 { parts.append("\(apps) \(apps == 1 ? "App" : "Apps")") }
        if cats > 0 { parts.append("\(cats) \(cats == 1 ? "Kategorie" : "Kategorien")") }
        if webs > 0 { parts.append("\(webs) \(webs == 1 ? "Website" : "Websites")") }
        if parts.isEmpty { parts.append("Noch nichts ausgewählt") }
        parts.append(rule.schedule?.label ?? "immer")
        return parts.joined(separator: " · ")
    }

    private var status: String {
        if !rule.isEnabled { return "ausgeschaltet" }
        if rule.isEmpty { return "leer" }
        if !shielding { return "ruht bis zum nächsten Zeitfenster" }
        if !rule.allowsUnlock { return "wacht, ohne Ausweg" }
        let q = rule.questionsRequired == 1 ? "1 Frage" : "\(rule.questionsRequired) Fragen"
        return "wacht · \(q) für \(rule.unlockMinutes) Min."
    }
}

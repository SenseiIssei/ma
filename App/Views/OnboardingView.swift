import FamilyControls
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0
    @State private var drawn = 0.0
    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false

    var body: some View {
        ZStack {
            WashiBackground()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcome.tag(0)
                    screenTime.tag(1)
                    notifications.tag(2)
                    topics.tag(3)
                    firstRule.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: page)

                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Zen.shu : Zen.line)
                            .frame(width: index == page ? 22 : 8, height: 8)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
                .padding(.bottom, 18)
            }
        }
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
    }

    // MARK: Pages

    private var welcome: some View {
        onboardingPage(
            kanji: "間",
            title: "Ma",
            text: tr(
                "In Japanese, Ma is the space between two things. The pause between two notes, the empty ground in a garden.\n\nThis app puts such a space between you and the next feed. Short, kind, and you learn something along the way.",
                "Im Japanischen ist Ma der Raum zwischen zwei Dingen. Die Pause zwischen zwei Tönen, der leere Platz im Garten.\n\nDiese App schiebt so einen Raum zwischen dich und den nächsten Feed. Kurz, freundlich, und du lernst dabei etwas."
            )
        ) {
            EnsoView(progress: drawn, lineWidth: 18, color: Zen.ink)
                .frame(width: 200, height: 200)
                .overlay(Text("間").font(.kanji(64, bold: true)).foregroundStyle(Zen.shu))
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.4)) { drawn = 1 }
                }
        } footer: {
            Button(tr("Continue", "Weiter")) { page = 1 }.buttonStyle(.ink)
        }
    }

    private var screenTime: some View {
        onboardingPage(
            kanji: "許",
            title: tr("Screen Time", "Bildschirmzeit"),
            text: tr(
                "Ma uses Apple's Screen Time to block apps. Only your iPhone knows which apps you pick, not even Ma itself: Apple hands the app anonymous placeholders.\n\nNothing leaves your device.",
                "Ma nutzt Apples Bildschirmzeit, um Apps zu sperren. Welche Apps du auswählst, sieht nur dein iPhone, nicht einmal Ma selbst: Apple gibt der App nur anonyme Platzhalter.\n\nNichts verlässt dein Gerät."
            )
        ) {
            statusBadge(done: model.authorization == .approved, doneText: tr("Allowed", "Erlaubt"), openText: tr("Not allowed yet", "Noch nicht erlaubt"))
        } footer: {
            if !BuildFlavor.screenTimeAvailable {
                Text(BuildFlavor.previewNote)
                    .font(.system(size: 14))
                    .foregroundStyle(Zen.shu)
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr("Continue", "Weiter")) { page = 2 }.buttonStyle(.ink)
            } else if model.authorization == .approved {
                Button(tr("Continue", "Weiter")) { page = 2 }.buttonStyle(.ink)
            } else {
                Button(tr("Allow access", "Zugriff erlauben")) {
                    Task { await model.requestScreenTime() }
                }
                .buttonStyle(.shu)
                Button(tr("Later", "Später")) { page = 2 }
                    .font(.system(size: 15))
                    .foregroundStyle(Zen.inkSoft)
            }
        }
    }

    private var notifications: some View {
        onboardingPage(
            kanji: "知",
            title: tr("Notifications", "Mitteilungen"),
            text: tr(
                "When you tap \"Answer a question\" on a blocked app, Ma sends you a notification that opens your question. iOS does not let the app start any other way from there.\n\nMa also tells you when a focus round is over.",
                "Wenn du auf einer gesperrten App \"Frage beantworten\" tippst, schickt dir Ma eine Mitteilung. Die öffnet deine Frage. Anders darf iOS die App von dort aus nicht starten.\n\nAußerdem sagt dir Ma, wann eine Fokusrunde vorbei ist."
            )
        ) {
            statusBadge(done: model.notificationsAllowed, doneText: tr("Allowed", "Erlaubt"), openText: tr("Not allowed yet", "Noch nicht erlaubt"))
        } footer: {
            if model.notificationsAllowed {
                Button(tr("Continue", "Weiter")) { page = 3 }.buttonStyle(.ink)
            } else {
                Button(tr("Allow notifications", "Mitteilungen erlauben")) {
                    Task {
                        await model.requestNotifications()
                        page = 3
                    }
                }
                .buttonStyle(.shu)
                Button(tr("Later", "Später")) { page = 3 }
                    .font(.system(size: 15))
                    .foregroundStyle(Zen.inkSoft)
            }
        }
    }

    private var topics: some View {
        onboardingPage(
            kanji: "学",
            title: tr("What do you want to learn?", "Was willst du lernen?"),
            text: tr(
                "Every unlock starts with a question from your topics. You can add your own topics later under Learn.",
                "Vor jeder Freigabe kommt eine Frage aus deinen Themen. Eigene Themen legst du später unter Lernen an."
            )
        ) {
            VStack(spacing: 10) {
                ForEach(model.decks.decks) { deck in
                    let active = model.decks.isActive(deck)
                    Button {
                        Haptics.tap()
                        model.decks.toggleActive(deck)
                    } label: {
                        HStack(spacing: 14) {
                            Hanko(text: deck.symbol, size: 36, color: active ? Zen.shu : Zen.inkFaint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(deck.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Zen.ink)
                                Text(tr("\(deck.cards.count) cards", "\(deck.cards.count) Karten")).font(.system(size: 13)).foregroundStyle(Zen.inkSoft)
                            }
                            Spacer()
                            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(active ? Zen.shu : Zen.line)
                        }
                        .padding(12)
                        .background(Zen.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        } footer: {
            Button(tr("Continue", "Weiter")) { page = 4 }.buttonStyle(.ink)
        }
    }

    @ViewBuilder
    private var firstRule: some View {
        if BuildFlavor.screenTimeAvailable {
            screenTimeRule
        } else {
            shortcutsRule
        }
    }

    /// Without Screen Time the first boundary is a Shortcuts automation.
    private var shortcutsRule: some View {
        onboardingPage(
            kanji: "門",
            title: tr("A pause before every app", "Eine Pause vor jeder App"),
            text: tr(
                "One automation in the Shortcuts app starts Ma whenever Instagram, YouTube, X or any app you pick opens. You set it up once, then Ma does the rest.\n\nThe next screen shows every step.",
                "Eine Automation in der Kurzbefehle-App startet Ma, sobald Instagram, YouTube, X oder eine andere App deiner Wahl geöffnet wird. Du richtest sie einmal ein, danach macht Ma den Rest.\n\nDie nächste Seite zeigt dir jeden Schritt."
            )
        ) {
            EnsoView(progress: 0.82, lineWidth: 14, color: Zen.ink)
                .frame(width: 150, height: 150)
                .overlay(Text("門").font(.kanji(46, bold: true)).foregroundStyle(Zen.shu))
        } footer: {
            Button(tr("Set it up", "Einrichten")) {
                Haptics.success()
                model.tab = .rules
                model.showShortcutsSetup = true
                model.onboarded = true
            }
            .buttonStyle(.shu)
            Button(tr("Later", "Später")) { model.onboarded = true }
                .font(.system(size: 15))
                .foregroundStyle(Zen.inkSoft)
        }
    }

    private var screenTimeRule: some View {
        let count = selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
        return onboardingPage(
            kanji: "結",
            title: tr("Your first boundary", "Deine erste Grenze"),
            text: tr(
                "Pick the apps that pull at you the most. Instagram, YouTube, X, LinkedIn, TikTok, or the whole Social category. You can change this any time.",
                "Wähl die Apps, die dich am meisten ziehen. Instagram, YouTube, X, LinkedIn, TikTok, oder gleich die ganze Kategorie Soziale Netze. Ändern kannst du das jederzeit."
            )
        ) {
            VStack(spacing: 14) {
                Button {
                    showPicker = true
                } label: {
                    HStack {
                        Image(systemName: "plus.app")
                        Text(count == 0 ? tr("Choose apps", "Apps auswählen") : tr("\(count) selected", "\(count) ausgewählt"))
                    }
                }
                .buttonStyle(.quiet)
                if !selection.applicationTokens.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(selection.applicationTokens.prefix(6)), id: \.self) { token in
                            Label(token)
                                .labelStyle(.iconOnly)
                                .scaleEffect(1.4)
                                .frame(width: 40, height: 40)
                        }
                    }
                }
            }
        } footer: {
            Button(count == 0 ? tr("Start without a boundary", "Ohne Grenze starten") : tr("Let's go", "Los geht's")) {
                if count > 0 {
                    var rule = BlockRule()
                    rule.selection = selection
                    model.save(rule)
                }
                Haptics.success()
                model.onboarded = true
            }
            .buttonStyle(count == 0 ? InkButtonStyle(kind: .quiet) : InkButtonStyle(kind: .shu))
        }
    }

    // MARK: Building blocks

    private func onboardingPage<Hero: View, Footer: View>(
        kanji: String,
        title: String,
        text: String,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 36)
                    PageTitle(kanji: kanji, title: title)
                    Text(text)
                        .font(.system(size: 17))
                        .foregroundStyle(Zen.inkSoft)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 12) {
                footer()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 16)
        }
    }

    private func statusBadge(done: Bool, doneText: String, openText: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.seal.fill" : "seal")
                .font(.system(size: 44))
                .foregroundStyle(done ? Zen.matcha : Zen.inkFaint)
            Text(done ? doneText : openText)
                .font(.mincho(20, weight: .medium))
                .foregroundStyle(done ? Zen.matcha : Zen.inkSoft)
        }
        .padding(.vertical, 30)
    }
}

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
            text: "Im Japanischen ist Ma der Raum zwischen zwei Dingen. Die Pause zwischen zwei Tönen, der leere Platz im Garten.\n\nDiese App schiebt so einen Raum zwischen dich und den nächsten Feed. Kurz, freundlich, und du lernst dabei etwas."
        ) {
            EnsoView(progress: drawn, lineWidth: 18, color: Zen.ink)
                .frame(width: 200, height: 200)
                .overlay(Text("間").font(.kanji(64, bold: true)).foregroundStyle(Zen.shu))
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.4)) { drawn = 1 }
                }
        } footer: {
            Button("Weiter") { page = 1 }.buttonStyle(.ink)
        }
    }

    private var screenTime: some View {
        onboardingPage(
            kanji: "許",
            title: "Bildschirmzeit",
            text: "Ma nutzt Apples Bildschirmzeit, um Apps zu sperren. Welche Apps du auswählst, sieht nur dein iPhone, nicht einmal Ma selbst: Apple gibt der App nur anonyme Platzhalter.\n\nNichts verlässt dein Gerät."
        ) {
            statusBadge(done: model.authorization == .approved, doneText: "Erlaubt", openText: "Noch nicht erlaubt")
        } footer: {
            if model.authorization == .approved {
                Button("Weiter") { page = 2 }.buttonStyle(.ink)
            } else {
                Button("Zugriff erlauben") {
                    Task { await model.requestScreenTime() }
                }
                .buttonStyle(.shu)
                Button("Später") { page = 2 }
                    .font(.system(size: 15))
                    .foregroundStyle(Zen.inkSoft)
            }
        }
    }

    private var notifications: some View {
        onboardingPage(
            kanji: "知",
            title: "Mitteilungen",
            text: "Wenn du auf einer gesperrten App \"Frage beantworten\" tippst, schickt dir Ma eine Mitteilung. Die öffnet deine Frage. Anders darf iOS die App von dort aus nicht starten.\n\nAußerdem sagt dir Ma, wann eine Fokusrunde vorbei ist."
        ) {
            statusBadge(done: model.notificationsAllowed, doneText: "Erlaubt", openText: "Noch nicht erlaubt")
        } footer: {
            if model.notificationsAllowed {
                Button("Weiter") { page = 3 }.buttonStyle(.ink)
            } else {
                Button("Mitteilungen erlauben") {
                    Task {
                        await model.requestNotifications()
                        page = 3
                    }
                }
                .buttonStyle(.shu)
                Button("Später") { page = 3 }
                    .font(.system(size: 15))
                    .foregroundStyle(Zen.inkSoft)
            }
        }
    }

    private var topics: some View {
        onboardingPage(
            kanji: "学",
            title: "Was willst du lernen?",
            text: "Vor jeder Freigabe kommt eine Frage aus deinen Themen. Eigene Themen legst du später unter Lernen an."
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
                                Text("\(deck.cards.count) Karten").font(.system(size: 13)).foregroundStyle(Zen.inkSoft)
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
            Button("Weiter") { page = 4 }.buttonStyle(.ink)
        }
    }

    private var firstRule: some View {
        let count = selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
        return onboardingPage(
            kanji: "結",
            title: "Deine erste Grenze",
            text: "Wähl die Apps, die dich am meisten ziehen. Instagram, YouTube, X, LinkedIn, TikTok, oder gleich die ganze Kategorie Soziale Netze. Ändern kannst du das jederzeit."
        ) {
            VStack(spacing: 14) {
                Button {
                    showPicker = true
                } label: {
                    HStack {
                        Image(systemName: "plus.app")
                        Text(count == 0 ? "Apps auswählen" : "\(count) ausgewählt")
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
            Button(count == 0 ? "Ohne Grenze starten" : "Los geht's") {
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

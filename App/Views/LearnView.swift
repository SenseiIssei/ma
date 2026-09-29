import SwiftUI
import UniformTypeIdentifiers

struct LearnView: View {
    @Environment(AppModel.self) private var model
    @State private var lesson: QuizSession?
    @State private var newDeck: Deck?
    @State private var importing = false
    @State private var creatingWithAI = false
    @State private var message: String?
    /// nil shows every shelf.
    @State private var shelf: DeckCategory?

    private var store: DeckStore { model.decks }

    private var shelves: [DeckCategory] {
        let present = Set(store.decks.map { DeckCategory(deck: $0) })
        return DeckCategory.allCases.filter { present.contains($0) }
    }

    private var shownDecks: [Deck] {
        guard let shelf else { return store.decks }
        return store.decks.filter { DeckCategory(deck: $0) == shelf }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    Illustration(name: "IllustrationLearn", height: 170)
                    goalCard
                    nextLessonCard

                    SectionHeader(icon: "books.vertical.fill", title: tr("Topics", "Themen")) {
                        addMenu
                    }
                    .padding(.top, 6)
                    Text(tr("Questions before an unlock come from the topics with a check mark.", "Die Fragen vor einer Freigabe kommen aus den Themen mit Haken."))
                        .font(.system(size: 14))
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, -12)

                    if store.decks.isEmpty {
                        emptyState
                    } else {
                        shelfPicker
                        VStack(spacing: 12) {
                            ForEach(shownDecks) { deck in
                                NavigationLink(value: deck.id) {
                                    DeckRow(
                                        deck: deck,
                                        active: store.isActive(deck),
                                        mastery: store.mastery(of: deck),
                                        due: store.dueCount(in: deck),
                                        counts: store.counts(in: deck)
                                    ) {
                                        store.toggleActive(deck)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if let message {
                        Label(message, systemImage: "info.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(Zen.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.bottom, 40)
            }
            .background(AppBackground())
            .navigationDestination(for: String.self) { id in
                DeckDetailView(deckID: id)
            }
            .fullScreenCover(item: $lesson) { session in
                LessonScreen(session: session) { lesson = nil }
            }
            .sheet(item: $newDeck) { deck in
                DeckEditorView(deck: deck, isNew: true)
            }
            .sheet(isPresented: $creatingWithAI) {
                CreateTopicView { deck in
                    message = tr("\(deck.title) is ready with \(deck.cards.count) cards and already checked for questions.",
                                 "\(deck.title) ist fertig, mit \(deck.cards.count) Karten, und schon für Fragen aktiv.")
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: true) { result in
                importFiles(result)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("Learn", "Lernen"))
                .font(.display(34))
                .foregroundStyle(Zen.ink)
            Text(tr("New cards are explained first, then practised. Just like a real lesson.", "Neue Karten werden erst erklärt, dann geübt. Wie in einer richtigen Lektion."))
                .font(.system(size: 15))
                .foregroundStyle(Zen.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: Cards

    private var goalCard: some View {
        let goal = max(1, store.profile.dailyGoal)
        let done = model.today.correct
        let ratio = min(1, Double(done) / Double(goal))
        let reached = done >= goal
        let streak = store.currentStreak
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                ZStack {
                    ProgressRing(progress: ratio, lineWidth: 10, tint: reached ? Zen.matcha : Zen.shu)
                    VStack(spacing: 0) {
                        Text("\(min(done, goal))")
                            .font(.display(22))
                            .monospacedDigit()
                            .foregroundStyle(Zen.ink)
                        Text("/ \(goal)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Zen.inkFaint)
                    }
                }
                .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text(reached ? tr("Daily goal reached", "Tagesziel erreicht") : tr("Daily goal", "Tagesziel"))
                        .font(.display(19, weight: .semibold))
                        .foregroundStyle(Zen.ink)
                    Text(reached ? tr("Anything more today is a bonus.", "Alles Weitere heute ist Bonus.") : tr("\(goal - done) right answers to go.", "Noch \(goal - done) richtige Antworten."))
                        .font(.system(size: 14))
                        .foregroundStyle(Zen.inkSoft)
                }
                Spacer(minLength: 0)
            }
            Rectangle().fill(Zen.line).frame(height: 1)
            HStack(spacing: 12) {
                StatTile(icon: "flame.fill", value: "\(streak)", label: streak == 1 ? tr("day streak", "Tag in Folge") : tr("day streak", "Tage in Folge"), tint: Zen.kin)
                StatTile(icon: "star.fill", value: "\(store.profile.xp)", label: "XP", tint: Zen.kin)
                StatTile(icon: "checkmark.seal.fill", value: "\(store.counts(in: store.decks).known)", label: tr("cards known", "Karten sicher"), tint: Zen.matcha)
            }
        }
        .zenCard()
    }

    private var nextLessonCard: some View {
        let decks = store.activeDecks
        let counts = store.counts(in: decks)
        let due = store.dueCount(in: decks)
        let hasNew = counts.new > 0
        let canPractise = counts.new + counts.introduced > 0
        let title = hasNew ? tr("Learn something new", "Lern etwas Neues") : tr("Keep it fresh", "Frisch halten")
        let subtitle = hasNew
            ? tr("Up to 3 new cards, explained first, then practised with what you already know.", "Bis zu 3 neue Karten, erst erklärt, dann zusammen mit Bekanntem geübt.")
            : tr("Everything has been introduced. Now it is about remembering.", "Alles ist eingeführt. Jetzt geht es ums Behalten.")
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(systemName: hasNew ? "sparkles" : "arrow.triangle.2.circlepath", tint: hasNew ? Zen.shu : Zen.ai, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.display(19, weight: .semibold))
                        .foregroundStyle(Zen.ink)
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                CountPill(icon: "sparkles", text: tr("\(counts.new) new", "\(counts.new) neu"), tint: Zen.shu)
                CountPill(icon: "clock.arrow.circlepath", text: tr("\(due) due", "\(due) fällig"), tint: Zen.kin)
            }
            Button {
                lesson = QuizSession(mode: .lesson(count: 8), store: store)
            } label: {
                Label(hasNew ? tr("Start lesson", "Lektion starten") : tr("Review", "Wiederholen"), systemImage: "play.fill")
            }
            .buttonStyle(.primary)
            .disabled(!canPractise)
            .opacity(canPractise ? 1 : 0.4)
        }
        .zenCard()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Illustration(name: "IllustrationEmpty", height: 160)
            Text(tr("No topics yet", "Noch keine Themen"))
                .font(.display(20, weight: .semibold))
                .foregroundStyle(Zen.ink)
            Text(tr("Create one with the plus button, or import a deck.", "Leg eins über das Plus an oder importier ein Deck."))
                .font(.system(size: 14))
                .foregroundStyle(Zen.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .zenCard()
    }

    /// Horizontal shelf chips: all topics or one category.
    private var shelfPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: tr("All", "Alle"), selected: shelf == nil) { shelf = nil }
                ForEach(shelves) { category in
                    Button {
                        Haptics.tap()
                        shelf = shelf == category ? nil : category
                    } label: {
                        Label(category.title, systemImage: category.icon)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(shelf == category ? Color.white : Zen.ink)
                            .padding(.vertical, 9)
                            .padding(.horizontal, 14)
                            .background(shelf == category ? AnyShapeStyle(Zen.shu) : AnyShapeStyle(Zen.sand), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var addMenu: some View {
        Menu {
            Button {
                newDeck = Deck(title: "", symbol: "学")
            } label: {
                Label(tr("New topic", "Neues Thema"), systemImage: "square.and.pencil")
            }
            Button {
                creatingWithAI = true
            } label: {
                Label(tr("Create a topic with AI", "Thema mit KI erstellen"), systemImage: "wand.and.stars")
            }
            Button {
                importing = true
            } label: {
                Label(tr("Import JSON file", "JSON-Datei importieren"), systemImage: "doc.badge.plus")
            }
            Button {
                importFromClipboard()
            } label: {
                Label(tr("JSON from clipboard", "JSON aus Zwischenablage"), systemImage: "doc.on.clipboard")
            }
            Button {
                UIPasteboard.general.string = DeckPrompt.text
                message = tr("Template copied. Paste it into a chat with any AI, fill in your topic and import the result from the clipboard.", "Vorlage kopiert. Füg sie in einen Chat mit einer KI deiner Wahl ein, trag dein Thema ein und importier das Ergebnis über die Zwischenablage.")
            } label: {
                Label(tr("Copy AI template", "KI-Vorlage kopieren"), systemImage: "sparkles")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Zen.shu)
        }
        .accessibilityLabel(tr("Add topic", "Thema hinzufügen"))
    }

    // MARK: Import

    private func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            message = tr("Import cancelled.", "Import abgebrochen.")
            return
        }
        var count = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let decks = try? store.importDecks(from: data) {
                count += decks.count
            }
        }
        message = count == 0 ? tr("No valid topics found. Is the format right?", "Keine gültigen Themen gefunden. Stimmt das Format?") : tr("\(count) \(count == 1 ? "topic" : "topics") imported.", "\(count) \(count == 1 ? "Thema" : "Themen") importiert.")
    }

    private func importFromClipboard() {
        guard var text = UIPasteboard.general.string else {
            message = tr("The clipboard is empty.", "Die Zwischenablage ist leer.")
            return
        }
        // Chat answers often wrap JSON in a code fence.
        if let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }),
           let end = text.lastIndex(where: { $0 == "}" || $0 == "]" }), start < end {
            text = String(text[start...end])
        }
        do {
            let decks = try store.importDecks(from: Data(text.utf8))
            message = tr("\(decks.count) \(decks.count == 1 ? "topic" : "topics") imported: \(decks.map(\.title).joined(separator: ", ")).", "\(decks.count) \(decks.count == 1 ? "Thema" : "Themen") importiert: \(decks.map(\.title).joined(separator: ", ")).")
        } catch {
            message = tr("That does not look like a Ma topic. The AI template shows the format.", "Das sieht nicht nach einem Ma-Thema aus. Die KI-Vorlage zeigt das Format.")
        }
    }
}

/// Small tinted capsule with an icon, for counts like "3 new".
struct CountPill: View {
    let icon: String
    let text: String
    var tint: Color = Zen.shu

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct DeckRow: View {
    let deck: Deck
    let active: Bool
    let mastery: Double
    let due: Int
    var counts: DeckCounts? = nil
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // The deck's own symbol is content (a kana, a kanji), not decoration.
            Hanko(text: deck.symbol, size: 48, color: active ? Zen.shu : Zen.inkFaint)

            VStack(alignment: .leading, spacing: 6) {
                Text(deck.title)
                    .font(.display(18, weight: .semibold))
                    .foregroundStyle(Zen.ink)
                    .lineLimit(1)
                if !deck.subtitle.isEmpty {
                    Text(deck.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Zen.inkSoft)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    InkProgress(value: mastery, color: Zen.matcha, height: 6)
                    Text("\(Int(mastery * 100)) %")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Zen.inkSoft)
                        .frame(width: 42, alignment: .trailing)
                }
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(due > 0 ? Zen.kin : Zen.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Button {
                Haptics.tap()
                toggle()
            } label: {
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(active ? Zen.shu : Zen.inkFaint)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(active ? tr("Used for questions", "Für Fragen aktiv") : tr("Not used for questions", "Für Fragen inaktiv"))
        }
        .zenCard()
    }

    private var detail: String {
        var parts: [String] = []
        if let counts {
            parts.append(tr("\(counts.new) new", "\(counts.new) neu"))
            parts.append(tr("\(counts.learning) learning", "\(counts.learning) in Arbeit"))
            parts.append(tr("\(counts.known) known", "\(counts.known) sicher"))
        } else {
            parts.append(tr("\(deck.cards.count) cards", "\(deck.cards.count) Karten"))
        }
        if due > 0 { parts.append(tr("\(due) due", "\(due) fällig")) }
        return parts.joined(separator: " · ")
    }
}

/// Full-screen lesson with a close button and a small celebration at the end.
struct LessonScreen: View {
    @Environment(AppModel.self) private var model
    let session: QuizSession
    let close: () -> Void
    @State private var done = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Zen.inkSoft)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(tr("Close", "Schließen"))
                    Spacer()
                }
                .padding(.horizontal, 8)

                if done || session.finished {
                    LessonSummary(session: session, streak: model.decks.currentStreak, close: close)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    QuizView(session: session) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { done = true }
                        model.reload()
                    }
                }
            }
        }
    }
}

/// End of a lesson: accuracy ring, XP, cards learned.
struct LessonSummary: View {
    let session: QuizSession
    let streak: Int
    let close: () -> Void
    @State private var shown = false

    private var empty: Bool { session.exercises.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    if empty {
                        emptyContent
                    } else {
                        content
                    }
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            Button(tr("Done", "Fertig"), action: close)
                .buttonStyle(.primary)
                .padding(.horizontal, Zen.gutter)
                .padding(.bottom, 20)
        }
        .onAppear {
            if !empty { Haptics.success() }
            withAnimation(.easeOut(duration: 1.0).delay(0.2)) { shown = true }
        }
    }

    private var content: some View {
        let accuracy = session.accuracy
        let percent = Int((accuracy * 100).rounded())
        let answered = session.correct + session.wrong
        let learned = session.learned
        return VStack(spacing: 20) {
            Illustration(name: "IllustrationLearn", height: 170)

            ZStack {
                ProgressRing(progress: shown ? accuracy : 0, lineWidth: 14, tint: Zen.matcha)
                VStack(spacing: 0) {
                    Text("\(percent) %")
                        .font(.display(32))
                        .monospacedDigit()
                        .foregroundStyle(Zen.ink)
                    Text(tr("right", "richtig"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Zen.inkSoft)
                }
            }
            .frame(width: 150, height: 150)

            VStack(spacing: 6) {
                Text(tr("Lesson complete", "Lektion geschafft"))
                    .font(.display(30))
                    .foregroundStyle(Zen.ink)
                Text(tr("\(session.correct) of \(answered) answers right", "\(session.correct) von \(answered) Antworten richtig"))
                    .font(.system(size: 16))
                    .foregroundStyle(Zen.inkSoft)
            }
            .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                StatTile(icon: "star.fill", value: "+\(session.xpEarned)", label: "XP", tint: Zen.kin)
                StatTile(icon: "lightbulb.fill", value: "\(learned)", label: learned == 1 ? tr("new card", "neue Karte") : tr("new cards", "neue Karten"), tint: Zen.ai)
                StatTile(icon: "flame.fill", value: "\(streak)", label: streak == 1 ? tr("day streak", "Tag in Folge") : tr("day streak", "Tage in Folge"), tint: Zen.kin)
            }
            .zenCard()
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 16) {
            Illustration(name: "IllustrationEmpty", height: 200)
            Text(tr("Nothing to learn here yet", "Hier gibt es noch nichts zu lernen"))
                .font(.display(24))
                .foregroundStyle(Zen.ink)
                .multilineTextAlignment(.center)
            Text(tr("Add a few cards to this topic, then come back.", "Leg ein paar Karten in diesem Thema an und komm dann wieder."))
                .font(.system(size: 15))
                .foregroundStyle(Zen.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }
}

/// A prompt for any chat assistant that returns a deck in Ma's format.
enum DeckPrompt {
    static var text: String { Loc.isGerman ? german : english }

    static let english = """
    Create a learning deck on the topic: <YOUR TOPIC HERE>

    Reply with JSON only, in exactly this format, no explanation:
    {
      "title": "Short title",
      "subtitle": "One line on what it covers",
      "symbol": "a single kanji that fits the topic",
      "cards": [
        {
          "prompt": "Question",
          "answer": "short correct answer (30 characters at most)",
          "accept": ["other accepted spellings"],
          "distractors": ["wrong 1", "wrong 2", "wrong 3"],
          "example": "A sentence that contains the answer word for word",
          "note": "1 to 2 sentences of explanation that help learning"
        }
      ]
    }

    Rules: 25 cards. Short answers. Wrong answers plausible and in the same style as the right one. Only include "example" if the sentence contains the answer exactly. For sentence-building exercises the answer can be a sentence whose words are separated by single spaces. Facts must be correct.
    """

    static let german = """
    Erstelle ein Lern-Deck zum Thema: <DEIN THEMA HIER>

    Antworte nur mit JSON in genau diesem Format, ohne Erklärtext:
    {
      "title": "Kurzer Titel",
      "subtitle": "Eine Zeile, worum es geht",
      "symbol": "ein einzelnes Kanji, das zum Thema passt",
      "cards": [
        {
          "prompt": "Frage",
          "answer": "kurze richtige Antwort (höchstens 30 Zeichen)",
          "accept": ["andere akzeptierte Schreibweisen"],
          "distractors": ["falsch 1", "falsch 2", "falsch 3"],
          "example": "Ein Satz, der die Antwort wörtlich enthält",
          "note": "1 bis 2 Sätze Erklärung, die beim Lernen hilft"
        }
      ]
    }

    Regeln: 25 Karten. Antworten kurz. Falsche Antworten plausibel und im selben Stil wie die richtige. "example" nur, wenn der Satz die Antwort exakt enthält. Für Satzbau-Übungen kann die Antwort ein Satz sein, dessen Wörter durch einzelne Leerzeichen getrennt sind. Fakten müssen stimmen.
    """
}

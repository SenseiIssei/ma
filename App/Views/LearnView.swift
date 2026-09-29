import SwiftUI
import UniformTypeIdentifiers

struct LearnView: View {
    @Environment(AppModel.self) private var model
    @State private var lesson: QuizSession?
    @State private var newDeck: Deck?
    @State private var importing = false
    @State private var message: String?

    private var store: DeckStore { model.decks }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageTitle(
                        kanji: "学び",
                        title: tr("Learn", "Lernen"),
                        subtitle: tr("Every question before an unlock comes from the topics that carry a red seal here.", "Jede Frage vor einer Freigabe kommt aus den Themen, die hier ein rotes Siegel tragen.")
                    )
                    progressCard
                    Button {
                        lesson = QuizSession(mode: .lesson(count: 8), store: store)
                    } label: {
                        Label(tr("Start a lesson", "Lektion starten"), systemImage: "play.fill")
                    }
                    .buttonStyle(.shu)

                    SectionHeader(kanji: "題", title: tr("Topics", "Themen")) {
                        addMenu
                    }
                    VStack(spacing: 12) {
                        ForEach(store.decks) { deck in
                            NavigationLink(value: deck.id) {
                                DeckRow(deck: deck, active: store.isActive(deck), mastery: store.mastery(of: deck), due: store.dueCount(in: deck)) {
                                    store.toggleActive(deck)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let message {
                        Text(message)
                            .font(.system(size: 14))
                            .foregroundStyle(Zen.inkSoft)
                    }
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.bottom, 40)
            }
            .background(WashiBackground())
            .navigationDestination(for: String.self) { id in
                DeckDetailView(deckID: id)
            }
            .fullScreenCover(item: $lesson) { session in
                LessonScreen(session: session) { lesson = nil }
            }
            .sheet(item: $newDeck) { deck in
                DeckEditorView(deck: deck, isNew: true)
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: true) { result in
                importFiles(result)
            }
        }
    }

    private var progressCard: some View {
        let goal = max(1, store.profile.dailyGoal)
        let done = model.today.correct
        return HStack(spacing: 18) {
            ZStack {
                EnsoView(progress: max(0.04, min(1, Double(done) / Double(goal))), lineWidth: 8, color: Zen.shu)
                Text("\(min(done, goal))")
                    .font(.mincho(20, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Zen.ink)
            }
            .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(done >= goal ? tr("Daily goal reached", "Tagesziel erreicht") : tr("\(goal - done) to your daily goal", "\(goal - done) bis zum Tagesziel"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Zen.ink)
                Text(tr("\(store.profile.xp) XP · \(store.currentStreak) \(store.currentStreak == 1 ? "day" : "days") in a row", "\(store.profile.xp) Erfahrung · \(store.currentStreak) \(store.currentStreak == 1 ? "Tag" : "Tage") in Folge"))
                    .font(.system(size: 14))
                    .foregroundStyle(Zen.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .zenCard()
    }

    private var addMenu: some View {
        Menu {
            Button {
                newDeck = Deck(title: "", symbol: "学")
            } label: {
                Label(tr("New topic", "Neues Thema"), systemImage: "square.and.pencil")
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
                .font(.system(size: 22))
                .foregroundStyle(Zen.shu)
        }
        .accessibilityLabel(tr("Add topic", "Thema hinzufügen"))
    }

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

struct DeckRow: View {
    let deck: Deck
    let active: Bool
    let mastery: Double
    let due: Int
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button {
                Haptics.tap()
                toggle()
            } label: {
                Hanko(text: deck.symbol, size: 48, color: active ? Zen.shu : Zen.inkFaint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(active ? tr("Used for questions", "Für Fragen aktiv") : tr("Not used for questions", "Für Fragen inaktiv"))

            VStack(alignment: .leading, spacing: 6) {
                Text(deck.title)
                    .font(.mincho(19, weight: .semibold))
                    .foregroundStyle(Zen.ink)
                if !deck.subtitle.isEmpty {
                    Text(deck.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Zen.inkSoft)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    InkProgress(value: mastery, color: Zen.matcha, height: 5)
                    Text("\(Int(mastery * 100)) %")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Zen.inkSoft)
                        .frame(width: 42, alignment: .trailing)
                }
                Text(due > 0 ? tr("\(deck.cards.count) cards · \(due) to review", "\(deck.cards.count) Karten · \(due) zum Wiederholen") : tr("\(deck.cards.count) cards", "\(deck.cards.count) Karten"))
                    .font(.system(size: 12))
                    .foregroundStyle(due > 0 ? Zen.shu : Zen.inkFaint)
            }
            Image(systemName: "chevron.right").foregroundStyle(Zen.inkFaint)
        }
        .zenCard()
    }
}

/// Full-screen lesson with a close button and a small summary at the end.
struct LessonScreen: View {
    @Environment(AppModel.self) private var model
    let session: QuizSession
    let close: () -> Void
    @State private var done = false

    var body: some View {
        ZStack {
            WashiBackground()
            VStack(spacing: 0) {
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Zen.inkSoft)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)

                if done || session.finished {
                    summary
                } else {
                    QuizView(session: session) {
                        withAnimation { done = true }
                        model.reload()
                    }
                }
            }
        }
    }

    private var summary: some View {
        VStack(spacing: 22) {
            Spacer()
            EnsoView(progress: 1, lineWidth: 16, color: Zen.ink)
                .frame(width: 180, height: 180)
                .overlay(Text("良").font(.kanji(56, bold: true)).foregroundStyle(Zen.shu))
            Text(session.exercises.isEmpty ? tr("No cards yet", "Noch keine Karten") : tr("Lesson done", "Lektion geschafft"))
                .font(.mincho(30, weight: .semibold))
                .foregroundStyle(Zen.ink)
            if !session.exercises.isEmpty {
                Text(tr("\(session.correct) of \(session.correct + session.wrong) right · +\(session.correct * 10) XP", "\(session.correct) von \(session.correct + session.wrong) richtig · +\(session.correct * 10) Erfahrung"))
                    .font(.system(size: 16))
                    .foregroundStyle(Zen.inkSoft)
            }
            Spacer()
            Button(tr("Done", "Fertig"), action: close)
                .buttonStyle(.ink)
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
        }
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

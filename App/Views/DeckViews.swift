import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct DeckDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let deckID: String
    @State private var lesson: QuizSession?
    @State private var editing: Deck?
    @State private var confirmDelete = false
    @State private var writingMore = false

    private var store: DeckStore { model.decks }

    var body: some View {
        Group {
            if let deck = store.deck(id: deckID) {
                content(deck)
            } else {
                VStack(spacing: 14) {
                    Illustration(name: "IllustrationEmpty", height: 160)
                    Text(tr("This topic no longer exists.", "Dieses Thema gibt es nicht mehr."))
                        .foregroundStyle(Zen.inkSoft)
                }
                .padding(Zen.gutter)
            }
        }
        .background(AppBackground())
        .fullScreenCover(item: $lesson) { session in
            LessonScreen(session: session) { lesson = nil }
        }
        .sheet(item: $editing) { deck in
            DeckEditorView(deck: deck, isNew: false)
        }
        .sheet(isPresented: $writingMore) {
            MoreCardsView(deckID: deckID)
        }
    }

    private func content(_ deck: Deck) -> some View {
        let counts = store.counts(in: deck)
        let due = store.dueCount(in: deck)
        let active = store.isActive(deck)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 16) {
                    Hanko(text: deck.symbol, size: 64, color: active ? Zen.shu : Zen.inkFaint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(deck.title)
                            .displayFont(28)
                            .foregroundStyle(Zen.ink)
                        if !deck.subtitle.isEmpty {
                            Text(deck.subtitle)
                                .scaledFont(size: 15)
                                .foregroundStyle(Zen.inkSoft)
                        }
                    }
                }
                .padding(.top, 8)

                statsCard(deck, counts: counts)
                learnCard(deck, counts: counts, due: due)

                Button {
                    Haptics.tap()
                    store.toggleActive(deck)
                } label: {
                    Label(active ? tr("Used for unlock questions", "Für Freigabe-Fragen aktiv") : tr("Use for unlock questions", "Für Freigabe-Fragen nutzen"),
                          systemImage: active ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.quiet)

                SectionHeader(icon: "rectangle.stack.fill", title: tr("Cards", "Karten")) {
                    HStack(spacing: 16) {
                        ShareLink(item: DeckFile(data: store.exportData(deck), name: deck.title), preview: SharePreview(deck.title)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(tr("Export", "Exportieren"))
                        if !deck.isBuiltIn {
                            Button {
                                editing = deck
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .accessibilityLabel(tr("Edit", "Bearbeiten"))
                        }
                    }
                    .foregroundStyle(Zen.shu)
                }

                if deck.cards.isEmpty {
                    VStack(spacing: 12) {
                        Illustration(name: "IllustrationEmpty", height: 150)
                        Text(tr("No cards yet. Add some with the pencil.", "Noch keine Karten. Leg welche über den Stift an."))
                            .scaledFont(size: 14)
                            .foregroundStyle(Zen.inkSoft)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .zenCard()
                } else {
                    VStack(spacing: 0) {
                        ForEach(deck.cards) { card in
                            let p = store.progress(of: card, in: deck)
                            CardLine(card: card, box: p.box, introduced: p.introduced)
                            if card.id != deck.cards.last?.id {
                                Divider().overlay(Zen.line)
                            }
                        }
                    }
                    .zenCard(padding: 6)
                }

                // Only own decks grow: bundled ones ship in two languages with matching card ids.
                if !deck.isBuiltIn && !deck.cards.isEmpty {
                    Button {
                        writingMore = true
                    } label: {
                        Label(tr("Make more cards like these", "Mehr Karten wie diese"), systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.quiet)
                }

                if !deck.isBuiltIn {
                    Button(tr("Delete topic", "Thema löschen"), role: .destructive) {
                        confirmDelete = true
                    }
                    .foregroundStyle(Zen.negative)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .confirmationDialog(tr("Delete \(deck.title)?", "\(deck.title) löschen?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button(tr("Delete", "Löschen"), role: .destructive) {
                            store.delete(deck)
                            dismiss()
                        }
                    }
                }
            }
            .padding(.horizontal, Zen.gutter)
            .padding(.bottom, 40)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statsCard(_ deck: Deck, counts: DeckCounts) -> some View {
        let total = max(1, counts.total)
        let known = Double(counts.known) / Double(total)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                StatTile(icon: "sparkles", value: "\(counts.new)", label: tr("new", "neu"), tint: Zen.shu)
                StatTile(icon: "arrow.triangle.2.circlepath", value: "\(counts.learning)", label: tr("learning", "in Arbeit"), tint: Zen.kin)
                StatTile(icon: "checkmark.seal.fill", value: "\(counts.known)", label: tr("known", "sicher"), tint: Zen.matcha)
            }
            InkProgress(value: known, color: Zen.matcha, height: 8)
                .accessibilityMeter(tr("Known", "Sicher"), value: known.formatted(.percent.precision(.fractionLength(0))))
        }
        .zenCard()
    }

    private func learnCard(_ deck: Deck, counts: DeckCounts, due: Int) -> some View {
        let hasNew = counts.new > 0
        let canReview = counts.introduced > 0
        let size = min(8, max(1, deck.cards.count))
        let subtitle: String
        if deck.cards.isEmpty {
            subtitle = tr("Add cards first, then you can learn them here.", "Leg zuerst Karten an, dann kannst du sie hier lernen.")
        } else if hasNew {
            subtitle = tr("Up to 3 new cards, each explained before you practise it.", "Bis zu 3 neue Karten, jede wird erklärt, bevor du sie übst.")
        } else {
            subtitle = tr("All cards introduced. Review keeps them in your head.", "Alle Karten eingeführt. Wiederholen hält sie im Kopf.")
        }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(systemName: "graduationcap.fill", tint: Zen.shu, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Learn", "Lernen"))
                        .displayFont(19, weight: .semibold)
                        .foregroundStyle(Zen.ink)
                    Text(subtitle)
                        .scaledFont(size: 14)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if hasNew {
                Button {
                    lesson = QuizSession(mode: .lesson(count: size), store: store, decks: [deck])
                } label: {
                    Label(tr("Learn new cards", "Neue Karten lernen"), systemImage: "sparkles")
                }
                .buttonStyle(.primary)
            }
            if canReview {
                Button {
                    lesson = QuizSession(mode: .review(count: size), store: store, decks: [deck])
                } label: {
                    Label(due > 0 ? tr("Review \(due) due", "\(due) fällige wiederholen") : tr("Review", "Wiederholen"), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(hasNew ? InkButtonStyle(kind: .quiet) : InkButtonStyle(kind: .shu))
            }
        }
        .zenCard()
    }
}

struct CardLine: View {
    let card: Card
    let box: Int
    var introduced = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.prompt)
                    .cardFont(for: card.prompt, kanji: 18, bold: true, size: 16, weight: .medium)
                    .foregroundStyle(Zen.ink)
                Text(card.answer)
                    .cardFont(for: card.answer, kanji: 15, size: 14)
                    .foregroundStyle(Zen.inkSoft)
            }
            Spacer(minLength: 8)
            if introduced {
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { index in
                        Circle()
                            .fill(index < box ? Zen.matcha : Zen.line)
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tr("Level \(box) of 5", "Stufe \(box) von 5"))
            } else {
                Text(tr("New", "Neu"))
                    .scaledFont(size: 12, weight: .semibold, design: .rounded)
                    .foregroundStyle(Zen.shu)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Zen.shu.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // One stop per card: prompt, answer and level together.
        .accessibilityElement(children: .combine)
    }
}

/// Exported deck as a real .json file, so it lands in Files or AirDrop.
struct DeckFile: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName { "\($0.name).json" }
    }
}

// MARK: - Editor

struct DeckEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var deck: Deck
    let isNew: Bool
    @State private var editingCard: Card?
    @State private var bulk = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(tr("Title, e.g. Korean or Anatomy", "Titel, z. B. Koreanisch oder Anatomie"), text: $deck.title)
                        .displayFont(19, weight: .semibold)
                    TextField(tr("What is it about?", "Worum geht es?"), text: $deck.subtitle)
                    HStack {
                        Text(tr("Symbol", "Symbol"))
                        Spacer()
                        TextField("学", text: Binding(
                            get: { deck.symbol },
                            set: { deck.symbol = String($0.suffix(1)) }
                        ))
                        .multilineTextAlignment(.center)
                        .kanjiFont(22, bold: true)
                        .frame(width: 60)
                    }
                } header: {
                    Text(tr("Topic", "Thema"))
                } footer: {
                    Text(tr("One character that stands for the topic, shown next to its name.", "Ein Zeichen, das für das Thema steht und neben dem Namen erscheint."))
                }

                Section {
                    ForEach(deck.cards) { card in
                        Button {
                            editingCard = card
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.prompt).foregroundStyle(Zen.ink)
                                Text(card.answer).scaledFont(size: 14).foregroundStyle(Zen.inkSoft)
                            }
                        }
                    }
                    .onDelete { deck.cards.remove(atOffsets: $0) }
                    .onMove { deck.cards.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        editingCard = Card(prompt: "", answer: "")
                    } label: {
                        Label(tr("Add card", "Karte hinzufügen"), systemImage: "plus")
                    }
                    Button {
                        bulk = true
                    } label: {
                        Label(tr("Paste many at once", "Viele auf einmal einfügen"), systemImage: "list.bullet.rectangle")
                    }
                } header: {
                    Text(tr("\(deck.cards.count) cards", "\(deck.cards.count) Karten"))
                } footer: {
                    Text(tr("From four cards on, Ma builds choice, gap, pair and typing exercises from them.", "Ab vier Karten baut Ma daraus Auswahl-, Lücken-, Paar- und Schreibübungen."))
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(isNew ? tr("New topic", "Neues Thema") : tr("Edit topic", "Thema bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Save", "Sichern")) {
                        var saved = deck
                        if saved.title.trimmingCharacters(in: .whitespaces).isEmpty { saved.title = tr("My topic", "Mein Thema") }
                        if saved.symbol.isEmpty { saved.symbol = "学" }
                        model.decks.upsert(saved)
                        if isNew { model.decks.profile.activeDeckIDs.insert(saved.id) }
                        Haptics.success()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(item: $editingCard) { card in
                CardEditorView(card: card) { updated in
                    if let index = deck.cards.firstIndex(where: { $0.id == updated.id }) {
                        deck.cards[index] = updated
                    } else {
                        deck.cards.append(updated)
                    }
                }
            }
            .sheet(isPresented: $bulk) {
                BulkCardsView { cards in
                    deck.cards.append(contentsOf: cards)
                }
            }
        }
    }
}

struct CardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var card: Card
    let save: (Card) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(tr("Question", "Frage"), text: $card.prompt, axis: .vertical)
                    TextField(tr("Right answer", "Richtige Antwort"), text: $card.answer)
                } header: {
                    Text(tr("Card", "Karte"))
                }
                Section {
                    TextField(tr("Wrong answers, separated by commas", "Falsche Antworten, durch Komma getrennt"), text: listBinding(\.distractors), axis: .vertical)
                    TextField(tr("Also right, separated by commas", "Auch richtig, durch Komma getrennt"), text: listBinding(\.accept), axis: .vertical)
                } header: {
                    Text(tr("Optional", "Optional"))
                } footer: {
                    Text(tr("Without wrong answers Ma borrows some from other cards.", "Ohne falsche Antworten leiht sich Ma welche von anderen Karten."))
                }
                Section {
                    TextField(tr("Example sentence containing the answer", "Beispielsatz, der die Antwort enthält"), text: optionalBinding(\.example), axis: .vertical)
                    TextField(tr("Explanation after answering", "Erklärung nach dem Antworten"), text: optionalBinding(\.note), axis: .vertical)
                } footer: {
                    Text(tr("Both appear when the card is first taught and after every answer, that is where the learning happens. With an example sentence you also get gap texts.", "Beides erscheint, wenn die Karte zum ersten Mal erklärt wird, und nach jeder Antwort. Dort passiert das eigentliche Lernen. Mit Beispielsatz gibt es außerdem Lückentexte."))
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(tr("Card", "Karte"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Fertig")) {
                        save(card)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(card.prompt.trimmingCharacters(in: .whitespaces).isEmpty || card.answer.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func listBinding(_ keyPath: WritableKeyPath<Card, [String]>) -> Binding<String> {
        Binding(
            get: { card[keyPath: keyPath].joined(separator: ", ") },
            set: { text in
                card[keyPath: keyPath] = text.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<Card, String?>) -> Binding<String> {
        Binding(
            get: { card[keyPath: keyPath] ?? "" },
            set: { card[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }
}

struct BulkCardsView: View {
    @Environment(\.dismiss) private var dismiss
    let add: ([Card]) -> Void
    @State private var text = ""

    private var parsed: [Card] { DeckStore.parseBulk(text) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("One card per line: question and answer, separated by ; or | or tab. Optionally followed by an example sentence and an explanation.", "Eine Karte pro Zeile: Frage und Antwort, getrennt durch ; oder | oder Tab. Optional danach ein Beispielsatz und eine Erklärung."))
                    .scaledFont(size: 14)
                    .foregroundStyle(Zen.inkSoft)
                Text(tr("dog ; 犬 (いぬ)\nCapital of Peru ; Lima ; Lima lies on the Pacific.", "Hund ; 犬 (いぬ)\nHauptstadt von Peru ; Lima ; Lima liegt am Pazifik."))
                    .scaledFont(size: 13, design: .monospaced)
                    .foregroundStyle(Zen.inkSoft)
                TextEditor(text: $text)
                    .scaledFont(size: 16, design: .monospaced)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Zen.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Zen.line))
                Text(tr("\(parsed.count) cards found", "\(parsed.count) Karten erkannt"))
                    .scaledFont(size: 14, weight: .medium)
                    .foregroundStyle(parsed.isEmpty ? Zen.inkSoft : Zen.matcha)
            }
            .padding(Zen.gutter)
            .background(AppBackground())
            .navigationTitle(tr("Many cards", "Viele Karten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Add", "Hinzufügen")) {
                        add(parsed)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(parsed.isEmpty)
                }
            }
        }
    }
}

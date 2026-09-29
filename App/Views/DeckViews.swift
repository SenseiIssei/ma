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

    private var store: DeckStore { model.decks }

    var body: some View {
        Group {
            if let deck = store.deck(id: deckID) {
                content(deck)
            } else {
                Text(tr("This topic no longer exists.", "Dieses Thema gibt es nicht mehr."))
                    .foregroundStyle(Zen.inkSoft)
            }
        }
        .background(WashiBackground())
        .fullScreenCover(item: $lesson) { session in
            LessonScreen(session: session) { lesson = nil }
        }
        .sheet(item: $editing) { deck in
            DeckEditorView(deck: deck, isNew: false)
        }
    }

    private func content(_ deck: Deck) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 16) {
                    Hanko(text: deck.symbol, size: 64, color: store.isActive(deck) ? Zen.shu : Zen.inkFaint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(deck.title)
                            .font(.mincho(28, weight: .semibold))
                            .foregroundStyle(Zen.ink)
                        if !deck.subtitle.isEmpty {
                            Text(deck.subtitle)
                                .font(.system(size: 15))
                                .foregroundStyle(Zen.inkSoft)
                        }
                    }
                }
                .padding(.top, 8)

                HStack(spacing: 12) {
                    StatStone(kanji: "札", value: "\(deck.cards.count)", label: tr("cards", "Karten"))
                    StatStone(kanji: "熟", value: "\(Int(store.mastery(of: deck) * 100))%", label: tr("known", "sicher"))
                    StatStone(kanji: "復", value: "\(store.dueCount(in: deck))", label: tr("due", "fällig"))
                }
                .zenCard()

                HStack(spacing: 12) {
                    Button {
                        lesson = QuizSession(mode: .lesson(count: min(10, max(1, deck.cards.count))), store: store, decks: [deck])
                    } label: {
                        Label(tr("Practise", "Üben"), systemImage: "play.fill")
                    }
                    .buttonStyle(.shu)
                    .disabled(deck.cards.isEmpty)

                    Button {
                        Haptics.tap()
                        store.toggleActive(deck)
                    } label: {
                        Text(store.isActive(deck) ? tr("In the gate", "In der Schranke") : tr("Use in gate", "Für Schranke"))
                    }
                    .buttonStyle(.quiet)
                }

                SectionHeader(kanji: "札", title: tr("Cards", "Karten")) {
                    HStack(spacing: 16) {
                        ShareLink(item: DeckFile(data: store.exportData(deck), name: deck.title), preview: SharePreview(deck.title)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        if !deck.isBuiltIn {
                            Button {
                                editing = deck
                            } label: {
                                Image(systemName: "pencil")
                            }
                        }
                    }
                    .foregroundStyle(Zen.shu)
                }

                VStack(spacing: 0) {
                    ForEach(deck.cards) { card in
                        CardLine(card: card, box: store.progress(of: card, in: deck).box)
                        if card.id != deck.cards.last?.id {
                            Divider().overlay(Zen.line)
                        }
                    }
                }
                .zenCard(padding: 6)

                if !deck.isBuiltIn {
                    Button(tr("Delete topic", "Thema löschen"), role: .destructive) {
                        confirmDelete = true
                    }
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
}

struct CardLine: View {
    let card: Card
    let box: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.prompt)
                    .font(ExerciseEngine.containsCJK(card.prompt) ? .kanji(18, bold: true) : .system(size: 16, weight: .medium))
                    .foregroundStyle(Zen.ink)
                Text(card.answer)
                    .font(ExerciseEngine.containsCJK(card.answer) ? .kanji(15) : .system(size: 14))
                    .foregroundStyle(Zen.inkSoft)
            }
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(index < box ? Zen.matcha : Zen.line)
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityLabel(tr("Level \(box) of 5", "Stufe \(box) von 5"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
                        .font(.mincho(19, weight: .semibold))
                    TextField(tr("What is it about?", "Worum geht es?"), text: $deck.subtitle)
                    HStack {
                        Text(tr("Seal", "Siegel"))
                        Spacer()
                        TextField("学", text: Binding(
                            get: { deck.symbol },
                            set: { deck.symbol = String($0.suffix(1)) }
                        ))
                        .multilineTextAlignment(.center)
                        .font(.kanji(22, bold: true))
                        .frame(width: 60)
                    }
                } header: {
                    Text(tr("Topic", "Thema"))
                } footer: {
                    Text(tr("A single character for the seal. A kanji looks best.", "Ein einzelnes Zeichen fürs Siegel. Ein Kanji sieht am schönsten aus."))
                }

                Section {
                    ForEach(deck.cards) { card in
                        Button {
                            editingCard = card
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.prompt).foregroundStyle(Zen.ink)
                                Text(card.answer).font(.system(size: 14)).foregroundStyle(Zen.inkSoft)
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
            .background(WashiBackground())
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
                    Text(tr("With an example sentence you get gap texts. The explanation shows after every answer, that is where the learning happens.", "Mit Beispielsatz gibt es Lückentexte. Die Erklärung erscheint nach jeder Antwort, dort passiert das eigentliche Lernen."))
                }
            }
            .scrollContentBackground(.hidden)
            .background(WashiBackground())
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
                    .font(.system(size: 14))
                    .foregroundStyle(Zen.inkSoft)
                Text(tr("dog ; 犬 (いぬ)\nCapital of Peru ; Lima ; Lima lies on the Pacific.", "Hund ; 犬 (いぬ)\nHauptstadt von Peru ; Lima ; Lima liegt am Pazifik."))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Zen.inkFaint)
                TextEditor(text: $text)
                    .font(.system(size: 16, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Zen.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Zen.line))
                Text(tr("\(parsed.count) cards found", "\(parsed.count) Karten erkannt"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(parsed.isEmpty ? Zen.inkFaint : Zen.matcha)
            }
            .padding(Zen.gutter)
            .background(WashiBackground())
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

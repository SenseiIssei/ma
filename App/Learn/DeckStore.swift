import Foundation
import Observation

@Observable
final class DeckStore {
    private(set) var builtIn: [Deck] = []
    private(set) var custom: [Deck] = []
    private(set) var progress: [String: CardProgress] = [:]
    var profile = LearnerProfile() {
        didSet { save(profile, to: "profile.json") }
    }

    var decks: [Deck] { builtIn + custom }

    /// Decks the gate draws questions from. With none picked, all of them.
    var activeDecks: [Deck] {
        let picked = decks.filter { profile.activeDeckIDs.contains($0.id) && !$0.cards.isEmpty }
        return picked.isEmpty ? decks.filter { !$0.cards.isEmpty } : picked
    }

    init() {
        load()
    }

    // MARK: Loading

    func load() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let editions = urls
            .filter { $0.lastPathComponent.hasPrefix("deck-") }
            .compactMap { url -> Deck? in
                guard let data = try? Data(contentsOf: url),
                      var deck = try? JSONDecoder().decode(Deck.self, from: data) else { return nil }
                deck.isBuiltIn = true
                return deck
            }
        // One edition per deck: the app language if there is one, otherwise
        // whatever exists. Files without a locale are the German originals.
        var chosen: [String: Deck] = [:]
        for deck in editions {
            let fits = (deck.locale ?? "de") == Loc.code
            if chosen[deck.id] == nil || fits { chosen[deck.id] = deck }
        }
        builtIn = chosen.values
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        custom = read([Deck].self, from: "decks.json") ?? []
        progress = read([String: CardProgress].self, from: "progress.json") ?? [:]
        profile = read(LearnerProfile.self, from: "profile.json") ?? LearnerProfile()
    }

    // MARK: Progress

    func key(_ deck: Deck, _ card: Card) -> String { "\(deck.id)/\(card.id)" }

    func progress(of card: Card, in deck: Deck) -> CardProgress {
        progress[key(deck, card)] ?? CardProgress()
    }

    func record(_ card: Card, in deck: Deck, correct: Bool) {
        var p = progress(of: card, in: deck)
        p.record(correct: correct)
        progress[key(deck, card)] = p
        save(progress, to: "progress.json")

        var profile = profile
        profile.xp += correct ? 10 : 1
        if correct {
            let today = SharedStore.dayKey()
            if profile.lastLearnedDay != today {
                let yesterday = SharedStore.dayKey(Date().addingTimeInterval(-86_400))
                profile.streakDays = profile.lastLearnedDay == yesterday ? profile.streakDays + 1 : 1
                profile.lastLearnedDay = today
            }
        }
        self.profile = profile

        SharedStore.updateToday {
            if correct { $0.correct += 1 } else { $0.wrong += 1 }
        }
    }

    /// The streak as it stands today: it only breaks once a whole day is missed.
    var currentStreak: Int {
        guard let last = profile.lastLearnedDay else { return 0 }
        let today = SharedStore.dayKey()
        let yesterday = SharedStore.dayKey(Date().addingTimeInterval(-86_400))
        return last == today || last == yesterday ? profile.streakDays : 0
    }

    var learnedToday: Bool { profile.lastLearnedDay == SharedStore.dayKey() }

    func mastery(of deck: Deck) -> Double {
        guard !deck.cards.isEmpty else { return 0 }
        let known = deck.cards.filter { progress(of: $0, in: deck).box >= 3 }.count
        return Double(known) / Double(deck.cards.count)
    }

    func dueCount(in deck: Deck, now: Date = Date()) -> Int {
        deck.cards.filter {
            let p = progress(of: $0, in: deck)
            return p.seen > 0 && p.due <= now
        }.count
    }

    func isActive(_ deck: Deck) -> Bool {
        profile.activeDeckIDs.contains(deck.id)
    }

    func toggleActive(_ deck: Deck) {
        if profile.activeDeckIDs.contains(deck.id) {
            profile.activeDeckIDs.remove(deck.id)
        } else {
            profile.activeDeckIDs.insert(deck.id)
        }
    }

    // MARK: Own decks

    func deck(id: String) -> Deck? {
        decks.first { $0.id == id }
    }

    func upsert(_ deck: Deck) {
        var deck = deck
        deck.isBuiltIn = false
        if let index = custom.firstIndex(where: { $0.id == deck.id }) {
            custom[index] = deck
        } else {
            custom.append(deck)
        }
        save(custom, to: "decks.json")
    }

    func delete(_ deck: Deck) {
        custom.removeAll { $0.id == deck.id }
        profile.activeDeckIDs.remove(deck.id)
        progress = progress.filter { !$0.key.hasPrefix(deck.id + "/") }
        save(custom, to: "decks.json")
        save(progress, to: "progress.json")
    }

    /// Accepts one deck or an array of decks. Ids that clash with an
    /// existing deck get a fresh id so an import never overwrites.
    @discardableResult
    func importDecks(from data: Data) throws -> [Deck] {
        let decoder = JSONDecoder()
        var incoming: [Deck]
        if let many = try? decoder.decode([Deck].self, from: data) {
            incoming = many
        } else {
            incoming = [try decoder.decode(Deck.self, from: data)]
        }
        let taken = Set(decks.map(\.id))
        for index in incoming.indices {
            if taken.contains(incoming[index].id) { incoming[index].id = UUID().uuidString }
            incoming[index].cards = incoming[index].cards.filter {
                !$0.prompt.trimmingCharacters(in: .whitespaces).isEmpty && !$0.answer.trimmingCharacters(in: .whitespaces).isEmpty
            }
            upsert(incoming[index])
        }
        return incoming
    }

    func exportData(_ deck: Deck) -> Data {
        var copy = deck
        copy.isBuiltIn = false
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(copy)) ?? Data()
    }

    /// One card per line. Separators, in order of preference: tab, `;`, `|`, ` = `.
    /// Third column is an example sentence, fourth a note.
    static func parseBulk(_ text: String) -> [Card] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            let separator = ["\t", ";", "|", " = "].first { line.contains($0) }
            guard let separator else { return nil }
            let parts = line.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            let example = parts.count > 2 && parts[2].contains(parts[1]) ? parts[2] : nil
            let note = parts.count > 3 ? parts[3] : (parts.count > 2 && example == nil ? parts[2] : nil)
            return Card(prompt: parts[0], answer: parts[1], example: example, note: note?.isEmpty == true ? nil : note)
        }
    }

    // MARK: Files

    private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: documents.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: documents.appendingPathComponent(name), options: .atomic)
    }
}

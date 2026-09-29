import Foundation

// The community gallery: decks people wrote for Ma, published with the
// website on GitHub Pages. gallery/build_index.py in the repo validates them
// and writes gallery/index.json, which this file reads. Nothing is sent
// along with these downloads: no account, no identifier, no usage data.

/// One deck in gallery/index.json. Editions of one deck share `deckID`, so
/// the path is what makes an entry unique.
struct GalleryEntry: Decodable, Identifiable, Hashable {
    var deckID: String
    var title: String
    var subtitle: String
    var symbol: String
    var category: String
    var locale: String
    var cardCount: Int
    /// Relative to the gallery folder, for example "decks/astronomy.en.json".
    var path: String

    var id: String { path }

    private enum CodingKeys: String, CodingKey {
        case deckID = "id", title, subtitle, symbol, category, locale, cardCount, path
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deckID = try c.decode(String.self, forKey: .deckID)
        title = try c.decode(String.self, forKey: .title)
        path = try c.decode(String.self, forKey: .path)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "学"
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? DeckCategory.knowledge.rawValue
        locale = try c.decodeIfPresent(String.self, forKey: .locale) ?? "en"
        cardCount = try c.decodeIfPresent(Int.self, forKey: .cardCount) ?? 0
    }

    /// The shelf it lands on in Learn. Unknown categories go to Knowledge,
    /// never to "Yours", which is for decks the learner wrote.
    var shelf: DeckCategory {
        guard let known = DeckCategory(rawValue: category), known != .own else { return .knowledge }
        return known
    }

    var languageName: String {
        switch locale {
        case "de": "Deutsch"
        case "en": "English"
        default: locale.uppercased()
        }
    }

    var cardsText: String {
        cardCount == 1 ? tr("1 card", "1 Karte") : tr("\(cardCount) cards", "\(cardCount) Karten")
    }

    /// "25 cards · English"
    var facts: String { "\(cardsText) · \(languageName)" }

    /// Search over title, subtitle, id and shelf name, ignoring case and accents.
    func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = [title, subtitle, deckID, shelf.title].joined(separator: " ")
        return words.allSatisfy {
            haystack.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

enum GalleryError: Error, LocalizedError {
    case badLink, offline, notFound, tooLarge, notADeck, empty

    var message: String {
        switch self {
        case .badLink:
            tr("This link does not point to a Ma topic.", "Dieser Link führt zu keinem Ma-Thema.")
        case .offline:
            tr("Could not reach the gallery. Check your connection and try again.", "Die Galerie ist gerade nicht erreichbar. Prüf deine Verbindung und versuch es noch einmal.")
        case .notFound:
            tr("The topic could not be found. It may have moved.", "Das Thema wurde nicht gefunden. Vielleicht ist es umgezogen.")
        case .tooLarge:
            tr("This file is too large for a topic.", "Diese Datei ist zu groß für ein Thema.")
        case .notADeck:
            tr("That does not look like a Ma topic.", "Das sieht nicht nach einem Ma-Thema aus.")
        case .empty:
            tr("This topic has no cards.", "Dieses Thema hat keine Karten.")
        }
    }

    var errorDescription: String? { message }
}

enum GalleryClient {
    /// Where the website publishes the gallery. Deck paths in the index are
    /// relative to this folder.
    static let base = URL(string: "https://senseiissei.github.io/ma/gallery/")!
    static var indexURL: URL { base.appendingPathComponent("index.json") }
    static var webURL: URL { base }

    /// A real deck is a few kilobytes. Anything past this is not a deck.
    static let maxBytes = 2 * 1024 * 1024

    static func fetchIndex() async throws -> [GalleryEntry] {
        try decodeIndex(try await fetch(indexURL))
    }

    /// Accepts {"version": 1, "decks": [...]} or a bare array. Entries that
    /// do not decode, or whose path leaves the gallery, are skipped instead of
    /// failing the whole list.
    static func decodeIndex(_ data: Data) throws -> [GalleryEntry] {
        let decoder = JSONDecoder()
        let raw: [Lossy<GalleryEntry>]
        if let index = try? decoder.decode(LossyIndex.self, from: data) {
            raw = index.decks
        } else if let list = try? decoder.decode([Lossy<GalleryEntry>].self, from: data) {
            raw = list
        } else {
            throw GalleryError.notADeck
        }
        return raw.compactMap(\.value).filter { (try? deckURL(for: $0)) != nil }
    }

    /// The absolute URL of an entry's JSON. Only paths inside the gallery
    /// folder on the same host are allowed.
    static func deckURL(for entry: GalleryEntry) throws -> URL {
        let path = entry.path
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains(".."), !path.contains(":"),
              let url = URL(string: path, relativeTo: base)?.absoluteURL,
              url.scheme == "https", url.host() == base.host(),
              url.path().hasPrefix(base.path()) else {
            throw GalleryError.badLink
        }
        return url
    }

    /// Downloads over HTTPS only, with a size cap.
    static func fetch(_ url: URL) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else { throw GalleryError.badLink }
        var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw GalleryError.offline
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else { throw GalleryError.offline }
        guard (200..<300).contains(http.statusCode) else { throw GalleryError.notFound }
        guard data.count <= maxBytes else { throw GalleryError.tooLarge }
        return data
    }

    /// One deck or a list of decks, each with at least one card. Used to
    /// check a download before anything touches the learner's topics.
    static func decodeDecks(_ data: Data) throws -> [Deck] {
        let decoder = JSONDecoder()
        let decks: [Deck]
        if let many = try? decoder.decode([Deck].self, from: data) {
            decks = many
        } else if let one = try? decoder.decode(Deck.self, from: data) {
            decks = [one]
        } else {
            throw GalleryError.notADeck
        }
        guard !decks.isEmpty, decks.allSatisfy({ !$0.cards.isEmpty }) else { throw GalleryError.empty }
        guard decks.count <= 50, decks.reduce(0, { $0 + $1.cards.count }) <= 5_000 else { throw GalleryError.tooLarge }
        return decks
    }

    private struct LossyIndex: Decodable {
        var decks: [Lossy<GalleryEntry>]
    }

    /// Decodes a value if it can, and stays nil instead of throwing.
    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: Decoder) throws {
            value = try? Value(from: decoder)
        }
    }
}

/// Adding gallery decks and handling `ma://import?url=<encoded https URL>`.
///
/// Route the link from `AppModel.handle(url:)`:
///
///     case "import":
///         Task { @MainActor in
///             importMessage = await GalleryImport.handle(url: url, into: decks)
///         }
enum GalleryImport {
    static func isImportLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "ma" && url.host()?.lowercased() == "import"
    }

    /// The deck file an import link points to. HTTPS only.
    static func sourceURL(from url: URL) -> URL? {
        guard isImportLink(url),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "url" })?.value,
              let source = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              source.scheme?.lowercased() == "https",
              let host = source.host(), !host.isEmpty else {
            return nil
        }
        return source
    }

    /// Downloads the deck behind an import link and adds it. Always returns a
    /// sentence to show the learner, for success and for every failure.
    @MainActor
    static func handle(url: URL, into store: DeckStore) async -> String {
        guard let source = sourceURL(from: url) else { return GalleryError.badLink.message }
        do {
            let data = try await GalleryClient.fetch(source)
            return successMessage(try importData(data, into: store))
        } catch {
            return message(for: error)
        }
    }

    /// Adds one gallery entry. Pass `data` when it is already downloaded,
    /// for example by the preview.
    @MainActor
    static func add(_ entry: GalleryEntry, data: Data? = nil, into store: DeckStore) async throws -> String {
        let payload: Data
        if let data {
            payload = data
        } else {
            payload = try await GalleryClient.fetch(try GalleryClient.deckURL(for: entry))
        }
        return successMessage(try importData(payload, into: store))
    }

    /// Validates first, so a broken file never leaves half an import behind.
    /// DeckStore gives a deck a fresh id if its id is taken, so nothing the
    /// learner has is ever overwritten.
    @MainActor
    @discardableResult
    static func importData(_ data: Data, into store: DeckStore) throws -> [Deck] {
        _ = try GalleryClient.decodeDecks(data)
        let added = try store.importDecks(from: data)
        guard !added.isEmpty else { throw GalleryError.notADeck }
        return added
    }

    static func successMessage(_ decks: [Deck]) -> String {
        if decks.count == 1, let deck = decks.first {
            let count = deck.cards.count
            return tr("Added \"\(deck.title)\" with \(count) cards. You find it under Learn.",
                      "„\(deck.title)“ mit \(count) Karten hinzugefügt. Du findest es unter Lernen.")
        }
        return tr("Added \(decks.count) topics. You find them under Learn.",
                  "\(decks.count) Themen hinzugefügt. Du findest sie unter Lernen.")
    }

    static func message(for error: Error) -> String {
        if let gallery = error as? GalleryError { return gallery.message }
        if error is DecodingError { return GalleryError.notADeck.message }
        return GalleryError.offline.message
    }
}

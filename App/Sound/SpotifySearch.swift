import Foundation

/// Links into Spotify's search. Only searches, never playlist IDs: a search
/// cannot go stale or point at something that was never there.
enum SpotifySearch {
    /// Unreserved URL characters stay as they are, everything else is
    /// percent encoded, so a space becomes %20 and not a plus.
    private static let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    static func encode(_ query: String) -> String {
        let trimmed: String = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// Opens the Spotify app straight on the search.
    static func appURL(for query: String) -> URL? {
        URL(string: "spotify:search:" + encode(query))
    }

    /// The fallback when Spotify is not installed.
    static func webURL(for query: String) -> URL? {
        URL(string: "https://open.spotify.com/search/" + encode(query))
    }
}

import Foundation

/// Switches for the Safari extension. The app writes them, the extension's
/// native handler reads them and hands them to the content script.
struct FilterSettings: Codable, Equatable {
    var instagramReels = true
    var instagramExplore = false
    var youtubeShorts = true
    var youtubeHome = false
    var xTrends = true
    var xFollowingOnly = false
    var linkedinFeed = false
    var facebookReels = true
    var tiktok = true

    init() {}

    init(from decoder: Decoder) throws {
        // Every key optional, so a switch added later never wipes the others.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FilterSettings()
        instagramReels = try c.decodeIfPresent(Bool.self, forKey: .instagramReels) ?? d.instagramReels
        instagramExplore = try c.decodeIfPresent(Bool.self, forKey: .instagramExplore) ?? d.instagramExplore
        youtubeShorts = try c.decodeIfPresent(Bool.self, forKey: .youtubeShorts) ?? d.youtubeShorts
        youtubeHome = try c.decodeIfPresent(Bool.self, forKey: .youtubeHome) ?? d.youtubeHome
        xTrends = try c.decodeIfPresent(Bool.self, forKey: .xTrends) ?? d.xTrends
        xFollowingOnly = try c.decodeIfPresent(Bool.self, forKey: .xFollowingOnly) ?? d.xFollowingOnly
        linkedinFeed = try c.decodeIfPresent(Bool.self, forKey: .linkedinFeed) ?? d.linkedinFeed
        facebookReels = try c.decodeIfPresent(Bool.self, forKey: .facebookReels) ?? d.facebookReels
        tiktok = try c.decodeIfPresent(Bool.self, forKey: .tiktok) ?? d.tiktok
    }

    static let fileName = "filter.json"

    static func load() -> FilterSettings {
        MaShared.read(FilterSettings.self, from: fileName) ?? FilterSettings()
    }

    func save() {
        MaShared.write(self, to: Self.fileName)
    }

    /// Plain dictionary for the JavaScript side.
    var dictionary: [String: Bool] {
        [
            "instagramReels": instagramReels,
            "instagramExplore": instagramExplore,
            "youtubeShorts": youtubeShorts,
            "youtubeHome": youtubeHome,
            "xTrends": xTrends,
            "xFollowingOnly": xFollowingOnly,
            "linkedinFeed": linkedinFeed,
            "facebookReels": facebookReels,
            "tiktok": tiktok,
        ]
    }
}

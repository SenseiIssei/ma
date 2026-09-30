import SwiftUI
import UIKit

/// One shortcut into Spotify's search.
struct MusicLink: Identifiable {
    let query: String
    let title: String
    let symbol: String

    var id: String { query }

    static var all: [MusicLink] {
        [
            MusicLink(query: "jazz for study", title: tr("Jazz for studying", "Jazz zum Lernen"), symbol: "music.quarternote.3"),
            MusicLink(query: "lofi beats", title: tr("Lofi beats", "Lofi-Beats"), symbol: "headphones"),
            MusicLink(query: "deep focus", title: tr("Deep focus", "Tiefer Fokus"), symbol: "scope"),
            MusicLink(query: "calm piano", title: tr("Calm piano", "Ruhiges Klavier"), symbol: "pianokeys"),
            MusicLink(query: "rain sounds sleep", title: tr("Rain to sleep", "Regen zum Einschlafen"), symbol: "cloud.moon.rain.fill"),
        ]
    }
}

enum SpotifyOpener {
    /// Tries the Spotify app first. Without it the system reports failure,
    /// and the same search opens on the web instead.
    @MainActor
    static func open(_ link: MusicLink) async {
        if let app = SpotifySearch.appURL(for: link.query) {
            let opened: Bool = await UIApplication.shared.open(app)
            if opened { return }
        }
        if let web = SpotifySearch.webURL(for: link.query) {
            _ = await UIApplication.shared.open(web)
        }
    }
}

/// A small card of Spotify shortcuts. Ma's own sounds mix with Spotify, so
/// rain under a piano playlist works too.
struct MusicCard: View {
    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "music.note", title: tr("Music", "Musik")) {
                Text("Spotify")
                    .scaledFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundStyle(Zen.inkSoft)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("Opens a matching search in Spotify.", "Öffnet eine passende Suche in Spotify."))
                    .scaledFont(size: 14)
                    .foregroundStyle(Zen.inkSoft)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(MusicLink.all) { link in
                        linkButton(link)
                    }
                }
            }
            .zenCard()
        }
    }

    private func linkButton(_ link: MusicLink) -> some View {
        Button {
            Haptics.tap()
            Task { await SpotifyOpener.open(link) }
        } label: {
            HStack(spacing: 10) {
                IconBadge(systemName: link.symbol, tint: Zen.shu, size: 32)
                Text(link.title)
                    .scaledFont(size: 14, weight: .semibold, design: .rounded)
                    .foregroundStyle(Zen.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Zen.sand.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(tr("Opens Spotify", "Öffnet Spotify"))
    }
}

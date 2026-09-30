import SwiftUI

/// Shown once after an update that brings something worth knowing. The
/// list belongs to a version; bump `WhatsNew.version` together with
/// MARKETING_VERSION when there is something new to tell.
enum WhatsNew {
    static let version = "0.2.0"
    private static let seenKey = "ma.whatsNewSeen"

    static var isDue: Bool {
        UserDefaults.standard.string(forKey: seenKey) != version
    }

    static func markSeen() {
        UserDefaults.standard.set(version, forKey: seenKey)
    }

    struct Item: Identifiable {
        let id = UUID()
        let icon: String
        let tint: Color
        let title: String
        let text: String
    }

    static var items: [Item] {
        [
            Item(icon: "moon.stars.fill", tint: Zen.shu,
                 title: tr("A calmer night look", "Ein ruhiger Nachtlook"),
                 text: tr("Deep blue, soft lavender, new illustrations. Switch to System in Settings if you prefer.",
                          "Tiefes Blau, sanftes Lavendel, neue Illustrationen. In den Einstellungen auf System umstellbar.")),
            Item(icon: "safari.fill", tint: Zen.ai,
                 title: tr("Open without Reels", "Ohne Reels öffnen"),
                 text: tr("Tap a blocked Instagram or YouTube and Ma offers the website, where the filter hides Reels and Shorts.",
                          "Tippst du auf gesperrtes Instagram oder YouTube, bietet Ma die Website an, wo der Filter Reels und Shorts ausblendet.")),
            Item(icon: "lock.fill", tint: Zen.negative,
                 title: tr("Boundaries that hold", "Grenzen, die halten"),
                 text: tr("Lockdown with no way through, daily unlock limits, rising friction and templates.",
                          "Sofort-Sperre ohne Ausweg, Tageslimit, steigende Hürde und Vorlagen.")),
            Item(icon: "book.fill", tint: Zen.matcha,
                 title: tr("Learn first, then practise", "Erst lernen, dann üben"),
                 text: tr("New cards are explained before they are asked. 21 topics, a community gallery and topics made by the on-device model.",
                          "Neue Karten werden erklärt, bevor sie abgefragt werden. 21 Themen, eine Community-Galerie und Themen vom Modell auf dem Gerät.")),
            Item(icon: "waveform", tint: Zen.kin,
                 title: tr("Sounds for focus", "Klänge für den Fokus"),
                 text: tr("Rain, brown noise, ocean and a night drone that keep playing when the screen locks, plus Spotify shortcuts.",
                          "Regen, Rauschen, Meer und ein Nachtklang, die bei gesperrtem Bildschirm weiterlaufen, dazu Spotify-Schnellstarts.")),
            Item(icon: "leaf.fill", tint: Zen.matcha,
                 title: tr("Balance", "Balance"),
                 text: tr("Short guided workouts, water and meals, and a wind-down before bed.",
                          "Kurze geführte Workouts, Wasser und Mahlzeiten und eine Abendroutine vor dem Schlafen.")),
            Item(icon: "flame.fill", tint: Zen.kin,
                 title: tr("A fitness goal with levels", "Ein Fitnessziel mit Levels"),
                 text: tr("Set a weight goal and Ma plans the sport a week needs. Workouts from your Garmin feed earn XP, quests and badges.",
                          "Setz ein Gewichtsziel und Ma plant den Sport, den eine Woche braucht. Trainings aus deinem Garmin-Feed bringen XP, Quests und Abzeichen.")),
            Item(icon: "square.grid.2x2.fill", tint: Zen.shu,
                 title: tr("Widgets and your week", "Widgets und deine Woche"),
                 text: tr("Rings on the Home Screen, the focus timer in the Dynamic Island, and a weekly review with your real Screen Time.",
                          "Ringe auf dem Homescreen, der Fokus-Timer in der Dynamic Island und ein Wochenrückblick mit deiner echten Bildschirmzeit.")),
            Item(icon: "person.2.fill", tint: Zen.ai,
                 title: tr("Friends without a feed", "Freunde ohne Feed"),
                 text: tr("Optional circles by invite code. Only streaks and numbers are shared, never content.",
                          "Freiwillige Kreise per Einladungscode. Geteilt werden nur Serien und Zahlen, nie Inhalte.")),
        ]
    }
}

struct WhatsNewView: View {
    let done: () -> Void

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tr("New in Ma \(WhatsNew.version)", "Neu in Ma \(WhatsNew.version)"))
                                .scaledFont(size: 13, weight: .semibold)
                                .foregroundStyle(Zen.shu)
                            Text(tr("A lot happened", "Es ist viel passiert"))
                                .displayFont(32)
                                .foregroundStyle(Zen.ink)
                                .accessibilityAddTraits(.isHeader)
                        }
                        .padding(.top, 28)
                        ForEach(WhatsNew.items) { item in
                            HStack(alignment: .top, spacing: 14) {
                                IconBadge(systemName: item.icon, tint: item.tint)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .scaledFont(size: 17, weight: .semibold)
                                        .foregroundStyle(Zen.ink)
                                    Text(item.text)
                                        .scaledFont(size: 15)
                                        .foregroundStyle(Zen.inkSoft)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
                }
                Button(tr("Let's go", "Los geht's"), action: done)
                    .buttonStyle(.primary)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 16)
            }
        }
    }
}

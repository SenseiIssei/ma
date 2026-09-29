import SwiftUI

struct FilterView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Reels lassen sich in der Instagram-App selbst nicht abschalten, das erlaubt iOS keiner App. Im Browser geht es.")
                    Text("Der Trick: Sperr die Instagram-App in einer Grenze und öffne instagram.com in Safari. Dort nimmt Ma Filter die Reels heraus, Nachrichten und Profile bleiben.")
                        .foregroundStyle(Zen.inkSoft)
                }
                .font(.system(size: 15))
                .padding(.vertical, 4)
            } header: {
                Text("So funktioniert es")
            }

            Section {
                Toggle("Reels ausblenden", isOn: $model.filter.instagramReels)
                Toggle("Entdecken ausblenden", isOn: $model.filter.instagramExplore)
            } header: {
                Text("Instagram")
            }

            Section {
                Toggle("Shorts ausblenden", isOn: $model.filter.youtubeShorts)
                Toggle("Startseite leeren", isOn: $model.filter.youtubeHome)
            } header: {
                Text("YouTube")
            } footer: {
                Text("Shorts-Links öffnen als normales Video. Mit leerer Startseite bleibt nur die Suche: du kommst für etwas Bestimmtes.")
            }

            Section {
                Toggle("Trends und Entdecken ausblenden", isOn: $model.filter.xTrends)
                Toggle("Immer \"Folge ich\" statt \"Für dich\"", isOn: $model.filter.xFollowingOnly)
            } header: {
                Text("X")
            }

            Section {
                Toggle("Feed ausblenden", isOn: $model.filter.linkedinFeed)
            } header: {
                Text("LinkedIn")
            } footer: {
                Text("Nachrichten, Jobs und Profile bleiben erreichbar.")
            }

            Section {
                Toggle("Facebook Reels ausblenden", isOn: $model.filter.facebookReels)
                Toggle("TikTok ganz ausschalten", isOn: $model.filter.tiktok)
            } header: {
                Text("Weitere")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    step(1, "Öffne Einstellungen, dann Apps, dann Safari.")
                    step(2, "Tippe auf Erweiterungen und wähle Ma Filter.")
                    step(3, "Schalte die Erweiterung ein und erlaube sie für die Seiten oben.")
                }
                .font(.system(size: 15))
                .padding(.vertical, 4)
            } header: {
                Text("Einmalig einschalten")
            }
        }
        .tint(Zen.shu)
        .scrollContentBackground(.hidden)
        .background(WashiBackground())
        .navigationTitle("Reels-Filter")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.filter) { _, _ in
            model.saveFilter()
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(KanjiDate.number(number))
                .font(.kanji(15, bold: true))
                .foregroundStyle(Zen.shu)
                .frame(width: 20)
            Text(text)
        }
    }
}

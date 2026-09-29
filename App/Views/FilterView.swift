import SwiftUI

struct FilterView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        IconBadge(systemName: "safari.fill", tint: Zen.ai)
                        Text(tr("Reels filter", "Reels-Filter"))
                            .font(.display(20))
                            .foregroundStyle(Zen.ink)
                    }
                    Text(tr("Reels cannot be switched off inside the Instagram app, iOS does not let any app do that. In the browser it works.", "Reels lassen sich in der Instagram-App selbst nicht abschalten, das erlaubt iOS keiner App. Im Browser geht es."))
                        .foregroundStyle(Zen.ink)
                    Text(tr("The trick: block the Instagram app in a boundary and open instagram.com in Safari. There Ma Filter takes the Reels out, messages and profiles stay.", "Der Trick: Sperr die Instagram-App in einer Grenze und öffne instagram.com in Safari. Dort nimmt Ma Filter die Reels heraus, Nachrichten und Profile bleiben."))
                        .foregroundStyle(Zen.inkSoft)
                }
                .font(.system(size: 15))
                .padding(.vertical, 4)
            } header: {
                FormHeader(icon: "questionmark.circle.fill", title: tr("How it works", "So funktioniert es"))
            }

            Section {
                Toggle(tr("Hide Reels", "Reels ausblenden"), isOn: $model.filter.instagramReels)
                Toggle(tr("Hide Explore", "Entdecken ausblenden"), isOn: $model.filter.instagramExplore)
            } header: {
                FormHeader(icon: "camera.fill", title: "Instagram")
            }

            Section {
                Toggle(tr("Hide Shorts", "Shorts ausblenden"), isOn: $model.filter.youtubeShorts)
                Toggle(tr("Empty the home page", "Startseite leeren"), isOn: $model.filter.youtubeHome)
            } header: {
                FormHeader(icon: "play.rectangle.fill", title: "YouTube")
            } footer: {
                Text(tr("Shorts links open as a normal video. With an empty home page only search is left: you come for something specific.", "Shorts-Links öffnen als normales Video. Mit leerer Startseite bleibt nur die Suche: du kommst für etwas Bestimmtes."))
            }

            Section {
                Toggle(tr("Hide Trends and Explore", "Trends und Entdecken ausblenden"), isOn: $model.filter.xTrends)
                Toggle(tr("Always \"Following\" instead of \"For you\"", "Immer \"Folge ich\" statt \"Für dich\""), isOn: $model.filter.xFollowingOnly)
            } header: {
                FormHeader(icon: "text.bubble.fill", title: "X")
            }

            Section {
                Toggle(tr("Hide the feed", "Feed ausblenden"), isOn: $model.filter.linkedinFeed)
            } header: {
                FormHeader(icon: "briefcase.fill", title: "LinkedIn")
            } footer: {
                Text(tr("Messages, jobs and profiles stay reachable.", "Nachrichten, Jobs und Profile bleiben erreichbar."))
            }

            Section {
                Toggle(tr("Hide Facebook Reels", "Facebook Reels ausblenden"), isOn: $model.filter.facebookReels)
                Toggle(tr("Switch TikTok off entirely", "TikTok ganz ausschalten"), isOn: $model.filter.tiktok)
            } header: {
                FormHeader(icon: "ellipsis.circle.fill", title: tr("More", "Weitere"))
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    StepRow(number: 1, text: tr("Open Settings, then Apps, then Safari.", "Öffne Einstellungen, dann Apps, dann Safari."))
                    StepRow(number: 2, text: tr("Tap Extensions and choose Ma Filter.", "Tippe auf Erweiterungen und wähle Ma Filter."))
                    StepRow(number: 3, text: tr("Switch the extension on and allow it for the sites above.", "Schalte die Erweiterung ein und erlaube sie für die Seiten oben."))
                }
                .padding(.vertical, 4)
            } header: {
                FormHeader(icon: "switch.2", title: tr("Switch on once", "Einmalig einschalten"))
            }
        }
        .tint(Zen.shu)
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(tr("Reels filter", "Reels-Filter"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.filter) { _, _ in
            model.saveFilter()
        }
    }
}

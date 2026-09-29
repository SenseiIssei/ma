import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.onboarded {
                MainTabs()
            } else {
                OnboardingView()
            }
        }
        .tint(Zen.shu)
        .fullScreenCover(item: $model.gate) { reason in
            GateView(reason: reason)
                .environment(model)
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Heute", systemImage: "sun.haze", value: MaTab.today) {
                TodayView()
            }
            Tab("Grenzen", systemImage: "shield.lefthalf.filled", value: MaTab.rules) {
                RulesView()
            }
            Tab("Lernen", systemImage: "character.book.closed", value: MaTab.learn) {
                LearnView()
            }
            Tab("Fokus", systemImage: "circle.dashed", value: MaTab.focus) {
                FocusView()
            }
        }
    }
}

/// Large serif title with a kanji over it, used at the top of every tab.
struct PageTitle: View {
    let kanji: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kanji)
                .font(.kanji(15, bold: true))
                .foregroundStyle(Zen.shu)
                .tracking(4)
            Text(title)
                .font(.mincho(34, weight: .semibold))
                .foregroundStyle(Zen.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

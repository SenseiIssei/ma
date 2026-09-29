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
            Tab(tr("Today", "Heute"), systemImage: "sun.max", value: MaTab.today) {
                TodayView()
            }
            Tab(tr("Boundaries", "Grenzen"), systemImage: "shield.lefthalf.filled", value: MaTab.rules) {
                RulesView()
            }
            Tab(tr("Learn", "Lernen"), systemImage: "book.closed", value: MaTab.learn) {
                LearnView()
            }
            Tab(tr("Focus", "Fokus"), systemImage: "timer", value: MaTab.focus) {
                FocusView()
            }
        }
    }
}

/// Large title at the top of every tab, with an optional small symbol
/// above it. The kanji initializer stays for older call sites and shows
/// nothing of the kanji.
struct PageTitle: View {
    let title: String
    var subtitle: String?
    var icon: String?

    init(title: String, subtitle: String? = nil, icon: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }

    init(kanji: String, title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Zen.shu)
                    .frame(width: 32, height: 32)
                    .background(Zen.shu.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.bottom, 2)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.display(34))
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

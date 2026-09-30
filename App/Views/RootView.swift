import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("ma.appearance") private var appearance = Appearance.night.rawValue
    @State private var showWhatsNew = false

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
        .preferredColorScheme(appearance == Appearance.system.rawValue ? nil : .dark)
        .onChange(of: appearance, initial: true) { _, value in
            Appearance.current = Appearance(rawValue: value) ?? .night
        }
        .alert(tr("Topics", "Themen"), isPresented: Binding(
            get: { model.importMessage != nil },
            set: { if !$0 { model.importMessage = nil } }
        )) {
            Button(tr("OK", "OK"), role: .cancel) { model.importMessage = nil }
        } message: {
            Text(model.importMessage ?? "")
        }
        .onAppear {
            // New installs meet everything in onboarding; only people who
            // update get the summary of what changed.
            if !model.onboarded {
                WhatsNew.markSeen()
            } else if WhatsNew.isDue {
                showWhatsNew = true
            }
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView {
                WhatsNew.markSeen()
                showWhatsNew = false
            }
            .interactiveDismissDisabled()
        }
        .fullScreenCover(item: $model.gate) { reason in
            GateView(reason: reason)
                .environment(model)
        }
    }
}

/// The tabs as the tab bar sees them. `MaTab` in AppModel knows the four
/// tabs the rest of the app can jump to; Balance lives only here, so the
/// bar keeps its own selection and mirrors `model.tab` both ways.
enum RootTab: Hashable {
    case today, rules, learn, focus, balance

    init(_ tab: MaTab) {
        switch tab {
        case .today: self = .today
        case .rules: self = .rules
        case .learn: self = .learn
        case .focus: self = .focus
        }
    }

    var maTab: MaTab? {
        switch self {
        case .today: .today
        case .rules: .rules
        case .learn: .learn
        case .focus: .focus
        case .balance: nil
        }
    }
}

extension EnvironmentValues {
    /// Switches the tab bar from inside a tab, Balance included.
    @Entry var selectRootTab: (RootTab) -> Void = { _ in }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model
    @Environment(FitnessStore.self) private var fitness
    @Environment(CompanionStore.self) private var companions
    @State private var selection: RootTab = .today

    var body: some View {
        TabView(selection: $selection) {
            Tab(tr("Today", "Heute"), systemImage: "sun.max", value: RootTab.today) {
                TodayView()
            }
            Tab(tr("Boundaries", "Grenzen"), systemImage: "shield.lefthalf.filled", value: RootTab.rules) {
                RulesView()
            }
            Tab(tr("Learn", "Lernen"), systemImage: "book.closed", value: RootTab.learn) {
                LearnView()
            }
            Tab(tr("Focus", "Fokus"), systemImage: "timer", value: RootTab.focus) {
                FocusView()
            }
            Tab(tr("Balance", "Balance"), systemImage: "leaf", value: RootTab.balance) {
                BalanceView()
            }
        }
        .environment(\.selectRootTab, { tab in selection = tab })
        .sheet(item: Binding(get: { fitness.celebration }, set: { fitness.celebration = $0 })) { celebration in
            LevelUpView(celebration: celebration) { fitness.celebration = nil }
        }
        .onChange(of: model.tab, initial: true) { _, tab in
            // While Balance is open, `model.tab` is parked on .today (see
            // below). That parking move must not pull the bar back to Today.
            if selection == .balance && tab == .today { return }
            selection = RootTab(tab)
        }
        .onChange(of: selection) { _, tab in
            // Park `model.tab` on .today while Balance is open. Nothing jumps
            // to Today from outside, so any later `model.tab = .focus` from a
            // notification or a deep link is a real change and is seen above,
            // even when Focus was the tab before Balance.
            let mirrored: MaTab = tab.maTab ?? .today
            if model.tab != mirrored { model.tab = mirrored }
        }
        .onReceive(NotificationCenter.default.publisher(for: .maNotificationOpened)) { note in
            let route: String? = note.userInfo?[Notifier.routeKey] as? String
            if route == BalanceStore.windDownRoute {
                selection = .balance
            } else if route == CompanionReminder.route {
                selection = .balance
                companions.openChat = true
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
                .displayFont(34)
                .foregroundStyle(Zen.ink)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .scaledFont(size: 15)
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

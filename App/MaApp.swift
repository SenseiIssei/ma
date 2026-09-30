import SwiftUI
import UserNotifications

@main
struct MaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    /// Journal, habits and breathing; separate from AppModel because none of
    /// it touches Screen Time or the extensions.
    @State private var day = DayStore()
    /// Movement, water, meals and sleep for the Balance tab. Also app-only.
    @State private var balance = BalanceStore()
    /// Optional friends circles; talks to Ma's server only when switched on.
    @State private var friends = FriendsStore()
    /// Weight goal, workouts from the Garmin feed, levels and quests.
    @State private var fitness = FitnessStore()
    /// Nyx or Kael and the chat with them.
    @State private var companions = CompanionStore()
    /// The optional account; the server decides what it unlocks.
    @State private var accounts = AccountStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(day)
                .environment(balance)
                .environment(friends)
                .environment(fitness)
                .environment(companions)
                .environment(accounts)
                .onOpenURL { url in
                    switch url.host {
                    // Back from the confirmation mail or the Discord page.
                    case "account": Task { await accounts.refresh() }
                    case "notify":
                        NotificationCenter.default.post(name: .maNotifyLinked, object: nil)
                    default: model.handle(url: url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .maNotificationOpened)) { note in
                    model.reload()
                    if (note.userInfo?[Notifier.routeKey] as? String) == "focus" {
                        model.tab = .focus
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.reload()
                let streak = model.decks.currentStreak
                let habits = day.habitsDoneToday
                Task { await friends.syncToday(streak: streak, habitsDone: habits) }
                CompanionReminder.refresh(CompanionSnapshot.make(fitness: fitness, day: day, model: model))
                Task {
                    await accounts.refresh()
                    if let progress = await accounts.dailyProgress() {
                        fitness.applyLessons(progress.records)
                    }
                }
                Task { await fitness.refresh() }
            }
        }
    }
}

extension Notification.Name {
    static let maNotificationOpened = Notification.Name("ma.notificationOpened")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let route = response.notification.request.content.userInfo[Notifier.routeKey] as? String ?? ""
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .maNotificationOpened, object: nil, userInfo: [Notifier.routeKey: route])
        }
        completionHandler()
    }
}

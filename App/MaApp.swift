import SwiftUI
import UserNotifications

@main
struct MaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    /// Journal, habits and breathing; separate from AppModel because none of
    /// it touches Screen Time or the extensions.
    @State private var day = DayStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(day)
                .onOpenURL { model.handle(url: $0) }
                .onReceive(NotificationCenter.default.publisher(for: .maNotificationOpened)) { note in
                    model.reload()
                    if (note.userInfo?[Notifier.routeKey] as? String) == "focus" {
                        model.tab = .focus
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.reload() }
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

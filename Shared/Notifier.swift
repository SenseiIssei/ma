import Foundation
import UserNotifications

enum Notifier {
    static let gateID = "ma.gate"
    static let focusID = "ma.focus"
    static let lockdownID = "ma.lockdown"
    static let routeKey = "ma.route"

    /// Sent by the shield when someone asks for a question. A shield cannot
    /// open the app itself; a notification is the one door it may open.
    static func askForQuestion(appName: String?, completion: @escaping () -> Void) {
        let content = UNMutableNotificationContent()
        content.title = tr("A moment for you", "Ein Moment für dich")
        if let appName {
            content.body = tr("Tap here, answer a question, then decide about \(appName) in peace.",
                              "Tippe hier, beantworte eine Frage und entscheide dann in Ruhe über \(appName).")
        } else {
            content.body = tr("Tap here, answer a question, then decide in peace.",
                              "Tippe hier, beantworte eine Frage und entscheide dann in Ruhe.")
        }
        content.sound = .default
        content.interruptionLevel = .active
        content.userInfo = [routeKey: "gate"]
        let request = UNNotificationRequest(identifier: gateID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in completion() }
    }

    /// `route` tells the app where to go when the notification is tapped.
    static func schedule(id: String, title: String, body: String, at date: Date, route: String = "focus") {
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [routeKey: route]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

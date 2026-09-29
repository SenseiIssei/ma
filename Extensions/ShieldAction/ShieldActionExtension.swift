import Foundation
import ManagedSettings

/// Handles the two buttons on the shield. The primary one cannot open Ma
/// directly (extensions are not allowed to launch apps), so it leaves a
/// pending request on disk and sends a notification that does.
final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(
            to: action,
            policy: UnlockPolicy.current(application: application),
            pending: PendingUnlock(application: application, displayName: SharedStore.name(for: application)),
            completion: completionHandler
        )
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(
            to: action,
            policy: UnlockPolicy.current(webDomain: webDomain),
            pending: PendingUnlock(webDomain: webDomain, displayName: SharedStore.name(for: webDomain)),
            completion: completionHandler
        )
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(
            to: action,
            policy: UnlockPolicy.current(),
            pending: PendingUnlock(category: category),
            completion: completionHandler
        )
    }

    private func respond(
        to action: ShieldAction,
        policy: UnlockPolicy,
        pending: PendingUnlock,
        completion: @escaping (ShieldActionResponse) -> Void
    ) {
        // A lockdown whose one-shot never fired would keep its store up for
        // good. Any tap on a shield is a chance to tidy that up.
        if LockdownEngine.liftIfDue() {
            completion(.defer)
            return
        }
        switch action {
        case .primaryButtonPressed:
            // Lockdown, strict focus, a wall or a spent daily budget: the
            // only button left leads back.
            // The reel-free web version stays open even in strict focus;
            // Ma is the one that can open Safari, so the tap goes there.
            guard policy.allowed || policy.reelFreeWeb != nil else {
                SharedStore.updateToday { $0.resisted += 1 }
                completion(.close)
                return
            }
            SharedStore.pending = pending
            // .defer redraws the shield, which now reads the pending request
            // and points at the notification instead of repeating itself.
            Notifier.askForQuestion(appName: pending.displayName) {
                completion(.defer)
            }
        case .secondaryButtonPressed:
            SharedStore.updateToday { $0.resisted += 1 }
            completion(.close)
        @unknown default:
            completion(.close)
        }
    }
}

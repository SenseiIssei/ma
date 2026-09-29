import DeviceActivity
import Foundation

/// Woken by the system at the edges of every activity Scheduler registered.
/// It never trusts its own memory: every callback reloads from the App Group
/// and recomputes the shields.
final class MonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if let id = Scheduler.ruleID(of: activity) {
            ShieldEngine.apply(forceActive: [id])
        } else if activity.rawValue == Scheduler.lockdownName {
            // Makes sure the lockdown store is up even if the app was killed
            // right after starting it.
            ShieldEngine.apply()
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if let id = Scheduler.ruleID(of: activity) {
            ShieldEngine.apply(forceInactive: [id])
            return
        }
        settle(activity)
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        // For one-shot activities the warning is the real deadline; the end
        // of the interval is only padding to satisfy the 15 minute minimum.
        guard Scheduler.ruleID(of: activity) == nil else { return }
        settle(activity)
    }

    private func settle(_ activity: DeviceActivityName) {
        if let grantID = Scheduler.grantID(of: activity) {
            var grants = SharedStore.grants
            grants.removeAll { $0.id == grantID }
            SharedStore.grants = grants
            ShieldEngine.apply()
            Scheduler.stop(activity)
        } else if activity.rawValue == Scheduler.focusName {
            // The warning can land a few seconds early. Phases chain from
            // their planned end, never from now, so a small lead is harmless.
            if !FocusEngine.advanceIfDue(now: Date().addingTimeInterval(15)) {
                ShieldEngine.apply()
            }
        } else if activity.rawValue == Scheduler.lockdownName {
            // Same small lead as focus. A lockdown that was stretched in the
            // meantime is still active here and stays up; its new one-shot
            // has already been registered by the app.
            if !LockdownEngine.liftIfDue(now: Date().addingTimeInterval(15)) {
                ShieldEngine.apply()
            }
        }
    }
}

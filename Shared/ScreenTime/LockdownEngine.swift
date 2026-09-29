import Foundation
import ManagedSettings

/// Starts and lifts a lockdown. Lives in Shared because the monitor
/// extension has to lift it on time while the app is closed.
enum LockdownEngine {
    /// Starts a lockdown for `minutes`, or stretches a running one. A
    /// running lockdown is never shortened from here.
    @discardableResult
    static func start(minutes: Int, now: Date = Date()) -> LockdownState {
        let wanted = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        let running = SharedStore.activeLockdown(at: now)
        var state = running ?? LockdownState(startedAt: now, until: wanted)
        state.until = max(state.until, wanted)

        // Snapshot what is blocked right now, so a boundary edited during
        // the lockdown cannot open a door.
        let tokens = ShieldEngine.lockdownSelection(state, settings: SharedStore.focusSettings, rules: SharedStore.rules)
        state.applications = tokens.apps
        state.categories = tokens.categories
        state.webDomains = tokens.web
        SharedStore.lockdown = state

        // Open unlocks and passes would otherwise pop back up afterwards.
        for grant in SharedStore.grants { Scheduler.unwatch(grant) }
        SharedStore.grants = []
        SharedStore.pending = nil
        SharedStore.shortcutPassUntil = nil

        Scheduler.watchLockdown(until: state.until)
        Notifier.schedule(
            id: Notifier.lockdownID,
            title: tr("Lockdown is over", "Die Sperre ist vorbei"),
            body: tr("Your apps are back. Take them gently.", "Deine Apps sind wieder da. Geh behutsam mit ihnen um."),
            at: state.until,
            route: "lockdown"
        )
        ShieldEngine.apply(now: now)
        return state
    }

    /// Ends the lockdown right away. Callers decide whether that is allowed:
    /// the app only calls this once it expired or after the hard gate.
    static func lift() {
        SharedStore.lockdown = nil
        Scheduler.watchLockdown(until: nil)
        Notifier.cancel(Notifier.lockdownID)
        ShieldEngine.apply()
    }

    /// Lifts an expired lockdown. Returns true if one was lifted.
    @discardableResult
    static func liftIfDue(now: Date = Date()) -> Bool {
        guard let state = SharedStore.lockdown, !state.isActive(at: now) else { return false }
        SharedStore.lockdown = nil
        Scheduler.watchLockdown(until: nil)
        ShieldEngine.apply(now: now)
        return true
    }
}

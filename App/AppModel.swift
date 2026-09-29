import ActivityKit
import FamilyControls
import Foundation
import ManagedSettings
import Observation
import SwiftUI
import UserNotifications
import WidgetKit

enum MaTab: Hashable {
    case today, rules, learn, focus
}

/// Why the question gate is open.
enum GateReason: Identifiable {
    case unlock(PendingUnlock)
    case disableRule(UUID)
    case stopFocus
    case practice
    /// Opened by the Shortcuts automation; carries the GuardedApp raw value.
    case shortcut(String)
    /// The deliberately hard way out of a lockdown: five right answers.
    case endLockdown

    var id: String {
        switch self {
        case .unlock(let pending): "unlock-\(pending.id)"
        case .disableRule(let id): "rule-\(id)"
        case .stopFocus: "focus"
        case .practice: "practice"
        case .shortcut(let app): "shortcut-\(app)"
        case .endLockdown: "lockdown"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var rules: [BlockRule] = []
    var grants: [UnlockGrant] = []
    var focus: FocusSession?
    var focusSettings = FocusSettings()
    var filter = FilterSettings()
    var today = DayStats()
    var week: [DayStats] = []
    var authorization: AuthorizationStatus = .notDetermined
    var notificationsAllowed = false
    var gate: GateReason?
    var tab: MaTab = .today
    var shortcutSettings = ShortcutSettings()
    var shortcutPassUntil: Date?
    var shortcutLastRun: Date?
    /// Asks the Boundaries tab to open the Shortcuts setup, e.g. from onboarding.
    var showShortcutsSetup = false
    /// End of the running lockdown, nil when there is none.
    var lockdownUntil: Date?
    let decks = DeckStore()

    /// What the widgets last saw, so reload() (once a second on the focus
    /// screen) only asks WidgetKit for new timelines when something changed.
    @ObservationIgnored private var widgetSignature = ""
    /// Focus phase the Live Activity was last requested for. Keeps a card the
    /// person swiped away from coming back until the next phase starts.
    @ObservationIgnored private var activitySessionID: UUID?
    /// Set by stopFocus so the next sync removes the card without delay.
    @ObservationIgnored private var dismissActivityNow = false

    var onboarded: Bool {
        didSet { UserDefaults.standard.set(onboarded, forKey: "ma.onboarded") }
    }

    /// When on, switching a rule off or ending focus early costs a question too.
    var mindfulRelease: Bool {
        didSet { UserDefaults.standard.set(mindfulRelease, forKey: "ma.mindfulRelease") }
    }

    init() {
        onboarded = UserDefaults.standard.bool(forKey: "ma.onboarded")
        mindfulRelease = UserDefaults.standard.bool(forKey: "ma.mindfulRelease")
        reload()
    }

    // MARK: Sync

    /// Pulls everything the extensions may have changed and re-derives the
    /// shields. Called on launch, on every return to the foreground and
    /// once a second while the focus screen is open.
    func reload() {
        FocusEngine.advanceIfDue()
        LockdownEngine.liftIfDue()
        ShieldEngine.apply()
        rules = SharedStore.rules
        grants = SharedStore.grants.filter { $0.expiresAt > Date() }
        focus = SharedStore.focus
        focusSettings = SharedStore.focusSettings
        filter = FilterSettings.load()
        today = SharedStore.today()
        let stats = SharedStore.stats
        week = (0..<7).reversed().map { offset in
            stats[SharedStore.dayKey(Date().addingTimeInterval(Double(-offset) * 86_400))] ?? DayStats()
        }
        authorization = AuthorizationCenter.shared.authorizationStatus
        shortcutSettings = SharedStore.shortcutSettings
        shortcutPassUntil = SharedStore.shortcutPassUntil.flatMap { $0 > Date() ? $0 : nil }
        shortcutLastRun = SharedStore.shortcutLastRun
        lockdownUntil = SharedStore.activeLockdown()?.until
        if gate == nil, let request = SharedStore.shortcutRequest, request.isFresh {
            gate = .shortcut(request.app)
        } else if gate == nil, let pending = SharedStore.pending, pending.isFresh {
            gate = .unlock(pending)
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            Task { @MainActor in self.notificationsAllowed = allowed }
        }
        // Every focus action (startFocus, startBreak, skipBreak, stopFocus)
        // ends in reload(), and so does a phase the monitor moved on while
        // the app was closed. Syncing here covers all of them in one place.
        syncFocusActivity()
        reloadWidgetsIfChanged()
    }

    func tick() {
        if let focus, focus.isOver {
            reload()
        } else if grants.contains(where: { $0.expiresAt <= Date() }) {
            reload()
        } else if let lockdownUntil, lockdownUntil <= Date() {
            reload()
        }
    }

    // MARK: Permissions

    func requestScreenTime() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            // Declined or unavailable; the status below tells the UI which.
        }
        authorization = AuthorizationCenter.shared.authorizationStatus
    }

    func requestNotifications() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        notificationsAllowed = granted
    }

    // MARK: Rules

    func save(_ rule: BlockRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        persistRules()
    }

    func delete(_ rule: BlockRule) {
        // Deleting is switching off for good, so it waits for the lockdown too.
        guard !isLockedDown else { return }
        rules.removeAll { $0.id == rule.id }
        ShieldEngine.store(for: rule.id).clearAllSettings()
        persistRules()
    }

    /// Switching on is always free. Switching off asks a question first if
    /// mindful release is on, so the off switch is never a reflex.
    func setEnabled(_ rule: BlockRule, _ enabled: Bool) {
        if !enabled && isLockedDown { return }
        if !enabled && mindfulRelease {
            gate = .disableRule(rule.id)
            return
        }
        applyEnabled(rule.id, enabled)
    }

    func applyEnabled(_ id: UUID, _ enabled: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].isEnabled = enabled
        persistRules()
    }

    private func persistRules() {
        SharedStore.rules = rules
        Scheduler.syncRules(rules)
        reload()
    }

    func isShielding(_ rule: BlockRule) -> Bool {
        rule.isActive(at: Date()) && !rule.isEmpty
    }

    /// Unlocks this rule gave today, for the daily budget.
    func unlocksToday(_ rule: BlockRule) -> Int {
        SharedStore.unlocksToday(for: rule.id)
    }

    // MARK: Lockdown

    var isLockedDown: Bool {
        guard let lockdownUntil else { return false }
        return lockdownUntil > Date()
    }

    /// Blocks everything from every boundary and the focus list for
    /// `minutes`, with no way through. Starting again while one runs can
    /// only make it longer.
    func startLockdown(minutes: Int) {
        LockdownEngine.start(minutes: minutes)
        reload()
    }

    /// Ends the lockdown if its time is up. Before that, the only way out is
    /// the hard gate with five right answers, which this opens instead.
    func endLockdown() {
        guard let until = SharedStore.lockdown?.until else {
            lockdownUntil = nil
            return
        }
        if until <= Date() {
            LockdownEngine.lift()
            reload()
        } else {
            gate = .endLockdown
        }
    }

    // MARK: Unlocks

    func policy(for pending: PendingUnlock) -> UnlockPolicy {
        UnlockPolicy.current(application: pending.application, webDomain: pending.webDomain)
    }

    /// Opens the pending app for `minutes`. Returns false when the door
    /// closed while the gate was open (daily budget, lockdown, strict focus).
    @discardableResult
    func grant(_ pending: PendingUnlock, minutes: Int) -> Bool {
        let policy = self.policy(for: pending)
        guard policy.allowed else {
            dismissPending()
            return false
        }
        var grant = UnlockGrant(expiresAt: Date().addingTimeInterval(TimeInterval(minutes * 60)))
        if let app = pending.application { grant.applications = [app] }
        if let web = pending.webDomain { grant.webDomains = [web] }
        if let category = pending.category { grant.categories = [category] }
        var all = SharedStore.grants
        all.append(grant)
        SharedStore.grants = all
        SharedStore.pending = nil
        SharedStore.updateToday { $0.unlocks += 1 }
        SharedStore.recordUnlock(for: policy.matchedRuleIDs)
        Scheduler.watch(grant)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Notifier.gateID])
        reload()
        return true
    }

    func resist(_ pending: PendingUnlock) {
        SharedStore.pending = nil
        SharedStore.updateToday { $0.resisted += 1 }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Notifier.gateID])
        reload()
    }

    func dismissPending() {
        SharedStore.pending = nil
        reload()
    }

    func revoke(_ grant: UnlockGrant) {
        var all = SharedStore.grants
        all.removeAll { $0.id == grant.id }
        SharedStore.grants = all
        Scheduler.unwatch(grant)
        reload()
    }

    /// Opens the app behind a shield, if it is one we know a URL scheme for.
    func open(appNamed name: String?) {
        guard let name = name?.lowercased() else { return }
        let schemes: [(String, String)] = [
            ("instagram", "instagram://"),
            ("youtube", "youtube://"),
            ("linkedin", "linkedin://"),
            ("threads", "barcelona://"),
            ("facebook", "fb://"),
            ("reddit", "reddit://"),
            ("snapchat", "snapchat://"),
            ("pinterest", "pinterest://"),
            ("tiktok", "tiktok://"),
            ("twitter", "twitter://"),
        ]
        var scheme: String?
        if name == "x" {
            scheme = "twitter://"
        } else if let match = schemes.first(where: { name.contains($0.0) }) {
            scheme = match.1
        }
        guard let scheme, let url = URL(string: scheme) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Focus

    func startFocus() {
        FocusEngine.start(round: FocusEngine.upcomingRound)
        reload()
    }

    func startBreak() {
        FocusEngine.startBreak(after: focus?.round ?? 1)
        reload()
    }

    func skipBreak() {
        guard let focus, focus.phase != .focus else { return }
        FocusEngine.upcomingRound = focus.phase == .longBreak ? 1 : focus.round + 1
        startFocus()
    }

    func requestStopFocus() {
        if mindfulRelease, focus?.phase == .focus {
            gate = .stopFocus
        } else {
            stopFocus()
        }
    }

    func stopFocus() {
        FocusEngine.stop()
        // Stopped by hand: the reload below ends the Live Activity at once
        // instead of letting it linger like a phase that ran out.
        dismissActivityNow = true
        reload()
    }

    func saveFocusSettings() {
        SharedStore.focusSettings = focusSettings
        reload()
    }

    // MARK: Filter

    func saveFilter() {
        filter.save()
    }

    // MARK: Gate results

    func gatePassed(_ reason: GateReason) {
        switch reason {
        case .disableRule(let id): applyEnabled(id, false)
        case .stopFocus: stopFocus()
        case .endLockdown:
            LockdownEngine.lift()
            reload()
        case .unlock, .practice, .shortcut: break
        }
    }

    // MARK: Shortcuts mode

    func saveShortcutSettings() {
        SharedStore.shortcutSettings = shortcutSettings
    }

    /// What the Shortcuts gate may offer. It has no rules, only its own
    /// settings, but lockdown and strict focus hold here too.
    func shortcutPolicy() -> UnlockPolicy {
        var policy = UnlockPolicy()
        policy.questions = shortcutSettings.questions
        policy.minutes = shortcutSettings.minutes
        let now = Date()
        if let lockdown = SharedStore.activeLockdown(at: now) {
            policy.lockdownUntil = lockdown.until
            policy.allowed = false
        } else if let session = SharedStore.focus, session.phase == .focus, now < session.endsAt, SharedStore.focusSettings.strict {
            policy.focusLocked = true
            policy.allowed = false
            policy.focusEndsAt = session.endsAt
        }
        return policy
    }

    /// Opens an app's website in Safari, where the filter strips Reels.
    /// Counts as resisting: the app itself stayed closed.
    func openReelFree(_ url: URL) {
        SharedStore.pending = nil
        SharedStore.shortcutRequest = nil
        SharedStore.updateToday { $0.resisted += 1 }
        reload()
        UIApplication.shared.open(url)
    }

    /// Opens every guarded app for a while, then sends you to the one you
    /// came from. The automation fires again on the way back, finds the pass
    /// and stays out of the way.
    func openShortcutPass(minutes: Int, app: GuardedApp) {
        guard !isLockedDown else { return }
        SharedStore.shortcutPassUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        SharedStore.shortcutRequest = nil
        SharedStore.updateToday { $0.unlocks += 1 }
        reload()
        if let url = app.url { UIApplication.shared.open(url) }
    }

    func resistShortcut() {
        SharedStore.shortcutRequest = nil
        SharedStore.updateToday { $0.resisted += 1 }
        reload()
    }

    func dismissShortcut() {
        SharedStore.shortcutRequest = nil
        reload()
    }

    func closeShortcutPass() {
        SharedStore.shortcutPassUntil = nil
        reload()
    }

    // MARK: Reset

    /// Everything except a running lockdown: that one has no reset button.
    func resetEverything() {
        guard !isLockedDown else { return }
        ShieldEngine.clearEverything()
        SharedStore.rules = []
        SharedStore.grants = []
        SharedStore.pending = nil
        SharedStore.unlockLedger = UnlockLedger(day: SharedStore.dayKey())
        LockdownEngine.lift()
        FocusEngine.stop()
        Scheduler.syncRules([])
        reload()
    }

    // MARK: Deep links

    func handle(url: URL) {
        switch url.host {
        case "today": tab = .today
        case "focus": tab = .focus
        case "learn": tab = .learn
        case "rules", "lockdown": tab = .rules
        case "gate":
            if let pending = SharedStore.pending, pending.isFresh { gate = .unlock(pending) }
        default: break
        }
    }
}

// MARK: - Live Activity and widgets

extension AppModel {
    /// Brings the focus Live Activity in line with `focus`: requests one when
    /// a phase starts, updates it when the phase changes, ends it once focus
    /// is over. reload() runs once a second on the focus screen, so this only
    /// talks to ActivityKit when the content really differs.
    fileprivate func syncFocusActivity() {
        let all: [Activity<FocusActivityAttributes>] = Activity<FocusActivityAttributes>.activities
        let live: [Activity<FocusActivityAttributes>] = all.filter {
            $0.activityState != .ended && $0.activityState != .dismissed
        }

        guard let focus else {
            let immediately: Bool = dismissActivityNow
            dismissActivityNow = false
            activitySessionID = nil
            endFocusActivities(live, immediately: immediately)
            return
        }
        dismissActivityNow = false

        let state: FocusActivityAttributes.ContentState = activityState(for: focus)
        // Stale at the planned end: if the app is closed by then, the card
        // says the time is up instead of sitting at 0:00.
        let content = ActivityContent(state: state, staleDate: focus.endsAt)

        if let current = live.first {
            // A second one can only be left over from a crash; keep the first.
            endFocusActivities(Array(live.dropFirst()), immediately: true)
            activitySessionID = focus.id
            guard current.content.state != state else { return }
            Task { await current.update(content) }
            return
        }

        // Requested for this phase already, so the person swiped it away.
        guard activitySessionID != focus.id else { return }
        activitySessionID = focus.id
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try Activity.request(attributes: FocusActivityAttributes(), content: content, pushType: nil)
        } catch {
            // Switched off in Settings or over the system limit. The in-app
            // timer and the phase notification still carry the round.
        }
    }

    fileprivate func activityState(for session: FocusSession) -> FocusActivityAttributes.ContentState {
        FocusActivityAttributes.ContentState(
            phase: session.phase.rawValue,
            title: session.phase.title,
            startedAt: session.startedAt,
            endsAt: session.endsAt,
            round: session.round,
            totalRounds: max(1, focusSettings.roundsUntilLongBreak)
        )
    }

    /// A phase that ran out stays readable on the Lock Screen for a few
    /// minutes; a round stopped by hand disappears at once.
    fileprivate func endFocusActivities(_ activities: [Activity<FocusActivityAttributes>], immediately: Bool) {
        guard !activities.isEmpty else { return }
        let later: Date = Date().addingTimeInterval(10 * 60)
        let policy: ActivityUIDismissalPolicy = immediately ? .immediate : .after(later)
        for activity in activities {
            Task { await activity.end(nil, dismissalPolicy: policy) }
        }
    }

    /// Asks WidgetKit for fresh timelines, but only when something a widget
    /// draws has changed. Reloads from the app in the foreground do not count
    /// against the widget budget, yet once a second would still be wasteful.
    fileprivate func reloadWidgetsIfChanged() {
        let focusPart: String = focus.map { "\($0.id.uuidString):\($0.phase.rawValue)" } ?? "idle"
        let statsPart: String = "\(today.focusMinutes):\(today.correct):\(today.resisted)"
        let s = focusSettings
        let settingsPart: String = "\(s.focusMinutes):\(s.shortBreakMinutes):\(s.longBreakMinutes):\(s.roundsUntilLongBreak):\(s.autoStartFocus)"
        let signature: String = [SharedStore.dayKey(), statsPart, settingsPart, focusPart].joined(separator: "|")
        guard signature != widgetSignature else { return }
        widgetSignature = signature
        WidgetCenter.shared.reloadAllTimelines()
    }
}

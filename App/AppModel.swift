import FamilyControls
import Foundation
import ManagedSettings
import Observation
import SwiftUI
import UserNotifications

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

    var id: String {
        switch self {
        case .unlock(let pending): "unlock-\(pending.id)"
        case .disableRule(let id): "rule-\(id)"
        case .stopFocus: "focus"
        case .practice: "practice"
        case .shortcut(let app): "shortcut-\(app)"
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
    let decks = DeckStore()

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
        if gate == nil, let request = SharedStore.shortcutRequest, request.isFresh {
            gate = .shortcut(request.app)
        } else if gate == nil, let pending = SharedStore.pending, pending.isFresh {
            gate = .unlock(pending)
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            Task { @MainActor in self.notificationsAllowed = allowed }
        }
    }

    func tick() {
        if let focus, focus.isOver {
            reload()
        } else if grants.contains(where: { $0.expiresAt <= Date() }) {
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
        rules.removeAll { $0.id == rule.id }
        ShieldEngine.store(for: rule.id).clearAllSettings()
        persistRules()
    }

    /// Switching on is always free. Switching off asks a question first if
    /// mindful release is on, so the off switch is never a reflex.
    func setEnabled(_ rule: BlockRule, _ enabled: Bool) {
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

    // MARK: Unlocks

    func policy(for pending: PendingUnlock) -> UnlockPolicy {
        UnlockPolicy.current(application: pending.application, webDomain: pending.webDomain)
    }

    func grant(_ pending: PendingUnlock, minutes: Int) {
        var grant = UnlockGrant(expiresAt: Date().addingTimeInterval(TimeInterval(minutes * 60)))
        if let app = pending.application { grant.applications = [app] }
        if let web = pending.webDomain { grant.webDomains = [web] }
        if let category = pending.category { grant.categories = [category] }
        var all = SharedStore.grants
        all.append(grant)
        SharedStore.grants = all
        SharedStore.pending = nil
        SharedStore.updateToday { $0.unlocks += 1 }
        Scheduler.watch(grant)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Notifier.gateID])
        reload()
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
        case .unlock, .practice, .shortcut: break
        }
    }

    // MARK: Shortcuts mode

    func saveShortcutSettings() {
        SharedStore.shortcutSettings = shortcutSettings
    }

    /// Opens every guarded app for a while, then sends you to the one you
    /// came from. The automation fires again on the way back, finds the pass
    /// and stays out of the way.
    func openShortcutPass(minutes: Int, app: GuardedApp) {
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

    func resetEverything() {
        ShieldEngine.clearEverything()
        SharedStore.rules = []
        SharedStore.grants = []
        SharedStore.pending = nil
        FocusEngine.stop()
        Scheduler.syncRules([])
        reload()
    }

    // MARK: Deep links

    func handle(url: URL) {
        switch url.host {
        case "focus": tab = .focus
        case "learn": tab = .learn
        case "gate":
            if let pending = SharedStore.pending, pending.isFresh { gate = .unlock(pending) }
        default: break
        }
    }
}

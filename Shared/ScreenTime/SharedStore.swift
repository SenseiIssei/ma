import Foundation
import FamilyControls
import ManagedSettings

/// Typed access to the App Group files. Every accessor reads from disk, on
/// purpose: the extensions run in their own processes and a cached copy
/// would drift from what the app last wrote.
enum SharedStore {
    static var rules: [BlockRule] {
        get { MaShared.read([BlockRule].self, from: "rules.json") ?? [] }
        set { MaShared.write(newValue, to: "rules.json") }
    }

    static var grants: [UnlockGrant] {
        get { MaShared.read([UnlockGrant].self, from: "grants.json") ?? [] }
        set { MaShared.write(newValue, to: "grants.json") }
    }

    static var pending: PendingUnlock? {
        get { MaShared.read(PendingUnlock.self, from: "pending.json") }
        set { MaShared.write(newValue, to: "pending.json") }
    }

    static var focus: FocusSession? {
        get { MaShared.read(FocusSession.self, from: "focus.json") }
        set { MaShared.write(newValue, to: "focus.json") }
    }

    static var focusSettings: FocusSettings {
        get { MaShared.read(FocusSettings.self, from: "focus-settings.json") ?? FocusSettings() }
        set { MaShared.write(newValue, to: "focus-settings.json") }
    }

    /// Rule ids that currently own a named ManagedSettingsStore. Kept so a
    /// deleted rule's store can still be found and emptied.
    static var knownStoreIDs: Set<UUID> {
        get { MaShared.read(Set<UUID>.self, from: "stores.json") ?? [] }
        set { MaShared.write(newValue, to: "stores.json") }
    }

    static var tokenNames: [TokenName] {
        get { MaShared.read([TokenName].self, from: "names.json") ?? [] }
        set { MaShared.write(newValue, to: "names.json") }
    }

    // MARK: Limits

    static var unlockLedger: UnlockLedger {
        get { MaShared.read(UnlockLedger.self, from: "unlock-ledger.json") ?? UnlockLedger(day: dayKey()) }
        set { MaShared.write(newValue, to: "unlock-ledger.json") }
    }

    /// Unlocks `rule` gave today.
    static func unlocksToday(for rule: UUID, now: Date = Date()) -> Int {
        unlockLedger.count(for: rule, on: dayKey(now))
    }

    static func recordUnlock(for rules: [UUID], now: Date = Date()) {
        guard !rules.isEmpty else { return }
        var ledger = unlockLedger
        ledger.record(rules, on: dayKey(now))
        unlockLedger = ledger
    }

    /// The running lockdown, if any. An expired one may still lie on disk
    /// until the monitor or the app clears it; always ask `isActive`.
    static var lockdown: LockdownState? {
        get { MaShared.read(LockdownState.self, from: "lockdown.json") }
        set { MaShared.write(newValue, to: "lockdown.json") }
    }

    static func activeLockdown(at now: Date = Date()) -> LockdownState? {
        guard let state = lockdown, state.isActive(at: now) else { return nil }
        return state
    }

    static func name(for application: ApplicationToken) -> String? {
        tokenNames.first { $0.application == application }?.name
    }

    static func name(for webDomain: WebDomainToken) -> String? {
        tokenNames.first { $0.webDomain == webDomain }?.name
    }

    static func remember(name: String, application: ApplicationToken? = nil, webDomain: WebDomainToken? = nil) {
        var names = tokenNames
        if let application {
            guard !names.contains(where: { $0.application == application && $0.name == name }) else { return }
            names.removeAll { $0.application == application }
        } else if let webDomain {
            guard !names.contains(where: { $0.webDomain == webDomain && $0.name == name }) else { return }
            names.removeAll { $0.webDomain == webDomain }
        } else {
            return
        }
        names.append(TokenName(application: application, webDomain: webDomain, name: name))
        tokenNames = Array(names.suffix(200))
    }

    // MARK: Stats

    static var stats: [String: DayStats] {
        get { MaShared.read([String: DayStats].self, from: "stats.json") ?? [:] }
        set { MaShared.write(newValue, to: "stats.json") }
    }

    static func dayKey(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func today() -> DayStats {
        stats[dayKey()] ?? DayStats()
    }

    static func updateToday(_ change: (inout DayStats) -> Void) {
        var all = stats
        var day = all[dayKey()] ?? DayStats()
        change(&day)
        all[dayKey()] = day
        // A year of history is plenty for the garden and costs a few kilobytes.
        if all.count > 400 {
            for key in all.keys.sorted().prefix(all.count - 400) { all.removeValue(forKey: key) }
        }
        stats = all
    }
}

// MARK: - Shortcuts mode

/// Settings for the gate that a Shortcuts automation opens. Works without
/// Screen Time, which is why it lives apart from the rules.
struct ShortcutSettings: Codable {
    var questions = 1
    var minutes = 5
}

/// Left by the Pause intent for the app to pick up once it is in front.
struct ShortcutRequest: Codable {
    var app: String
    var createdAt = Date()

    var isFresh: Bool { Date().timeIntervalSince(createdAt) < 5 * 60 }
}

extension SharedStore {
    static var shortcutSettings: ShortcutSettings {
        get { MaShared.read(ShortcutSettings.self, from: "shortcut-settings.json") ?? ShortcutSettings() }
        set { MaShared.write(newValue, to: "shortcut-settings.json") }
    }

    static var shortcutRequest: ShortcutRequest? {
        get { MaShared.read(ShortcutRequest.self, from: "shortcut-request.json") }
        set { MaShared.write(newValue, to: "shortcut-request.json") }
    }

    /// While this lies in the future, the automation lets every app through.
    /// This is also what breaks the loop: opening the app after answering
    /// fires the automation again, and it finds the pass.
    static var shortcutPassUntil: Date? {
        get { MaShared.read(Date.self, from: "shortcut-pass.json") }
        set { MaShared.write(newValue, to: "shortcut-pass.json") }
    }

    /// Last time the automation ran, so the setup screen can show it works.
    static var shortcutLastRun: Date? {
        get { MaShared.read(Date.self, from: "shortcut-last-run.json") }
        set { MaShared.write(newValue, to: "shortcut-last-run.json") }
    }
}

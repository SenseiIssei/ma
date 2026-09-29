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

    static func dayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
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

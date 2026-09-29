import Foundation
import FamilyControls
import ManagedSettings

/// Turns rules, unlocks and the focus timer into ManagedSettings shields.
///
/// Each rule owns a named store, focus owns one more. The system combines
/// all stores and the strictest wins, so an unlock has to be written into
/// every rule store as a gap instead of into a store of its own.
enum ShieldEngine {
    static func store(for ruleID: UUID) -> ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name("rule.\(ruleID.uuidString)"))
    }

    static var focusStore: ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name("focus"))
    }

    /// Lockdown has a store of its own and never gets gaps, so no unlock,
    /// grant or pass can reach through it.
    static var lockdownStore: ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name("lockdown"))
    }

    /// Recomputes every shield from what is on disk. Cheap and idempotent,
    /// so every entry point simply calls it.
    ///
    /// `forceActive` and `forceInactive` exist for the monitor extension: a
    /// schedule callback can arrive a second before or after its minute, and
    /// the callback itself is the better witness than the clock.
    static func apply(now: Date = Date(), forceActive: Set<UUID> = [], forceInactive: Set<UUID> = []) {
        let allGrants = SharedStore.grants
        let grants = allGrants.filter { $0.expiresAt > now }
        if grants.count != allGrants.count { SharedStore.grants = grants }

        var openApps = Set<ApplicationToken>()
        var openWeb = Set<WebDomainToken>()
        var openCategories = Set<ActivityCategoryToken>()
        for grant in grants {
            openApps.formUnion(grant.applications)
            openWeb.formUnion(grant.webDomains)
            openCategories.formUnion(grant.categories)
        }

        let rules = SharedStore.rules
        let ids = Set(rules.map(\.id))
        for stale in SharedStore.knownStoreIDs.subtracting(ids) {
            store(for: stale).clearAllSettings()
        }
        SharedStore.knownStoreIDs = ids

        for rule in rules {
            let active = rule.isEnabled
                && !forceInactive.contains(rule.id)
                && (forceActive.contains(rule.id) || rule.isActive(at: now))
            let ruleStore = store(for: rule.id)
            guard active, !rule.isEmpty else {
                ruleStore.clearAllSettings()
                continue
            }
            if rule.allowsUnlock {
                shield(ruleStore, with: Tokens(rule.selection), apps: openApps, web: openWeb, categories: openCategories)
            } else {
                shield(ruleStore, with: Tokens(rule.selection), apps: [], web: [], categories: [])
            }
        }

        if let session = SharedStore.focus, session.phase == .focus, now < session.endsAt {
            let settings = SharedStore.focusSettings
            let selection = focusSelection(settings: settings, rules: rules)
            if settings.strict {
                shield(focusStore, with: selection, apps: [], web: [], categories: [])
            } else {
                shield(focusStore, with: selection, apps: openApps, web: openWeb, categories: openCategories)
            }
        } else {
            focusStore.clearAllSettings()
        }

        if let lockdown = SharedStore.lockdown {
            if lockdown.isActive(at: now) {
                let tokens = lockdownSelection(lockdown, settings: SharedStore.focusSettings, rules: rules)
                shield(lockdownStore, with: tokens, apps: [], web: [], categories: [])
            } else {
                // Expired while nobody was watching: tidy up here as well.
                lockdownStore.clearAllSettings()
                SharedStore.lockdown = nil
            }
        } else {
            lockdownStore.clearAllSettings()
        }
    }

    /// Lifts everything Ma ever put up. Used by "reset" in settings.
    static func clearEverything() {
        for id in SharedStore.knownStoreIDs { store(for: id).clearAllSettings() }
        for rule in SharedStore.rules { store(for: rule.id).clearAllSettings() }
        focusStore.clearAllSettings()
        lockdownStore.clearAllSettings()
        ManagedSettingsStore().clearAllSettings()
    }

    /// Plain sets, so selections can be merged without relying on
    /// FamilyActivitySelection being mutable.
    struct Tokens {
        var apps = Set<ApplicationToken>()
        var categories = Set<ActivityCategoryToken>()
        var web = Set<WebDomainToken>()

        init() {}

        init(_ selection: FamilyActivitySelection) {
            apps = selection.applicationTokens
            categories = selection.categoryTokens
            web = selection.webDomainTokens
        }

        mutating func merge(_ other: Tokens) {
            apps.formUnion(other.apps)
            categories.formUnion(other.categories)
            web.formUnion(other.web)
        }

        var count: Int { apps.count + categories.count + web.count }
        var isEmpty: Bool { count == 0 }
    }

    static func focusSelection(settings: FocusSettings, rules: [BlockRule]) -> Tokens {
        let own = Tokens(settings.selection)
        if !own.isEmpty { return own }
        var merged = Tokens()
        for rule in rules {
            merged.apps.formUnion(rule.selection.applicationTokens)
            merged.categories.formUnion(rule.selection.categoryTokens)
            merged.web.formUnion(rule.selection.webDomainTokens)
        }
        return merged
    }

    /// Everything a lockdown covers: what was blocked when it started, plus
    /// every boundary (switched off ones too) and the focus list as they are
    /// now. Adding apps during a lockdown tightens it, removing them does not.
    static func lockdownSelection(_ lockdown: LockdownState, settings: FocusSettings, rules: [BlockRule]) -> Tokens {
        var tokens = Tokens()
        tokens.apps = lockdown.applications
        tokens.categories = lockdown.categories
        tokens.web = lockdown.webDomains
        tokens.merge(Tokens(settings.selection))
        for rule in rules { tokens.merge(Tokens(rule.selection)) }
        return tokens
    }

    private static func shield(
        _ store: ManagedSettingsStore,
        with tokens: Tokens,
        apps: Set<ApplicationToken>,
        web: Set<WebDomainToken>,
        categories: Set<ActivityCategoryToken>
    ) {
        let blockedApps = tokens.apps.subtracting(apps)
        store.shield.applications = blockedApps.isEmpty ? nil : blockedApps

        let blockedCategories = tokens.categories.subtracting(categories)
        store.shield.applicationCategories = blockedCategories.isEmpty
            ? nil
            : .specific(blockedCategories, except: apps)

        let blockedWeb = tokens.web.subtracting(web)
        store.shield.webDomains = blockedWeb.isEmpty ? nil : blockedWeb
        store.shield.webDomainCategories = blockedCategories.isEmpty
            ? nil
            : .specific(blockedCategories, except: web)
    }
}

/// What the shield may offer for one blocked thing.
struct UnlockPolicy {
    var allowed = true
    var questions = 1
    var minutes = 5
    var focusLocked = false
    var ruleName: String?
    var focusEndsAt: Date?
    /// Set while a lockdown runs. Nothing opens, not even with answers.
    var lockdownUntil: Date?
    /// The daily unlock budget of a matching rule is used up.
    var budgetSpent = false
    /// Smallest daily limit among the matching rules, if any has one.
    var dailyLimit: Int?
    /// Unlocks left today under that limit.
    var unlocksLeft: Int?
    /// Unlocks the matching rules already gave today (the highest count).
    var unlocksToday = 0
    /// A matching rule makes every unlock cost one answer more.
    var rising = false
    /// Seconds the gate waits before the first question.
    var waitSeconds = 0
    /// Rules the unlock will be counted against.
    var matchedRuleIDs: [UUID] = []

    var isLockdown: Bool { lockdownUntil != nil }

    static func current(application: ApplicationToken? = nil, webDomain: WebDomainToken? = nil, now: Date = Date()) -> UnlockPolicy {
        var policy = UnlockPolicy()

        if let lockdown = SharedStore.activeLockdown(at: now) {
            policy.lockdownUntil = lockdown.until
            policy.allowed = false
            return policy
        }

        if let session = SharedStore.focus, session.phase == .focus, now < session.endsAt {
            policy.focusEndsAt = session.endsAt
            if SharedStore.focusSettings.strict {
                policy.focusLocked = true
                policy.allowed = false
                return policy
            }
        }

        let active = SharedStore.rules.filter { $0.isActive(at: now) && !$0.isEmpty }
        var matched = active.filter { rule in
            if let application { return rule.selection.applicationTokens.contains(application) }
            if let webDomain { return rule.selection.webDomainTokens.contains(webDomain) }
            return false
        }
        // Tokens reached through a category cannot be matched directly: the
        // category is opaque. Fall back to the rules that shield categories.
        if matched.isEmpty {
            matched = active.filter { !$0.selection.categoryTokens.isEmpty }
        }
        guard !matched.isEmpty else { return policy }

        let ledger = SharedStore.unlockLedger
        let day = SharedStore.dayKey(now)
        policy.apply(matched) { ledger.count(for: $0, on: day) }
        return policy
    }

    /// The pure part: folds the matching rules and their counts for today
    /// into one policy. The strictest rule wins every question.
    mutating func apply(_ matched: [BlockRule], unlocksToday used: (UUID) -> Int) {
        guard !matched.isEmpty else { return }
        matchedRuleIDs = matched.map(\.id)
        ruleName = matched.first?.name

        let counts: [Int] = matched.map { used($0.id) }
        unlocksToday = counts.max() ?? 0

        if let wall = matched.first(where: { !$0.allowsUnlock }) {
            allowed = false
            ruleName = wall.name
            return
        }

        for (rule, count) in zip(matched, counts) {
            guard let limit = rule.dailyUnlockLimit, let left = rule.unlocksLeft(usedToday: count) else { continue }
            if unlocksLeft == nil || left < (unlocksLeft ?? 0) {
                unlocksLeft = left
                dailyLimit = limit
                if left == 0 { ruleName = rule.name }
            }
        }
        if unlocksLeft == 0 {
            allowed = false
            budgetSpent = true
            return
        }

        let needed: [Int] = zip(matched, counts).map { $0.questionsNeeded(unlocksToday: $1) }
        questions = max(1, needed.max() ?? 1)
        minutes = max(1, matched.map(\.unlockMinutes).min() ?? 5)
        waitSeconds = max(0, matched.map(\.waitSeconds).max() ?? 0)
        rising = matched.contains(where: \.risingFriction)
    }
}

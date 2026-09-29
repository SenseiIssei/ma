import Foundation
import DeviceActivity

/// Wraps DeviceActivityCenter. The monitor extension is only woken for
/// activities registered here, which is how shields change while the app
/// is closed.
///
/// DeviceActivity refuses intervals shorter than 15 minutes. For shorter
/// deadlines (a 5 minute unlock, a 5 minute break) the interval is padded
/// to 16 minutes and the warning callback is aimed at the real moment.
enum Scheduler {
    static let unlockPrefix = "unlock."
    static let rulePrefix = "rule."
    static let focusName = "focus"

    private static var center: DeviceActivityCenter { DeviceActivityCenter() }

    // MARK: Rules

    static func syncRules(_ rules: [BlockRule]) {
        let activityCenter = center
        let old = activityCenter.activities.filter { $0.rawValue.hasPrefix(rulePrefix) }
        // An empty list would stop every activity, unlocks and focus included.
        if !old.isEmpty { activityCenter.stopMonitoring(old) }

        for rule in rules where rule.isEnabled {
            guard let s = rule.schedule, s.startMinute != s.endMinute else { continue }
            let days = s.effectiveWeekdays
            if days.count == 7 {
                let schedule = DeviceActivitySchedule(
                    intervalStart: DateComponents(hour: s.startMinute / 60, minute: s.startMinute % 60),
                    intervalEnd: DateComponents(hour: s.endMinute / 60, minute: s.endMinute % 60),
                    repeats: true
                )
                try? activityCenter.startMonitoring(name(rule: rule.id, suffix: "d"), during: schedule)
            } else {
                for day in days {
                    let endDay = s.wrapsMidnight ? (day % 7) + 1 : day
                    let schedule = DeviceActivitySchedule(
                        intervalStart: DateComponents(hour: s.startMinute / 60, minute: s.startMinute % 60, weekday: day),
                        intervalEnd: DateComponents(hour: s.endMinute / 60, minute: s.endMinute % 60, weekday: endDay),
                        repeats: true
                    )
                    try? activityCenter.startMonitoring(name(rule: rule.id, suffix: String(day)), during: schedule)
                }
            }
        }
    }

    static func name(rule id: UUID, suffix: String) -> DeviceActivityName {
        DeviceActivityName("\(rulePrefix)\(id.uuidString).\(suffix)")
    }

    static func ruleID(of activity: DeviceActivityName) -> UUID? {
        let raw = activity.rawValue
        guard raw.hasPrefix(rulePrefix) else { return nil }
        let parts = raw.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return UUID(uuidString: String(parts[1]))
    }

    // MARK: Unlocks

    static func watch(_ grant: UnlockGrant) {
        oneShot(DeviceActivityName(unlockPrefix + grant.id.uuidString), firingAt: grant.expiresAt)
    }

    static func unwatch(_ grant: UnlockGrant) {
        stop(DeviceActivityName(unlockPrefix + grant.id.uuidString))
    }

    static func grantID(of activity: DeviceActivityName) -> UUID? {
        let raw = activity.rawValue
        guard raw.hasPrefix(unlockPrefix) else { return nil }
        return UUID(uuidString: String(raw.dropFirst(unlockPrefix.count)))
    }

    // MARK: Focus

    static func watchFocus(_ session: FocusSession?) {
        let name = DeviceActivityName(focusName)
        center.stopMonitoring([name])
        guard let session else { return }
        oneShot(name, firingAt: session.endsAt)
    }

    static func stop(_ activity: DeviceActivityName) {
        center.stopMonitoring([activity])
    }

    // MARK: Plumbing

    private static func oneShot(_ name: DeviceActivityName, firingAt target: Date) {
        let now = Date()
        let wanted = max(30, target.timeIntervalSince(now))
        let span = max(16 * 60, wanted + 60)
        let lead = Int((span - wanted).rounded())
        let schedule = DeviceActivitySchedule(
            intervalStart: components(now),
            intervalEnd: components(now.addingTimeInterval(span)),
            repeats: false,
            warningTime: DateComponents(minute: lead / 60, second: lead % 60)
        )
        let activityCenter = center
        activityCenter.stopMonitoring([name])
        try? activityCenter.startMonitoring(name, during: schedule)
    }

    private static func components(_ date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }
}

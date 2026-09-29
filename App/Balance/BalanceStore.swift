import Foundation
import Observation
import SwiftUI
import UserNotifications

/// Movement, water, meals and the evening wind-down. Only the app reads
/// these, but they live in the App Group like everything else, so a backup
/// of the container holds the whole picture.
@MainActor
@Observable
final class BalanceStore {
    private(set) var days: [String: BalanceDay] = [:]
    private(set) var settings = BalanceSettings()

    /// Identifier of the daily wind-down notification.
    static let windDownID = "ma.winddown"
    /// Route in the notification's userInfo, read by the tab bar.
    static let windDownRoute = "winddown"

    private enum File {
        static let days = "balance-days.json"
        static let settings = "balance-settings.json"
    }

    init() {
        days = MaShared.read([String: BalanceDay].self, from: File.days) ?? [:]
        settings = MaShared.read(BalanceSettings.self, from: File.settings) ?? BalanceSettings()
    }

    // MARK: Days

    func key(for date: Date) -> String { SharedStore.dayKey(date) }

    var todayKey: String { SharedStore.dayKey() }

    var today: BalanceDay { days[todayKey] ?? BalanceDay() }

    func day(_ date: Date) -> BalanceDay { days[key(for: date)] ?? BalanceDay() }

    /// The evening the wind-down list belongs to; after midnight that is
    /// still yesterday's.
    var tonightKey: String { SharedStore.dayKey(BalanceNight.date(for: Date())) }

    var tonight: BalanceDay { days[tonightKey] ?? BalanceDay() }

    private func change(_ key: String, _ edit: (inout BalanceDay) -> Void) {
        var entry = days[key] ?? BalanceDay()
        edit(&entry)
        days[key] = entry
        persistDays()
    }

    private func persistDays() {
        // A year of history is plenty for the week view and the streaks.
        if days.count > 400 {
            for key in days.keys.sorted().prefix(days.count - 400) { days.removeValue(forKey: key) }
        }
        MaShared.write(days, to: File.days)
    }

    private func persistSettings() {
        MaShared.write(settings, to: File.settings)
    }

    // MARK: Water

    var waterToday: Int { today.water }

    var waterProgress: Double {
        WaterMath.progress(glasses: today.water, target: settings.waterTarget)
    }

    func addWater() {
        let target = settings.waterTarget
        change(todayKey) { day in
            day.water = WaterMath.added(to: day.water)
            day.waterGoal = target
        }
    }

    func removeWater() {
        change(todayKey) { day in
            day.water = WaterMath.removed(from: day.water)
        }
    }

    func setWaterTarget(_ target: Int) {
        settings.waterTarget = WaterMath.clampTarget(target)
        persistSettings()
        // Today follows the new target; earlier days keep the one they had.
        if days[todayKey] != nil {
            let goal = settings.waterTarget
            change(todayKey) { $0.waterGoal = goal }
        }
    }

    var waterStreak: Int {
        let target = settings.waterTarget
        return BalanceStreak.count(key: { SharedStore.dayKey($0) }) { key in
            self.days[key]?.waterMet(defaultTarget: target) ?? false
        }
    }

    // MARK: Meals

    func toggleEaten(_ meal: Meal) {
        change(todayKey) { day in
            var entry = day.meal(meal)
            entry.eaten.toggle()
            day.meals[meal.rawValue] = entry
        }
    }

    /// Tagging a meal also marks it as eaten; a tag on an uneaten meal
    /// would make no sense.
    func toggle(_ tag: MealTag, for meal: Meal) {
        change(todayKey) { day in
            var entry = day.meal(meal)
            if entry.tags.contains(tag) {
                entry.tags.remove(tag)
            } else {
                entry.tags.insert(tag)
                entry.eaten = true
            }
            day.meals[meal.rawValue] = entry
        }
    }

    // MARK: Movement

    var moveMinutesToday: Int { today.moveMinutes }

    var moveProgress: Double {
        let goal: Double = Double(max(1, settings.moveGoalMinutes))
        return min(1, Double(today.moveSeconds) / 60 / goal)
    }

    func recordMove(seconds: Int) {
        guard seconds > 0 else { return }
        change(todayKey) { day in
            day.moveSessions += 1
            day.moveSeconds += seconds
        }
    }

    func setMoveGoal(_ minutes: Int) {
        settings.moveGoalMinutes = max(1, minutes)
        persistSettings()
    }

    func setVoice(_ on: Bool) {
        settings.voice = on
        persistSettings()
    }

    var moveStreak: Int {
        BalanceStreak.count(key: { SharedStore.dayKey($0) }) { key in
            (self.days[key]?.moveSessions ?? 0) > 0
        }
    }

    // MARK: Sleep

    var windDownProgress: Double { tonight.windDownProgress }

    func toggle(_ item: WindDownItem) {
        change(tonightKey) { day in
            if day.windDown.contains(item) {
                day.windDown.remove(item)
            } else {
                day.windDown.insert(item)
            }
        }
    }

    func setSleep(_ plan: SleepPlan) {
        guard plan != settings.sleep else { return }
        settings.sleep = plan
        persistSettings()
        if settings.reminder { scheduleWindDown() }
    }

    /// Turning the reminder on asks for permission first. Returns whether it
    /// ended up on, so the toggle can fall back when the answer was no.
    @discardableResult
    func setReminder(_ on: Bool) async -> Bool {
        guard on else {
            settings.reminder = false
            persistSettings()
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.windDownID])
            return false
        }
        let granted: Bool = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        settings.reminder = granted
        persistSettings()
        if granted { scheduleWindDown() }
        return granted
    }

    /// One repeating notification at bedtime minus the wind-down. Same
    /// identifier every time, so a new plan replaces the old one.
    private func scheduleWindDown() {
        let plan = settings.sleep
        let start: Int = plan.windDownStart
        var when = DateComponents()
        when.hour = start / 60
        when.minute = start % 60

        let content = UNMutableNotificationContent()
        content.title = tr("Time to wind down", "Zeit zum Runterfahren")
        content.body = tr("Bedtime is at \(SleepPlan.clock(plan.bedtime)). Put the phone aside, dim the lights, breathe slowly.",
                          "Um \(SleepPlan.clock(plan.bedtime)) ist Schlafenszeit. Leg das Handy weg, dimm das Licht und atme ruhig.")
        content.sound = .default
        content.interruptionLevel = .active
        content.userInfo = [Notifier.routeKey: Self.windDownRoute]

        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        let request = UNNotificationRequest(identifier: Self.windDownID, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.windDownID])
        center.add(request)
    }

    // MARK: Summary

    /// Each ring full, a day in balance.
    var dayInBalance: Bool {
        waterProgress >= 1 && moveProgress >= 1 && windDownProgress >= 1
    }

    struct WeekDay: Identifiable {
        let date: Date
        let key: String
        let water: Bool
        let vegetables: Bool
        let moveMinutes: Int

        var id: String { key }
    }

    func week(asOf date: Date = Date()) -> [WeekDay] {
        let target = settings.waterTarget
        return BalanceStreak.lastDays(7, asOf: date).map { day in
            let key: String = SharedStore.dayKey(day)
            let entry: BalanceDay = days[key] ?? BalanceDay()
            return WeekDay(date: day, key: key,
                           water: entry.waterMet(defaultTarget: target),
                           vegetables: entry.hadVegetables,
                           moveMinutes: entry.moveMinutes)
        }
    }
}

import DeviceActivity
import ManagedSettings
import SwiftUI

/// Everything the week view shows, boiled down from the raw activity data.
struct WeekActivity {
    struct DayUsage: Identifiable {
        let start: Date
        let duration: TimeInterval
        var id: Date { start }
    }

    struct AppUsage: Identifiable {
        let rank: Int
        let token: ApplicationToken?
        let name: String?
        let duration: TimeInterval
        let pickups: Int
        var id: Int { rank }
    }

    var total: TimeInterval = 0
    /// Always seven entries, oldest first, the last one is today.
    var days: [DayUsage] = []
    var topApps: [AppUsage] = []
    var pickups = 0

    var hasData: Bool { total > 0 }
}

/// The scene for the "week" context. The app asks with a daily segment over
/// the last seven days, so every ActivitySegment here is one calendar day.
struct WeekActivityReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .week
    let content: (WeekActivity) -> WeekActivityView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> WeekActivity {
        let calendar = Calendar.current
        var perDay: [Date: TimeInterval] = [:]
        var perApp: [AppKey: AppTally] = [:]
        var total: TimeInterval = 0
        var pickups = 0

        // One DeviceActivityData per device and user. Without a device filter
        // that is only this iPhone, but summing keeps it right either way.
        for await device in data {
            for await segment in device.activitySegments {
                let day: Date = calendar.startOfDay(for: segment.dateInterval.start)
                perDay[day, default: 0] += segment.totalActivityDuration
                total += segment.totalActivityDuration
                // Pickups that led into no app; the rest are counted per app below.
                pickups += segment.totalPickupsWithoutApplicationActivity

                for await category in segment.categories {
                    for await usage in category.applications {
                        pickups += usage.numberOfPickups
                        guard let key = AppKey(usage.application) else { continue }
                        var tally: AppTally = perApp[key] ?? AppTally(
                            token: usage.application.token,
                            name: usage.application.localizedDisplayName
                        )
                        tally.duration += usage.totalActivityDuration
                        tally.pickups += usage.numberOfPickups
                        perApp[key] = tally
                    }
                }
            }
        }

        var result = WeekActivity()
        result.total = total
        result.pickups = pickups
        result.days = Self.lastSevenDays(from: perDay, calendar: calendar)
        result.topApps = Self.topFive(perApp)
        return result
    }

    private static func lastSevenDays(from perDay: [Date: TimeInterval], calendar: Calendar) -> [WeekActivity.DayUsage] {
        let today: Date = calendar.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let start: Date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return WeekActivity.DayUsage(start: start, duration: perDay[start] ?? 0)
        }
    }

    private static func topFive(_ perApp: [AppKey: AppTally]) -> [WeekActivity.AppUsage] {
        // Under a minute over a whole week is noise, not a habit.
        let meaningful: [AppTally] = perApp.values.filter { $0.duration >= 60 }
        let sorted: [AppTally] = meaningful.sorted { $0.duration > $1.duration }
        return sorted.prefix(5).enumerated().map { index, tally in
            WeekActivity.AppUsage(rank: index + 1, token: tally.token, name: tally.name,
                                  duration: tally.duration, pickups: tally.pickups)
        }
    }
}

/// The same app shows up once per day segment, so tallies are keyed by its
/// token, or by bundle id when iOS hands out no token.
private enum AppKey: Hashable {
    case token(ApplicationToken)
    case bundle(String)

    init?(_ application: Application) {
        if let token = application.token {
            self = .token(token)
        } else if let bundle = application.bundleIdentifier {
            self = .bundle(bundle)
        } else {
            return nil
        }
    }
}

private struct AppTally {
    let token: ApplicationToken?
    let name: String?
    var duration: TimeInterval = 0
    var pickups = 0
}

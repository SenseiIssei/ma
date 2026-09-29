import DeviceActivity
import SwiftUI

/// Entry point of the Screen Time report. iOS runs this in a sealed sandbox:
/// it may read usage data and draw it, but nothing it sees can leave, not
/// even back to the app. That is why the whole view is built in here.
@main
struct MaReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        WeekActivityReport { activity in
            WeekActivityView(activity: activity)
        }
    }
}

extension DeviceActivityReport.Context {
    /// Must match the context the app asks for in WeekReviewView.
    static let week = Self("week")
}

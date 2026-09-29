import FamilyControls
import ManagedSettings
import SwiftUI

/// What the app embeds under "Screen time". The host gives this view a fixed
/// height (a report cannot size itself to its content), so everything is laid
/// out top down and the layout stays within about 680 points.
struct WeekActivityView: View {
    let activity: WeekActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if activity.hasData {
                totalCard
                daysCard
                if !activity.topApps.isEmpty { appsCard }
            } else {
                emptyCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Total

    private var totalCard: some View {
        let perDay: TimeInterval = activity.total / 7
        let average: String = tr("about \(ReportFormat.duration(perDay)) a day",
                                 "etwa \(ReportFormat.duration(perDay)) am Tag")
        return VStack(alignment: .leading, spacing: 8) {
            Text(tr("SCREEN TIME, LAST 7 DAYS", "BILDSCHIRMZEIT, LETZTE 7 TAGE"))
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(ReportTheme.inkSoft)
            Text(ReportFormat.duration(activity.total))
                .font(ReportTheme.display(34))
                .monospacedDigit()
                .foregroundStyle(ReportTheme.ink)
            HStack(spacing: 10) {
                Text(average)
                    .font(.system(size: 14))
                    .foregroundStyle(ReportTheme.inkSoft)
                Spacer(minLength: 0)
                if activity.pickups > 0 { pickupsPill }
            }
        }
        .reportCard(padding: 20)
        .accessibilityElement(children: .combine)
    }

    private var pickupsPill: some View {
        let count = activity.pickups
        let text: String = tr(count == 1 ? "1 pickup" : "\(count) pickups",
                              count == 1 ? "1 Aktivierung" : "\(count) Aktivierungen")
        return Label(text, systemImage: "iphone.radiowaves.left.and.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ReportTheme.kin)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(ReportTheme.kin.opacity(0.13), in: Capsule())
    }

    // MARK: Days

    private var daysCard: some View {
        let days: [WeekActivity.DayUsage] = activity.days
        let peak: TimeInterval = max(60, days.map(\.duration).max() ?? 60)
        let lastIndex = days.count - 1

        return VStack(alignment: .leading, spacing: 12) {
            Text(tr("Per day", "Pro Tag"))
                .font(ReportTheme.display(17, weight: .semibold))
                .foregroundStyle(ReportTheme.ink)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    dayColumn(day, peak: peak, isToday: index == lastIndex)
                }
            }
        }
        .reportCard(padding: 20)
    }

    private func dayColumn(_ day: WeekActivity.DayUsage, peak: TimeInterval, isToday: Bool) -> some View {
        let barHeight: CGFloat = max(6, 92 * CGFloat(day.duration / peak))
        let fill: AnyShapeStyle = isToday ? AnyShapeStyle(ReportTheme.accentGradient) : AnyShapeStyle(ReportTheme.shu.opacity(0.28))
        let weekday: String = ReportFormat.weekday(day.start)
        let spoken: String = "\(weekday), \(ReportFormat.duration(day.duration))"

        return VStack(spacing: 6) {
            Text(day.duration >= 60 ? ReportFormat.short(day.duration) : " ")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ReportTheme.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill)
                    .frame(height: barHeight)
            }
            .frame(height: 92)
            Text(weekday)
                .font(.system(size: 11, weight: isToday ? .bold : .medium))
                .foregroundStyle(isToday ? ReportTheme.ink : ReportTheme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    // MARK: Apps

    private var appsCard: some View {
        let top: TimeInterval = max(1, activity.topApps.first?.duration ?? 1)

        return VStack(alignment: .leading, spacing: 14) {
            Text(tr("Most used", "Am meisten genutzt"))
                .font(ReportTheme.display(17, weight: .semibold))
                .foregroundStyle(ReportTheme.ink)
            VStack(spacing: 12) {
                ForEach(activity.topApps) { app in
                    appRow(app, share: app.duration / top)
                }
            }
        }
        .reportCard(padding: 20)
    }

    private func appRow(_ app: WeekActivity.AppUsage, share: Double) -> some View {
        HStack(spacing: 12) {
            appIcon(app)
                .frame(width: 34, height: 34)
                .background(ReportTheme.sand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    appName(app)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ReportTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(ReportFormat.duration(app.duration))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ReportTheme.inkSoft)
                }
                ShareBar(value: share)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The token draws the real app icon. Only this sandbox may resolve it,
    /// which is the whole point of doing the drawing in here.
    @ViewBuilder
    private func appIcon(_ app: WeekActivity.AppUsage) -> some View {
        if let token = app.token {
            Label(token)
                .labelStyle(.iconOnly)
                .font(.system(size: 26))
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ReportTheme.inkFaint)
        }
    }

    @ViewBuilder
    private func appName(_ app: WeekActivity.AppUsage) -> some View {
        if let name = app.name, !name.isEmpty {
            Text(name)
        } else if let token = app.token {
            Label(token).labelStyle(.titleOnly)
        } else {
            Text(tr("App", "App"))
        }
    }

    // MARK: Empty

    private var emptyCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "hourglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ReportTheme.shu)
                .frame(width: 44, height: 44)
                .background(ReportTheme.shu.opacity(0.13), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("No screen time yet", "Noch keine Bildschirmzeit"))
                    .font(ReportTheme.display(17, weight: .semibold))
                    .foregroundStyle(ReportTheme.ink)
                Text(tr("iOS has not recorded anything for these days. It fills the numbers in over time.",
                        "iOS hat für diese Tage noch nichts erfasst. Die Zahlen kommen nach und nach dazu."))
                    .font(.system(size: 14))
                    .foregroundStyle(ReportTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .reportCard(padding: 20)
    }
}

/// A thin capsule showing an app's share of the top app's time.
private struct ShareBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            let clamped: Double = min(1, max(0, value))
            let width: CGFloat = max(4, geo.size.width * CGFloat(clamped))
            ZStack(alignment: .leading) {
                Capsule().fill(ReportTheme.sand)
                Capsule().fill(ReportTheme.ai).frame(width: width)
            }
        }
        .frame(height: 5)
    }
}

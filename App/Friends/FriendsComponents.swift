import SwiftUI

// Small pieces shared by the Friends screens.

/// A member's avatar: their SF Symbol in a tinted rounded square.
struct FriendAvatarBadge: View {
    let avatar: String
    var size: CGFloat = 44
    var highlighted = false

    var body: some View {
        IconBadge(systemName: FriendAvatar.symbol(avatar), tint: highlighted ? Zen.shu : Zen.ai, size: size, filled: highlighted)
    }
}

/// Reference goals for a friend's day. The server does not know anyone's
/// personal goals, so every member is drawn against the same yardstick.
enum FriendDayGoal {
    static let focusMinutes = 50
    static let correctAnswers = 10
    static let habits = 3

    static func focus(_ day: FriendDay) -> Double { Double(day.focusMinutes) / Double(focusMinutes) }
    static func learn(_ day: FriendDay) -> Double { Double(day.correctAnswers) / Double(correctAnswers) }
    static func habitShare(_ day: FriendDay) -> Double { Double(day.habitsDone) / Double(habits) }
}

/// Three nested rings for one day, like the Today screen: focus outside,
/// learning in the middle, habits inside. A day without numbers stays empty.
struct FriendDayRings: View {
    let day: FriendDay?
    var size: CGFloat = 34

    var body: some View {
        let line = max(2.5, size * 0.1)
        ZStack {
            if let day {
                ProgressRing(progress: FriendDayGoal.focus(day), lineWidth: line, tint: Zen.shu)
                    .frame(width: size, height: size)
                ProgressRing(progress: FriendDayGoal.learn(day), lineWidth: line, tint: Zen.ai)
                    .frame(width: size - line * 2.6, height: size - line * 2.6)
                ProgressRing(progress: FriendDayGoal.habitShare(day), lineWidth: line, tint: Zen.matcha)
                    .frame(width: size - line * 5.2, height: size - line * 5.2)
            } else {
                Circle()
                    .strokeBorder(Zen.sand, style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                    .frame(width: size - line, height: size - line)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The last seven local days, oldest first, as App Group day keys.
enum FriendWeek {
    static func keys(now: Date = Date()) -> [String] {
        (0..<7).reversed().map { offset in
            SharedStore.dayKey(Calendar.current.date(byAdding: .day, value: -offset, to: now) ?? now)
        }
    }

    /// One narrow weekday letter per day ("M", "T" / "M", "D").
    static func letters(now: Date = Date()) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Loc.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return (0..<7).reversed().map { offset in
            formatter.string(from: Calendar.current.date(byAdding: .day, value: -offset, to: now) ?? now)
        }
    }
}

/// One line in the "what is shared" lists.
struct FriendsFactRow: View {
    let icon: String
    let text: String
    var tint: Color = Zen.shu

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Zen.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// Inline error instead of an alert: the list and the circle screen can both
/// be on the navigation stack, and two alerts would fight over one message.
struct FriendsErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Zen.negative)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Zen.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Zen.inkSoft)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Dismiss", "Schließen"))
        }
        .zenCard(padding: 14)
    }
}

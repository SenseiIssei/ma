import ActivityKit
import SwiftUI
import WidgetKit

/// Draws the focus Live Activity the app starts in AppModel. The timer texts
/// count down by themselves, so the app only has to update on phase changes.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            FocusActivityLockView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Night.paper.opacity(0.9))
                .activitySystemActionForegroundColor(Night.ink)
                .widgetURL(MaLink.focus.url)
        } dynamicIsland: { context in
            let state: FocusActivityAttributes.ContentState = context.state
            let tint: Color = Night.tint(isBreak: state.isBreak)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(state.title)
                    } icon: {
                        Image(systemName: Night.symbol(isBreak: state.isBreak))
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FocusTimeLeft(state: state, isStale: context.isStale, size: 28)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ProgressView(timerInterval: state.interval, countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .progressViewStyle(.linear)
                        .tint(tint)
                        HStack {
                            RoundDots(round: state.round, totalRounds: state.totalRounds, isBreak: state.isBreak)
                            Spacer()
                            Text(FocusText.round(state))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Night.inkSoft)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                FocusTimerRing(state: state, lineWidth: 3)
                    .frame(width: 20, height: 20)
            } compactTrailing: {
                Text(timerInterval: state.interval, countsDown: true)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 46)
            } minimal: {
                FocusTimerRing(state: state, lineWidth: 3)
                    .frame(width: 20, height: 20)
            }
            .widgetURL(MaLink.focus.url)
            .keylineTint(tint)
        }
    }
}

/// Lock Screen and banner presentation.
struct FocusActivityLockView: View {
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let tint: Color = Night.tint(isBreak: state.isBreak)
        HStack(spacing: 14) {
            ZStack {
                FocusTimerRing(state: state, lineWidth: 5)
                Image(systemName: Night.symbol(isBreak: state.isBreak))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text(state.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Night.ink)
                if isStale {
                    Text(tr("Time is up. Open Ma to carry on.", "Die Zeit ist um. Öffne Ma, um weiterzumachen."))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Night.inkSoft)
                        .lineLimit(2)
                } else {
                    RoundDots(round: state.round, totalRounds: state.totalRounds, isBreak: state.isBreak)
                    Text(FocusText.round(state))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Night.inkSoft)
                }
            }

            Spacer(minLength: 0)

            FocusTimeLeft(state: state, isStale: isStale, size: 34)
        }
        .padding(16)
    }
}

/// Big countdown with a small caption, or a check mark once the phase is over.
struct FocusTimeLeft: View {
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool
    let size: CGFloat

    var body: some View {
        if isStale {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size * 0.8, weight: .semibold))
                .foregroundStyle(Night.tint(isBreak: state.isBreak))
                .accessibilityLabel(Text(tr("Time is up", "Die Zeit ist um")))
        } else {
            VStack(alignment: .trailing, spacing: 0) {
                Text(timerInterval: state.interval, countsDown: true)
                    .font(.system(size: size, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Night.ink)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(tr("left", "übrig"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Night.inkSoft)
            }
            // Text(timerInterval:) claims all the width it can get otherwise.
            .frame(maxWidth: size * 3.4, alignment: .trailing)
        }
    }
}

/// A ring that drains by itself between startedAt and endsAt.
struct FocusTimerRing: View {
    let state: FocusActivityAttributes.ContentState
    let lineWidth: CGFloat

    var body: some View {
        ProgressView(timerInterval: state.interval, countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.circular)
        .tint(Night.tint(isBreak: state.isBreak))
        .accessibilityHidden(true)
    }
}

enum FocusText {
    static func round(_ state: FocusActivityAttributes.ContentState) -> String {
        let total: Int = max(state.totalRounds, state.round)
        return tr("Round \(state.round) of \(total)", "Runde \(state.round) von \(total)")
    }
}

import SwiftUI

/// Pick a rhythm and a length, then follow the circle and the taps on the
/// wrist. The same three patterns as the Breathe screen on the iPhone.
struct BreatheView: View {
    @State private var runner = BreathRunner()
    @State private var pattern: WatchBreathPattern = .calm
    @State private var minutes = 3

    var body: some View {
        // A ZStack, not a Group: a Group hands onDisappear to each child, so
        // swapping setup for the session would stop the session it started.
        ZStack {
            if let startedAt = runner.startedAt {
                BreathSessionView(runner: runner, startedAt: startedAt)
            } else if let seconds = runner.finishedSeconds {
                done(seconds: seconds)
            } else {
                setup
            }
        }
        .navigationTitle(tr("Breathe", "Atmen"))
        .containerBackground(Night.background, for: .navigation)
        .onDisappear { runner.stop(finished: false) }
    }

    // MARK: Setup

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Rhythm", "Rhythmus"))
                    .font(.footnote)
                    .foregroundStyle(Night.inkSoft)
                ForEach(WatchBreathPattern.all) { option in
                    patternRow(option)
                }
                Text(tr("Length", "Dauer"))
                    .font(.footnote)
                    .foregroundStyle(Night.inkSoft)
                    .padding(.top, 4)
                HStack(spacing: 6) {
                    ForEach(WatchBreathPattern.durations, id: \.self) { value in
                        minuteButton(value)
                    }
                }
                Button {
                    runner.start(pattern, minutes: minutes)
                } label: {
                    Label(tr("Start", "Starten"), systemImage: "wind")
                }
                .buttonStyle(NightButtonStyle(tint: Night.matcha, filled: true))
                .padding(.top, 6)
            }
        }
    }

    private func patternRow(_ option: WatchBreathPattern) -> some View {
        let selected: Bool = option == pattern
        return Button {
            pattern = option
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(Night.ink)
                    Text(option.rhythm)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Night.inkSoft)
                }
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Night.matcha : Night.inkFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Night.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func minuteButton(_ value: Int) -> some View {
        let selected: Bool = value == minutes
        let fill: Color = selected ? Night.matcha : Night.card
        let text: Color = selected ? Night.paper : Night.ink
        return Button {
            minutes = value
        } label: {
            Text(tr("\(value) min", "\(value) Min."))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(text)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Done

    private func done(seconds: Int) -> some View {
        let wholeMinutes: Int = seconds / 60
        let summary: String = wholeMinutes >= 1
            ? tr("\(wholeMinutes) min of quiet.", "\(wholeMinutes) Min. Ruhe.")
            : tr("\(seconds) seconds of quiet.", "\(seconds) Sekunden Ruhe.")
        return ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Night.matcha)
                Text(tr("Well done", "Gut gemacht"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Night.ink)
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Night.inkSoft)
                    .multilineTextAlignment(.center)
                Button {
                    runner.start(pattern, minutes: minutes)
                } label: {
                    Text(tr("Again", "Noch einmal"))
                }
                .buttonStyle(NightButtonStyle(tint: Night.matcha))
                Button {
                    runner.reset()
                } label: {
                    Text(tr("Done", "Fertig"))
                }
                .buttonStyle(NightButtonStyle(tint: Night.inkSoft))
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// The running session: the circle, what to do now and how long it lasts.
private struct BreathSessionView: View {
    let runner: BreathRunner
    let startedAt: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        // Always On draws once a minute; no point asking for frames then.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: dimmed)) { context in
            let elapsed: Double = context.date.timeIntervalSince(startedAt)
            let state: WatchBreathState = runner.pattern.state(at: elapsed)
            let left: Double = max(0, runner.length - elapsed)
            content(state: state, left: left)
        }
    }

    private func content(state: WatchBreathState, left: Double) -> some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            ZStack {
                circle(openness: state.openness)
                VStack(spacing: 0) {
                    Text(state.kind.label)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Night.ink)
                    Text("\(state.secondsLeft)")
                        .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(Night.ink)
                }
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(Self.clock(left))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Night.inkSoft)
                Spacer()
                Button {
                    runner.stop(finished: false)
                } label: {
                    Text(tr("End", "Beenden"))
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(Night.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                        .background(Night.card, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Grows and shrinks with the breath. With Reduce Motion it keeps its
    /// size and only brightens and dims, so nothing on screen moves.
    @ViewBuilder
    private func circle(openness: Double) -> some View {
        if reduceMotion || dimmed {
            let glow: Double = 0.25 + 0.55 * openness
            Circle()
                .fill(Night.matcha.opacity(glow))
                .overlay(Circle().strokeBorder(Night.matcha, lineWidth: 2))
                .padding(8)
        } else {
            let scale: Double = 0.5 + 0.5 * openness
            ZStack {
                Circle()
                    .strokeBorder(Night.line, lineWidth: 1.5)
                Circle()
                    .fill(Night.accentGradient)
                    .opacity(0.35 + 0.35 * openness)
                    .scaleEffect(scale)
            }
            .padding(4)
        }
    }

    private static func clock(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

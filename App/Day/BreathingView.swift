import SwiftUI
import UIKit

/// Guided breathing: pick a rhythm and a length, then follow the circle.
/// Timing is derived from the start date, so a trip to the background never
/// leaves the circle out of step with the clock.
struct BreathingView: View {
    @Environment(DayStore.self) private var day
    @Environment(\.dismiss) private var dismiss
    @State private var pattern: BreathPattern = .calm
    @State private var minutes = 3
    @State private var startedAt: Date?
    @State private var lastTick = -1
    @State private var finishedSeconds: Int?

    private static let durations = [1, 3, 5]

    private var sound: SoundEngine { SoundEngine.shared }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                topBar
                if let startedAt {
                    session(since: startedAt)
                        .transition(.opacity)
                } else if let finishedSeconds {
                    done(seconds: finishedSeconds)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    setup
                        .transition(.opacity)
                }
            }
        }
        .task(id: startedAt) { await run() }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            // Leaving the screen ends the background sound too, even a preview.
            sound.stop(scope: .breathing)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                if startedAt != nil { stop() }
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Zen.inkSoft)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(tr("Close", "Schließen"))
            Spacer()
            if startedAt != nil {
                soundToggle
            }
        }
        .padding(.horizontal, 8)
    }

    /// The off switch during a session, one tap away from the circle.
    private var soundToggle: some View {
        let on: Bool = sound.isPlaying(in: .breathing)
        return Button {
            Haptics.tap()
            toggleSound()
        } label: {
            Image(systemName: on ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(on ? Zen.shu : Zen.inkSoft)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(on ? tr("Turn the sound off", "Klang ausschalten") : tr("Turn the sound on", "Klang einschalten"))
    }

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "waveform", title: tr("Background sound", "Hintergrundklang"))
            VStack(alignment: .leading, spacing: 10) {
                SoundPicker(scope: .breathing)
                Text(tr("Plays softly while you breathe. Choose Off for silence.", "Läuft leise, während du atmest. Mit Aus bleibt es still."))
                    .scaledFont(size: 13)
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .zenCard()
        }
    }

    // MARK: Setup

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Breathe", "Atmen"))
                        .displayFont(34)
                        .foregroundStyle(Zen.ink)
                    Text(tr("A few slow breaths calm the pull to reach for your phone.", "Ein paar ruhige Atemzüge nehmen dem Griff zum Handy den Zug."))
                        .scaledFont(size: 15)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Image("IllustrationBreathe")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: Zen.radius, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "waveform.path", title: tr("Rhythm", "Rhythmus"))
                    VStack(spacing: 10) {
                        ForEach(BreathPattern.all) { option in
                            patternRow(option)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "timer", title: tr("Length", "Dauer"))
                    HStack(spacing: 10) {
                        ForEach(Self.durations, id: \.self) { value in
                            Chip(title: tr("\(value) min", "\(value) Min."), selected: minutes == value) {
                                minutes = value
                            }
                        }
                        Spacer()
                    }
                }

                soundSection

                if day.breath.sessions > 0 {
                    Label(statsLine, systemImage: "chart.bar.fill")
                        .scaledFont(size: 14, weight: .medium)
                        .foregroundStyle(Zen.inkSoft)
                }

                Button {
                    start()
                } label: {
                    Label(tr("Begin", "Los geht's"), systemImage: "play.fill")
                }
                .buttonStyle(.primary)
            }
            .padding(.horizontal, Zen.gutter)
            .padding(.bottom, 32)
        }
    }

    private var statsLine: String {
        let sessions = day.breath.sessions
        let mins = day.breath.minutes
        return tr("\(sessions) \(sessions == 1 ? "session" : "sessions"), \(mins) min in total",
                  "\(sessions) \(sessions == 1 ? "Übung" : "Übungen"), insgesamt \(mins) Min.")
    }

    private func patternRow(_ option: BreathPattern) -> some View {
        let isOn: Bool = option == pattern
        return Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { pattern = option }
        } label: {
            HStack(spacing: 14) {
                IconBadge(systemName: isOn ? "checkmark" : "circle.dotted", tint: Zen.shu, size: 40, filled: isOn)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(option.title)
                            .scaledFont(size: 17, weight: .semibold)
                            .foregroundStyle(Zen.ink)
                        Text(option.rhythm)
                            .scaledFont(size: 13, weight: .semibold, design: .rounded)
                            .monospacedDigit()
                            .foregroundStyle(Zen.shu)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Zen.shu.opacity(0.12), in: Capsule())
                    }
                    Text(option.summary)
                        .scaledFont(size: 14)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Zen.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isOn ? Zen.shu : Zen.line, lineWidth: isOn ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Session

    private func session(since start: Date) -> some View {
        let length = pattern.sessionLength(minutes: minutes)
        return TimelineView(.animation) { context in
            let elapsed: Double = context.date.timeIntervalSince(start)
            let state: BreathState = pattern.state(at: elapsed)
            let left: Int = max(0, Int((length - elapsed).rounded(.up)))
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                Text(pattern.title + "  " + pattern.rhythm)
                    .scaledFont(size: 14, weight: .semibold, design: .rounded)
                    .foregroundStyle(Zen.inkSoft)
                ZStack {
                    ProgressRing(progress: min(1, elapsed / length), lineWidth: 4, tint: Zen.shu.opacity(0.5))
                    BreathCircle(openness: state.openness, tint: Zen.shu)
                        .padding(18)
                }
                .frame(width: 300, height: 300)
                .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text(state.kind.label)
                        .displayFont(32)
                        .foregroundStyle(Zen.ink)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: state.tick)
                    Text("\(state.secondsLeft)")
                        .displayFont(20, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(Zen.inkSoft)
                }
                .accessibilityMeter(state.kind.label, value: state.secondsLeft == 1
                                    ? tr("1 second", "1 Sekunde")
                                    : tr("\(state.secondsLeft) seconds", "\(state.secondsLeft) Sekunden"))
                .accessibilityAddTraits(.updatesFrequently)
                Spacer(minLength: 0)
                VStack(spacing: 14) {
                    Text(tr("\(Self.clock(left)) left", "noch \(Self.clock(left))"))
                        .scaledFont(size: 14, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(Zen.inkSoft)
                        .accessibilityLabel(tr("\(Spoken.duration(TimeInterval(left))) left", "noch \(Spoken.duration(TimeInterval(left)))"))
                    // A separate element, so the button stays reachable.
                    Button(tr("End early", "Früher beenden")) { stop() }
                        .buttonStyle(.quiet)
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func done(seconds: Int) -> some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(Zen.matcha.opacity(0.14)).frame(width: 140, height: 140)
                Image(systemName: "checkmark")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(Zen.matcha)
            }
            .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(tr("Well breathed", "Gut geatmet"))
                    .displayFont(30)
                    .foregroundStyle(Zen.ink)
                Text(tr("\(Self.clock(seconds)) of calm. Session \(day.breathSessionsToday) today.",
                        "\(Self.clock(seconds)) Ruhe. Heute Übung Nummer \(day.breathSessionsToday)."))
                    .scaledFont(size: 16)
                    .foregroundStyle(Zen.inkSoft)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            VStack(spacing: 12) {
                Button(tr("Done", "Fertig")) { dismiss() }
                    .buttonStyle(.primary)
                Button(tr("Once more", "Noch einmal")) {
                    withAnimation { finishedSeconds = nil }
                }
                .buttonStyle(.quiet)
            }
            .padding(.horizontal, Zen.gutter)
            .padding(.bottom, 24)
        }
    }

    // MARK: Flow

    private func start() {
        Haptics.tap()
        lastTick = -1
        UIApplication.shared.isIdleTimerDisabled = true
        let now = Date()
        withAnimation(.easeInOut(duration: 0.4)) {
            finishedSeconds = nil
            startedAt = now
        }
        let chosen: AmbientSound = sound.sound(for: .breathing)
        if chosen != .off {
            sound.play(chosen, scope: .breathing, until: sessionEnd(from: now))
        }
    }

    /// The sound's own deadline: it ends with the session even when the
    /// phone is locked and this view no longer updates.
    private func sessionEnd(from start: Date) -> Date {
        start.addingTimeInterval(pattern.sessionLength(minutes: minutes) + 1)
    }

    private func toggleSound() {
        if sound.isPlaying(in: .breathing) {
            sound.stop(scope: .breathing)
            return
        }
        guard let startedAt else { return }
        let chosen: AmbientSound = sound.sound(for: .breathing)
        // "Off" in the picker still means a sound when you ask for one here.
        let pick: AmbientSound = chosen == .off ? .nightDrone : chosen
        sound.play(pick, scope: .breathing, until: sessionEnd(from: startedAt))
    }

    /// Ending early still counts once there was at least half a minute of it.
    private func stop() {
        guard let startedAt else { return }
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        finish(seconds: elapsed, record: elapsed >= 30)
    }

    private func finish(seconds: Int, record: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
        sound.stop(scope: .breathing)
        if record {
            day.recordBreath(seconds: seconds)
            Haptics.success()
        }
        withAnimation(.easeInOut(duration: 0.4)) {
            startedAt = nil
            finishedSeconds = record ? seconds : nil
        }
    }

    /// Haptics on every phase change and the end of the session. The circle
    /// itself is drawn by the TimelineView; this loop only watches the clock.
    private func run() async {
        guard let start = startedAt else { return }
        let length = pattern.sessionLength(minutes: minutes)
        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= length {
                finish(seconds: Int(length), record: true)
                return
            }
            let state: BreathState = pattern.state(at: elapsed)
            if state.tick != lastTick {
                if lastTick >= 0 { Haptics.tap() }
                lastTick = state.tick
                // What the haptic tap is for sighted users, spoken for VoiceOver.
                AccessibilityNotification.Announcement(state.kind.label).post()
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Soft layered circles; `openness` 0 is fully out, 1 fully in.
struct BreathCircle: View {
    var openness: Double
    var tint: Color = Zen.shu
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let raw = CGFloat(min(1, max(0, openness)))
        // Reduce Motion: the circles keep their size and the core brightens
        // on the in-breath instead of swelling.
        let o: CGFloat = reduceMotion ? 1 : raw
        let glow: Double = reduceMotion ? 0.4 + 0.6 * Double(raw) : 1
        ZStack {
            Circle()
                .fill(tint.opacity(0.10))
                .scaleEffect(0.62 + 0.38 * o)
            Circle()
                .fill(tint.opacity(0.18))
                .scaleEffect(0.50 + 0.30 * o)
            Circle()
                .fill(Zen.accentGradient)
                .scaleEffect(0.34 + 0.20 * o)
                .shadow(color: tint.opacity(0.35), radius: 24, y: 8)
                .opacity(glow)
        }
    }
}

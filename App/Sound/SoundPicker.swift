import SwiftUI

extension AmbientSound {
    var title: String {
        switch self {
        case .rain: tr("Rain", "Regen")
        case .brownNoise: tr("Brown noise", "Braunes Rauschen")
        case .ocean: tr("Ocean", "Meer")
        case .nightDrone: tr("Night drone", "Nachtklang")
        case .off: tr("Off", "Aus")
        }
    }

    var symbol: String {
        switch self {
        case .rain: "cloud.rain.fill"
        case .brownNoise: "waveform"
        case .ocean: "water.waves"
        case .nightDrone: "moon.stars.fill"
        case .off: "speaker.slash.fill"
        }
    }
}

/// Sound chips, a volume slider and (optionally) a sleep timer. A tap plays
/// the sound right away, so you choose by ear; tapping the sound that is
/// playing, or "Off", stops it.
struct SoundPicker: View {
    let scope: SoundScope
    /// Sound started from here ends by itself at this time, e.g. with the
    /// running focus round.
    var until: Date? = nil
    var showsSleepTimer = false

    private var engine: SoundEngine { SoundEngine.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            chips
            volumeRow
            if showsSleepTimer && engine.isPlaying(in: scope) {
                sleepRow
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: engine.playing)
    }

    private var chips: some View {
        let chosen: AmbientSound = engine.sound(for: scope)
        let live: AmbientSound = engine.isPlaying(in: scope) ? engine.playing : .off
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AmbientSound.allCases) { sound in
                    SoundChip(sound: sound, selected: sound == chosen, playing: sound != .off && sound == live) {
                        engine.choose(sound, for: scope, until: until)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var volumeRow: some View {
        let volume = Binding<Double>(
            get: { engine.volume(for: scope) },
            set: { engine.setVolume($0, for: scope) }
        )
        return HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Zen.inkFaint)
                .accessibilityHidden(true)
            Slider(value: volume, in: 0...1)
                .tint(Zen.shu)
                .accessibilityLabel(tr("Volume", "Lautstärke"))
            Image(systemName: "speaker.wave.3.fill")
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Zen.inkFaint)
                .accessibilityHidden(true)
        }
    }

    private var sleepRow: some View {
        // Refreshing twice a minute is plenty for a label in whole minutes.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Menu {
                ForEach(SleepTimer.options, id: \.self) { minutes in
                    Button(tr("\(minutes) minutes", "\(minutes) Minuten")) {
                        engine.setSleepTimer(minutes: minutes)
                    }
                }
                if engine.sleepEndsAt != nil {
                    Button(tr("No timer", "Kein Timer"), role: .destructive) {
                        engine.setSleepTimer(minutes: nil)
                    }
                }
            } label: {
                Label(sleepLabel(now: context.date), systemImage: "moon.zzz.fill")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(engine.sleepEndsAt == nil ? Zen.inkSoft : Zen.shu)
            }
        }
    }

    private func sleepLabel(now: Date) -> String {
        guard let end = engine.sleepEndsAt else {
            return tr("Sleep timer", "Schlaf-Timer")
        }
        let left: Int = SleepTimer.minutesLeft(until: end, now: now)
        return tr("Stops in \(left) min.", "Endet in \(left) Min.")
    }
}

/// A pill with an SF Symbol. The symbol pulses while its sound is audible.
private struct SoundChip: View {
    let sound: AmbientSound
    let selected: Bool
    let playing: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let fill: AnyShapeStyle = selected ? AnyShapeStyle(Zen.accentGradient) : AnyShapeStyle(Zen.sand)
        // The endless pulse stops with Reduce Motion; "Playing" is still said.
        let pulsing: Bool = playing && !reduceMotion
        return Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: sound.symbol)
                    .scaledFont(size: 14, weight: .semibold)
                    .symbolEffect(.pulse, options: .repeating, isActive: pulsing)
                    .accessibilityHidden(true)
                Text(sound.title)
                    .scaledFont(size: 15, weight: .semibold, design: .rounded)
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.white : Zen.ink)
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .background(fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(playing ? tr("Playing", "Läuft") : "")
    }
}

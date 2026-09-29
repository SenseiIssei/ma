import Foundation
import Synchronization

// The pure half of Ma's ambient sound: generators, fades and the sleep timer.
// Nothing here touches AVFoundation, so the whole file compiles and runs in
// the Linux test harness. `SoundEngine` wires it to the speaker.

/// The sounds Ma can synthesize. `code` is what travels to the audio thread.
enum AmbientSound: String, CaseIterable, Identifiable, Codable, Sendable {
    case rain, brownNoise, ocean, nightDrone, off

    var id: String { rawValue }

    var code: UInt32 {
        switch self {
        case .rain: 0
        case .brownNoise: 1
        case .ocean: 2
        case .nightDrone: 3
        case .off: 4
        }
    }

    init(code: UInt32) {
        switch code {
        case 0: self = .rain
        case 1: self = .brownNoise
        case 2: self = .ocean
        case 3: self = .nightDrone
        default: self = .off
        }
    }
}

// MARK: - Fades

enum Fade {
    /// Every start and stop glides in or out over this long.
    static let seconds: Double = 1.5
    /// Switching from one sound to another dips briefly instead.
    static let switchSeconds: Double = 0.4

    /// How far a gain moves per sample so a full 0 to 1 ramp takes `seconds`.
    static func stepSize(seconds: Double, sampleRate: Double) -> Float {
        let samples: Double = max(1, seconds * sampleRate)
        return Float(1 / samples)
    }

    /// One linear step toward `target`, never past it.
    static func step(_ current: Float, toward target: Float, by step: Float) -> Float {
        if current < target { return min(target, current + step) }
        if current > target { return max(target, current - step) }
        return current
    }

    /// Smoothstep: the linear ramp sounds abrupt at its ends, this one eases.
    static func curve(_ x: Float) -> Float {
        let t: Float = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }

    /// The slider is linear, the ear is not: squaring spreads the quiet end.
    static func loudness(_ slider: Double) -> Float {
        let v: Double = min(1, max(0, slider))
        return Float(v * v)
    }
}

// MARK: - Sleep timer

enum SleepTimer {
    static let options = [15, 30, 60]

    static func endDate(minutes: Int, from now: Date) -> Date {
        now.addingTimeInterval(TimeInterval(max(0, minutes) * 60))
    }

    /// Whichever comes first: the sleep timer or the end of the thing the
    /// sound belongs to (a focus round, a breathing session).
    static func stopDate(sleepEndsAt: Date?, boundUntil: Date?) -> Date? {
        switch (sleepEndsAt, boundUntil) {
        case let (a?, b?): return min(a, b)
        case let (a?, nil): return a
        case let (nil, b?): return b
        case (nil, nil): return nil
        }
    }

    /// Whole minutes left, rounded up so "1 min" shows until the very end.
    static func minutesLeft(until end: Date, now: Date) -> Int {
        let seconds: Double = end.timeIntervalSince(now)
        guard seconds > 0 else { return 0 }
        return Int((seconds / 60).rounded(.up))
    }
}

// MARK: - Parameters shared with the audio thread

/// The only state both threads touch. Atomics, so the render callback never
/// takes a lock or sees a torn value.
final class AmbientParams: Sendable {
    private let soundCode = Atomic<UInt32>(AmbientSound.off.code)
    private let gainBits = Atomic<UInt32>(Float(0).bitPattern)
    private let volumeBits = Atomic<UInt32>(Float(0.36).bitPattern)

    init() {}

    var sound: AmbientSound {
        get { AmbientSound(code: soundCode.load(ordering: .relaxed)) }
        set { soundCode.store(newValue.code, ordering: .relaxed) }
    }

    /// 1 plays, 0 fades out. The renderer ramps toward it.
    var targetGain: Float {
        get { Float(bitPattern: gainBits.load(ordering: .relaxed)) }
        set { gainBits.store(newValue.bitPattern, ordering: .relaxed) }
    }

    /// Linear amplitude, already shaped by `Fade.loudness`.
    var volume: Float {
        get { Float(bitPattern: volumeBits.load(ordering: .relaxed)) }
        set { volumeBits.store(newValue.bitPattern, ordering: .relaxed) }
    }
}

// MARK: - Building blocks

/// Xorshift: fast, allocation free and good enough for noise.
struct NoiseRNG {
    private var state: UInt32

    init(seed: UInt32) { state = seed == 0 ? 0x9E37_79B9 : seed }

    mutating func nextBits() -> UInt32 {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return state
    }

    /// Uniform in [-1, 1).
    mutating func bipolar() -> Float {
        Float(Int32(bitPattern: nextBits())) * (1.0 / 2_147_483_648.0)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Float {
        Float(nextBits() >> 8) * (1.0 / 16_777_216.0)
    }
}

/// Paul Kellet's pink filter: white noise in, a -3 dB per octave slope out,
/// which the ear hears as even, like steady rain.
struct PinkFilter {
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0
    private var b4: Float = 0, b5: Float = 0, b6: Float = 0

    mutating func process(_ white: Float) -> Float {
        b0 = 0.99886 * b0 + white * 0.0555179
        b1 = 0.99332 * b1 + white * 0.0750759
        b2 = 0.96900 * b2 + white * 0.1538520
        b3 = 0.86650 * b3 + white * 0.3104856
        b4 = 0.55000 * b4 + white * 0.5329522
        b5 = -0.7616 * b5 - white * 0.0168980
        let sum: Float = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
        b6 = white * 0.115926
        return sum * 0.11
    }
}

/// A leaky integrator: brown noise, deep and rounded. The leak keeps it
/// from drifting off to one side.
struct BrownFilter {
    private var last: Float = 0

    mutating func process(_ white: Float) -> Float {
        last = (last + 0.02 * white) / 1.02
        return last * 3.5
    }
}

/// One pole low pass.
struct OnePole {
    private var z: Float = 0
    private let a: Float

    init(cutoff: Double, sampleRate: Double) {
        let x: Double = exp(-2 * Double.pi * cutoff / sampleRate)
        a = Float(1 - x)
    }

    mutating func process(_ input: Float) -> Float {
        z += a * (input - z)
        return z
    }
}

/// A single raindrop: a short sine that drops a little in pitch and dies away.
struct Droplet {
    var phase: Float = 0
    var increment: Float = 0
    var glide: Float = 1
    var amp: Float = 0
    var decay: Float = 0
    var pan: Float = 0.5

    var isActive: Bool { amp > 0.0004 }
}

/// Slow ocean swell. Each wave takes 8 to 12 seconds, rises faster than it
/// draws back, and never falls fully silent.
struct Swell {
    static let minPeriod: Double = 8
    static let maxPeriod: Double = 12

    // Double, because a 10 s period at 48 kHz is a step Float cannot count.
    private(set) var phase: Double = 0
    private(set) var period: Double = 10

    mutating func next(sampleRate: Double, rng: inout NoiseRNG) -> Float {
        phase += 1 / (period * sampleRate)
        if phase >= 1 {
            phase -= 1
            let spread: Double = Swell.maxPeriod - Swell.minPeriod
            period = Swell.minPeriod + spread * Double(rng.unit())
        }
        return Swell.shape(phase)
    }

    static func shape(_ phase: Double) -> Float {
        let rise: Double = 0.35
        let x: Double = phase < rise ? phase / rise : 1 - (phase - rise) / (1 - rise)
        let eased: Float = Fade.curve(Float(x))
        return 0.2 + 0.8 * eased
    }
}

/// One sine of the night drone, with its own slow detune wobble.
struct DroneVoice {
    var frequency: Float
    var amp: Float
    var lfoRate: Double
    var lfo: Double
    var phaseL: Float = 0
    var phaseR: Float = 0
}

// MARK: - Renderer

/// Produces the ambient sound sample by sample. After `init` its state is
/// touched only by the audio render thread; the main thread talks to it
/// through `AmbientParams` alone. Hence `@unchecked Sendable`.
/// Every buffer is preallocated in `init`, so rendering never allocates.
final class AmbientRenderer: @unchecked Sendable {
    let sampleRate: Double
    private let params: AmbientParams
    private let fadeStep: Float
    private let switchStep: Float
    private let volumeCoefficient: Float
    private let dropChance: Float

    private var rng: NoiseRNG
    private var pinkL = PinkFilter()
    private var pinkR = PinkFilter()
    private var brownL = BrownFilter()
    private var brownR = BrownFilter()
    private var rainTopL: OnePole
    private var rainTopR: OnePole
    private var rainRumbleL: OnePole
    private var rainRumbleR: OnePole
    private var washL: OnePole
    private var washR: OnePole
    private var drops: ContiguousArray<Droplet>
    private var swell = Swell()
    private var drone: ContiguousArray<DroneVoice>
    private var droneBreath: Double = 0

    private var active: AmbientSound = .off
    private var fade: Float = 0
    private var switchGain: Float = 1
    private var volume: Float

    /// A calm D chord, low enough to sit under thoughts, high enough that a
    /// phone speaker still carries most of it.
    static let droneChord: [(frequency: Float, amp: Float)] = [
        (73.42, 0.20), (110.0, 0.19), (146.83, 0.15), (185.0, 0.11), (220.0, 0.09), (329.63, 0.04),
    ]

    init(sampleRate: Double, params: AmbientParams, seed: UInt32 = 0x5EED_1234) {
        let rate: Double = sampleRate > 0 ? sampleRate : 48_000
        self.sampleRate = rate
        self.params = params
        fadeStep = Fade.stepSize(seconds: Fade.seconds, sampleRate: rate)
        switchStep = Fade.stepSize(seconds: Fade.switchSeconds, sampleRate: rate)
        volumeCoefficient = Float(1 - exp(-1 / (0.05 * rate)))
        dropChance = Float(7 / rate)
        rng = NoiseRNG(seed: seed)
        rainTopL = OnePole(cutoff: 5_500, sampleRate: rate)
        rainTopR = OnePole(cutoff: 5_500, sampleRate: rate)
        rainRumbleL = OnePole(cutoff: 240, sampleRate: rate)
        rainRumbleR = OnePole(cutoff: 240, sampleRate: rate)
        washL = OnePole(cutoff: 1_600, sampleRate: rate)
        washR = OnePole(cutoff: 1_600, sampleRate: rate)
        drops = ContiguousArray(repeating: Droplet(), count: 12)
        var voices = ContiguousArray<DroneVoice>()
        voices.reserveCapacity(Self.droneChord.count)
        for (index, note) in Self.droneChord.enumerated() {
            // Each voice wobbles at its own slow rate, so the chord never repeats exactly.
            let lfoRate: Double = 0.05 + 0.013 * Double(index)
            let offset: Double = 0.17 * Double(index)
            voices.append(DroneVoice(frequency: note.frequency, amp: note.amp, lfoRate: lfoRate, lfo: offset))
        }
        drone = voices
        volume = params.volume
    }

    /// The current fade level, for tests.
    var fadeLevel: Float { fade }

    /// Fills one buffer. Parameters are read once per buffer: cheap, and a
    /// change never lands halfway through a buffer.
    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?) {
        let requested: AmbientSound = params.sound
        let target: Float = params.targetGain
        let wanted: Float = params.volume
        for i in 0..<frames {
            let frame = nextFrame(requested: requested, target: target, volume: wanted)
            if let right {
                left[i] = frame.left
                right[i] = frame.right
            } else {
                left[i] = 0.5 * (frame.left + frame.right)
            }
        }
    }

    /// One stereo frame, faded, scaled and clamped to [-1, 1].
    func nextFrame(requested: AmbientSound, target: Float, volume wanted: Float) -> (left: Float, right: Float) {
        advanceGains(requested: requested, target: target, volume: wanted)
        if active == .off || (fade <= 0 && target <= 0) {
            return (0, 0)
        }
        let raw = sample(active)
        let shaped: Float = Fade.curve(fade) * Fade.curve(switchGain)
        let gain: Float = shaped * volume
        let l: Float = min(1, max(-1, raw.left * gain))
        let r: Float = min(1, max(-1, raw.right * gain))
        return (l, r)
    }

    private func advanceGains(requested: AmbientSound, target: Float, volume wanted: Float) {
        if requested != active {
            if fade <= 0 {
                // Silent anyway, so switch at once instead of dipping.
                active = requested
                switchGain = 1
            } else {
                switchGain = Fade.step(switchGain, toward: 0, by: switchStep)
                if switchGain <= 0 { active = requested }
            }
        } else {
            switchGain = Fade.step(switchGain, toward: 1, by: switchStep)
        }
        fade = Fade.step(fade, toward: target, by: fadeStep)
        volume += (wanted - volume) * volumeCoefficient
    }

    private func sample(_ sound: AmbientSound) -> (left: Float, right: Float) {
        switch sound {
        case .rain: return rain()
        case .brownNoise: return brown()
        case .ocean: return ocean()
        case .nightDrone: return nightDrone()
        case .off: return (0, 0)
        }
    }

    // MARK: Generators

    private func rain() -> (left: Float, right: Float) {
        let a: Float = pinkL.process(rng.bipolar())
        let b: Float = pinkR.process(rng.bipolar())
        // Soften the hiss at the top and cut the rumble at the bottom.
        let topL: Float = rainTopL.process(a)
        let topR: Float = rainTopR.process(0.75 * b + 0.25 * a)
        let hissL: Float = topL - rainRumbleL.process(topL)
        let hissR: Float = topR - rainRumbleR.process(topR)
        var l: Float = hissL * 1.5
        var r: Float = hissR * 1.5

        if rng.unit() < dropChance { spawnDrop() }
        let twoPi: Float = 2 * Float.pi
        for i in drops.indices where drops[i].isActive {
            let s: Float = sin(twoPi * drops[i].phase) * drops[i].amp
            l += s * (1 - drops[i].pan)
            r += s * drops[i].pan
            drops[i].phase += drops[i].increment
            if drops[i].phase >= 1 { drops[i].phase -= 1 }
            drops[i].increment *= drops[i].glide
            drops[i].amp *= drops[i].decay
        }
        return (l, r)
    }

    private func spawnDrop() {
        guard let slot = drops.firstIndex(where: { !$0.isActive }) else { return }
        let pitch: Double = 1_700 + 2_600 * Double(rng.unit())
        let tau: Double = 0.008 + 0.025 * Double(rng.unit())
        let loud: Float = rng.unit()
        drops[slot].phase = 0
        drops[slot].increment = Float(pitch / sampleRate)
        drops[slot].glide = 1 - 0.00003 * rng.unit()
        drops[slot].amp = 0.03 + 0.12 * loud * loud
        drops[slot].decay = Float(exp(-1 / (tau * sampleRate)))
        drops[slot].pan = 0.15 + 0.7 * rng.unit()
    }

    private func brown() -> (left: Float, right: Float) {
        let l: Float = brownL.process(rng.bipolar())
        let r: Float = brownR.process(rng.bipolar())
        return (l * 0.9, r * 0.9)
    }

    private func ocean() -> (left: Float, right: Float) {
        let level: Float = swell.next(sampleRate: sampleRate, rng: &rng)
        let deepL: Float = brownL.process(rng.bipolar())
        let deepR: Float = brownR.process(rng.bipolar())
        // A bright wash that only comes up near the crest of a wave.
        let foamL: Float = washL.process(pinkL.process(rng.bipolar()))
        let foamR: Float = washR.process(pinkR.process(rng.bipolar()))
        let crest: Float = level * level * 0.9
        let l: Float = (deepL * 0.8 + foamL * crest) * level
        let r: Float = (deepR * 0.8 + foamR * crest) * level
        return (l, r)
    }

    private func nightDrone() -> (left: Float, right: Float) {
        let twoPi: Double = 2 * Double.pi
        let twoPiF: Float = 2 * Float.pi
        droneBreath += 0.06 / sampleRate
        if droneBreath >= 1 { droneBreath -= 1 }
        let breath: Float = 0.8 + 0.2 * Float(sin(twoPi * droneBreath))
        var l: Float = 0
        var r: Float = 0
        for i in drone.indices {
            drone[i].lfo += drone[i].lfoRate / sampleRate
            if drone[i].lfo >= 1 { drone[i].lfo -= 1 }
            // Left and right drift apart by a few cents: slow, living width.
            let detune: Float = 0.0035 * Float(sin(twoPi * drone[i].lfo))
            let base: Float = drone[i].frequency / Float(sampleRate)
            drone[i].phaseL += base * (1 + detune)
            drone[i].phaseR += base * (1 - detune)
            if drone[i].phaseL >= 1 { drone[i].phaseL -= 1 }
            if drone[i].phaseR >= 1 { drone[i].phaseR -= 1 }
            l += sin(twoPiF * drone[i].phaseL) * drone[i].amp
            r += sin(twoPiF * drone[i].phaseR) * drone[i].amp
        }
        return (l * breath, r * breath)
    }
}

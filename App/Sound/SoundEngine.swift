import AVFoundation
import Foundation
import Observation

/// Who asked for the sound. Focus and breathing each remember their own
/// sound and volume, and each only stops what it started itself.
enum SoundScope: String, Sendable {
    case focus, breathing
}

/// Calm ambient sound, synthesized live: no audio files in the bundle.
/// The main actor owns the graph and the preferences; the audio thread only
/// sees `AmbientParams` (atomics) and its own `AmbientRenderer`.
@MainActor
@Observable
final class SoundEngine {
    static let shared = SoundEngine()

    /// What is audible right now. `.off` while silent or fading out.
    private(set) var playing: AmbientSound = .off
    /// Who started the current sound.
    private(set) var scope: SoundScope?
    /// When the user's sleep timer ends the sound, if set.
    private(set) var sleepEndsAt: Date?
    /// When the thing the sound belongs to ends (a focus round, a breath session).
    private(set) var boundUntil: Date?

    /// Start the focus sound together with each focus round.
    var playsDuringFocus: Bool {
        didSet { defaults.set(playsDuringFocus, forKey: Key.duringFocus) }
    }

    private(set) var focusSound: AmbientSound
    private(set) var breathSound: AmbientSound
    private(set) var focusVolume: Double
    private(set) var breathVolume: Double

    private let params = AmbientParams()
    private let defaults = UserDefaults.standard
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var source: AVAudioSourceNode?
    @ObservationIgnored private var configObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var shutdownTask: Task<Void, Never>?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?

    private enum Key {
        static let duringFocus = "ma.sound.duringFocus"
        static let focusSound = "ma.sound.focus"
        static let breathSound = "ma.sound.breath"
        static let focusVolume = "ma.sound.focusVolume"
        static let breathVolume = "ma.sound.breathVolume"
    }

    private init() {
        let store = UserDefaults.standard
        playsDuringFocus = store.bool(forKey: Key.duringFocus)
        focusSound = store.string(forKey: Key.focusSound).flatMap(AmbientSound.init(rawValue:)) ?? .rain
        breathSound = store.string(forKey: Key.breathSound).flatMap(AmbientSound.init(rawValue:)) ?? .nightDrone
        focusVolume = (store.object(forKey: Key.focusVolume) as? Double) ?? 0.6
        // Breathing wants the sound far in the background.
        breathVolume = (store.object(forKey: Key.breathVolume) as? Double) ?? 0.3
        observeInterruptions()
    }

    // MARK: Preferences

    func sound(for scope: SoundScope) -> AmbientSound {
        switch scope {
        case .focus: focusSound
        case .breathing: breathSound
        }
    }

    func volume(for scope: SoundScope) -> Double {
        switch scope {
        case .focus: focusVolume
        case .breathing: breathVolume
        }
    }

    func setVolume(_ value: Double, for scope: SoundScope) {
        let clamped: Double = min(1, max(0, value))
        switch scope {
        case .focus:
            focusVolume = clamped
            defaults.set(clamped, forKey: Key.focusVolume)
        case .breathing:
            breathVolume = clamped
            defaults.set(clamped, forKey: Key.breathVolume)
        }
        if self.scope == scope {
            params.volume = Fade.loudness(clamped)
        }
    }

    private func setPreferred(_ sound: AmbientSound, for scope: SoundScope) {
        switch scope {
        case .focus:
            focusSound = sound
            defaults.set(sound.rawValue, forKey: Key.focusSound)
        case .breathing:
            breathSound = sound
            defaults.set(sound.rawValue, forKey: Key.breathSound)
        }
    }

    func isPlaying(in scope: SoundScope) -> Bool {
        playing != .off && self.scope == scope
    }

    /// A tap in the picker: remember the choice and play it right away.
    /// Tapping the sound that is already playing stops it, "Off" stops too.
    func choose(_ sound: AmbientSound, for scope: SoundScope, until end: Date? = nil) {
        let tappedPlaying: Bool = isPlaying(in: scope) && playing == sound
        setPreferred(sound, for: scope)
        if sound == .off || tappedPlaying {
            stop(scope: scope)
        } else {
            play(sound, scope: scope, until: end)
        }
    }

    // MARK: Playback

    /// Fades `sound` in (or crossfades from the current one). With `until`
    /// it fades out by itself at that time, even with the screen locked.
    func play(_ sound: AmbientSound, scope: SoundScope, until end: Date? = nil) {
        guard sound != .off else {
            stop(scope: scope)
            return
        }
        shutdownTask?.cancel()
        shutdownTask = nil
        params.volume = Fade.loudness(volume(for: scope))
        params.sound = sound
        params.targetGain = 1
        guard startEngine() else {
            params.targetGain = 0
            playing = .off
            self.scope = nil
            return
        }
        if self.scope != scope { sleepEndsAt = nil }
        playing = sound
        self.scope = scope
        boundUntil = end
        scheduleDeadline()
    }

    /// Ties the running sound to a new end time, e.g. the next focus round.
    func bind(until end: Date?) {
        guard playing != .off else { return }
        boundUntil = end
        scheduleDeadline()
    }

    /// Stops only if `scope` started the current sound, so the end of a
    /// breathing session never silences a sound someone else chose.
    func stop(scope: SoundScope) {
        guard self.scope == scope else { return }
        stop()
    }

    /// Fades out over 1.5 s, then releases the audio session.
    func stop() {
        deadlineTask?.cancel()
        deadlineTask = nil
        playing = .off
        scope = nil
        sleepEndsAt = nil
        boundUntil = nil
        params.targetGain = 0
        guard engine?.isRunning == true else { return }
        shutdownTask?.cancel()
        shutdownTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Fade.seconds + 0.25))
            guard !Task.isCancelled else { return }
            self?.shutdown()
        }
    }

    /// `nil` clears the timer. Only meaningful while something plays.
    func setSleepTimer(minutes: Int?) {
        guard playing != .off else {
            sleepEndsAt = nil
            return
        }
        sleepEndsAt = minutes.map { SleepTimer.endDate(minutes: $0, from: Date()) }
        scheduleDeadline()
    }

    private func scheduleDeadline() {
        deadlineTask?.cancel()
        deadlineTask = nil
        guard playing != .off, let end = SleepTimer.stopDate(sleepEndsAt: sleepEndsAt, boundUntil: boundUntil) else { return }
        let delay: Double = max(0, end.timeIntervalSinceNow)
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    // MARK: Engine

    private func startEngine() -> Bool {
        if let engine, engine.isRunning { return true }
        let session = AVAudioSession.sharedInstance()
        do {
            // Playback keeps sounding with the screen locked (the app declares
            // background audio); mixWithOthers leaves Spotify and co. playing.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            return false
        }
        if engine == nil { buildGraph() }
        guard let engine else { return false }
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    private func buildGraph() {
        let engine = AVAudioEngine()
        let hardwareRate: Double = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let rate: Double = hardwareRate > 0 ? hardwareRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        let renderer = AmbientRenderer(sampleRate: rate, params: params)
        let node = Self.makeSourceNode(renderer: renderer, format: format)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        self.engine = engine
        source = node
        observeConfiguration(of: engine)
    }

    /// Built outside the main actor on purpose: a closure formed in a
    /// main actor context may inherit that isolation, and the render thread
    /// is never the main thread.
    nonisolated private static func makeSourceNode(renderer: AmbientRenderer, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count > 0, let leftRaw = buffers[0].mData else { return noErr }
            let left = leftRaw.assumingMemoryBound(to: Float.self)
            let right: UnsafeMutablePointer<Float>? = buffers.count > 1
                ? buffers[1].mData?.assumingMemoryBound(to: Float.self)
                : nil
            renderer.render(frames: Int(frameCount), left: left, right: right)
            return noErr
        }
    }

    private func shutdown() {
        // A play() during the fade out cancelled this task, but be sure.
        guard playing == .off else { return }
        engine?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func tearDownGraph() {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
        configObserver = nil
        engine?.stop()
        engine = nil
        source = nil
    }

    // MARK: System events

    /// A route change (headphones in or out) stops the engine and may change
    /// the sample rate, so the graph is rebuilt from scratch.
    private func observeConfiguration(of engine: AVAudioEngine) {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuildAfterConfigurationChange()
            }
        }
    }

    private func rebuildAfterConfigurationChange() {
        tearDownGraph()
        guard playing != .off else { return }
        params.targetGain = 1
        if !startEngine() {
            stop()
        }
    }

    /// Calls and alarms pause the engine; pick up again afterwards.
    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            let typeRaw: UInt? = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw: UInt = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            MainActor.assumeIsolated {
                self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
            }
        }
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt) {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        guard type == .ended, playing != .off else { return }
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
        if options.contains(.shouldResume), startEngine() {
            return
        }
        // Not allowed to resume: say so honestly instead of showing "playing".
        stop()
    }
}

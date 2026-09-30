import AVFoundation
import Foundation
import Observation

/// One recorded Japanese line with its subtitles.
struct VoiceLine: Equatable, Identifiable {
    let who: CompanionID
    let cue: VoiceCue
    let japanese: String
    let english: String
    let german: String
    /// Bundle file name without extension, e.g. "nyx_proud_2".
    let file: String

    var id: String { file }
    var subtitle: String { Loc.isGerman ? german : english }
}

/// The lines in voice_lines.json, with the clips scripts/make_voices.py
/// rendered for them. A line whose clip is missing is left out, so a
/// build without voices simply stays quiet.
enum VoiceLibrary {
    private struct Raw: Decodable {
        struct Line: Decodable {
            let who: String
            let cue: String
            let ja: String
            let en: String
            let de: String
        }
        let lines: [Line]
    }

    private static let byKey: [String: [VoiceLine]] = load()

    private static func key(_ who: CompanionID, _ cue: VoiceCue) -> String { "\(who.rawValue)_\(cue.rawValue)" }

    private static func load() -> [String: [VoiceLine]] {
        guard let url = Bundle.main.url(forResource: "voice_lines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return [:] }
        var counters: [String: Int] = [:]
        var result: [String: [VoiceLine]] = [:]
        for line in raw.lines {
            // Numbered per character and situation in file order, exactly
            // like the render script names the clips.
            let group: String = "\(line.who)_\(line.cue)"
            counters[group, default: 0] += 1
            guard let who = CompanionID(rawValue: line.who), let cue = VoiceCue(rawValue: line.cue) else { continue }
            let file: String = "\(group)_\(counters[group] ?? 1)"
            guard Bundle.main.url(forResource: file, withExtension: "m4a") != nil else { continue }
            result[key(who, cue), default: []].append(
                VoiceLine(who: who, cue: cue, japanese: line.ja, english: line.en, german: line.de, file: file))
        }
        return result
    }

    static func line(_ who: CompanionID, _ cue: VoiceCue, seed: Int) -> VoiceLine? {
        guard let options = byKey[key(who, cue)], !options.isEmpty else { return nil }
        return options[((seed % options.count) + options.count) % options.count]
    }

    static func line(file: String) -> VoiceLine? {
        byKey.values.lazy.flatMap { $0 }.first { $0.file == file }
    }

    static var isEmpty: Bool { byKey.isEmpty }
}

/// Plays the clips. Uses the ambient audio category, so it mixes with
/// music and stays silent when the ring switch is off, like a game would.
@MainActor
@Observable
final class CompanionVoice {
    static let shared = CompanionVoice()

    /// The line playing right now; the portrait shows its subtitle.
    private(set) var current: VoiceLine?

    private var player: AVAudioPlayer?
    private let finish = FinishDelegate()

    private init() {
        finish.onFinish = { [weak self] in
            Task { @MainActor in self?.current = nil }
        }
    }

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "ma.companion.voiceClips") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "ma.companion.voiceClips"); if !newValue { stop() } }
    }

    func play(_ line: VoiceLine?) {
        guard enabled, let line, let url = Bundle.main.url(forResource: line.file, withExtension: "m4a") else { return }
        stop()
        if SoundEngine.shared.playing == .off {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = finish
        player.volume = 1
        player.prepareToPlay()
        player.play()
        self.player = player
        current = line
    }

    func stop() {
        player?.stop()
        player = nil
        current = nil
    }

    private final class FinishDelegate: NSObject, AVAudioPlayerDelegate {
        var onFinish: (() -> Void)?

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            onFinish?()
        }
    }
}

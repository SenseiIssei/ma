import AVFoundation
import Foundation
import Observation

struct CompanionMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case user, companion, quest }

    var id = UUID()
    var role: Role
    var text: String
    var mood: CompanionMood = .neutral
    /// Only for quest windows: the heading and the reward.
    var title: String?
    var reward: Int?
    var date = Date()
}

/// The chat with the chosen companion. Answers come from the on-device
/// model when the iPhone has one and from the scripted lines otherwise;
/// either way they are built on the same snapshot of real numbers.
@MainActor
@Observable
final class CompanionStore {
    private(set) var companion: CompanionID = CompanionID.current
    private(set) var messages: [CompanionMessage] = []
    private(set) var thinking = false
    /// The portrait on top follows the last answer for a while.
    var mood: CompanionMood = .neutral
    var voiceOn: Bool = UserDefaults.standard.bool(forKey: "ma.companion.voice") {
        didSet {
            UserDefaults.standard.set(voiceOn, forKey: "ma.companion.voice")
            if !voiceOn { voice.stop() }
        }
    }

    private let brain = CompanionBrain()
    private let voice = RoutineVoice()
    private var moodReset: Task<Void, Never>?
    private var seed: Int = Int.random(in: 0..<1000)

    private static let file = "companion-chat.json"
    /// Enough to scroll back through a week of short talks.
    private static let keep = 80

    init() {
        messages = MaShared.read([CompanionMessage].self, from: Self.file) ?? []
    }

    var usesModel: Bool { brain.isReady }

    func choose(_ id: CompanionID) {
        guard id != companion || !CompanionID.hasChosen else { return }
        CompanionID.current = id
        companion = id
        brain.reset()
        voice.stop()
        messages.removeAll()
        persist()
    }

    func clear() {
        messages.removeAll()
        brain.reset()
        persist()
    }

    /// Called when the chat opens: a greeting and today's quest window,
    /// unless the companion already spoke in the last three hours.
    func open(_ snapshot: CompanionSnapshot) {
        seed += 1
        if let last = messages.last(where: { $0.role != .user }), Date().timeIntervalSince(last.date) < 3 * 3600 {
            return
        }
        let line: CompanionLine = CompanionScript.greeting(companion, snapshot, seed: seed)
        append(CompanionMessage(role: .companion, text: line.text, mood: line.mood))
        if let quest = CompanionScript.dailyQuest(snapshot) {
            append(CompanionMessage(role: .quest, text: quest.detail, title: quest.title, reward: quest.reward))
        }
        show(line.mood)
        speak(line.text)
    }

    func send(_ raw: String, snapshot: CompanionSnapshot) async {
        let text: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }
        seed += 1
        let recent: [CompanionMessage] = messages
        append(CompanionMessage(role: .user, text: text))
        let mood: CompanionMood = CompanionIntent.of(text).mood(for: snapshot)
        thinking = true
        defer { thinking = false }

        if brain.isReady {
            var reply = CompanionMessage(role: .companion, text: "", mood: mood)
            messages.append(reply)
            let index: Int = messages.count - 1
            do {
                let answer: String = try await brain.reply(to: text, who: companion, snapshot: snapshot, recent: recent) { [weak self] partial in
                    guard let self, index < self.messages.count else { return }
                    self.messages[index].text = partial
                }
                if answer.isEmpty { throw CancellationError() }
                reply.text = answer
                messages[index] = reply
                persist()
                show(mood)
                speak(answer)
                return
            } catch {
                // The scripted voice takes over; the half answer goes.
                if index < messages.count, messages[index].id == reply.id {
                    messages.remove(at: index)
                }
            }
        }
        // A short pause so the answer does not land before the question.
        try? await Task.sleep(for: .milliseconds(450))
        let line: CompanionLine = CompanionScript.reply(companion, to: text, snapshot, seed: seed)
        append(CompanionMessage(role: .companion, text: line.text, mood: line.mood))
        show(line.mood)
        speak(line.text)
    }

    func stopVoice() {
        voice.stop()
    }

    // MARK: Private

    private func append(_ message: CompanionMessage) {
        messages.append(message)
        persist()
    }

    private func persist() {
        if messages.count > Self.keep { messages.removeFirst(messages.count - Self.keep) }
        MaShared.write(messages, to: Self.file)
    }

    private func show(_ mood: CompanionMood) {
        self.mood = mood
        moodReset?.cancel()
        guard mood != .neutral else { return }
        moodReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(9))
            guard !Task.isCancelled else { return }
            self?.mood = .neutral
        }
    }

    private func speak(_ text: String) {
        guard voiceOn else { return }
        voice.say(Self.speakable(text), voice: Self.voice(for: companion), pitch: companion.pitch)
    }

    /// "[Quest]" reads badly aloud.
    private static func speakable(_ text: String) -> String {
        text.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: ":")
    }

    /// The best installed voice of the app language, female for Nyx and
    /// male for Kael when the iPhone has one.
    private static func voice(for who: CompanionID) -> AVSpeechSynthesisVoice? {
        let language: String = Loc.isGerman ? "de" : "en"
        let voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }
        let gender: AVSpeechSynthesisVoiceGender = who.prefersFemaleVoice ? .female : .male
        let ranked: [AVSpeechSynthesisVoice] = voices.sorted { a, b in
            let aScore: Int = (a.gender == gender ? 10 : 0) + a.quality.rawValue
            let bScore: Int = (b.gender == gender ? 10 : 0) + b.quality.rawValue
            return aScore > bScore
        }
        return ranked.first ?? AVSpeechSynthesisVoice(language: Loc.isGerman ? "de-DE" : "en-US")
    }
}

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
    /// The recorded line that played with this answer and its subtitle.
    var voice: String?
    var subtitle: String?
    var date = Date()
}

/// The chat with the chosen companion. Answers come from the on-device
/// model when the iPhone has one and from the scripted lines otherwise;
/// either way they are built on the same snapshot of real numbers, and a
/// recorded Japanese line in the companion's own voice plays with them.
@MainActor
@Observable
final class CompanionStore {
    private(set) var companion: CompanionID = CompanionID.current
    private(set) var messages: [CompanionMessage] = []
    private(set) var thinking = false
    /// The portrait on top follows the last answer for a while.
    var mood: CompanionMood = .neutral
    var voiceOn: Bool = CompanionVoice.shared.enabled {
        didSet { CompanionVoice.shared.enabled = voiceOn }
    }

    private let brain = CompanionBrain()
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
        CompanionVoice.shared.stop()
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
        let line: CompanionLine = CompanionScript.greeting(snapshot)
        say(line.text, cue: line.cue)
        if let quest = CompanionScript.dailyQuest(snapshot) {
            append(CompanionMessage(role: .quest, text: quest.detail, title: quest.title, reward: quest.reward))
        }
    }

    func send(_ raw: String, snapshot: CompanionSnapshot) async {
        let text: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }
        seed += 1
        let recent: [CompanionMessage] = messages
        append(CompanionMessage(role: .user, text: text))
        let cue: VoiceCue = CompanionIntent.of(text).cue(for: snapshot)
        thinking = true
        defer { thinking = false }

        if brain.isReady {
            let voice: VoiceLine? = VoiceLibrary.line(companion, cue, seed: seed)
            // The line plays while the model writes; it is the character's
            // first reaction, the text follows.
            CompanionVoice.shared.play(voice)
            show(cue.mood)
            let reply = CompanionMessage(role: .companion, text: "", mood: cue.mood,
                                         voice: voice?.file, subtitle: voice?.subtitle)
            messages.append(reply)
            let index: Int = messages.count - 1
            do {
                let answer: String = try await brain.reply(to: text, who: companion, snapshot: snapshot, recent: recent) { [weak self] partial in
                    guard let self, index < self.messages.count else { return }
                    self.messages[index].text = partial
                }
                if answer.isEmpty { throw CancellationError() }
                messages[index].text = answer
                persist()
                return
            } catch {
                // The scripted answer takes over; the half one goes.
                if index < messages.count, messages[index].id == reply.id {
                    messages.remove(at: index)
                }
            }
        }
        // A short pause so the answer does not land before the question.
        try? await Task.sleep(for: .milliseconds(450))
        let line: CompanionLine = CompanionScript.reply(to: text, snapshot, seed: seed)
        say(line.text, cue: line.cue)
    }

    /// Plays the line of an earlier answer again.
    func replay(_ message: CompanionMessage) {
        guard let file = message.voice else { return }
        CompanionVoice.shared.play(VoiceLibrary.line(file: file))
        show(message.mood)
    }

    func stopVoice() {
        CompanionVoice.shared.stop()
    }

    // MARK: Private

    private func say(_ text: String, cue: VoiceCue) {
        let voice: VoiceLine? = VoiceLibrary.line(companion, cue, seed: seed)
        append(CompanionMessage(role: .companion, text: text, mood: cue.mood, voice: voice?.file, subtitle: voice?.subtitle))
        show(cue.mood)
        CompanionVoice.shared.play(voice)
    }

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
}

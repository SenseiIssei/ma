import FoundationModels
import Foundation

/// The companion's voice when Apple's on-device model can run. One session
/// carries the conversation; it starts over when the facts change, when a
/// different companion speaks, or before the context window fills up. The
/// last few lines travel along into the fresh session, so nothing feels
/// forgotten.
@MainActor
final class CompanionBrain {
    private var session: LanguageModelSession?
    private var instructions = ""
    private var turns = 0

    /// A session this many turns long is replaced before it gets too big
    /// for the small on-device context.
    private static let maxTurns = 6

    var isReady: Bool { MaAI.status.isReady }

    func reset() {
        session = nil
        turns = 0
    }

    /// Streams the answer, calling `partial` with the whole text so far.
    func reply(to text: String, who: CompanionID, snapshot: CompanionSnapshot,
               recent: [CompanionMessage], partial: @escaping (String) -> Void) async throws -> String {
        let wanted: String = CompanionPrompt.instructions(who, snapshot)
        var prompt: String = text
        if session == nil || wanted != instructions || turns >= Self.maxTurns {
            session = LanguageModelSession(instructions: wanted)
            instructions = wanted
            turns = 0
            prompt = Self.withRecap(text, recent: recent, who: who)
        }
        do {
            return try await stream(prompt, partial: partial)
        } catch let error as LanguageModelSession.GenerationError {
            guard case .exceededContextWindowSize = error else { throw error }
            // Too long after all: once more with a clean slate.
            session = LanguageModelSession(instructions: wanted)
            turns = 0
            return try await stream(text, partial: partial)
        }
    }

    private func stream(_ prompt: String, partial: @escaping (String) -> Void) async throws -> String {
        guard let session else { return "" }
        var text = ""
        for try await snapshot in session.streamResponse(to: prompt) {
            text = MaAI.clean(snapshot.content)
            partial(text)
        }
        turns += 1
        return text
    }

    /// The last lines of the chat in front of the new message, for a
    /// session that starts without them.
    private static func withRecap(_ text: String, recent: [CompanionMessage], who: CompanionID) -> String {
        let lines: [String] = recent.suffix(4).compactMap { message in
            switch message.role {
            case .user: return (Loc.isGerman ? "Person: " : "Person: ") + message.text
            case .companion: return "\(who.name): " + message.text
            case .quest: return nil
            }
        }
        guard !lines.isEmpty else { return text }
        let header: String = Loc.isGerman ? "Bisheriges Gespräch:" : "Conversation so far:"
        let now: String = Loc.isGerman ? "Neue Nachricht:" : "New message:"
        return "\(header)\n\(lines.joined(separator: "\n"))\n\n\(now) \(text)"
    }
}

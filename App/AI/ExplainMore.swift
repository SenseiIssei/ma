import FoundationModels
import Observation
import SwiftUI

/// Explanations written by the on-device model, kept in memory per card.
/// One store for the whole app, so an explanation that finishes after the
/// learner moved on is still there when the card comes back.
@MainActor
@Observable
final class ExplanationStore {
    static let shared = ExplanationStore()

    enum Phase: Equatable {
        case streaming
        case done
        case failed(String)
    }

    struct Entry: Equatable {
        var text = ""
        var phase: Phase = .streaming
    }

    private(set) var entries: [String: Entry] = [:]
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var runningKey: String?

    private init() {}

    static func key(_ deck: Deck, _ card: Card) -> String { "\(deck.id)/\(card.id)" }

    func entry(for deck: Deck, _ card: Card) -> Entry? {
        entries[Self.key(deck, card)]
    }

    /// Starts writing unless there already is a finished or running text.
    /// Only one explanation streams at a time; the model is shared by the
    /// whole phone, and the learner only reads one card at once anyway.
    func explain(_ card: Card, in deck: Deck, afterMistake: Bool) {
        let key = Self.key(deck, card)
        if let existing = entries[key] {
            switch existing.phase {
            case .done:
                return
            case .streaming:
                if runningKey == key { return }
            case .failed:
                // A failed try may be retried.
                break
            }
        }
        guard MaAI.status.isReady else {
            entries[key] = Entry(text: "", phase: .failed(MaAI.note(for: MaAI.status)))
            return
        }

        if let runningKey, runningKey != key, entries[runningKey]?.phase == .streaming {
            // Half an explanation is worse than none; the cancelled one starts over next time.
            entries[runningKey] = nil
        }
        running?.cancel()

        entries[key] = Entry()
        runningKey = key
        let instructions = ExplainPrompt.instructions
        let prompt = ExplainPrompt.prompt(card: card, deck: deck, afterMistake: afterMistake)
        running = Task {
            await self.stream(key: key, instructions: instructions, prompt: prompt)
        }
    }

    private func stream(key: String, instructions: String, prompt: String) async {
        // A fresh session per card: nothing from the last card should leak in,
        // and a short transcript keeps us far from the context limit.
        let session = LanguageModelSession(instructions: instructions)
        let stream = session.streamResponse(to: prompt)
        do {
            for try await snapshot in stream {
                // Snapshots carry the whole text so far, not just the new tokens.
                let partial: String = snapshot.content
                entries[key]?.text = MaAI.clean(partial)
            }
            if Task.isCancelled {
                entries[key] = nil
            } else if entries[key]?.text.isEmpty ?? true {
                entries[key] = Entry(text: "", phase: .failed(MaAI.genericFailure))
            } else {
                entries[key]?.phase = .done
            }
        } catch {
            if MaAI.isCancellation(error) {
                entries[key] = nil
            } else {
                entries[key] = Entry(text: "", phase: .failed(MaAI.message(for: error)))
            }
        }
        if runningKey == key {
            runningKey = nil
            running = nil
        }
    }
}

/// What the model is told. Written in the app language so the answer
/// comes back in it too, in du-form for German.
enum ExplainPrompt {
    static var instructions: String {
        if Loc.isGerman {
            return """
            Du bist eine freundliche, geduldige Lernbegleitung in Ma, einer ruhigen Lern-App. \
            Schreib immer auf Deutsch und sprich die lernende Person mit du an. \
            Erkläre eine Lernkarte in 3 bis 5 kurzen Sätzen Fließtext: warum die Antwort stimmt, \
            eine Eselsbrücke oder einen anschaulichen Vergleich und ein weiteres Beispiel. \
            Keine Listen, keine Überschriften, kein Markdown, keine Emojis. \
            Bleib sachlich richtig. Wenn du unsicher bist, erklär lieber einfach, statt etwas zu erfinden.
            """
        }
        return """
        You are a warm, patient tutor inside Ma, a calm learning app. \
        Always write in English and speak to the learner directly. \
        Explain one flash card in 3 to 5 short sentences of plain prose: why the answer is right, \
        a memory hook or a vivid analogy, and one extra example. \
        No lists, no headings, no Markdown, no emojis. \
        Stay accurate. If you are unsure, keep it simple rather than invent facts.
        """
    }

    static func prompt(card: Card, deck: Deck, afterMistake: Bool) -> String {
        let german = Loc.isGerman
        var lines: [String] = []
        lines.append((german ? "Thema: " : "Topic: ") + deck.title)
        lines.append((german ? "Frage: " : "Question: ") + card.prompt)
        lines.append((german ? "Antwort: " : "Answer: ") + card.answer)
        if let note = card.note, !note.isEmpty {
            lines.append((german ? "Notiz auf der Karte: " : "Note on the card: ") + note)
        }
        if let example = card.example, !example.isEmpty {
            lines.append((german ? "Beispiel auf der Karte: " : "Example on the card: ") + example)
        }
        if afterMistake {
            lines.append(german
                ? "Die Person hat diese Karte gerade falsch beantwortet. Mach ihr Mut."
                : "The learner just got this card wrong. Be encouraging.")
        }
        lines.append(german ? "Erkläre diese Karte." : "Explain this card.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Panel

/// "Explain more": a small button that opens into a panel where the model's
/// explanation streams in. Used on the teaching card and after a wrong answer.
struct ExplainMorePanel: View {
    let deck: Deck
    let card: Card
    var afterMistake = false
    /// Caps the text height, for the feedback sheet that must not grow past the screen.
    var maxTextHeight: CGFloat? = nil

    @State private var open = false
    @State private var status: MaAI.Status = .ready
    private var store: ExplanationStore { ExplanationStore.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toggle
            if open {
                panel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: open)
    }

    private var toggle: some View {
        Button {
            Haptics.tap()
            if !open {
                status = MaAI.status
                if status.isReady { store.explain(card, in: deck, afterMistake: afterMistake) }
            }
            open.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                Text(tr("Explain more", "Mehr erklären"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .foregroundStyle(Zen.ai)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Zen.ai.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(MaAI.privacyLine)
    }

    @ViewBuilder
    private var panel: some View {
        if !status.isReady {
            AIUnavailableNote(status: status)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                explanation
                AIPrivacyLabel()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Zen.sand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder
    private var explanation: some View {
        let entry = store.entry(for: deck, card)
        if let entry, case .failed(let message) = entry.phase {
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr("Try again", "Nochmal versuchen")) {
                    status = MaAI.status
                    if status.isReady { store.explain(card, in: deck, afterMistake: afterMistake) }
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Zen.ai)
            }
        } else if let entry, !entry.text.isEmpty {
            textBlock(entry.text, streaming: entry.phase == .streaming)
        } else {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Zen.ai)
                Text(tr("Thinking it through…", "Wird durchdacht…"))
                    .font(.system(size: 14))
                    .foregroundStyle(Zen.inkSoft)
            }
        }
    }

    @ViewBuilder
    private func textBlock(_ text: String, streaming: Bool) -> some View {
        let content = Text(text)
            .font(.system(size: 16))
            .foregroundStyle(Zen.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.15), value: text)
        if let maxTextHeight {
            ScrollView {
                content
            }
            .frame(maxHeight: maxTextHeight)
            .scrollBounceBehavior(.basedOnSize)
        } else {
            content
        }
    }
}

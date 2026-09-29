import FoundationModels
import Foundation

// MARK: - Shapes the model fills in

/// One flash card as the model writes it. Property order is generation
/// order: prompt and answer first, so the rest is written with them in view.
@Generable(description: "One flash card for a learning app")
struct GeneratedCard {
    @Guide(description: "The question or the word to learn, short and clear")
    var prompt: String

    @Guide(description: "The correct answer, a word or a few words, at most 40 characters")
    var answer: String

    @Guide(description: "Three plausible but clearly wrong answers, in the same style and length as the correct answer", .count(3))
    var distractors: [String]

    @Guide(description: "One natural example sentence that contains the correct answer exactly as written")
    var example: String

    @Guide(description: "One or two friendly sentences on why the answer is right or how to remember it")
    var note: String
}

/// First batch of a new topic: the deck's face plus ten cards.
@Generable(description: "A learning topic with flash cards")
struct GeneratedTopic {
    @Guide(description: "Short title of the topic, one to three words")
    var title: String

    @Guide(description: "One short line on what the topic covers")
    var subtitle: String

    @Guide(description: "Exactly one character that stands for the topic, for example a kanji or a capital letter, never an emoji")
    var symbol: String

    @Guide(description: "Ten different flash cards, from easy to harder", .count(10))
    var cards: [GeneratedCard]
}

/// Every later batch: just ten more cards.
@Generable(description: "Ten more flash cards for a learning topic")
struct GeneratedCardBatch {
    @Guide(description: "Ten different flash cards, from easy to harder", .count(10))
    var cards: [GeneratedCard]
}

// MARK: - Level

enum TopicLevel: String, CaseIterable, Identifiable {
    case beginner, basics, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner: tr("Beginner", "Einsteiger")
        case .basics: tr("Some basics", "Etwas Vorwissen")
        case .advanced: tr("Advanced", "Fortgeschritten")
        }
    }

    /// How the level reads inside the prompt.
    var promptText: String {
        switch self {
        case .beginner:
            Loc.isGerman ? "Einsteiger ohne Vorwissen" : "a beginner with no prior knowledge"
        case .basics:
            Loc.isGerman ? "jemand mit etwas Vorwissen" : "someone who knows the basics"
        case .advanced:
            Loc.isGerman ? "Fortgeschrittene, die in die Tiefe wollen" : "an advanced learner who wants depth"
        }
    }
}

// MARK: - Writer

/// What a finished run hands back, before anything is saved.
struct TopicDraft {
    var title: String
    var subtitle: String
    var symbol: String
    var cards: [Card]
    /// Set when some batches failed but earlier ones gave usable cards.
    var shortfall: String?
}

/// Writes cards with guided generation. The on-device model has a small
/// context window, so cards come in batches of ten, each from a fresh
/// session that only gets a short list of questions to avoid.
@MainActor
enum TopicWriter {
    static let batchSize = 10
    static let maxAnswerLength = 40

    /// A new topic with `count` cards (10, 20 or 30). `progress` gets the
    /// number of usable cards after every batch.
    static func writeTopic(topic: String, level: TopicLevel, count: Int, progress: (Int) -> Void) async throws -> TopicDraft {
        let subject = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let batches = max(1, min(3, (count + batchSize - 1) / batchSize))

        let firstPrompt = TopicPrompt.newTopic(subject: subject, level: level)
        let firstSession = LanguageModelSession(instructions: TopicPrompt.instructions)
        let first = try await firstSession.respond(to: firstPrompt, generating: GeneratedTopic.self)
        let head: GeneratedTopic = first.content

        var cards = accept(head.cards, avoiding: [])
        var draft = TopicDraft(
            title: clip(MaAI.clean(head.title), to: 60, fallback: subject),
            subtitle: clip(MaAI.clean(head.subtitle), to: 90, fallback: ""),
            symbol: symbol(from: head.symbol),
            cards: cards
        )
        progress(cards.count)

        if batches > 1 {
            for _ in 1..<batches {
                try Task.checkCancellation()
                let taken = cards.map(\.prompt)
                let prompt = TopicPrompt.moreCards(subject: subject, level: level, avoiding: taken, samples: [])
                do {
                    let more = try await writeBatch(prompt: prompt)
                    cards += accept(more, avoiding: taken)
                    progress(cards.count)
                } catch {
                    if MaAI.isCancellation(error) { throw error }
                    // Keep what already worked; a partial topic beats losing everything.
                    guard !cards.isEmpty else { throw error }
                    draft.shortfall = MaAI.message(for: error)
                    break
                }
            }
        }

        draft.cards = cards
        return draft
    }

    /// Ten more cards in the style of an existing deck.
    static func writeMore(for deck: Deck) async throws -> [Card] {
        let taken = deck.cards.map(\.prompt)
        let samples = Array(deck.cards.shuffled().prefix(3))
        let subject = deck.subtitle.isEmpty ? deck.title : "\(deck.title) (\(deck.subtitle))"
        let prompt = TopicPrompt.moreCards(subject: subject, level: nil, avoiding: taken, samples: samples)
        let raw = try await writeBatch(prompt: prompt)
        return accept(raw, avoiding: taken)
    }

    private static func writeBatch(prompt: String) async throws -> [GeneratedCard] {
        let session = LanguageModelSession(instructions: TopicPrompt.instructions)
        let response = try await session.respond(to: prompt, generating: GeneratedCardBatch.self)
        let batch: GeneratedCardBatch = response.content
        return batch.cards
    }

    // MARK: Validation

    /// Model cards into Ma cards, dropping anything the exercises cannot use.
    static func accept(_ raw: [GeneratedCard], avoiding existing: [String]) -> [Card] {
        var seen = Set(existing.map(Grader.normalize))
        var result: [Card] = []
        for item in raw {
            guard let card = validate(prompt: item.prompt, answer: item.answer, distractors: item.distractors, example: item.example, note: item.note) else { continue }
            let key = Grader.normalize(card.prompt)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(card)
        }
        return result
    }

    /// The rules from the deck format: a short answer, distinct wrong
    /// answers that never equal the right one, and an example only if it
    /// holds the answer word for word (otherwise gap exercises break).
    static func validate(prompt rawPrompt: String, answer rawAnswer: String, distractors rawDistractors: [String], example rawExample: String, note rawNote: String) -> Card? {
        let prompt = MaAI.clean(rawPrompt)
        let answer = trimAnswer(MaAI.clean(rawAnswer))
        guard !prompt.isEmpty, !answer.isEmpty, answer.count <= maxAnswerLength else { return nil }
        guard Grader.normalize(prompt) != Grader.normalize(answer) else { return nil }

        let answerKey = Grader.normalize(answer)
        var used: Set<String> = [answerKey]
        var distractors: [String] = []
        for raw in rawDistractors {
            let option = trimAnswer(MaAI.clean(raw))
            let key = Grader.normalize(option)
            guard !option.isEmpty, !key.isEmpty, option.count <= maxAnswerLength, !used.contains(key) else { continue }
            used.insert(key)
            distractors.append(option)
        }

        let exampleText = MaAI.clean(rawExample)
        let example: String? = exampleText.contains(answer) && exampleText != answer ? exampleText : nil
        let noteText = MaAI.clean(rawNote)
        let note: String? = noteText.isEmpty ? nil : noteText

        return Card(prompt: prompt, answer: answer, distractors: Array(distractors.prefix(3)), example: example, note: note)
    }

    /// Answers sometimes arrive in quotes or with a closing full stop, which
    /// would make typing exercises and gap texts needlessly strict. A dot
    /// inside the answer (an abbreviation like U.S.) is left alone.
    private static func trimAnswer(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") {
            s = String(s.dropFirst().dropLast())
        }
        let dots = s.filter { $0 == "." }.count
        if dots == 1, s.hasSuffix(".") { s.removeLast() }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// One visible character, never an emoji or punctuation; else Ma's default.
    static func symbol(from raw: String) -> String {
        let fallback = "学"
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return fallback }
        let isEmoji = first.unicodeScalars.contains { $0.properties.isEmojiPresentation }
        if isEmoji || first.isPunctuation || first.isSymbol || first.isWhitespace { return fallback }
        return String(first)
    }

    private static func clip(_ text: String, to limit: Int, fallback: String) -> String {
        let value = text.isEmpty ? fallback : text
        return value.count > limit ? String(value.prefix(limit)) : value
    }
}

// MARK: - Prompts

/// Written in the app language, so the cards come back in it.
enum TopicPrompt {
    static var instructions: String {
        if Loc.isGerman {
            return """
            Du schreibst Lernkarten für Ma, eine ruhige Lern-App. Schreib alles auf Deutsch. \
            Fakten müssen stimmen. Antworten sind kurz: ein Wort oder wenige Wörter, höchstens 40 Zeichen. \
            Die drei falschen Antworten sind plausibel, im selben Stil wie die richtige, aber eindeutig falsch. \
            Der Beispielsatz enthält die richtige Antwort genau so, wie sie geschrieben ist. \
            Die Notiz ist freundlich und hat ein oder zwei Sätze. Kein Markdown, keine Emojis.
            """
        }
        return """
        You write flash cards for Ma, a calm learning app. Write everything in English. \
        Facts must be correct. Answers are short: a word or a few words, at most 40 characters. \
        The three wrong answers are plausible, in the same style as the correct one, but clearly wrong. \
        The example sentence contains the correct answer exactly as written. \
        The note is friendly and one or two sentences long. No Markdown, no emojis.
        """
    }

    static func newTopic(subject: String, level: TopicLevel) -> String {
        let german = Loc.isGerman
        var lines: [String] = []
        lines.append((german ? "Thema: " : "Topic: ") + subject)
        lines.append((german ? "Niveau: " : "Level: ") + level.promptText)
        lines.append(german
            ? "Gib dem Thema einen kurzen Titel, eine Unterzeile und ein Zeichen. Schreib dann 10 verschiedene Lernkarten, die das Wichtigste abdecken."
            : "Give the topic a short title, a subtitle and one character. Then write 10 different flash cards that cover the essentials.")
        return lines.joined(separator: "\n")
    }

    static func moreCards(subject: String, level: TopicLevel?, avoiding: [String], samples: [Card]) -> String {
        let german = Loc.isGerman
        var lines: [String] = []
        lines.append((german ? "Thema: " : "Topic: ") + subject)
        if let level {
            lines.append((german ? "Niveau: " : "Level: ") + level.promptText)
        }
        if !samples.isEmpty {
            lines.append(german ? "So sehen vorhandene Karten aus, halte Stil und Schwierigkeit:" : "Existing cards look like this, keep the style and difficulty:")
            for card in samples {
                lines.append("\(short(card.prompt)) = \(short(card.answer))")
            }
        }
        // Only the most recent questions: enough to avoid repeats, small enough for the context window.
        let recent = avoiding.suffix(30).map { short($0) }
        if !recent.isEmpty {
            lines.append(german ? "Diese Fragen gibt es schon, wiederhole keine davon:" : "These questions already exist, repeat none of them:")
            lines.append(recent.joined(separator: "; "))
        }
        lines.append(german
            ? "Schreib 10 neue, verschiedene Lernkarten zu weiteren Aspekten des Themas."
            : "Write 10 new, different flash cards on further aspects of the topic.")
        return lines.joined(separator: "\n")
    }

    private static func short(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 60 ? String(flat.prefix(60)) : flat
    }
}

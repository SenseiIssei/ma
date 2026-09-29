import Foundation

/// A topic. Built-in decks ship as JSON in the bundle, your own live in
/// Documents and use exactly the same format, so any deck can be exported,
/// edited by hand or generated elsewhere and imported again.
struct Deck: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String = ""
    var symbol: String = "学"
    /// "ja" marks Japanese decks: no typing exercises for kana answers.
    var language: String?
    var cards: [Card] = []
    var isBuiltIn = false
    /// Language edition of a built-in deck. Editions share deck and card
    /// ids, so progress carries over when the app language changes.
    var locale: String?

    init(id: String = UUID().uuidString, title: String, subtitle: String = "", symbol: String = "学", language: String? = nil, cards: [Card] = [], isBuiltIn: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.language = language
        self.cards = cards
        self.isBuiltIn = isBuiltIn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "学"
        language = try c.decodeIfPresent(String.self, forKey: .language)
        cards = try c.decodeIfPresent([Card].self, forKey: .cards) ?? []
        isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        locale = try c.decodeIfPresent(String.self, forKey: .locale)
    }
}

struct Card: Codable, Identifiable, Hashable {
    var id: String
    var prompt: String
    var answer: String
    /// Other spellings accepted when typing.
    var accept: [String] = []
    /// Hand-picked wrong answers. Without them, other cards lend theirs.
    var distractors: [String] = []
    /// A sentence containing `answer` verbatim, for fill-in-the-gap.
    var example: String?
    /// Shown after answering. The part where learning actually happens.
    var note: String?

    init(id: String = UUID().uuidString, prompt: String, answer: String, accept: [String] = [], distractors: [String] = [], example: String? = nil, note: String? = nil) {
        self.id = id
        self.prompt = prompt
        self.answer = answer
        self.accept = accept
        self.distractors = distractors
        self.example = example
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        prompt = try c.decode(String.self, forKey: .prompt)
        answer = try c.decode(String.self, forKey: .answer)
        accept = try c.decodeIfPresent([String].self, forKey: .accept) ?? []
        distractors = try c.decodeIfPresent([String].self, forKey: .distractors) ?? []
        example = try c.decodeIfPresent(String.self, forKey: .example)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    var tokens: [String] {
        answer.split(separator: " ").map(String.init)
    }
}

/// Leitner box per card. Box 0 is new, box 5 is "you know this".
struct CardProgress: Codable {
    var box = 0
    var due = Date.distantPast
    var seen = 0
    var correct = 0
    var wrong = 0
    /// The learner has seen the teaching screen for this card. Only
    /// introduced cards are ever asked, nobody should be quizzed on
    /// something they were never shown.
    var introduced = false

    /// Minutes until the card comes back, per box after a correct answer.
    static let intervals: [Double] = [0, 10, 60 * 24, 60 * 24 * 3, 60 * 24 * 7, 60 * 24 * 21]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        box = try c.decodeIfPresent(Int.self, forKey: .box) ?? 0
        due = try c.decodeIfPresent(Date.self, forKey: .due) ?? .distantPast
        seen = try c.decodeIfPresent(Int.self, forKey: .seen) ?? 0
        correct = try c.decodeIfPresent(Int.self, forKey: .correct) ?? 0
        wrong = try c.decodeIfPresent(Int.self, forKey: .wrong) ?? 0
        // Progress from before the teaching step: anything already answered
        // counts as introduced, so old learners are not taught it again.
        introduced = try c.decodeIfPresent(Bool.self, forKey: .introduced) ?? (seen > 0)
    }

    /// Introduced, but not yet in box 3.
    var isLearning: Bool { introduced && box < 3 }
    var isKnown: Bool { box >= 3 }

    mutating func record(correct right: Bool, now: Date = Date()) {
        seen += 1
        introduced = true
        if right {
            correct += 1
            box = min(5, box + 1)
        } else {
            wrong += 1
            box = max(0, box - 2)
        }
        let minutes = right ? Self.intervals[box] : 2
        due = now.addingTimeInterval(minutes * 60)
    }
}

/// Where the cards of a deck stand: never shown, being learned, known.
struct DeckCounts: Equatable {
    var new = 0
    var learning = 0
    var known = 0

    var introduced: Int { learning + known }
    var total: Int { new + learning + known }
}

struct LearnerProfile: Codable {
    var xp = 0
    var activeDeckIDs: Set<String> = []
    var streakDays = 0
    var lastLearnedDay: String?
    var dailyGoal = 20

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        xp = try c.decodeIfPresent(Int.self, forKey: .xp) ?? 0
        activeDeckIDs = try c.decodeIfPresent(Set<String>.self, forKey: .activeDeckIDs) ?? []
        streakDays = try c.decodeIfPresent(Int.self, forKey: .streakDays) ?? 0
        lastLearnedDay = try c.decodeIfPresent(String.self, forKey: .lastLearnedDay)
        dailyGoal = try c.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? 20
    }
}

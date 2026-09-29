import Foundation
import Observation

/// One run of questions. A lesson teaches a few new cards and then asks a
/// fixed number of questions; the gate keeps asking until enough answers
/// were right, because the point of the gate is to arrive at the app with a
/// slightly different head. Teaching steps never count as answers.
@Observable
final class QuizSession {
    enum Mode: Equatable {
        case gate(required: Int)
        case lesson(count: Int)
        /// Like a lesson, but only cards that were already taught.
        case review(count: Int)
    }

    let mode: Mode
    private let store: DeckStore
    private let decks: [Deck]
    private(set) var exercises: [Exercise]
    private(set) var index = 0
    private(set) var correct = 0
    private(set) var wrong = 0
    private(set) var finished = false
    /// Cards taught in this session.
    private(set) var learned = 0
    /// XP earned, the same rule as `DeckStore.record`.
    private(set) var xpEarned = 0

    init(mode: Mode, store: DeckStore, decks: [Deck]? = nil) {
        self.mode = mode
        self.store = store
        let source = decks ?? store.activeDecks
        self.decks = source
        let engine = ExerciseEngine(store: store)
        switch mode {
        case .gate(let needed):
            exercises = engine.gate(required: max(1, needed), from: source)
        case .lesson(let count):
            exercises = engine.lesson(count: count, from: source)
        case .review(let count):
            exercises = engine.lesson(count: count, from: source, teachNew: false)
        }
        if exercises.isEmpty { finished = true }
    }

    var current: Exercise? {
        exercises.indices.contains(index) ? exercises[index] : nil
    }

    var needed: Int {
        if case .gate(let needed) = mode { return needed }
        return exercises.count
    }

    /// Questions only, without the teaching steps.
    var questionCount: Int {
        exercises.filter { $0.kind != .teach }.count
    }

    /// Cards this session is going to teach.
    var teachCount: Int {
        exercises.filter { $0.kind == .teach }.count
    }

    var progress: Double {
        switch mode {
        case .gate(let needed):
            return Double(correct) / Double(max(1, needed))
        case .lesson, .review:
            return Double(index) / Double(max(1, exercises.count))
        }
    }

    var accuracy: Double {
        let total = correct + wrong
        return total == 0 ? 1 : Double(correct) / Double(total)
    }

    /// The teaching screen was read. Marks the card introduced, nothing more.
    func introduce(_ exercise: Exercise) {
        guard exercise.kind == .teach else { return }
        if !store.isIntroduced(exercise.card, in: exercise.deck) { learned += 1 }
        store.markIntroduced(exercise.card, in: exercise.deck)
    }

    /// Records the answer for every card the exercise touched. A teaching
    /// step is passed on to `introduce` and counts neither way.
    func grade(_ exercise: Exercise, correct right: Bool, perCard: [String: Bool] = [:]) {
        if exercise.kind == .teach {
            introduce(exercise)
            return
        }
        if exercise.kind == .pairs {
            for card in exercise.pairCards {
                let cardRight = perCard[card.id] ?? right
                store.record(card, in: exercise.deck, correct: cardRight)
                xpEarned += cardRight ? 10 : 1
            }
        } else {
            store.record(exercise.card, in: exercise.deck, correct: right)
            xpEarned += right ? 10 : 1
        }
        if right { correct += 1 } else { wrong += 1 }
    }

    func advance() {
        switch mode {
        case .gate(let needed):
            if correct >= needed {
                finished = true
                return
            }
            if index + 1 >= exercises.count {
                // Wrong answers earn another question, drawn fresh so it is
                // not the same card again straight away. Only taught cards.
                let recent = Set(exercises.suffix(3).map(\.card.id))
                let engine = ExerciseEngine(store: store)
                if let next = engine.one(from: decks, avoiding: recent) ?? engine.one(from: decks) {
                    exercises.append(next)
                } else {
                    finished = true
                    return
                }
            }
            index += 1
        case .lesson, .review:
            if index + 1 >= exercises.count {
                finished = true
            } else {
                index += 1
            }
        }
    }
}

extension QuizSession: Identifiable {}

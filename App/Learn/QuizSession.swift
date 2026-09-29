import Foundation
import Observation

/// One run of questions. A lesson is a fixed number of exercises; the gate
/// keeps asking until enough answers were right, because the point of the
/// gate is to arrive at the app with a slightly different head.
@Observable
final class QuizSession {
    enum Mode: Equatable {
        case gate(required: Int)
        case lesson(count: Int)
    }

    let mode: Mode
    private let store: DeckStore
    private let decks: [Deck]
    private(set) var exercises: [Exercise]
    private(set) var index = 0
    private(set) var correct = 0
    private(set) var wrong = 0
    private(set) var finished = false

    init(mode: Mode, store: DeckStore, decks: [Deck]? = nil) {
        self.mode = mode
        self.store = store
        let source = decks ?? store.activeDecks
        self.decks = source
        let engine = ExerciseEngine(store: store)
        switch mode {
        case .gate(let needed):
            exercises = engine.exercises(count: max(1, needed), from: source)
        case .lesson(let count):
            exercises = engine.exercises(count: count, from: source)
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

    var progress: Double {
        switch mode {
        case .gate(let needed):
            return Double(correct) / Double(max(1, needed))
        case .lesson:
            return Double(index) / Double(max(1, exercises.count))
        }
    }

    var accuracy: Double {
        let total = correct + wrong
        return total == 0 ? 1 : Double(correct) / Double(total)
    }

    /// Records the answer for every card the exercise touched.
    func grade(_ exercise: Exercise, correct right: Bool, perCard: [String: Bool] = [:]) {
        if exercise.kind == .pairs {
            for card in exercise.pairCards {
                store.record(card, in: exercise.deck, correct: perCard[card.id] ?? right)
            }
        } else {
            store.record(exercise.card, in: exercise.deck, correct: right)
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
                // not the same card again straight away.
                let recent = Set(exercises.suffix(3).map(\.card.id))
                if let next = ExerciseEngine(store: store).one(from: decks, avoiding: recent)
                    ?? ExerciseEngine(store: store).one(from: decks) {
                    exercises.append(next)
                } else {
                    finished = true
                    return
                }
            }
            index += 1
        case .lesson:
            if index + 1 >= exercises.count {
                finished = true
            } else {
                index += 1
            }
        }
    }
}

extension QuizSession: Identifiable {}

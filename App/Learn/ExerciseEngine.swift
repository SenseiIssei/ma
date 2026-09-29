import Foundation

enum ExerciseKind: String {
    /// Not a question: the card is shown with its answer and explanation.
    case teach
    case choice, reverse, trueFalse, typeIn, cloze, order, pairs, flash
}

struct Exercise: Identifiable {
    let id = UUID()
    let kind: ExerciseKind
    let deck: Deck
    let card: Card
    var instruction: String
    var prompt: String
    var options: [String] = []
    /// The one right option (choice, reverse, cloze) or the expected text.
    var solution: String = ""
    var statement: String = ""
    var statementIsTrue = true
    var tiles: [String] = []
    var pairCards: [Card] = []
}

/// Turns plain prompt/answer cards into varied exercises. A card is taught
/// before it is ever asked. Freshly taught cards get recognition (pick one,
/// true or false, pairs); cards you keep getting right move on to recall
/// (type it, build it). Same idea as Duolingo, driven by a Leitner box per card.
struct ExerciseEngine {
    let store: DeckStore
    /// Keys (`deck/card`) that count as introduced although the store does
    /// not know it yet: the cards a lesson is about to teach.
    var alsoKnown: Set<String> = []

    /// New cards per lesson. More than three at once and nothing sticks.
    static let newPerLesson = 3

    typealias Pick = (deck: Deck, card: Card)

    // MARK: Plans

    /// A lesson: teach up to three new cards, check each one right away
    /// with an easy exercise, then mix a second look at them with due
    /// reviews. `count` is the number of questions; teaching comes on top.
    func lesson(count: Int, from decks: [Deck], teachNew: Bool = true) -> [Exercise] {
        let slots = max(1, count)
        let fresh: [Pick] = teachNew ? newCards(limit: min(Self.newPerLesson, max(1, slots / 2)), from: decks) : []
        var engine = self

        var plan: [Exercise] = []
        var practised = 0
        var lastKind: [String: ExerciseKind] = [:]

        func practise(_ item: Pick) {
            let key = store.key(item.deck, item.card)
            let exercise = engine.recognition(card: item.card, deck: item.deck, avoiding: lastKind[key])
            lastKind[key] = exercise.kind
            plan.append(exercise)
            practised += 1
        }

        // Teach, then ask straight away while it is fresh. A card joins the
        // known set only once taught, so pairs never show a card too early.
        for item in fresh {
            engine.alsoKnown.insert(store.key(item.deck, item.card))
            plan.append(engine.teach(card: item.card, deck: item.deck))
            if practised < slots { practise(item) }
        }

        let freshKeys = Set(fresh.map { store.key($0.deck, $0.card) })
        let pool = engine.reviewPool(from: decks, excluding: freshKeys)
        var due = pool.due.makeIterator()
        var later = pool.later.makeIterator()
        var second = fresh.makeIterator()
        var third = fresh.makeIterator()

        // Due reviews take turns with a second look at the new cards, then
        // old friends take turns with a third look.
        var turn = 0
        while practised < slots {
            turn += 1
            let reviewFirst = turn % 2 == 1
            if reviewFirst, let next = due.next() {
                plan.append(engine.build(card: next.card, deck: next.deck))
                practised += 1
            } else if let next = second.next() {
                practise(next)
            } else if let next = due.next() {
                plan.append(engine.build(card: next.card, deck: next.deck))
                practised += 1
            } else if reviewFirst, let next = later.next() {
                plan.append(engine.build(card: next.card, deck: next.deck))
                practised += 1
            } else if let next = third.next() {
                practise(next)
            } else if let next = later.next() {
                plan.append(engine.build(card: next.card, deck: next.deck))
                practised += 1
            } else {
                break
            }
        }
        return plan
    }

    /// The gate only asks what has been taught. On the very first unlock
    /// nothing has been, so it teaches one card and then asks about it.
    func gate(required: Int, from decks: [Deck]) -> [Exercise] {
        let asked = exercises(count: max(1, required), from: decks)
        if !asked.isEmpty { return asked }
        guard let first = newCards(limit: 1, from: decks).first else { return [] }
        var engine = self
        engine.alsoKnown.insert(store.key(first.deck, first.card))
        return [
            engine.teach(card: first.card, deck: first.deck),
            engine.recognition(card: first.card, deck: first.deck),
        ]
    }

    /// Review exercises from introduced cards only: due first, weakest box
    /// first, then cards that are not due yet.
    func exercises(count: Int, from decks: [Deck]) -> [Exercise] {
        pickCards(count: count, from: decks).map { build(card: $0.card, deck: $0.deck) }
    }

    func one(from decks: [Deck], avoiding: Set<String> = []) -> Exercise? {
        let picked = pickCards(count: 1, from: decks, avoiding: avoiding)
        return picked.first.map { build(card: $0.card, deck: $0.deck) }
    }

    // MARK: Picking

    /// Cards never taught, in deck order, because bundled decks are sorted
    /// from easy to hard. One deck at a time so a lesson stays on one topic.
    func newCards(limit: Int, from decks: [Deck]) -> [Pick] {
        guard limit > 0 else { return [] }
        let candidates = decks.filter { deck in
            deck.cards.contains { !isKnown($0, in: deck) }
        }
        var result: [Pick] = []
        for deck in candidates.shuffled() {
            for card in deck.cards where !isKnown(card, in: deck) {
                guard result.count < limit else { return result }
                result.append((deck, card))
            }
        }
        return result
    }

    private func pickCards(count: Int, from decks: [Deck], avoiding: Set<String> = []) -> [Pick] {
        let pool = reviewPool(from: decks, avoiding: avoiding)
        return Array((pool.due + pool.later).prefix(max(0, count)))
    }

    private func reviewPool(from decks: [Deck], avoiding: Set<String> = [], excluding keys: Set<String> = []) -> (due: [Pick], later: [Pick]) {
        let now = Date()
        var due: [(pick: Pick, box: Int)] = []
        var later: [Pick] = []
        for deck in decks {
            for card in deck.cards where !avoiding.contains(card.id) {
                guard !keys.contains(store.key(deck, card)) else { continue }
                let p = store.progress(of: card, in: deck)
                guard p.introduced else { continue }
                if p.due <= now {
                    due.append(((deck, card), p.box))
                } else {
                    later.append((deck, card))
                }
            }
        }
        due.shuffle()
        due.sort { $0.box < $1.box }
        return (due.map(\.pick), later.shuffled())
    }

    func isKnown(_ card: Card, in deck: Deck) -> Bool {
        alsoKnown.contains(store.key(deck, card)) || store.progress(of: card, in: deck).introduced
    }

    // MARK: Building

    func teach(card: Card, deck: Deck) -> Exercise {
        make(.teach, card: card, deck: deck)
    }

    /// An easy check right after teaching: pick one, true or false, or
    /// pairs. Tries not to repeat the kind the card had last time.
    func recognition(card: Card, deck: Deck, avoiding previous: ExerciseKind? = nil) -> Exercise {
        let canChoice = !wrongAnswers(for: card, in: deck).isEmpty
        let sentence = card.tokens.count >= 3
        var kinds: [ExerciseKind] = []
        if canChoice { kinds.append(.choice) }
        if canChoice && !sentence { kinds.append(.trueFalse) }
        if canPair(card, in: deck) { kinds.append(.pairs) }
        if kinds.isEmpty { kinds.append(sentence && deck.cards.count >= 2 ? .order : .flash) }
        let varied = kinds.filter { $0 != previous }
        let kind = (varied.isEmpty ? kinds : varied).randomElement() ?? .flash
        return make(kind, card: card, deck: deck)
    }

    func build(card: Card, deck: Deck) -> Exercise {
        let box = store.progress(of: card, in: deck).box
        let kind = chooseKind(card: card, deck: deck, box: box)
        return make(kind, card: card, deck: deck)
    }

    /// Pairs only with cards the learner has been shown.
    private func canPair(_ card: Card, in deck: Deck) -> Bool {
        guard Self.isPairable(card) else { return false }
        let partners = deck.cards.filter {
            $0.id != card.id && Self.isPairable($0) && $0.answer != card.answer && $0.prompt != card.prompt && isKnown($0, in: deck)
        }
        return Set(partners.map(\.answer)).count >= 3
    }

    private func chooseKind(card: Card, deck: Deck, box: Int) -> ExerciseKind {
        let others = deck.cards.filter { $0.id != card.id }
        let wrongPool = wrongAnswers(for: card, in: deck)
        let canChoice = !wrongPool.isEmpty
        let typable = !Self.containsCJK(card.answer) && card.answer.count <= 32
        let sentence = card.tokens.count >= 3
        let hasCloze = card.example.map { $0.contains(card.answer) && $0 != card.answer } ?? false
        let pairable = canPair(card, in: deck)
        let canReverse = card.prompt.count <= 40 && others.count >= 3

        var weights: [(ExerciseKind, Int)] = []
        if sentence && others.count >= 1 {
            weights.append((.order, box == 0 ? 3 : 6))
            if canChoice { weights.append((.choice, 1)) }
        } else {
            switch box {
            case 0:
                if canChoice { weights.append((.choice, 4)) }
                if canChoice { weights.append((.trueFalse, 2)) }
                if pairable { weights.append((.pairs, 2)) }
                if hasCloze && canChoice { weights.append((.cloze, 1)) }
            case 1, 2:
                if canChoice { weights.append((.choice, 2)) }
                if canReverse { weights.append((.reverse, 2)) }
                if hasCloze && canChoice { weights.append((.cloze, 3)) }
                if canChoice { weights.append((.trueFalse, 1)) }
                if pairable { weights.append((.pairs, 1)) }
                if typable { weights.append((.typeIn, 2)) }
            default:
                if typable { weights.append((.typeIn, 5)) }
                if hasCloze && canChoice { weights.append((.cloze, 2)) }
                if canReverse { weights.append((.reverse, 2)) }
                if canChoice { weights.append((.choice, 1)) }
            }
        }
        if weights.isEmpty { return typable ? .typeIn : .flash }

        let total = weights.reduce(0) { $0 + $1.1 }
        var roll = Int.random(in: 0..<total)
        for (kind, weight) in weights {
            if roll < weight { return kind }
            roll -= weight
        }
        return weights[0].0
    }

    private func make(_ kind: ExerciseKind, card: Card, deck: Deck) -> Exercise {
        switch kind {
        case .choice:
            let options = ([card.answer] + Array(wrongAnswers(for: card, in: deck).prefix(3))).shuffled()
            return Exercise(kind: .choice, deck: deck, card: card, instruction: tr("Pick the right answer", "Wähle die richtige Antwort"), prompt: card.prompt, options: options, solution: card.answer)

        case .reverse:
            let wrong = deck.cards
                .filter { $0.id != card.id && $0.prompt != card.prompt }
                .map(\.prompt)
                .uniqued()
                .shuffled()
                .prefix(3)
            let options = ([card.prompt] + wrong).shuffled()
            return Exercise(kind: .reverse, deck: deck, card: card, instruction: tr("What goes with this answer?", "Was gehört zu dieser Antwort?"), prompt: card.answer, options: options, solution: card.prompt)

        case .trueFalse:
            let honest = Bool.random()
            let shown = honest ? card.answer : (wrongAnswers(for: card, in: deck).first ?? card.answer)
            return Exercise(kind: .trueFalse, deck: deck, card: card, instruction: tr("True or not?", "Stimmt das?"), prompt: card.prompt, solution: card.answer, statement: shown, statementIsTrue: shown == card.answer)

        case .typeIn:
            return Exercise(kind: .typeIn, deck: deck, card: card, instruction: tr("Type the answer", "Schreib die Antwort"), prompt: card.prompt, solution: card.answer)

        case .cloze:
            let gap = (card.example ?? "").replacingOccurrences(of: card.answer, with: "＿＿＿")
            let options = ([card.answer] + Array(wrongAnswers(for: card, in: deck).prefix(3))).shuffled()
            return Exercise(kind: .cloze, deck: deck, card: card, instruction: tr("Fill the gap", "Füll die Lücke"), prompt: gap, options: options, solution: card.answer, statement: card.prompt)

        case .order:
            let own = card.tokens
            let foreign = deck.cards
                .filter { $0.id != card.id }
                .flatMap(\.tokens)
                .filter { !own.contains($0) }
                .uniqued()
                .shuffled()
                .prefix(own.count >= 5 ? 3 : 2)
            return Exercise(kind: .order, deck: deck, card: card, instruction: tr("Build the sentence", "Bau den Satz"), prompt: card.prompt, solution: card.answer, tiles: (own + foreign).shuffled())

        case .pairs:
            let partners = deck.cards
                .filter { $0.id != card.id && Self.isPairable($0) && $0.answer != card.answer && $0.prompt != card.prompt && isKnown($0, in: deck) }
                .shuffled()
                .reduce(into: [Card]()) { acc, next in
                    if acc.count < 3, !acc.contains(where: { $0.answer == next.answer || $0.prompt == next.prompt }) {
                        acc.append(next)
                    }
                }
            return Exercise(kind: .pairs, deck: deck, card: card, instruction: tr("Match the pairs", "Finde die Paare"), prompt: "", solution: card.answer, pairCards: ([card] + partners).shuffled())

        case .flash:
            return Exercise(kind: .flash, deck: deck, card: card, instruction: tr("Do you know it?", "Weißt du es?"), prompt: card.prompt, solution: card.answer)

        case .teach:
            return Exercise(kind: .teach, deck: deck, card: card, instruction: tr("New card", "Neue Karte"), prompt: card.prompt, solution: card.answer, statement: card.example ?? "")
        }
    }

    /// Hand-written distractors first, then other cards' answers of a
    /// similar shape, never anything that would also count as right.
    private func wrongAnswers(for card: Card, in deck: Deck) -> [String] {
        let forbidden = Set(([card.answer] + card.accept).map(Grader.normalize))
        let own = card.distractors.filter { !forbidden.contains(Grader.normalize($0)) }
        let sameShape = deck.cards
            .filter { $0.id != card.id }
            .map(\.answer)
            .filter { !forbidden.contains(Grader.normalize($0)) && Self.containsCJK($0) == Self.containsCJK(card.answer) }
            .shuffled()
        return (own.shuffled() + sameShape).uniqued()
    }

    static func isPairable(_ card: Card) -> Bool {
        card.prompt.count <= 22 && card.answer.count <= 22
    }

    static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }
    }
}

extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Grading typed answers

enum Verdict: Equatable {
    case right
    case typo
    case wrong
}

enum Grader {
    static func normalize(_ text: String) -> String {
        var s = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "de_DE"))
        s = s.replacingOccurrences(of: "ß", with: "ss")
        let dropped = CharacterSet.punctuationCharacters.union(.symbols).union(CharacterSet(charactersIn: "`"))
        s = String(s.unicodeScalars.filter { !dropped.contains($0) })
        s = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for article in ["der ", "die ", "das ", "ein ", "eine ", "the ", "a ", "an ", "to "] where s.hasPrefix(article) {
            s.removeFirst(article.count)
            break
        }
        return s
    }

    static func check(_ input: String, against card: Card) -> Verdict {
        let given = normalize(input)
        guard !given.isEmpty else { return .wrong }
        let accepted = ([card.answer] + card.accept).map(normalize)
        if accepted.contains(given) { return .right }
        for target in accepted {
            let allowed = target.count >= 9 ? 2 : (target.count >= 4 ? 1 : 0)
            if allowed > 0 && distance(given, target) <= allowed { return .typo }
        }
        return .wrong
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

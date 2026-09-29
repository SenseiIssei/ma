import Foundation

enum ExerciseKind: String {
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

/// Turns plain prompt/answer cards into varied exercises. New cards get
/// recognition (pick one, true or false, pairs); cards you keep getting
/// right move on to recall (type it, build it). Same idea as Duolingo,
/// driven by a Leitner box per card.
struct ExerciseEngine {
    let store: DeckStore

    func exercises(count: Int, from decks: [Deck]) -> [Exercise] {
        pickCards(count: count, from: decks).map { build(card: $0.card, deck: $0.deck) }
    }

    func one(from decks: [Deck], avoiding: Set<String> = []) -> Exercise? {
        let picked = pickCards(count: 1, from: decks, avoiding: avoiding)
        return picked.first.map { build(card: $0.card, deck: $0.deck) }
    }

    // MARK: Picking

    private func pickCards(count: Int, from decks: [Deck], avoiding: Set<String> = []) -> [(deck: Deck, card: Card)] {
        let now = Date()
        var due: [(deck: Deck, card: Card, box: Int)] = []
        var fresh: [(deck: Deck, card: Card, box: Int)] = []
        var later: [(deck: Deck, card: Card, box: Int)] = []

        for deck in decks {
            for card in deck.cards where !avoiding.contains(card.id) {
                let p = store.progress(of: card, in: deck)
                if p.seen == 0 {
                    fresh.append((deck, card, p.box))
                } else if p.due <= now {
                    due.append((deck, card, p.box))
                } else {
                    later.append((deck, card, p.box))
                }
            }
        }

        due.shuffle()
        due.sort { $0.box < $1.box }
        fresh.shuffle()
        later.shuffle()

        // Mostly review, a steady trickle of new cards, and old friends as filler.
        var result: [(deck: Deck, card: Card)] = []
        var d = due.makeIterator()
        var f = fresh.makeIterator()
        var l = later.makeIterator()
        while result.count < count {
            let wantNew = result.count % 3 == 2
            if wantNew, let next = f.next() {
                result.append((next.deck, next.card))
            } else if let next = d.next() {
                result.append((next.deck, next.card))
            } else if let next = f.next() {
                result.append((next.deck, next.card))
            } else if let next = l.next() {
                result.append((next.deck, next.card))
            } else {
                break
            }
        }
        return result
    }

    // MARK: Building

    func build(card: Card, deck: Deck) -> Exercise {
        let box = store.progress(of: card, in: deck).box
        let kind = chooseKind(card: card, deck: deck, box: box)
        return make(kind, card: card, deck: deck)
    }

    private func chooseKind(card: Card, deck: Deck, box: Int) -> ExerciseKind {
        let others = deck.cards.filter { $0.id != card.id }
        let wrongPool = wrongAnswers(for: card, in: deck)
        let canChoice = !wrongPool.isEmpty
        let typable = !Self.containsCJK(card.answer) && card.answer.count <= 32
        let sentence = card.tokens.count >= 3
        let hasCloze = card.example.map { $0.contains(card.answer) && $0 != card.answer } ?? false
        let pairable = Self.isPairable(card) && deck.cards.filter(Self.isPairable).count >= 4
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
            return Exercise(kind: .choice, deck: deck, card: card, instruction: "Wähle die richtige Antwort", prompt: card.prompt, options: options, solution: card.answer)

        case .reverse:
            let wrong = deck.cards
                .filter { $0.id != card.id && $0.prompt != card.prompt }
                .map(\.prompt)
                .uniqued()
                .shuffled()
                .prefix(3)
            let options = ([card.prompt] + wrong).shuffled()
            return Exercise(kind: .reverse, deck: deck, card: card, instruction: "Was gehört zu dieser Antwort?", prompt: card.answer, options: options, solution: card.prompt)

        case .trueFalse:
            let honest = Bool.random()
            let shown = honest ? card.answer : (wrongAnswers(for: card, in: deck).first ?? card.answer)
            return Exercise(kind: .trueFalse, deck: deck, card: card, instruction: "Stimmt das?", prompt: card.prompt, solution: card.answer, statement: shown, statementIsTrue: shown == card.answer)

        case .typeIn:
            return Exercise(kind: .typeIn, deck: deck, card: card, instruction: "Schreib die Antwort", prompt: card.prompt, solution: card.answer)

        case .cloze:
            let gap = (card.example ?? "").replacingOccurrences(of: card.answer, with: "＿＿＿")
            let options = ([card.answer] + Array(wrongAnswers(for: card, in: deck).prefix(3))).shuffled()
            return Exercise(kind: .cloze, deck: deck, card: card, instruction: "Füll die Lücke", prompt: gap, options: options, solution: card.answer, statement: card.prompt)

        case .order:
            let own = card.tokens
            let foreign = deck.cards
                .filter { $0.id != card.id }
                .flatMap(\.tokens)
                .filter { !own.contains($0) }
                .uniqued()
                .shuffled()
                .prefix(own.count >= 5 ? 3 : 2)
            return Exercise(kind: .order, deck: deck, card: card, instruction: "Bau den Satz", prompt: card.prompt, solution: card.answer, tiles: (own + foreign).shuffled())

        case .pairs:
            let partners = deck.cards
                .filter { $0.id != card.id && Self.isPairable($0) && $0.answer != card.answer }
                .shuffled()
                .reduce(into: [Card]()) { acc, next in
                    if acc.count < 3, !acc.contains(where: { $0.answer == next.answer || $0.prompt == next.prompt }) {
                        acc.append(next)
                    }
                }
            return Exercise(kind: .pairs, deck: deck, card: card, instruction: "Finde die Paare", prompt: "", solution: card.answer, pairCards: ([card] + partners).shuffled())

        case .flash:
            return Exercise(kind: .flash, deck: deck, card: card, instruction: "Weißt du es?", prompt: card.prompt, solution: card.answer)
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

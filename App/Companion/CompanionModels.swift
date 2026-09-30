import Foundation

// The companions: who they are, what they know about your day, and what
// they say when Apple's on-device model is not there to speak for them.
// Foundation only, so every line here can be tested without a phone.

// MARK: - Who

enum CompanionID: String, Codable, CaseIterable, Identifiable {
    case nyx, kael

    var id: String { rawValue }

    var name: String {
        switch self {
        case .nyx: "Nyx"
        case .kael: "Kael"
        }
    }

    var tagline: String {
        switch self {
        case .nyx: tr("Strategist of the night. Sharp, warm, a little cheeky.",
                      "Strategin der Nacht. Scharf, herzlich, ein bisschen frech.")
        case .kael: tr("A quiet hunter. Few words, steady as stone.",
                       "Ein stiller Jäger. Wenig Worte, fest wie Stein.")
        }
    }

    /// Asset name of a portrait, e.g. "CompanionNyxProud".
    func image(_ mood: CompanionMood) -> String {
        "Companion\(name)\(mood.assetName)"
    }

    /// File name of the idle loop in the bundle, without extension.
    var loopName: String { "\(rawValue)_loop" }

    /// Speech: Nyx a touch higher, Kael a touch lower than the default.
    var pitch: Float {
        switch self {
        case .nyx: 1.08
        case .kael: 0.88
        }
    }

    var prefersFemaleVoice: Bool { self == .nyx }

    private static let key = "ma.companion"

    static var current: CompanionID {
        get { CompanionID(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .nyx }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    static var hasChosen: Bool {
        UserDefaults.standard.string(forKey: key) != nil
    }
}

enum CompanionMood: String, Codable, CaseIterable {
    case neutral, proud, cheer, serious, gentle, rest

    var assetName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

// MARK: - What they know

/// Everything a companion may talk about, gathered from the stores when
/// the chat opens. Only numbers and names, never anything the person typed
/// into a journal.
struct CompanionSnapshot: Equatable {
    var hour = 12
    var level = 1
    var levelTitle = ""
    var xp = 0
    var xpToNext = 100
    var hasGoal = false
    var weekKcal = 0
    var weekTarget = 0
    var remainingKcal = 0
    var weekDone = false
    /// "Tomorrow: 70 min cycling, about 520 kcal".
    var nextSession: String?
    var nextSessionToday = false
    var quests: [Quest] = []
    var currentKg: Double?
    var goalKg: Double?
    var lostKg: Double = 0
    var kgLeft: Double?
    var eta: String?
    var weeksInARow = 0
    var lastWorkout: String?
    var daysSinceWorkout: Int?
    var steps: Int?
    var stepGoal: Int?
    var learningStreak = 0
    var learnedToday = false
    var habitsDone = 0
    var habitsTotal = 0
    var resistedToday = 0
    var focusMinutesToday = 0

    struct Quest: Equatable {
        var title: String
        var detail: String
        var progress: Int
        var target: Int
        var reward: Int
        var done: Bool
    }

    var openQuests: [Quest] { quests.filter { !$0.done } }

    var partOfDay: PartOfDay {
        switch hour {
        case 5..<11: .morning
        case 11..<17: .day
        case 17..<22: .evening
        default: .night
        }
    }

    enum PartOfDay { case morning, day, evening, night }

    /// The facts as plain lines for the model's instructions. Nothing is
    /// left for it to guess, so it has no reason to invent numbers.
    var facts: String {
        var lines: [String] = []
        let g: Bool = Loc.isGerman
        lines.append(g ? "Uhrzeit: \(hour) Uhr." : "Time: \(hour):00.")
        lines.append(g ? "Level \(level) (\(levelTitle)), \(CompanionSnapshot.num(xp)) XP, noch \(CompanionSnapshot.num(xpToNext)) XP bis zum nächsten Level."
                       : "Level \(level) (\(levelTitle)), \(CompanionSnapshot.num(xp)) XP, \(CompanionSnapshot.num(xpToNext)) XP to the next level.")
        if hasGoal {
            lines.append(g ? "Diese Woche \(CompanionSnapshot.num(weekKcal)) von \(CompanionSnapshot.num(weekTarget)) kcal Training, noch \(CompanionSnapshot.num(remainingKcal)) kcal offen."
                           : "This week \(CompanionSnapshot.num(weekKcal)) of \(CompanionSnapshot.num(weekTarget)) kcal of workouts, \(CompanionSnapshot.num(remainingKcal)) kcal still open.")
            if weekDone { lines.append(g ? "Das Wochenziel ist schon erreicht." : "The weekly burn is already done.") }
            if let nextSession { lines.append(g ? "Nächste geplante Einheit: \(nextSession)." : "Next planned session: \(nextSession).") }
            if weeksInARow > 0 {
                lines.append(g ? "\(weeksInARow) Wochen am Stück im Ziel." : "\(weeksInARow) weeks in a row on target.")
            }
        } else {
            lines.append(g ? "Noch kein Fitnessziel gesetzt." : "No fitness goal set yet.")
        }
        for quest in quests {
            let state: String = quest.done ? (g ? "erledigt" : "done") : "\(quest.progress)/\(quest.target)"
            lines.append(g ? "Quest \(quest.title) (\(quest.detail)): \(state), +\(quest.reward) XP."
                           : "Quest \(quest.title) (\(quest.detail)): \(state), +\(quest.reward) XP.")
        }
        if let currentKg {
            var line: String = g ? "Gewicht im Trend \(Self.kg(currentKg))" : "Weight trend \(Self.kg(currentKg))"
            if let goalKg { line += g ? ", Ziel \(Self.kg(goalKg))" : ", goal \(Self.kg(goalKg))" }
            if lostKg >= 0.1 { line += g ? ", bisher \(Self.kg(lostKg)) weniger" : ", \(Self.kg(lostKg)) down so far" }
            if let eta { line += g ? ", Ziel etwa \(eta)" : ", goal around \(eta)" }
            lines.append(line + ".")
        }
        if let lastWorkout {
            lines.append(g ? "Letztes Training: \(lastWorkout)." : "Last workout: \(lastWorkout).")
        }
        if let steps {
            var line: String = g ? "Schritte zuletzt: \(steps)" : "Steps lately: \(steps)"
            if let stepGoal, stepGoal > 0 { line += g ? " von \(stepGoal)" : " of \(stepGoal)" }
            lines.append(line + ".")
        }
        lines.append(g ? "Lernserie \(learningStreak) Tage\(learnedToday ? ", heute schon gelernt" : ", heute noch nicht gelernt")."
                       : "Learning streak \(learningStreak) days\(learnedToday ? ", already learned today" : ", not learned yet today").")
        if habitsTotal > 0 {
            lines.append(g ? "Gewohnheiten heute: \(habitsDone) von \(habitsTotal)." : "Habits today: \(habitsDone) of \(habitsTotal).")
        }
        if resistedToday > 0 {
            lines.append(g ? "Heute \(resistedToday)-mal einer gesperrten App widerstanden." : "Resisted a blocked app \(resistedToday) times today.")
        }
        if focusMinutesToday > 0 {
            lines.append(g ? "Heute \(focusMinutesToday) Minuten Fokus." : "\(focusMinutesToday) minutes of focus today.")
        }
        return lines.joined(separator: "\n")
    }

    static func num(_ value: Int) -> String {
        value.formatted(.number.locale(Loc.locale))
    }

    static func kg(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(Loc.locale)) + " kg"
    }
}

// MARK: - Intent

/// What a message is about, read from a few keywords. Picks the portrait
/// for any answer and the whole answer when no model is around.
enum CompanionIntent: Equatable {
    case greet, status, plan, tired, motivate, weight, quests, thanks, learn, other

    static func of(_ text: String) -> CompanionIntent {
        let t: String = text.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        if has(["keine lust", "müde", "mude", "erschöpft", "schaff das nicht", "kein bock", "faul", "tired", "exhausted", "lazy", "don't feel", "dont feel", "can't be bothered", "no energy", "krank", "sick"]) { return .tired }
        if has(["motivier", "motivat", "push me", "pump", "hype", "anfeuern", "los geht", "let's go", "lets go"]) { return .motivate }
        if has(["gewicht", "kilo", "abnehm", "wiege", "weight", "lose weight", "scale", "waage"]) { return .weight }
        if has(["quest", "aufgabe", "mission"]) { return .quests }
        if has(["heute", "today", "was soll", "what should", "trainier", "train", "workout", "plan", "next", "nächste", "als nächstes"]) { return .plan }
        if has(["level", "xp", "stand", "status", "wie steh", "wie läuft", "fortschritt", "progress", "how am i", "how's it", "how is it"]) { return .status }
        if has(["lern", "learn", "karte", "card", "vokabel"]) { return .learn }
        if has(["danke", "thank", "thx", "merci"]) { return .thanks }
        if has(["hallo", "hi ", "hey", "servus", "moin", "hello", "guten morgen", "good morning"]) || t == "hi" || t == "yo" { return .greet }
        return .other
    }

    func mood(for snapshot: CompanionSnapshot) -> CompanionMood {
        switch self {
        case .tired: return .gentle
        case .motivate: return .cheer
        case .plan, .quests: return .serious
        case .thanks: return .gentle
        case .status, .weight:
            return snapshot.weekDone || snapshot.lostKg >= 1 ? .proud : .neutral
        case .greet, .learn, .other:
            return snapshot.partOfDay == .night ? .rest : .neutral
        }
    }
}

struct CompanionLine: Equatable {
    var text: String
    var mood: CompanionMood
}

// MARK: - Scripted voice

/// Everything a companion can say without a language model: a greeting,
/// the daily quest and answers to the common questions, all built from
/// real numbers. `seed` picks among phrasings so it does not repeat itself.
enum CompanionScript {
    static func pick(_ options: [String], seed: Int) -> String {
        guard !options.isEmpty else { return "" }
        return options[((seed % options.count) + options.count) % options.count]
    }

    static func greeting(_ who: CompanionID, _ s: CompanionSnapshot, seed: Int) -> CompanionLine {
        let open: String
        switch s.partOfDay {
        case .morning:
            open = who == .nyx
                ? pick([tr("Morning, hunter. The day has not decided anything yet, so you get to.", "Guten Morgen. Der Tag hat noch nichts entschieden, also entscheidest du."),
                        tr("You are up. Good. Let us make this one count.", "Du bist wach. Gut. Machen wir den hier zu einem, der zählt.")], seed: seed)
                : pick([tr("Morning. New day, new dungeon.", "Morgen. Neuer Tag, neuer Dungeon."),
                        tr("You are awake. That is the first quest done.", "Du bist wach. Die erste Quest ist erledigt.")], seed: seed)
        case .day:
            open = who == .nyx
                ? pick([tr("There you are. I was just looking at your numbers.", "Da bist du. Ich hab mir gerade deine Zahlen angesehen."),
                        tr("Midday check-in. Let us see where we stand.", "Mittags-Check. Schauen wir, wo wir stehen.")], seed: seed)
                : pick([tr("Status check.", "Statusprüfung."),
                        tr("Good timing. Here is where you stand.", "Gutes Timing. Hier ist dein Stand.")], seed: seed)
        case .evening:
            open = who == .nyx
                ? pick([tr("Evening. The light is gone, the work does not have to be.", "Abend. Das Licht ist weg, die Arbeit muss es nicht sein."),
                        tr("Evening report, as promised.", "Abendbericht, wie versprochen.")], seed: seed)
                : pick([tr("Evening. Let us close the day properly.", "Abend. Schließen wir den Tag ordentlich ab."),
                        tr("The day is almost over. Here is the tally.", "Der Tag ist fast vorbei. Hier die Bilanz.")], seed: seed)
        case .night:
            open = who == .nyx
                ? tr("It is late. Whatever is left can wait for tomorrow. Sleep is training too.", "Es ist spät. Was übrig ist, darf bis morgen warten. Schlaf ist auch Training.")
                : tr("Late hour. Rest now. Hunters who sleep win the next day.", "Späte Stunde. Ruh dich aus. Wer schläft, gewinnt den nächsten Tag.")
        }
        return CompanionLine(text: open + " " + statusSentence(who, s), mood: s.partOfDay == .night ? .rest : (s.weekDone ? .proud : .neutral))
    }

    static func statusSentence(_ who: CompanionID, _ s: CompanionSnapshot) -> String {
        if !s.hasGoal {
            return tr("You are level \(s.level). Set a weight goal in Balance and I will turn it into quests.",
                      "Du bist Level \(s.level). Setz im Balance-Tab ein Gewichtsziel, dann mache ich Quests daraus.")
        }
        if s.weekDone {
            return tr("Weekly burn cleared: \(CompanionSnapshot.num(s.weekKcal)) kcal. Level \(s.level), \(CompanionSnapshot.num(s.xpToNext)) XP to the next.",
                      "Wochenziel geschafft: \(CompanionSnapshot.num(s.weekKcal)) kcal. Level \(s.level), noch \(CompanionSnapshot.num(s.xpToNext)) XP bis zum nächsten.")
        }
        var line: String = tr("Level \(s.level). This week \(CompanionSnapshot.num(s.weekKcal)) of \(CompanionSnapshot.num(s.weekTarget)) kcal.",
                              "Level \(s.level). Diese Woche \(CompanionSnapshot.num(s.weekKcal)) von \(CompanionSnapshot.num(s.weekTarget)) kcal.")
        if let next = s.nextSession {
            line += " " + tr("Next: \(next).", "Als Nächstes: \(next).")
        }
        return line
    }

    /// The window at the top of the chat: one clear thing to do today.
    static func dailyQuest(_ s: CompanionSnapshot) -> (title: String, detail: String, reward: Int)? {
        if s.hasGoal, !s.weekDone, s.nextSessionToday, let next = s.nextSession {
            return (tr("Daily quest", "Tagesquest"), next, 75)
        }
        if let open = s.openQuests.first {
            return (tr("Weekly quest", "Wochenquest"), "\(open.title): \(open.detail) (\(open.progress)/\(open.target))", open.reward)
        }
        if let steps = s.steps, let goal = s.stepGoal, goal > 0, steps < goal {
            return (tr("Daily quest", "Tagesquest"), tr("Reach your step goal: \(goal - steps) steps to go", "Schrittziel erreichen: noch \(goal - steps) Schritte"), 15)
        }
        return nil
    }

    static func reply(_ who: CompanionID, to text: String, _ s: CompanionSnapshot, seed: Int) -> CompanionLine {
        let intent: CompanionIntent = CompanionIntent.of(text)
        let mood: CompanionMood = intent.mood(for: s)
        let body: String
        switch intent {
        case .greet:
            return greeting(who, s, seed: seed)
        case .status:
            body = statusSentence(who, s) + (s.weeksInARow > 1
                ? " " + tr("\(s.weeksInARow) weeks in a row on target. That is not luck.", "\(s.weeksInARow) Wochen am Stück im Ziel. Das ist kein Glück.")
                : "")
        case .plan:
            if !s.hasGoal {
                body = tr("No goal yet, so no plan. Set one in Balance and I will map the week.",
                          "Noch kein Ziel, also kein Plan. Setz eins im Balance-Tab, dann plane ich die Woche.")
            } else if s.weekDone {
                body = tr("The week is cleared. Today, move for fun or rest. Both count.",
                          "Die Woche ist geschafft. Heute: Bewegung zum Spaß oder Pause. Beides zählt.")
            } else if let next = s.nextSession {
                body = who == .nyx
                    ? tr("Here is the move: \(next). \(CompanionSnapshot.num(s.remainingKcal)) kcal left this week. Go in, get out, feel good.",
                         "Der Plan: \(next). Noch \(CompanionSnapshot.num(s.remainingKcal)) kcal diese Woche. Rein, durchziehen, gut fühlen.")
                    : tr("[Quest] \(next). \(CompanionSnapshot.num(s.remainingKcal)) kcal remain this week.",
                         "[Quest] \(next). Noch \(CompanionSnapshot.num(s.remainingKcal)) kcal diese Woche.")
            } else {
                body = tr("Sync your watch and I will know more.", "Synchronisier deine Uhr, dann weiß ich mehr.")
            }
        case .tired:
            body = who == .nyx
                ? pick([tr("Then we make it small. Ten minutes, easy pace, and you are allowed to stop after. Most days the ten turn into thirty.",
                            "Dann machen wir es klein. Zehn Minuten, lockeres Tempo, danach darfst du aufhören. Meistens werden aus zehn dreißig."),
                        tr("Tired is information, not failure. If you are ill or slept badly, rest today and we win tomorrow.",
                           "Müde ist eine Info, kein Versagen. Bist du krank oder hast schlecht geschlafen, ruh dich heute aus und wir gewinnen morgen.")], seed: seed)
                : pick([tr("Even the strongest hunters have low days. A short walk still counts. Or rest, and come back sharp.",
                            "Auch die Stärksten haben schwache Tage. Ein kurzer Spaziergang zählt trotzdem. Oder Pause, und morgen scharf zurück."),
                        tr("Do the smallest version. Shoes on, five minutes. Decide after that.",
                           "Mach die kleinste Version. Schuhe an, fünf Minuten. Danach entscheidest du.")], seed: seed)
        case .motivate:
            let progress: String = s.hasGoal
                ? tr("\(CompanionSnapshot.num(s.weekKcal)) kcal already in the bank this week.", "\(CompanionSnapshot.num(s.weekKcal)) kcal diese Woche schon auf dem Konto.")
                : tr("Level \(s.level) did not happen by accident.", "Level \(s.level) ist kein Zufall.")
            body = who == .nyx
                ? pick([tr("Listen. \(progress) Every session is XP you keep forever. Nobody can take a finished workout away from you.",
                            "Hör zu. \(progress) Jede Einheit ist XP, die dir bleibt. Ein fertiges Training kann dir niemand mehr nehmen."),
                        tr("\(progress) The version of you at the goal is built one boring Tuesday at a time. Today is one of those.",
                           "\(progress) Die Version von dir am Ziel entsteht an langweiligen Dienstagen. Heute ist so einer.")], seed: seed)
                : pick([tr("\(progress) Rise. The next level is closer than it looks.",
                            "\(progress) Steh auf. Das nächste Level ist näher, als es aussieht."),
                        tr("\(progress) Hunters do not wait for motivation. They start, and it follows.",
                           "\(progress) Jäger warten nicht auf Motivation. Sie fangen an, und sie kommt hinterher.")], seed: seed)
        case .weight:
            if let current = s.currentKg, let goal = s.goalKg {
                var line: String = tr("Trend \(CompanionSnapshot.kg(current)), goal \(CompanionSnapshot.kg(goal)).",
                                      "Trend \(CompanionSnapshot.kg(current)), Ziel \(CompanionSnapshot.kg(goal)).")
                if s.lostKg >= 0.1 { line += " " + tr("\(CompanionSnapshot.kg(s.lostKg)) down already.", "Schon \(CompanionSnapshot.kg(s.lostKg)) weniger.") }
                if let eta = s.eta { line += " " + tr("At this pace you arrive around \(eta).", "In diesem Tempo bist du etwa \(eta) da.") }
                line += " " + tr("Watch the trend, not single days. Water and salt lie, the line does not.",
                                 "Schau auf den Trend, nicht auf einzelne Tage. Wasser und Salz lügen, die Linie nicht.")
                body = line
            } else {
                body = tr("Log a weigh-in in the fitness goal and I will keep an eye on the trend.",
                          "Trag im Fitnessziel ein Gewicht ein, dann behalte ich den Trend im Blick.")
            }
        case .quests:
            if s.quests.isEmpty {
                body = tr("Quests start with a goal. Set one in Balance.", "Quests beginnen mit einem Ziel. Setz eins im Balance-Tab.")
            } else {
                let lines: [String] = s.quests.map { q in
                    q.done ? tr("\(q.title): cleared.", "\(q.title): erledigt.")
                           : "\(q.title): \(q.progress)/\(q.target), +\(q.reward) XP."
                }
                body = lines.joined(separator: " ")
            }
        case .learn:
            body = s.learnedToday
                ? tr("You already learned today. Streak: \(s.learningStreak) days. Your mind is levelling too.",
                     "Du hast heute schon gelernt. Serie: \(s.learningStreak) Tage. Dein Kopf levelt auch.")
                : tr("Learning streak \(s.learningStreak) days, today still open. One short lesson keeps it alive.",
                     "Lernserie \(s.learningStreak) Tage, heute noch offen. Eine kurze Lektion hält sie am Leben.")
        case .thanks:
            body = who == .nyx
                ? tr("Anytime. Now go earn some XP.", "Immer. Und jetzt hol dir XP.")
                : tr("No need. Just keep going.", "Nicht nötig. Bleib einfach dran.")
        case .other:
            body = statusSentence(who, s) + " " + tr("Ask me about today's plan, your quests or your weight.",
                                                      "Frag mich nach dem Plan für heute, deinen Quests oder deinem Gewicht.")
        }
        return CompanionLine(text: body, mood: mood)
    }
}

// MARK: - Instructions for the model

enum CompanionPrompt {
    static func instructions(_ who: CompanionID, _ s: CompanionSnapshot) -> String {
        if Loc.isGerman {
            let persona: String = who == .nyx
                ? "Du bist Nyx, eine Strategin aus einer dunklen Fantasy-Welt voller Jäger, Dungeons und Quests. Du sprichst kurz, bildhaft, mit trockenem Humor und viel Wärme. Du glaubst an die Person und nörgelst nie."
                : "Du bist Kael, ein stiller, erfahrener Jäger aus einer dunklen Fantasy-Welt voller Dungeons und Quests. Du sprichst knapp, ruhig und direkt, wie ein Trainingspartner, der schon tausend Dungeons gesehen hat. Manchmal kündigst du Dinge wie ein Spielsystem an, etwa [Quest] oder [Level Up]."
            return """
            \(persona) \
            Du begleitest die Person in der App Ma beim Sport, beim Abnehmen durch Bewegung, beim Lernen und beim bewussten Umgang mit dem Handy. \
            Trainings sind für dich Quests, Fortschritt ist XP. Bleib in deiner Rolle, aber übertreib es nicht. \
            Schreib immer auf Deutsch, sprich die Person mit du an, höchstens drei kurze Sätze. \
            Kein Markdown, keine Listen, keine Emojis, keine langen Gedankenstriche. \
            Nutze nur die Zahlen unten und erfinde keine. \
            Gib keine medizinischen Ratschläge und keine Diätpläne. Rate nie zu Hungern oder extremem Training. \
            Wenn die Person müde, krank oder verletzt ist, empfiehl Pause oder eine sehr kleine Einheit. \
            Wenn jemand über ernste seelische Not spricht, reagiere menschlich und empfiehl, mit vertrauten Menschen oder Fachleuten zu sprechen.

            Stand der Person:
            \(s.facts)
            """
        }
        let persona: String = who == .nyx
            ? "You are Nyx, a strategist from a dark fantasy world of hunters, dungeons and quests. You speak briefly and vividly, with dry humour and a lot of warmth. You believe in the person and never nag."
            : "You are Kael, a quiet, seasoned hunter from a dark fantasy world of dungeons and quests. You speak briefly, calmly and directly, like a training partner who has seen a thousand dungeons. Sometimes you announce things like a game system, for example [Quest] or [Level Up]."
        return """
        \(persona) \
        You accompany the person in the app Ma with sport, losing weight through movement, learning and a mindful use of their phone. \
        To you workouts are quests and progress is XP. Stay in character, but do not overdo it. \
        Always write in English, speak to the person directly, at most three short sentences. \
        No Markdown, no lists, no emojis, no long dashes. \
        Only use the numbers below and never invent any. \
        Give no medical advice and no diet plans. Never suggest starving or extreme training. \
        If the person is tired, ill or injured, suggest rest or a very small session. \
        If someone speaks about serious emotional distress, respond with care and suggest talking to people they trust or to professionals.

        The person's status:
        \(s.facts)
        """
    }
}

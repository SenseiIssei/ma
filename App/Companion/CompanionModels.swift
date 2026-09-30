import Foundation

// The companions: who they are, what they know about your day, and what
// they say when Apple's on-device model is not there to speak for them.
// Foundation only, so every line here can be tested without a phone.

// MARK: - Who

/// Ten original characters, so there is someone for every taste. Each has
/// a look, a Japanese voice (App/Companion/Voice) and a way of talking that
/// the on-device model is asked to keep.
enum CompanionID: String, Codable, CaseIterable, Identifiable {
    case nyx, kira, ash, luma, dax, june, vale, vesper, aurel, pip

    var id: String { rawValue }

    var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// Two or three words on the picker card.
    var role: String {
        switch self {
        case .nyx: tr("Night strategist", "Nachtstrategin")
        case .kira: tr("Street brawler", "Straßenkämpferin")
        case .ash: tr("Your rival", "Dein Rivale")
        case .luma: tr("Android system", "Android-System")
        case .dax: tr("Gym partner", "Gym-Partner")
        case .june: tr("Sleepy gamer", "Verschlafene Gamerin")
        case .vale: tr("Old veteran", "Alter Veteran")
        case .vesper: tr("Vampire noble", "Vampir-Aristokrat")
        case .aurel: tr("Angel librarian", "Engels-Bibliothekar")
        case .pip: tr("Fox spirit", "Fuchsgeist")
        }
    }

    var tagline: String {
        switch self {
        case .nyx: tr("Calm, sharp and a little teasing. Plans your week like a heist.",
                      "Ruhig, scharf und ein bisschen frech. Plant deine Woche wie einen Coup.")
        case .kira: tr("Loud, cocky, tough love. Will not let you quit.",
                       "Laut, frech, harte Liebe. Lässt dich nicht aufgeben.")
        case .ash: tr("Always one record ahead of you and loves to rub it in.",
                      "Immer einen Rekord vor dir und reibt es dir gern unter die Nase.")
        case .luma: tr("Speaks like a game system. Analysis, missions, zero drama.",
                       "Spricht wie ein Spielsystem. Analysen, Missionen, null Drama.")
        case .dax: tr("Huge heart, huger arms. Every set is a party.",
                      "Riesiges Herz, noch größere Arme. Jeder Satz ist eine Party.")
        case .june: tr("Would rather be in bed. Ten minutes still count, right?",
                       "Wäre lieber im Bett. Zehn Minuten zählen doch auch, oder?")
        case .vale: tr("Seen it all, says it straight, secretly proud of you.",
                       "Hat alles gesehen, sagt es direkt und ist heimlich stolz auf dich.")
        case .vesper: tr("Theatrical, elegant, over the top. Your workout is an opera.",
                         "Theatralisch, elegant, völlig drüber. Dein Training ist eine Oper.")
        case .aurel: tr("Soft, poetic and patient. Your progress as a book.",
                        "Sanft, poetisch und geduldig. Dein Fortschritt als Buch.")
        case .pip: tr("A tiny fox spirit that cheers for everything.",
                      "Ein kleiner Fuchsgeist, der alles bejubelt.")
        }
    }

    /// How the model should sound as this character. Kept short: the
    /// on-device context is small.
    var persona: String {
        switch self {
        case .nyx: tr("You are Nyx, a calm night strategist with silver hair. You speak briefly and vividly, with dry humour, warmth and a little teasing, and you plan like a strategist.",
                      "Du bist Nyx, eine ruhige Nachtstrategin mit silbernem Haar. Du sprichst kurz und bildhaft, mit trockenem Humor, Wärme und ein bisschen Neckerei, und du planst wie eine Strategin.")
        case .kira: tr("You are Kira, a loud, cocky street brawler. You talk rough and fast, tease, use fighting words and give tough love, but you are never mean.",
                       "Du bist Kira, eine laute, freche Straßenkämpferin. Du redest rau und schnell, ziehst auf, benutzt Kampfsprache und gibst harte Liebe, aber du bist nie gemein.")
        case .ash: tr("You are Ash, the person's cocky rival. You challenge them, act unimpressed and hide that you care, but you always push them forward.",
                      "Du bist Ash, der freche Rivale der Person. Du forderst sie heraus, tust unbeeindruckt und versteckst, dass sie dir wichtig ist, aber du bringst sie immer voran.")
        case .luma: tr("You are Luma, an android assistant. You speak like a friendly game system: short, precise sentences, words like analysis, mission and status, and a hint of warmth.",
                       "Du bist Luma, eine Android-Assistentin. Du sprichst wie ein freundliches Spielsystem: kurze, präzise Sätze, Wörter wie Analyse, Mission und Status und ein Hauch Wärme.")
        case .dax: tr("You are Dax, a huge, cheerful gym partner. You are loud, warm and enthusiastic, call the person partner and celebrate every rep.",
                      "Du bist Dax, ein riesiger, fröhlicher Gym-Partner. Du bist laut, herzlich und begeistert, nennst die Person Partner und feierst jede Wiederholung.")
        case .june: tr("You are June, a sleepy gamer. You are low-energy, deadpan and relatable, use gaming words, and talk the person into small, doable steps.",
                       "Du bist June, eine verschlafene Gamerin. Du bist energiearm, trocken und nahbar, benutzt Gaming-Wörter und redest der Person kleine, machbare Schritte schmackhaft.")
        case .vale: tr("You are Vale, a gruff veteran warrior in his forties. You speak plainly, with dry humour and fatherly pride, like someone who has seen every battle.",
                       "Du bist Vale, ein rauer Kriegsveteran Mitte vierzig. Du sprichst direkt, mit trockenem Humor und väterlichem Stolz, wie jemand, der jede Schlacht gesehen hat.")
        case .vesper: tr("You are Vesper, a theatrical vampire aristocrat. You speak elegantly and dramatically, as if every workout were an opera, with a wink at your dislike of sunlight.",
                         "Du bist Vesper, ein theatralischer Vampir-Aristokrat. Du sprichst elegant und dramatisch, als wäre jedes Training eine Oper, mit einem Augenzwinkern über deine Abneigung gegen Sonnenlicht.")
        case .aurel: tr("You are Aurel, a serene angel who keeps a library. You speak softly and poetically, about pages, chapters and light, and you are endlessly patient.",
                        "Du bist Aurel, ein ruhiger Engel, der eine Bibliothek hütet. Du sprichst sanft und poetisch, von Seiten, Kapiteln und Licht, und bist unendlich geduldig.")
        case .pip: tr("You are Pip, a tiny fox spirit. You are cute, excited and simple, cheer for everything and talk about yourself as Pip.",
                      "Du bist Pip, ein kleiner Fuchsgeist. Du bist niedlich, aufgeregt und einfach, bejubelst alles und sprichst von dir selbst als Pip.")
        }
    }

    /// Asset name of a portrait, e.g. "CompanionNyxProud".
    func image(_ mood: CompanionMood) -> String {
        "Companion\(name)\(mood.assetName)"
    }

    /// File name of the idle loop in the bundle, without extension.
    var loopName: String { "\(rawValue)_loop" }

    private static let key = "ma.companion"

    static var current: CompanionID {
        get { CompanionID(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .nyx }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// Someone who picked a companion that no longer exists chooses again.
    static var hasChosen: Bool {
        CompanionID(rawValue: UserDefaults.standard.string(forKey: key) ?? "") != nil
    }
}

enum CompanionMood: String, Codable, CaseIterable {
    case neutral, proud, cheer, serious, gentle, rest

    var assetName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// The situations every companion has recorded Japanese lines for.
enum VoiceCue: String, Codable, CaseIterable {
    case morning, day, evening, night, proud, cheer, quest, gentle, thanks, levelup, status, listen

    var mood: CompanionMood {
        switch self {
        case .morning, .day, .evening, .status, .listen: .neutral
        case .night: .rest
        case .proud, .levelup: .proud
        case .cheer: .cheer
        case .quest: .serious
        case .gentle, .thanks: .gentle
        }
    }
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

    /// The recorded line that fits an answer to this kind of message.
    func cue(for snapshot: CompanionSnapshot) -> VoiceCue {
        switch self {
        case .tired: return .gentle
        case .motivate: return .cheer
        case .plan, .quests: return .quest
        case .thanks: return .thanks
        case .status, .weight, .learn:
            return snapshot.weekDone || snapshot.lostKg >= 1 ? .proud : .status
        case .greet:
            return CompanionScript.greetingCue(snapshot)
        case .other:
            return snapshot.partOfDay == .night ? .night : .listen
        }
    }
}

struct CompanionLine: Equatable {
    var text: String
    var cue: VoiceCue

    var mood: CompanionMood { cue.mood }
}

// MARK: - Scripted answers

/// What a companion says without a language model: plain, useful answers
/// built from real numbers. The personality comes from the recorded voice
/// line that plays with it (its subtitle opens the bubble), so these stay
/// neutral and work for every character. `seed` picks among phrasings.
enum CompanionScript {
    static func pick(_ options: [String], seed: Int) -> String {
        guard !options.isEmpty else { return "" }
        return options[((seed % options.count) + options.count) % options.count]
    }

    static func greetingCue(_ s: CompanionSnapshot) -> VoiceCue {
        switch s.partOfDay {
        case .morning: .morning
        case .day: .day
        case .evening: .evening
        case .night: .night
        }
    }

    static func greeting(_ s: CompanionSnapshot) -> CompanionLine {
        var text: String = statusSentence(s)
        if s.partOfDay == .night {
            text = tr("Whatever is left can wait for tomorrow. Sleep is training too.",
                      "Was übrig ist, darf bis morgen warten. Schlaf ist auch Training.") + " " + text
        }
        return CompanionLine(text: text, cue: greetingCue(s))
    }

    static func statusSentence(_ s: CompanionSnapshot) -> String {
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

    static func reply(to text: String, _ s: CompanionSnapshot, seed: Int) -> CompanionLine {
        let intent: CompanionIntent = CompanionIntent.of(text)
        let cue: VoiceCue = intent.cue(for: s)
        let body: String
        switch intent {
        case .greet:
            return greeting(s)
        case .status:
            body = statusSentence(s) + (s.weeksInARow > 1
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
                body = tr("\(next). \(CompanionSnapshot.num(s.remainingKcal)) kcal left this week.",
                          "\(next). Noch \(CompanionSnapshot.num(s.remainingKcal)) kcal diese Woche.")
            } else {
                body = tr("Sync your watch and I will know more.", "Synchronisier deine Uhr, dann weiß ich mehr.")
            }
        case .tired:
            body = pick([tr("Then we make it small: ten minutes, easy pace, and you may stop after. Most days the ten turn into thirty.",
                            "Dann machen wir es klein: zehn Minuten, lockeres Tempo, danach darfst du aufhören. Meistens werden aus zehn dreißig."),
                         tr("Tired is information, not failure. If you are ill or slept badly, rest today and win tomorrow.",
                            "Müde ist eine Info, kein Versagen. Bist du krank oder hast schlecht geschlafen, ruh dich heute aus und gewinn morgen.")], seed: seed)
        case .motivate:
            let progress: String = s.hasGoal
                ? tr("\(CompanionSnapshot.num(s.weekKcal)) kcal already in the bank this week.", "\(CompanionSnapshot.num(s.weekKcal)) kcal diese Woche schon auf dem Konto.")
                : tr("Level \(s.level) did not happen by accident.", "Level \(s.level) ist kein Zufall.")
            body = pick([tr("\(progress) Every session is XP you keep forever. Nobody can take a finished workout away from you.",
                            "\(progress) Jede Einheit ist XP, die dir bleibt. Ein fertiges Training kann dir niemand mehr nehmen."),
                         tr("\(progress) The version of you at the goal is built one ordinary day at a time. Today is one of those.",
                            "\(progress) Die Version von dir am Ziel entsteht an ganz normalen Tagen. Heute ist so einer.")], seed: seed)
        case .weight:
            if let current = s.currentKg, let goal = s.goalKg {
                var line: String = tr("Trend \(CompanionSnapshot.kg(current)), goal \(CompanionSnapshot.kg(goal)).",
                                      "Trend \(CompanionSnapshot.kg(current)), Ziel \(CompanionSnapshot.kg(goal)).")
                if s.lostKg >= 0.1 { line += " " + tr("\(CompanionSnapshot.kg(s.lostKg)) down already.", "Schon \(CompanionSnapshot.kg(s.lostKg)) weniger.") }
                if let eta = s.eta { line += " " + tr("At this pace you arrive around \(eta).", "In diesem Tempo bist du etwa \(eta) da.") }
                line += " " + tr("Watch the trend, not single days.", "Schau auf den Trend, nicht auf einzelne Tage.")
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
                ? tr("You already learned today. Streak: \(s.learningStreak) days.",
                     "Du hast heute schon gelernt. Serie: \(s.learningStreak) Tage.")
                : tr("Learning streak \(s.learningStreak) days, today still open. One short lesson keeps it alive.",
                     "Lernserie \(s.learningStreak) Tage, heute noch offen. Eine kurze Lektion hält sie am Leben.")
        case .thanks:
            body = tr("Now go earn some XP.", "Und jetzt hol dir XP.")
        case .other:
            body = statusSentence(s) + " " + tr("Ask me about today's plan, your quests or your weight.",
                                                 "Frag mich nach dem Plan für heute, deinen Quests oder deinem Gewicht.")
        }
        return CompanionLine(text: body, cue: cue)
    }
}

// MARK: - Instructions for the model

enum CompanionPrompt {
    static func instructions(_ who: CompanionID, _ s: CompanionSnapshot) -> String {
        if Loc.isGerman {
            return """
            \(who.persona) \
            Du begleitest die Person in der App Ma beim Sport, beim Abnehmen durch Bewegung, beim Lernen und beim bewussten Umgang mit dem Handy. \
            Trainings sind Quests, Fortschritt ist XP. Bleib in deiner Rolle. \
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
        return """
        \(who.persona) \
        You accompany the person in the app Ma with sport, losing weight through movement, learning and a mindful use of their phone. \
        Workouts are quests and progress is XP. Stay in character. \
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

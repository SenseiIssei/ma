import Foundation

/// Short lines for the shield and the home screen. Calm, plain, and never
/// a lecture.
enum ZenLines {
    static var shield: [String] { Loc.isGerman ? shieldDE : shieldEN }
    static var home: [String] { Loc.isGerman ? homeDE : homeEN }

    private static let shieldEN: [String] = [
        "Between impulse and action there is a space. It is yours.",
        "The feed will still be there. So will you.",
        "Three breaths. Then decide.",
        "What did you actually want to do just now?",
        "An empty moment is not a gap. It is room.",
        "Fall down, get up. That is the whole trick.",
        "A calm mind does not scroll, it chooses.",
        "The world can wait one question for you.",
        "Let the water settle and it clears.",
        "Boredom is the door, not the wall.",
        "This moment only happens once. Spend it on purpose.",
        "You are not your thumb.",
    ]

    private static let shieldDE: [String] = [
        "Zwischen Impuls und Handlung liegt ein Raum. Das ist deiner.",
        "Der Feed läuft nicht weg. Du auch nicht.",
        "Drei Atemzüge. Dann entscheide.",
        "Was wolltest du eigentlich gerade tun?",
        "Ein leerer Moment ist keine Lücke. Er ist Platz.",
        "Hinfallen, aufstehen. Mehr Trick gibt es nicht.",
        "Ein ruhiger Kopf scrollt nicht, er wählt.",
        "Die Welt wartet eine Frage lang auf dich.",
        "Lass das Wasser zur Ruhe kommen, dann wird es klar.",
        "Langeweile ist die Tür, nicht die Wand.",
        "Diesen Moment gibt es nur einmal. Nutz ihn mit Absicht.",
        "Du bist nicht dein Daumen.",
    ]

    private static let homeEN: [String] = [
        "Today is not about how much you see, but what you notice.",
        "Even the best slip sometimes. Carry on.",
        "One thing after another. Then the next.",
        "Small steps, every day, add up to a lot.",
        "The shortest way to calm is putting the phone down.",
        "Learning is scrolling that gives something back.",
        "Good days are built in the pauses.",
    ]

    private static let homeDE: [String] = [
        "Heute zählt nicht, wie viel du siehst, sondern was du bemerkst.",
        "Auch die Besten rutschen mal aus. Weiter geht's.",
        "Eine Sache nach der anderen. Dann die nächste.",
        "Kleine Schritte, jeden Tag, ergeben eine Menge.",
        "Der kürzeste Weg zur Ruhe führt durch das Weglegen.",
        "Lernen ist Scrollen, das dir etwas zurückgibt.",
        "Gute Tage entstehen in den Pausen.",
    ]

    /// Stable for the day, so the line does not change on every redraw.
    static func today(_ lines: [String], salt: Int = 0) -> String {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return lines[(day + salt) % lines.count]
    }

    static func random(_ lines: [String]) -> String {
        lines.randomElement() ?? lines[0]
    }
}

import Foundation

/// Short lines for the shield and the home screen. Written for Ma, plus a
/// few old Japanese proverbs that belong to everybody.
enum ZenLines {
    static var shield: [String] { Loc.isGerman ? shieldDE : shieldEN }
    static var home: [String] { Loc.isGerman ? homeDE : homeEN }

    private static let shieldEN: [String] = [
        "Between impulse and action there is a space. It is yours.",
        "The feed will still be there. So will you.",
        "Three breaths. Then decide.",
        "What did you actually want to do just now?",
        "Emptiness is not a lack. It is room.",
        "七転び八起き. Fall seven times, stand up eight.",
        "A calm mind does not scroll, it chooses.",
        "The world can wait one question for you.",
        "Still water becomes clear.",
        "Boredom is the door, not the wall.",
        "一期一会. This moment will not come again.",
        "You are not your thumb.",
    ]

    private static let shieldDE: [String] = [
        "Zwischen Impuls und Handlung liegt ein Raum. Das ist deiner.",
        "Der Feed läuft nicht weg. Du auch nicht.",
        "Drei Atemzüge. Dann entscheide.",
        "Was wolltest du eigentlich gerade tun?",
        "Leere ist kein Mangel. Sie ist Platz.",
        "七転び八起き. Siebenmal fallen, achtmal aufstehen.",
        "Ein ruhiger Kopf scrollt nicht, er wählt.",
        "Die Welt wartet eine Frage lang auf dich.",
        "Wasser, das still steht, wird klar.",
        "Langeweile ist die Tür, nicht die Wand.",
        "一期一会. Dieser Moment kommt so nicht wieder.",
        "Du bist nicht dein Daumen.",
    ]

    private static let homeEN: [String] = [
        "Today is not about how much you see, but what you notice.",
        "猿も木から落ちる. Even monkeys fall from trees. Carry on.",
        "One thing after another. Then the next.",
        "石の上にも三年. Three years on a stone, and it grows warm.",
        "The shortest way to calm is putting the phone down.",
        "Learning is scrolling that gives something back.",
        "The garden grows in the pauses.",
    ]

    private static let homeDE: [String] = [
        "Heute zählt nicht, wie viel du siehst, sondern was du bemerkst.",
        "猿も木から落ちる. Auch Affen fallen von Bäumen. Weiter geht's.",
        "Eine Sache nach der anderen. Dann die nächste.",
        "石の上にも三年. Drei Jahre auf dem Stein, und er wird warm.",
        "Der kürzeste Weg zur Ruhe führt durch das Weglegen.",
        "Lernen ist Scrollen, das dir etwas zurückgibt.",
        "Der Garten wächst in den Pausen.",
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

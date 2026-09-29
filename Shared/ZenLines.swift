import Foundation

/// Short lines for the shield and the home screen. Written for Ma, plus a
/// few old Japanese proverbs that belong to everybody.
enum ZenLines {
    static let shield: [String] = [
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

    static let home: [String] = [
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

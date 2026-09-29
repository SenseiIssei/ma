import Foundation

/// English is the base language, German the translation. Both live inline,
/// next to each other, instead of in a String Catalog: the project is built
/// without Xcode's catalog editor, and a mistyped catalog key would fall back
/// to the wrong language without any warning.
enum Loc {
    /// Follows the per-app language in iOS Settings, then the device language.
    static let isGerman: Bool = {
        let preferred = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("de")
    }()

    static var code: String { isGerman ? "de" : "en" }
    static var locale: Locale { Locale(identifier: isGerman ? "de_DE" : "en_US") }
}

/// Picks the English or the German text.
func tr(_ english: String, _ german: String) -> String {
    Loc.isGerman ? german : english
}

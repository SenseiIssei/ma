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

/// Which kind of build this is. A preview build is signed without the
/// Family Controls entitlement, so it can reach TestFlight before Apple
/// approves that entitlement. Everything works except blocking apps.
enum BuildFlavor {
    #if MA_PREVIEW
    static let screenTimeAvailable = false
    #else
    static let screenTimeAvailable = true
    #endif

    static var previewNote: String {
        tr("This preview build cannot block apps yet. Apple still has to approve the Screen Time permission for Ma. Learning, focus and the Safari filter already work.",
           "Diese Vorschau kann noch keine Apps sperren. Apple muss die Bildschirmzeit-Berechtigung für Ma erst freigeben. Lernen, Fokus und der Safari-Filter funktionieren schon.")
    }
}

import Foundation

/// The watch's own language switch. Shared/Loc.swift reads the App Group and
/// the bundle's localizations, neither of which the watch has, so this one
/// follows the watch's preferred language only.
enum WatchLoc {
    static let isGerman: Bool = {
        let preferred: String = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("de")
    }()
}

/// Picks the English or the German text, like tr() in the iPhone app.
func tr(_ english: String, _ german: String) -> String {
    WatchLoc.isGerman ? german : english
}

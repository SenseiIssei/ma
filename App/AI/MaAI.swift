import FoundationModels
import SwiftUI

/// The one door to Apple's on-device model. Everything that talks to
/// FoundationModels lives in App/AI, so the rest of the app never has to
/// know whether this iPhone can run it. Without the model Ma works exactly
/// as before, the AI buttons just explain why they are resting.
enum MaAI {
    /// Our own view of `SystemLanguageModel.Availability`, so views outside
    /// App/AI can switch on it without importing FoundationModels.
    enum Status: Equatable {
        case ready
        /// Apple Intelligence is switched off in Settings.
        case turnedOff
        /// The iPhone cannot run Apple Intelligence at all.
        case notEligible
        /// Usually still downloading the model.
        case notReady
        /// The model runs, but not in the app language.
        case languageUnsupported
        /// A reason Apple added after iOS 26.0.
        case unavailable

        var isReady: Bool { self == .ready }
    }

    /// Read fresh every time: the person may switch Apple Intelligence on
    /// while Ma is open, and the model may finish downloading.
    static var status: Status {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            // The app language decides the answer language, so it has to be supported too.
            return model.supportsLocale(Loc.locale) ? .ready : .languageUnsupported
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                return .turnedOff
            case .deviceNotEligible:
                return .notEligible
            case .modelNotReady:
                return .notReady
            @unknown default:
                return .unavailable
            }
        @unknown default:
            return .unavailable
        }
    }

    /// Small inline buttons (explain more) stay hidden on iPhones that can
    /// never run the model. A button that can only ever say "no" is noise.
    static var offersInline: Bool { status != .notEligible }

    static var privacyLine: String {
        tr("Runs privately on your iPhone", "Läuft privat auf deinem iPhone")
    }

    static func note(for status: Status) -> String {
        switch status {
        case .ready:
            return ""
        case .turnedOff:
            return tr("Turn on Apple Intelligence in Settings to use this. Everything else in Ma works as usual.",
                      "Schalte Apple Intelligence in den Einstellungen ein, um das zu nutzen. Alles andere in Ma funktioniert wie gewohnt.")
        case .notEligible:
            return tr("This iPhone does not support Apple Intelligence, so the AI helpers are not available here. Everything else in Ma works as usual.",
                      "Dieses iPhone unterstützt Apple Intelligence nicht, deshalb gibt es die KI-Helfer hier nicht. Alles andere in Ma funktioniert wie gewohnt.")
        case .notReady:
            return tr("The on-device model is still getting ready, usually it is downloading. Try again in a little while.",
                      "Das Modell auf deinem iPhone ist noch nicht bereit, meistens lädt es gerade. Versuch es in einer Weile nochmal.")
        case .languageUnsupported:
            return tr("Apple Intelligence does not support the app language on this iPhone yet.",
                      "Apple Intelligence unterstützt die Sprache der App auf diesem iPhone noch nicht.")
        case .unavailable:
            return tr("The on-device model is not available right now. Try again later.",
                      "Das Modell auf deinem iPhone ist gerade nicht verfügbar. Versuch es später nochmal.")
        }
    }

    /// Turns framework errors into something a learner can act on.
    static func message(for error: Error) -> String {
        if let generation = error as? LanguageModelSession.GenerationError {
            switch generation {
            case .guardrailViolation:
                return tr("The on-device model would rather not write about this. Try a different wording.",
                          "Dazu schreibt das Modell lieber nichts. Versuch es mit anderen Worten.")
            case .exceededContextWindowSize:
                return tr("That was too much text for the on-device model in one go. Try a shorter topic or fewer cards.",
                          "Das war zu viel Text auf einmal für das Modell. Versuch ein kürzeres Thema oder weniger Karten.")
            case .unsupportedLanguageOrLocale:
                return note(for: .languageUnsupported)
            case .assetsUnavailable:
                return note(for: .notReady)
            case .rateLimited, .concurrentRequests:
                return tr("The on-device model is busy. Wait a moment and try again.",
                          "Das Modell ist gerade beschäftigt. Warte einen Moment und versuch es nochmal.")
            case .decodingFailure:
                return tr("The answer came back in a shape Ma could not read. Try again.",
                          "Die Antwort kam in einer Form, die Ma nicht lesen konnte. Versuch es nochmal.")
            default:
                break
            }
        }
        return genericFailure
    }

    static var genericFailure: String {
        tr("Something went wrong on the on-device model. Try again.",
           "Beim Modell auf deinem iPhone ist etwas schiefgelaufen. Versuch es nochmal.")
    }

    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || Task.isCancelled
    }

    /// The model sometimes answers with Markdown or long dashes. Ma's copy
    /// uses neither, so both are smoothed out before anything is shown.
    static func clean(_ text: String) -> String {
        let longDash = "\u{2014}"
        let midDash = "\u{2013}"
        var s = text
        s = s.replacingOccurrences(of: " " + longDash + " ", with: ", ")
        s = s.replacingOccurrences(of: " " + midDash + " ", with: ", ")
        s = s.replacingOccurrences(of: longDash, with: ", ")
        s = s.replacingOccurrences(of: midDash, with: "-")
        s = s.replacingOccurrences(of: "**", with: "")
        s = s.replacingOccurrences(of: "__", with: "")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Shared views

/// "Runs privately on your iPhone", with a lock. Shown next to every AI feature.
struct AIPrivacyLabel: View {
    var tint: Color = Zen.inkFaint

    var body: some View {
        Label(MaAI.privacyLine, systemImage: "lock.iphone")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
    }
}

/// Friendly card for when the model cannot run. Never an error colour:
/// nothing is broken, the helper is simply resting.
struct AIUnavailableNote: View {
    let status: MaAI.Status

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemName: icon, tint: Zen.kin, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Apple Intelligence is not available", "Apple Intelligence ist nicht verfügbar"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Zen.ink)
                Text(MaAI.note(for: status))
                    .font(.system(size: 14))
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Zen.sand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var icon: String {
        switch status {
        case .notReady: "arrow.down.circle"
        case .turnedOff: "gearshape"
        default: "moon.zzz"
        }
    }
}

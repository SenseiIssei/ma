import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Draws the screen iOS shows instead of a blocked app. Only text, colours,
/// one icon and two buttons are allowed here, so the calm has to come from
/// the words and a quiet background.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        shieldFor(application: application)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        shieldFor(application: application)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        shieldFor(webDomain: webDomain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        shieldFor(webDomain: webDomain)
    }

    // MARK: -

    private func shieldFor(application: Application) -> ShieldConfiguration {
        let name = application.localizedDisplayName
        if let name, let token = application.token {
            SharedStore.remember(name: name, application: token)
        }
        let pending = SharedStore.pending
        let waiting = pending?.isFresh == true && pending?.application != nil && pending?.application == application.token
        return make(
            name: name ?? tr("This app", "Diese App"),
            policy: UnlockPolicy.current(application: application.token),
            waiting: waiting
        )
    }

    private func shieldFor(webDomain: WebDomain) -> ShieldConfiguration {
        let name = webDomain.domain
        if let name, let token = webDomain.token {
            SharedStore.remember(name: name, webDomain: token)
        }
        let pending = SharedStore.pending
        let waiting = pending?.isFresh == true && pending?.webDomain != nil && pending?.webDomain == webDomain.token
        return make(
            name: name ?? tr("This site", "Diese Seite"),
            policy: UnlockPolicy.current(webDomain: webDomain.token),
            waiting: waiting
        )
    }

    private func make(name: String, policy: UnlockPolicy, waiting: Bool) -> ShieldConfiguration {
        countSighting()

        let backToCalm = tr("Back to calm", "Zurück zur Ruhe")

        if let until = policy.lockdownUntil {
            let clock = until.formatted(date: .omitted, time: .shortened)
            let left = Self.duration(until.timeIntervalSinceNow)
            return config(
                icon: "lock.fill",
                title: tr("Locked until \(clock)", "Gesperrt bis \(clock)"),
                subtitle: tr(
                    "Lockdown is on, \(left) left. Nothing opens before then, not even with questions.",
                    "Die Sperre läuft noch \(left). Bis dahin öffnet sich nichts, auch nicht mit Fragen."
                ),
                primary: backToCalm,
                secondary: nil
            )
        }

        if policy.focusLocked {
            let minutes = max(1, Int(((policy.focusEndsAt ?? Date()).timeIntervalSinceNow / 60).rounded(.up)))
            return config(
                icon: "timer",
                title: tr("Focus is on", "Fokus läuft"),
                subtitle: tr(
                    "\(minutes) \(minutes == 1 ? "minute" : "minutes") left. \(name) will wait until the round is over.",
                    "Noch \(minutes) \(minutes == 1 ? "Minute" : "Minuten"). \(name) wartet, bis die Runde vorbei ist."
                ),
                primary: tr("Back to work", "Zurück zur Arbeit"),
                secondary: nil
            )
        }

        if policy.budgetSpent {
            let limit = policy.dailyLimit ?? 0
            let rule = policy.ruleName ?? tr("this boundary", "diese Grenze")
            return config(
                icon: "hourglass.bottomhalf.filled",
                title: tr("No unlocks left today", "Keine Freigaben mehr für heute"),
                subtitle: tr(
                    "You gave yourself \(limit) \(limit == 1 ? "unlock" : "unlocks") a day for \(rule), and they are used up. \(name) opens again tomorrow.",
                    "Du hast dir für \(rule) \(limit) \(limit == 1 ? "Freigabe" : "Freigaben") am Tag gegeben, und die sind aufgebraucht. Morgen geht \(name) wieder auf."
                ),
                primary: backToCalm,
                secondary: nil
            )
        }

        if !policy.allowed {
            return config(
                icon: "shield.lefthalf.filled",
                title: policy.ruleName ?? tr("Boundary", "Grenze"),
                subtitle: tr(
                    "You set this boundary with no way through. Your earlier self knew why.",
                    "Diese Grenze hast du ohne Ausweg gesetzt. Dein früheres Ich wusste warum."
                ),
                primary: backToCalm,
                secondary: nil
            )
        }

        if waiting {
            return config(
                icon: "bell.badge.fill",
                title: tr("Your question is waiting", "Deine Frage wartet"),
                subtitle: tr(
                    "Check your notifications. Ma just sent you a question.",
                    "Schau in deine Mitteilungen. Ma hat dir gerade eine Frage geschickt."
                ),
                primary: tr("Send again", "Nochmal senden"),
                secondary: backToCalm
            )
        }

        let questions = policy.questions == 1
            ? tr("one question", "eine Frage")
            : tr("\(policy.questions) questions", "\(policy.questions) Fragen")
        var details = tr(
            "Answer \(questions) and \(name) opens for \(policy.minutes) minutes.",
            "Beantworte \(questions), dann ist \(name) \(policy.minutes) Minuten offen."
        )
        if let left = policy.unlocksLeft {
            details += " " + tr(
                "\(left) \(left == 1 ? "unlock" : "unlocks") left today.",
                "Heute \(left == 1 ? "bleibt noch eine Freigabe" : "bleiben noch \(left) Freigaben")."
            )
        }
        if policy.rising {
            details += " " + tr("Every unlock today costs one question more.", "Jede Freigabe heute kostet eine Frage mehr.")
        }
        return config(
            icon: "hand.raised.fill",
            title: tr("\(name) can wait", "\(name) kann warten"),
            subtitle: ZenLines.random(ZenLines.shield) + "\n\n" + details,
            primary: tr("Answer a question", "Frage beantworten"),
            secondary: backToCalm
        )
    }

    private func config(icon: String, title: String, subtitle: String, primary: String, secondary: String?) -> ShieldConfiguration {
        let symbol = UIImage.SymbolConfiguration(pointSize: 44, weight: .semibold)
        let image = UIImage(systemName: icon, withConfiguration: symbol)?
            .withTintColor(Palette.accent, renderingMode: .alwaysOriginal)
        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: Palette.background,
            icon: image,
            title: ShieldConfiguration.Label(text: title, color: Palette.text),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: Palette.secondary),
            primaryButtonLabel: ShieldConfiguration.Label(text: primary, color: .white),
            primaryButtonBackgroundColor: Palette.accent,
            secondaryButtonLabel: secondary.map { ShieldConfiguration.Label(text: $0, color: Palette.text) }
        )
    }

    /// "1 h 20 min." or "25 min.", rounded up so it never reads zero.
    private static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return tr("\(minutes) min.", "\(minutes) Min.") }
        if rest == 0 { return tr("\(hours) h", "\(hours) Std.") }
        return tr("\(hours) h \(rest) min.", "\(hours) Std. \(rest) Min.")
    }

    /// iOS asks for a configuration more than once per sighting, so a
    /// sighting only counts if the last one is half a minute old.
    private func countSighting() {
        let last = MaShared.read(Date.self, from: "last-shield.json") ?? .distantPast
        guard Date().timeIntervalSince(last) > 30 else { return }
        MaShared.write(Date(), to: "last-shield.json")
        SharedStore.updateToday { $0.shieldsSeen += 1 }
    }
}

private enum Palette {
    static let background = dynamic(light: 0xF6F5F3, dark: 0x0E0F12)
    static let text = dynamic(light: 0x16171B, dark: 0xF3F3F5)
    static let secondary = dynamic(light: 0x6B6D75, dark: 0xA3A5AE)
    static let accent = dynamic(light: 0x5B5FEF, dark: 0x8286FF)

    static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) }
    }

    static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

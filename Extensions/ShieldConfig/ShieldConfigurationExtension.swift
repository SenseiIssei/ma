import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Draws the screen iOS shows instead of a blocked app. Only text, colours,
/// one icon and two buttons are allowed here, so the calm has to come from
/// the words and the paper colour.
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
            name: name ?? "Diese App",
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
            name: name ?? "Diese Seite",
            policy: UnlockPolicy.current(webDomain: webDomain.token),
            waiting: waiting
        )
    }

    private func make(name: String, policy: UnlockPolicy, waiting: Bool) -> ShieldConfiguration {
        countSighting()

        if policy.focusLocked {
            let minutes = max(1, Int(((policy.focusEndsAt ?? Date()).timeIntervalSinceNow / 60).rounded(.up)))
            return config(
                title: "集中  Fokus läuft",
                subtitle: "Noch \(minutes) \(minutes == 1 ? "Minute" : "Minuten"). \(name) wartet, bis die Runde vorbei ist.",
                primary: "Zurück zur Arbeit",
                secondary: nil
            )
        }

        if !policy.allowed {
            return config(
                title: "結界  \(policy.ruleName ?? "Grenze")",
                subtitle: "Diese Grenze hast du ohne Ausweg gesetzt. Dein früheres Ich wusste warum.",
                primary: "Zurück zur Ruhe",
                secondary: nil
            )
        }

        if waiting {
            return config(
                title: "間  Deine Frage wartet",
                subtitle: "Schau in deine Mitteilungen. Ma hat dir gerade eine Frage geschickt.",
                primary: "Nochmal senden",
                secondary: "Zurück zur Ruhe"
            )
        }

        let questions = policy.questions == 1 ? "eine Frage" : "\(policy.questions) Fragen"
        return config(
            title: "間  \(name) kann warten",
            subtitle: "\(ZenLines.random(ZenLines.shield))\n\nBeantworte \(questions), dann ist \(name) \(policy.minutes) Minuten offen.",
            primary: "Frage beantworten",
            secondary: "Zurück zur Ruhe"
        )
    }

    private func config(title: String, subtitle: String, primary: String, secondary: String?) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: Palette.paper,
            icon: UIImage(named: "ShieldEnso"),
            title: ShieldConfiguration.Label(text: title, color: Palette.ink),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: Palette.inkSoft),
            primaryButtonLabel: ShieldConfiguration.Label(text: primary, color: Palette.paper),
            primaryButtonBackgroundColor: Palette.shu,
            secondaryButtonLabel: secondary.map { ShieldConfiguration.Label(text: $0, color: Palette.ink) }
        )
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
    static let paper = dynamic(light: 0xF4EFE6, dark: 0x151412)
    static let ink = dynamic(light: 0x1F1D1B, dark: 0xECE6DA)
    static let inkSoft = dynamic(light: 0x5E5850, dark: 0xA69E92)
    static let shu = dynamic(light: 0xC8412C, dark: 0xD9573F)

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

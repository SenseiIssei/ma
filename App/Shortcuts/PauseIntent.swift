import AppIntents
import Foundation

/// Apps the Shortcuts mode knows how to send you back to.
enum GuardedApp: String, AppEnum, CaseIterable {
    case any, instagram, youtube, tiktok, x, linkedin, facebook, reddit, snapchat, threads, pinterest

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "App"

    static let caseDisplayRepresentations: [GuardedApp: DisplayRepresentation] = [
        .any: "Any app",
        .instagram: "Instagram",
        .youtube: "YouTube",
        .tiktok: "TikTok",
        .x: "X",
        .linkedin: "LinkedIn",
        .facebook: "Facebook",
        .reddit: "Reddit",
        .snapchat: "Snapchat",
        .threads: "Threads",
        .pinterest: "Pinterest",
    ]

    var displayName: String {
        switch self {
        case .any: tr("your app", "deine App")
        case .instagram: "Instagram"
        case .youtube: "YouTube"
        case .tiktok: "TikTok"
        case .x: "X"
        case .linkedin: "LinkedIn"
        case .facebook: "Facebook"
        case .reddit: "Reddit"
        case .snapchat: "Snapchat"
        case .threads: "Threads"
        case .pinterest: "Pinterest"
        }
    }

    var url: URL? {
        switch self {
        case .any: nil
        case .instagram: URL(string: "instagram://")
        case .youtube: URL(string: "youtube://")
        case .tiktok: URL(string: "tiktok://")
        case .x: URL(string: "twitter://")
        case .linkedin: URL(string: "linkedin://")
        case .facebook: URL(string: "fb://")
        case .reddit: URL(string: "reddit://")
        case .snapchat: URL(string: "snapchat://")
        case .threads: URL(string: "barcelona://")
        case .pinterest: URL(string: "pinterest://")
        }
    }
}

/// Run by a Shortcuts automation ("When Instagram is opened"). It starts in
/// the background and only brings Ma forward when there is no open pass, so
/// an unlocked app opens without a flicker and the automation cannot loop.
struct PauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Ma Pause"
    static let description = IntentDescription("Puts a breath and a question between you and an app. Add it to an automation that runs when your apps open.")

    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "App", default: .any)
    var app: GuardedApp

    func perform() async throws -> some IntentResult {
        SharedStore.shortcutLastRun = Date()
        if let until = SharedStore.shortcutPassUntil, until > Date() {
            return .result()
        }

        SharedStore.shortcutRequest = ShortcutRequest(app: app.rawValue)
        SharedStore.updateToday { $0.shieldsSeen += 1 }

        if systemContext.currentMode.canContinueInForeground {
            try await continueInForeground(alwaysConfirm: false)
        }
        await MainActor.run {
            NotificationCenter.default.post(name: .maNotificationOpened, object: nil, userInfo: [Notifier.routeKey: "shortcut"])
        }
        return .result()
    }
}

struct MaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PauseIntent(),
            phrases: ["Pause with \(.applicationName)", "\(.applicationName) pause"],
            shortTitle: "Ma Pause",
            systemImageName: "circle.dashed"
        )
    }
}

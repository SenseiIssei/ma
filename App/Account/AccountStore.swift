import Foundation
import Observation

/// The signed-in account, if any. Keeps the last known account in the App
/// Group so owner features show immediately on launch and refreshes it from
/// the server when the app comes to the front.
@MainActor
@Observable
final class AccountStore {
    private(set) var account: AccountDTO?
    private(set) var busy = false
    var errorMessage: String?
    /// Shown once after registering: "check your inbox".
    var infoMessage: String?

    private var api: AccountAPI
    private let google = GoogleSignIn()
    private static let file = "account.json"

    init() {
        let token = AccountKeychain.load()
        api = AccountAPI(session: token)
        account = token == nil ? nil : MaShared.read(AccountDTO.self, from: Self.file)
    }

    var isSignedIn: Bool { account != nil }

    func has(_ feature: String) -> Bool { account?.has(feature) ?? false }

    // MARK: Signing in and out

    func register(email: String, password: String) async -> Bool {
        await run {
            let result = try await self.api.register(email: email.trimmingCharacters(in: .whitespaces), password: password)
            self.adopt(result)
            self.infoMessage = result.mailSent == false
                ? tr("Your account is ready, but the confirmation mail could not be sent yet. Try again later from here.",
                     "Dein Konto ist angelegt, die Bestätigungsmail ging aber noch nicht raus. Versuch es später hier nochmal.")
                : tr("Almost there: we sent a confirmation link to \(result.account.email).",
                     "Fast geschafft: Wir haben dir einen Bestätigungslink an \(result.account.email) geschickt.")
        }
    }

    func login(email: String, password: String) async -> Bool {
        await run {
            self.adopt(try await self.api.login(email: email.trimmingCharacters(in: .whitespaces), password: password))
        }
    }

    func signInWithGoogle() async -> Bool {
        await run {
            let idToken = try await self.google.idToken()
            self.adopt(try await self.api.google(idToken: idToken))
        }
    }

    func forgotPassword(email: String) async -> Bool {
        await run {
            try await self.api.forgot(email: email.trimmingCharacters(in: .whitespaces))
            self.infoMessage = tr("If there is an account for this address, a reset link is on its way.",
                                  "Wenn es ein Konto zu dieser Adresse gibt, ist ein Link zum Zurücksetzen unterwegs.")
        }
    }

    func resendConfirmation() async {
        await run {
            try await self.api.resend()
            self.infoMessage = tr("Sent again. Check your inbox and spam folder.", "Nochmal geschickt. Schau in Posteingang und Spam.")
        }
    }

    func signOut() async {
        try? await api.logout()
        forget()
    }

    func deleteAccount() async -> Bool {
        await run {
            try await self.api.deleteAccount()
            self.forget()
        }
    }

    /// Picks up a confirmed address or new features.
    func refresh() async {
        guard api.session != nil else { return }
        do {
            let fresh = try await api.me()
            account = fresh
            MaShared.write(fresh, to: Self.file)
        } catch AccountError.unauthorized {
            forget()
        } catch {
            // Offline: keep the last known account.
        }
    }

    // MARK: Owner features

    func dailyLinkCode() async -> DailyLinkCode? {
        var code: DailyLinkCode?
        await run { code = try await self.api.dailyLinkCode() }
        return code
    }

    func dailyProgress() async -> DailyProgressDTO? {
        guard has("daily") else { return nil }
        return try? await api.dailyProgress()
    }

    func notifyStatus() async -> NotifyStatusDTO? {
        guard has("reminders") else { return nil }
        return try? await api.notifyStatus()
    }

    func notifyLink(_ channel: String) async -> URL? {
        var url: URL?
        await run { url = try await self.api.notifyLink(channel) }
        return url
    }

    func notifyUnlink(_ channel: String) async {
        await run { try await self.api.notifyUnlink(channel) }
    }

    func notifyTime(_ time: String) async {
        await run { try await self.api.notifyTime(time) }
    }

    func notifyTest() async -> [String]? {
        var failures: [String]?
        await run { failures = try await self.api.notifyTest() }
        return failures
    }

    // MARK: Private

    private func adopt(_ result: AccountSessionDTO) {
        AccountKeychain.save(result.session)
        api.session = result.session
        account = result.account
        MaShared.write(result.account, to: Self.file)
    }

    private func forget() {
        AccountKeychain.delete()
        api.session = nil
        account = nil
        MaShared.write(AccountDTO?.none, to: Self.file)
    }

    @discardableResult
    private func run(_ work: () async throws -> Void) async -> Bool {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try await work()
            return true
        } catch AccountError.cancelled {
            return false
        } catch AccountError.unauthorized {
            forget()
            errorMessage = AccountError.unauthorized.errorDescription
            return false
        } catch let error as AccountError {
            errorMessage = error.errorDescription
            return false
        } catch {
            errorMessage = AccountError.server.errorDescription
            return false
        }
    }
}

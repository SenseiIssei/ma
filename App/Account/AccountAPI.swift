import Foundation
import Security

// The optional Ma account: email and password with a confirmation mail, or
// Google. Ma works fully without one. The server decides what an account
// unlocks (`features`); today only the owner gets the daily lessons from
// senseiissei.dev and personal reminders.

struct AccountDTO: Codable, Equatable, Sendable {
    var id: String
    var email: String
    var verified: Bool
    var hasPassword: Bool
    var google: Bool
    var features: [String]

    func has(_ feature: String) -> Bool { features.contains(feature) }
}

struct AccountSessionDTO: Decodable, Sendable {
    var account: AccountDTO
    var session: String
    var mailSent: Bool?
}

struct NotifyChannelDTO: Decodable, Equatable, Sendable {
    var available: Bool
    var connected: Bool
    var label: String?
}

struct NotifyStatusDTO: Decodable, Equatable, Sendable {
    var telegram: NotifyChannelDTO
    var discord: NotifyChannelDTO
    var time: String
}

enum AccountError: LocalizedError, Equatable {
    case offline, unauthorized, forbidden, conflict(String), invalid(String), rateLimited, server, cancelled

    var errorDescription: String? {
        switch self {
        case .offline: tr("Ma's server is not reachable right now.", "Mas Server ist gerade nicht erreichbar.")
        case .unauthorized: tr("Please sign in again.", "Bitte melde dich erneut an.")
        case .forbidden: tr("This account cannot use that.", "Dieses Konto kann das nicht nutzen.")
        case .conflict(let message), .invalid(let message): message
        case .rateLimited: tr("Too many tries. Wait a little.", "Zu viele Versuche. Warte kurz.")
        case .server: tr("Something went wrong.", "Etwas ist schiefgelaufen.")
        case .cancelled: nil
        }
    }
}

/// The session token lives in the Keychain, this device only.
enum AccountKeychain {
    private static let service = "com.sensei.ma.account"
    private static let account = "session"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) {
        delete()
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

struct AccountAPI: Sendable {
    var baseURL: URL = FriendsAPI.defaultBaseURL
    var session: String?

    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private struct ServerError: Decodable { var message: String }

    private func request(_ method: String, _ path: String, body: [String: Any]? = nil, authorized: Bool = true) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized {
            guard let session else { throw AccountError.unauthorized }
            request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.urlSession.data(for: request)
        } catch {
            throw AccountError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw AccountError.server }
        if (200..<300).contains(http.statusCode) { return data }
        let message: String = (try? JSONDecoder().decode(ServerError.self, from: data))?.message ?? AccountError.server.errorDescription ?? ""
        switch http.statusCode {
        case 401: throw request.value(forHTTPHeaderField: "Authorization") == nil ? AccountError.invalid(message) : AccountError.unauthorized
        case 403: throw AccountError.forbidden
        case 409: throw AccountError.conflict(message)
        case 400, 404, 413: throw AccountError.invalid(message)
        case 429: throw AccountError.rateLimited
        default: throw AccountError.server
        }
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil, authorized: Bool = true) async throws -> T {
        let data = try await perform(request(method, path, body: body, authorized: authorized))
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AccountError.server
        }
    }

    private func sendEmpty(_ method: String, _ path: String, body: [String: Any]? = nil, authorized: Bool = true) async throws {
        _ = try await perform(request(method, path, body: body, authorized: authorized))
    }

    // MARK: Account

    func register(email: String, password: String) async throws -> AccountSessionDTO {
        try await send("POST", "auth/register", body: ["email": email, "password": password, "lang": Loc.code], authorized: false)
    }

    func login(email: String, password: String) async throws -> AccountSessionDTO {
        try await send("POST", "auth/login", body: ["email": email, "password": password], authorized: false)
    }

    func google(idToken: String) async throws -> AccountSessionDTO {
        try await send("POST", "auth/google", body: ["idToken": idToken], authorized: false)
    }

    func me() async throws -> AccountDTO { try await send("GET", "auth/me") }

    func resend() async throws { try await sendEmpty("POST", "auth/resend", body: ["lang": Loc.code]) }

    func forgot(email: String) async throws {
        try await sendEmpty("POST", "auth/forgot", body: ["email": email, "lang": Loc.code], authorized: false)
    }

    func logout() async throws { try await sendEmpty("POST", "auth/logout") }

    func deleteAccount() async throws { try await sendEmpty("DELETE", "auth/me") }

    // MARK: Owner features

    func dailyLinkCode() async throws -> DailyLinkCode { try await send("POST", "daily/link-code") }

    func dailyProgress() async throws -> DailyProgressDTO { try await send("GET", "daily/progress") }

    func notifyStatus() async throws -> NotifyStatusDTO { try await send("GET", "notify") }

    func notifyLink(_ channel: String) async throws -> URL {
        struct Link: Decodable { var url: URL }
        let link: Link = try await send("POST", "notify/\(channel)/link")
        return link.url
    }

    func notifyUnlink(_ channel: String) async throws { try await sendEmpty("DELETE", "notify/\(channel)") }

    func notifyTime(_ time: String) async throws { try await sendEmpty("PUT", "notify/time", body: ["time": time]) }

    func notifyTest() async throws -> [String] {
        struct Result: Decodable { var failures: [String] }
        let result: Result = try await send("POST", "notify/test")
        return result.failures
    }
}

import Foundation

/// What can go wrong talking to the Friends server, phrased for people.
enum FriendsError: LocalizedError, Equatable {
    case offline
    case unauthorized
    case notFound(String)
    case conflict(String)
    case invalid(String)
    case rateLimited
    case server

    var errorDescription: String? {
        switch self {
        case .offline:
            tr("No connection to the Friends server. Try again in a moment.",
               "Keine Verbindung zum Friends-Server. Versuch es gleich noch einmal.")
        case .unauthorized:
            tr("This device is no longer known to the server. Switch Friends off and on again to start fresh.",
               "Dieses Gerät ist dem Server nicht mehr bekannt. Schalte Friends aus und wieder ein, um neu zu beginnen.")
        case .notFound(let message), .conflict(let message), .invalid(let message):
            message
        case .rateLimited:
            tr("That was a lot at once. Please wait a little.", "Das war viel auf einmal. Bitte warte kurz.")
        case .server:
            tr("The server had a problem. Try again later.", "Der Server hatte ein Problem. Versuch es später noch einmal.")
        }
    }
}

/// Thin async client for the Friends backend. Stateless apart from the
/// credentials, so it is a plain Sendable value.
struct FriendsAPI: Sendable {
    static let defaultBaseURL = URL(string: "https://senseiissei.dev/ma/api")!

    var baseURL: URL = FriendsAPI.defaultBaseURL
    var credentials: FriendCredentials?

    /// Ephemeral: no cookies, no URL cache, nothing about the member on disk.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // MARK: Members

    func register(_ creds: FriendCredentials, nickname: String, avatar: String) async throws -> FriendProfile {
        let body = try JSONSerialization.data(withJSONObject: [
            "id": creds.memberId, "secret": creds.secret, "nickname": nickname, "avatar": avatar,
        ])
        return try await send("POST", "members", body: body, authorized: false)
    }

    func me() async throws -> FriendProfile {
        try await send("GET", "me")
    }

    func updateProfile(nickname: String, avatar: String) async throws -> FriendProfile {
        let body = try JSONSerialization.data(withJSONObject: ["nickname": nickname, "avatar": avatar])
        return try await send("PATCH", "me", body: body)
    }

    func deleteMe() async throws {
        try await sendEmpty("DELETE", "me")
    }

    // MARK: Circles

    func circles() async throws -> [CircleSummary] {
        let list: CircleList = try await send("GET", "circles")
        return list.circles
    }

    func circle(_ id: String) async throws -> CircleDetail {
        try await send("GET", "circles/\(id)")
    }

    func createCircle(name: String) async throws -> CircleDetail {
        let body = try JSONSerialization.data(withJSONObject: ["name": name])
        return try await send("POST", "circles", body: body)
    }

    func join(code: String) async throws -> CircleDetail {
        let body = try JSONSerialization.data(withJSONObject: ["code": code])
        return try await send("POST", "circles/join", body: body)
    }

    func leave(_ id: String) async throws {
        try await sendEmpty("POST", "circles/\(id)/leave")
    }

    func rotateCode(_ id: String) async throws -> CircleSummary {
        try await send("POST", "circles/\(id)/rotate-code")
    }

    func removeMember(_ memberId: String, from circleId: String) async throws {
        try await sendEmpty("DELETE", "circles/\(circleId)/members/\(memberId)")
    }

    func setChallenge(_ kind: String?, for circleId: String) async throws -> CircleDetail {
        // {"kind": null} clears it, so the null has to be written explicitly.
        let value: Any
        if let kind { value = kind } else { value = NSNull() }
        let body = try JSONSerialization.data(withJSONObject: ["kind": value])
        return try await send("PUT", "circles/\(circleId)/challenge", body: body)
    }

    // MARK: Numbers

    func publish(_ day: DayUpload, date: String) async throws {
        let body = try JSONEncoder().encode(day)
        let _: FriendDay = try await send("PUT", "stats/\(date)", body: body)
    }

    // MARK: Daily lessons (senseiissei.dev)

    func dailyLinkCode() async throws -> DailyLinkCode {
        try await send("POST", "daily/link-code")
    }

    func dailyProgress() async throws -> DailyProgressDTO {
        try await send("GET", "daily/progress")
    }

    // MARK: Plumbing

    private func request(_ method: String, _ path: String, body: Data?, authorized: Bool) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized {
            guard let credentials else { throw FriendsError.unauthorized }
            request.setValue(credentials.bearer, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let result: (Data, URLResponse)
        do {
            result = try await Self.session.data(for: request)
        } catch {
            throw FriendsError.offline
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else { throw FriendsError.server }
        if (200..<300).contains(http.statusCode) { return data }
        let message = (try? JSONDecoder().decode(ServerError.self, from: data))?.message
            ?? tr("Something went wrong.", "Etwas ist schiefgelaufen.")
        switch http.statusCode {
        case 401: throw FriendsError.unauthorized
        case 404: throw FriendsError.notFound(message)
        case 409: throw FriendsError.conflict(message)
        case 400, 403, 413: throw FriendsError.invalid(message)
        case 429: throw FriendsError.rateLimited
        default: throw FriendsError.server
        }
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: Data? = nil, authorized: Bool = true) async throws -> T {
        let data = try await perform(request(method, path, body: body, authorized: authorized))
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw FriendsError.server
        }
    }

    private func sendEmpty(_ method: String, _ path: String) async throws {
        _ = try await perform(request(method, path, body: nil, authorized: true))
    }

    private struct ServerError: Decodable {
        var error: String
        var message: String
    }
}

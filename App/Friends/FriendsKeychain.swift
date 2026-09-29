import Foundation
import Security

/// The device's Friends identity: a random member id and a random 32 byte
/// secret. It is the only "account" there is, so it lives in the Keychain,
/// this device only, never synced to iCloud.
struct FriendCredentials: Codable, Equatable, Sendable {
    var memberId: String
    var secret: String

    var bearer: String { "Bearer \(memberId).\(secret)" }

    /// Fresh identity. The secret comes from the system CSPRNG, 64 hex chars.
    static func generate() -> FriendCredentials? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return FriendCredentials(memberId: UUID().uuidString.lowercased(), secret: hex)
    }
}

enum FriendsKeychain {
    private static let service = "com.sensei.ma.friends"
    private static let account = "member"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func load() -> FriendCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(FriendCredentials.self, from: data)
    }

    @discardableResult
    static func save(_ credentials: FriendCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        // After first unlock so the upload on app activation works; ThisDeviceOnly
        // keeps the secret out of iCloud Keychain and out of other devices' backups.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

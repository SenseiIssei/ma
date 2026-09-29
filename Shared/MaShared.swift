import Foundation

/// Everything the app and its extensions agree on lives in one App Group
/// container. Each value is a small JSON file, written atomically, so a
/// reader in another process never sees half a write.
enum MaShared {
    static let appGroup = "group.com.sensei.ma"

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return url
        }
        // Only reached in an unsigned build (simulator, CI compile check).
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    static func fileURL(_ name: String) -> URL {
        containerURL.appendingPathComponent(name)
    }

    static func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: fileURL(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func write<T: Encodable>(_ value: T?, to name: String) {
        let url = fileURL(name)
        guard let value else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

import CryptoKit
import Foundation

/// The last good answer from the network, kept on disk per account.
///
/// Every store that polls keeps what it last heard, so a bad connection shows the
/// balance from a minute ago rather than a zero, and a cold launch opens on what the
/// app knew rather than on nothing. One small JSON file per store under Application
/// Support. The account is part of the path, so two people sharing a phone never
/// read each other's figures, and a file is only ever replaced by a fresher answer
/// for the same account.
struct SnapshotCache: Sendable {
    private let root: URL

    static let shared = SnapshotCache()

    init(root: URL? = nil) {
        self.root = root
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "Recourse/snapshots", directoryHint: .isDirectory)
    }

    func load<Value: Decodable>(_ type: Value.Type, key: String, scope: String?) -> Value? {
        guard let data = try? Data(contentsOf: url(key: key, scope: scope)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func save<Value: Encodable>(_ value: Value, key: String, scope: String?) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let file = url(key: key, scope: scope)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    func remove(key: String, scope: String?) {
        try? FileManager.default.removeItem(at: url(key: key, scope: scope))
    }

    // The scope is an account identifier from the sign-in provider, so it is hashed
    // into a folder name rather than written into the file system as it is.
    private func url(key: String, scope: String?) -> URL {
        let folder = scope.map { scope in
            SHA256.hash(data: Data(scope.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        } ?? "anonymous"
        return root.appending(path: folder, directoryHint: .isDirectory).appending(path: "\(key).json")
    }
}

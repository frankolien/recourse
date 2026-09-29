import CryptoKit
import Foundation

/// The last good answer from the network, kept on disk per account and per chain.
///
/// Every store that polls keeps what it last heard, so a bad connection shows the
/// balance from a minute ago rather than a zero, and a cold launch opens on what the
/// app knew rather than on nothing. One small JSON file per store under Application
/// Support. The account is part of the path, so two people sharing a phone never read
/// each other's figures, and a file is only ever replaced by a fresher answer for the
/// same account.
///
/// The chain is fixed when the cache is built, and every store is handed the cache of
/// the chain it was built for. That is not a convenience. A store still finishing a
/// read when the person switches chains would otherwise look up the chain at the
/// moment it writes, find the new one, and file the old chain's figures under it. One
/// person is the same account on both chains, so that is a testnet balance shown as
/// real money. A cache that knows its own chain writes where it belongs no matter when
/// it writes.
struct SnapshotCache: Sendable {
    let chainID: UInt64
    private let root: URL

    init(chainID: UInt64, root: URL? = nil) {
        self.chainID = chainID
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
    // into a folder name rather than written into the file system as it is. The chain
    // goes into the hash beside it, and is this instance's chain, never the app's
    // current one.
    //
    // The namespace is versioned. A build that shipped on 2026-09-29 partitioned by the
    // app's current chain at write time and could misfile one chain's figures under
    // another; those files hash to the old names and are never read again. The cost is
    // one launch that fetches instead of opening on a remembered figure, once, which
    // is nothing beside reading the wrong chain's money as your own.
    private static let namespace = "v2"

    private func url(key: String, scope: String?) -> URL {
        let folder = scope.map { scope -> String in
            let scoped = "\(Self.namespace):\(chainID):\(scope)"
            return SHA256.hash(data: Data(scoped.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        } ?? "\(Self.namespace)-anonymous-\(chainID)"
        return root.appending(path: folder, directoryHint: .isDirectory).appending(path: "\(key).json")
    }
}

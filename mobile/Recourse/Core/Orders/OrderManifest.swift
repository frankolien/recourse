import Foundation

// A merchant's per-checkout order details. The manifest is an exact JSON document whose
// keccak256 over the raw bytes IS the bytes32 orderRef the escrow receives in pay(), so
// the buyer verifies an order by rehashing the fetched bytes; parsed fields are then
// cross-checked against the scanned QR before any money moves. The backend stores the
// bytes content-addressed and is trusted for transport only, never for content.
struct OrderManifest: Codable, Hashable, Sendable {
    let version: UInt8
    let chainID: UInt64
    let escrow: String
    let merchant: String
    let policyID: UInt64
    // USDC base units (6 decimals) as a decimal string, exactly like the QR payload.
    let amount: String
    let orderReference: String
    let itemName: String
    let description: String
    let imageHash: String?
    let imageContentType: String?
    let createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case version
        case chainID = "chainId"
        case escrow
        case merchant
        case policyID = "policyId"
        case amount
        case orderReference
        case itemName
        case description
        case imageHash
        case imageContentType
        case createdAt
    }
}

enum OrderManifestError: Error, Equatable {
    // Fetched bytes do not rehash to the orderRef: tampered or wrong document.
    case hashMismatch
    // The manifest disagrees with the scanned QR on an economic field.
    case fieldMismatch(String)
    case invalidManifest
    // Fetched image bytes do not rehash to the manifest's imageHash.
    case imageHashMismatch
}

extension OrderManifest {
    // Decode manifest bytes only after they rehash to the expected orderRef.
    static func decode(verifying bytes: Data, orderReference: ChainHash) throws -> OrderManifest {
        guard bytes.keccak256Hash.value.lowercased() == orderReference.value.lowercased() else {
            throw OrderManifestError.hashMismatch
        }
        guard let manifest = try? JSONDecoder().decode(OrderManifest.self, from: bytes) else {
            throw OrderManifestError.invalidManifest
        }
        return manifest
    }

    // Every field the buyer is about to act on economically must match the scanned QR
    // (which PaymentRequest.validate already pinned to this app's chain and escrow).
    // Any mismatch blocks payment.
    func crossCheck(against request: PaymentRequest) throws {
        guard version == 1 else {
            throw OrderManifestError.fieldMismatch("version")
        }
        guard chainID == request.chainID else {
            throw OrderManifestError.fieldMismatch("chain")
        }
        guard escrow.lowercased() == request.escrow.value.lowercased() else {
            throw OrderManifestError.fieldMismatch("escrow")
        }
        guard merchant.lowercased() == request.merchant.value.lowercased() else {
            throw OrderManifestError.fieldMismatch("merchant")
        }
        guard policyID == request.policyID else {
            throw OrderManifestError.fieldMismatch("policy")
        }
        guard amount == String(request.amount.baseUnits) else {
            throw OrderManifestError.fieldMismatch("amount")
        }
        let name = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !details.isEmpty else {
            throw OrderManifestError.invalidManifest
        }
    }

    // Merchant side: serialize once and derive the orderRef from those exact bytes. The
    // returned bytes must be published verbatim; re-encoding would change the hash.
    func encodedForPublishing() throws -> (bytes: Data, orderReference: ChainHash) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(self)
        return (bytes, bytes.keccak256Hash)
    }
}

import Foundation

enum EvidenceAPIError: Error, Equatable, Sendable {
    case invalidURL
    case invalidResponse
    case invalidChallenge
    case invalidSignature
    case httpStatus(Int, String?)
    case evidenceHashMismatch(expected: ChainHash, received: ChainHash)
}

actor EvidenceAPIClient: EvidenceRepository {
    private let baseURL: URL
    private let chainID: UInt64
    private let signer: any BuyerSigner
    private let transport: any EvidenceAPITransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        baseURL: URL,
        chainID: UInt64,
        signer: any BuyerSigner,
        transport: any EvidenceAPITransport = URLSessionEvidenceAPITransport()
    ) {
        self.baseURL = baseURL
        self.chainID = chainID
        self.signer = signer
        self.transport = transport
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    func upload(_ evidence: EvidenceDraft, paymentID: UInt64) async throws -> UploadedEvidence {
        let response = try await authorizedPost(
            action: .upload,
            paymentID: paymentID,
            path: "api/evidence",
            contentType: evidence.contentType,
            body: evidence.content
        )
        let stored = try decoder.decode(StoredEvidenceResponse.self, from: response)
        let receivedHash = try ChainHash(stored.hash)
        let expectedHash = evidence.content.keccak256Hash
        guard receivedHash.value.lowercased() == expectedHash.value.lowercased() else {
            throw EvidenceAPIError.evidenceHashMismatch(
                expected: expectedHash,
                received: receivedHash
            )
        }
        return UploadedEvidence(kind: evidence.kind, hash: receivedHash)
    }

    func publishManifest(
        paymentID: UInt64,
        evidence: [UploadedEvidence]
    ) async throws -> EvidenceManifestReceipt {
        let body = try encoder.encode(
            ManifestRequest(
                paymentID: paymentID,
                items: evidence.map { .init(evidence: $0) }
            )
        )
        let response = try await authorizedPost(
            action: .manifest,
            paymentID: paymentID,
            path: "api/evidence/manifest",
            contentType: "application/json",
            body: body
        )
        let receipt = try decoder.decode(ManifestResponse.self, from: response)
        return EvidenceManifestReceipt(
            paymentID: receipt.paymentID,
            matches: receipt.matches,
            computedRoot: try ChainHash(receipt.computedRoot),
            onchainRoot: try ChainHash(receipt.onchainRoot)
        )
    }

    private func authorizedPost(
        action: EvidenceAuthorizationAction,
        paymentID: UInt64,
        path: String,
        contentType: String,
        body: Data
    ) async throws -> Data {
        let challengeResponse = try await transport.execute(
            EvidenceHTTPRequest(
                method: .post,
                path: "api/auth/challenge",
                headers: [:],
                body: Data()
            ),
            baseURL: baseURL
        )
        let challengeData = try successfulBody(challengeResponse)
        guard let challenge = try? decoder.decode(ChallengeResponse.self, from: challengeData),
              challenge.expiresAt > 0,
              let nonce = try? ChainHash(challenge.nonce) else {
            throw EvidenceAPIError.invalidChallenge
        }

        let wallet = try await signer.address()
        let authorization = EvidenceAuthorizationRequest(
            action: action,
            paymentID: paymentID,
            walletAddress: wallet,
            chainID: chainID,
            bodyHash: body.keccak256Hash,
            nonce: nonce,
            expiresAt: challenge.expiresAt
        )
        let signature = try await signer.signEIP712(authorization.typedDataJSON())
        guard signature.count == 65 else {
            throw EvidenceAPIError.invalidSignature
        }
        let envelope = EvidenceAuthorizationEnvelope(
            request: authorization,
            signature: signature.hexEncoded
        )
        let authHeader = try encoder.encode(envelope).base64EncodedString()
        let response = try await transport.execute(
            EvidenceHTTPRequest(
                method: .post,
                path: path,
                headers: [
                    "Content-Type": contentType,
                    "X-Recourse-Auth": authHeader
                ],
                body: body
            ),
            baseURL: baseURL
        )
        return try successfulBody(response)
    }

    private func successfulBody(_ response: EvidenceHTTPResponse) throws -> Data {
        guard (200 ... 299).contains(response.statusCode) else {
            let message = try? decoder.decode(ErrorResponse.self, from: response.body).error
            throw EvidenceAPIError.httpStatus(response.statusCode, message)
        }
        return response.body
    }
}

private struct ChallengeResponse: Decodable {
    let nonce: String
    let expiresAt: UInt64
}

private struct StoredEvidenceResponse: Decodable {
    let hash: String
}

private struct ManifestRequest: Encodable {
    let paymentID: UInt64
    let items: [ManifestItem]

    enum CodingKeys: String, CodingKey {
        case paymentID = "paymentId"
        case items
    }
}

private struct ManifestItem: Encodable {
    let evidenceType: UInt8
    let hash: String

    init(evidence: UploadedEvidence) {
        evidenceType = evidence.kind.rawValue
        hash = evidence.hash.value
    }

    enum CodingKeys: String, CodingKey {
        case evidenceType = "evType"
        case hash
    }
}

private struct ManifestResponse: Decodable {
    let paymentID: UInt64
    let matches: Bool
    let computedRoot: String
    let onchainRoot: String

    enum CodingKeys: String, CodingKey {
        case paymentID = "paymentId"
        case matches, computedRoot, onchainRoot
    }
}

private struct ErrorResponse: Decodable {
    let error: String
}

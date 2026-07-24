import Foundation

struct StoredOrderImage: Decodable, Sendable {
    let hash: String
    let size: Int
    let contentType: String
}

struct StoredOrderManifest: Decodable, Sendable {
    let orderRef: String
    let size: Int
}

enum OrderAPIError: Error, Equatable {
    case invalidResponse
    case rejected(status: Int, message: String)
}

// Client for the backend order store. Writes send raw bytes (the exact document or image
// that was hashed); reads re-verify content addressing where the expected hash is known,
// so a compromised backend can deny service but never alter an order unnoticed.
actor OrderAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func uploadImage(_ data: Data, contentType: String) async throws -> StoredOrderImage {
        let stored: StoredOrderImage = try await post(
            path: "api/orders/image",
            body: data,
            contentType: contentType
        )
        // The backend echoes the content hash; recompute locally so a wrong echo cannot
        // seed a manifest with an unverifiable image reference.
        guard stored.hash.lowercased() == data.keccak256Hash.value.lowercased() else {
            throw OrderAPIError.invalidResponse
        }
        return stored
    }

    func publishManifest(_ bytes: Data) async throws -> StoredOrderManifest {
        let stored: StoredOrderManifest = try await post(
            path: "api/orders",
            body: bytes,
            contentType: "application/json"
        )
        guard stored.orderRef.lowercased() == bytes.keccak256Hash.value.lowercased() else {
            throw OrderAPIError.invalidResponse
        }
        return stored
    }

    // Raw bytes on purpose: the caller verifies keccak256(bytes) == orderRef before
    // parsing anything out of the document.
    func fetchManifestBytes(orderReference: ChainHash) async throws -> Data {
        try await get(path: "api/orders/\(orderReference.value)")
    }

    // Image bytes are verified against the manifest's imageHash here, so callers only
    // ever see an image the manifest actually committed to.
    func fetchImage(hash: String) async throws -> Data {
        let data = try await get(path: "api/orders/image/\(hash)")
        guard data.keccak256Hash.value.lowercased() == hash.lowercased() else {
            throw OrderManifestError.imageHashMismatch
        }
        return data
    }

    private func post<Response: Decodable>(
        path: String,
        body: Data,
        contentType: String
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Self.check(response: response, data: data)
        return try decoder.decode(Response.self, from: data)
    }

    private func get(path: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try Self.check(response: response, data: data)
        return data
    }

    private static func check(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OrderAPIError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.error
            throw OrderAPIError.rejected(
                status: http.statusCode,
                message: message ?? "Request failed"
            )
        }
    }
}

private struct APIErrorBody: Decodable {
    let error: String
}

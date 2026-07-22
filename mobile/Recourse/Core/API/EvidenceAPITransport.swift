import Foundation

struct EvidenceHTTPRequest: Sendable {
    enum Method: String, Sendable {
        case post = "POST"
    }

    let method: Method
    let path: String
    let headers: [String: String]
    let body: Data
}

struct EvidenceHTTPResponse: Sendable {
    let statusCode: Int
    let body: Data
}

protocol EvidenceAPITransport: Sendable {
    func execute(_ request: EvidenceHTTPRequest, baseURL: URL) async throws -> EvidenceHTTPResponse
}

actor URLSessionEvidenceAPITransport: EvidenceAPITransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func execute(_ request: EvidenceHTTPRequest, baseURL: URL) async throws -> EvidenceHTTPResponse {
        guard let url = URL(string: request.path, relativeTo: baseURL) else {
            throw EvidenceAPIError.invalidURL
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        request.headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }

        let (body, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EvidenceAPIError.invalidResponse
        }
        return EvidenceHTTPResponse(statusCode: httpResponse.statusCode, body: body)
    }
}

import Foundation

/// The account's Safe as the server knows it.
struct SmartAccountRecord: Codable, Equatable, Sendable {
    let safe: String
    let cloudOwner: String
    let deviceOwner: String
    let deviceX: String
    let deviceY: String
    let recoveryOwner: String
    let threshold: Int
    let status: String
    let entryPoint: String
    let module: String

    var isLive: Bool { status == "live" }
}

struct RecoveryCodeIssued: Decodable, Equatable, Sendable {
    let expiresAt: String
    let sentTo: String
}

struct RecoveryGrant: Decodable, Equatable, Sendable {
    let grantId: String
    let expiresAt: String
}

/// The swap the server staged: what the Cloud Key signs, and the owner it moves to.
struct DeviceRotationPlan: Decodable, Equatable, Sendable {
    let rotationId: Int64
    let safeTxHash: String
    let oldDeviceOwner: String
    let newDeviceOwner: String
    let prevOwner: String
    let safeNonce: String
}

struct DeviceRotationOutcome: Decodable, Equatable, Sendable {
    let txHash: String
    let deviceOwner: String
}

enum SmartAccountAPIError: Error, Equatable {
    case invalidResponse
    /// No Safe yet. The ordinary answer on a fresh account.
    case none
    case rejected(status: Int, message: String)

    var message: String {
        switch self {
        case .invalidResponse: return "Could not reach your account."
        case .none: return "This account has no wallet yet."
        case .rejected(_, let message): return message
        }
    }
}

protocol SmartAccountAPI: Sendable {
    func current(accessToken: String) async throws -> SmartAccountRecord
    func provision(cloudOwner: String, deviceKey: DevicePublicKey, accessToken: String) async throws -> SmartAccountRecord
    func requestRecoveryCode(accessToken: String) async throws -> RecoveryCodeIssued
    func verifyRecoveryCode(_ code: String, accessToken: String) async throws -> RecoveryGrant
    func prepareDeviceSwap(grantID: String, deviceKey: DevicePublicKey, accessToken: String) async throws -> DeviceRotationPlan
    func executeDeviceSwap(rotationID: Int64, cloudSignature: Data, accessToken: String) async throws -> DeviceRotationOutcome
}

actor SmartAccountAPIClient: SmartAccountAPI {
    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func current(accessToken: String) async throws -> SmartAccountRecord {
        try await request("GET", "api/me/account", body: nil, accessToken: accessToken)
    }

    func provision(cloudOwner: String, deviceKey: DevicePublicKey, accessToken: String) async throws -> SmartAccountRecord {
        try await request("POST", "api/me/account/provision", body: [
            "cloudOwner": cloudOwner,
            "deviceKey": ["x": deviceKey.xHex, "y": deviceKey.yHex],
        ], accessToken: accessToken)
    }

    func requestRecoveryCode(accessToken: String) async throws -> RecoveryCodeIssued {
        try await request("POST", "api/me/account/recovery/code", body: [:], accessToken: accessToken)
    }

    func verifyRecoveryCode(_ code: String, accessToken: String) async throws -> RecoveryGrant {
        try await request("POST", "api/me/account/recovery/verify", body: ["code": code], accessToken: accessToken)
    }

    func prepareDeviceSwap(grantID: String, deviceKey: DevicePublicKey, accessToken: String) async throws -> DeviceRotationPlan {
        try await request("POST", "api/me/account/device/prepare", body: [
            "grantId": grantID,
            "deviceKey": ["x": deviceKey.xHex, "y": deviceKey.yHex],
        ], accessToken: accessToken)
    }

    func executeDeviceSwap(rotationID: Int64, cloudSignature: Data, accessToken: String) async throws -> DeviceRotationOutcome {
        try await request("POST", "api/me/account/device/execute", body: [
            "rotationId": rotationID,
            "cloudSignature": cloudSignature.hexString,
        ], accessToken: accessToken)
    }

    private func request<Response: Decodable>(
        _ method: String,
        _ path: String,
        body: [String: Any]?,
        accessToken: String
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SmartAccountAPIError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            if http.statusCode == 404 { throw SmartAccountAPIError.none }
            let message = (try? JSONDecoder().decode(APIFailure.self, from: data))?.error
            throw SmartAccountAPIError.rejected(
                status: http.statusCode,
                message: message ?? "Your account refused that (\(http.statusCode))."
            )
        }
        guard let decoded = try? decoder.decode(Response.self, from: data) else {
            throw SmartAccountAPIError.invalidResponse
        }
        return decoded
    }
}

private struct APIFailure: Decodable {
    let error: String
}

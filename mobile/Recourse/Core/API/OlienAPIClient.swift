import Foundation

/// A treasury the signed-in account is a member of, as its list row.
struct OlienSummary: Codable, Equatable, Sendable, Identifiable {
    let address: String
    let name: String
    let status: String
    let threshold: Int
    let signerCount: Int
    /// Base units as a decimal string; a treasury balance outgrows a JSON number.
    let usdcBalance: String
    let openProposals: Int
    let scheduledChanges: Int
    let createdAt: Int64

    var id: String { address.lowercased() }
    var usdc: USDCAmount { USDCAmount(baseUnits: UInt64(usdcBalance) ?? 0) }
    var shortAddress: String { shortened(address) }
    var displayName: String { name.isEmpty ? shortAddress : name }
}

/// One member of a treasury. `kind` is the curve or contract the account checks
/// signatures against; people read it as the word.
struct OlienSigner: Codable, Equatable, Sendable, Identifiable {
    let signerId: String
    let kind: String
    let address: String?
    let label: String
    let permissions: [String]
    let since: Int64
    let mine: Bool

    var id: String { signerId.lowercased() }
    var canApprove: Bool { permissions.contains("approve") }
    var canVeto: Bool { permissions.contains("veto") }

    var kindWord: String {
        switch kind {
        case "ecdsa": "Wallet"
        case "webauthn": "Passkey"
        case "p256": "P-256"
        case "contract": "Account"
        default: kind
        }
    }

    var displayName: String {
        if !label.isEmpty { return label }
        if let address { return shortened(address) }
        return String(signerId.prefix(10))
    }
}

struct OlienAccountMembership: Codable, Equatable, Sendable {
    let creator: Bool
    let signerIds: [String]
}

/// A treasury as its home screen needs it: rules, members and who the caller is
/// among them. The service sends more (limits, lanes, sub-accounts); the phone
/// decodes what it shows.
struct OlienAccount: Codable, Equatable, Sendable, Identifiable {
    let address: String
    let name: String
    let status: String
    let chainId: Int64
    let epoch: Int64
    let threshold: Int
    let vetoThreshold: Int
    let effectiveVetoThreshold: Int
    let configDelay: Int64
    let signers: [OlienSigner]
    let usdcBalance: String
    let createdAt: Int64
    let membership: OlienAccountMembership

    var id: String { address.lowercased() }
    var usdc: USDCAmount { USDCAmount(baseUnits: UInt64(usdcBalance) ?? 0) }
    var shortAddress: String { shortened(address) }
    var displayName: String { name.isEmpty ? shortAddress : name }

    func signer(id signerID: String) -> OlienSigner? {
        signers.first { $0.signerId.lowercased() == signerID.lowercased() }
    }
}

struct OlienCall: Codable, Equatable, Sendable {
    let to: String
    let value: String
    let data: String
}

struct OlienDecodedCall: Codable, Equatable, Sendable {
    let to: String
    let label: String
    let summary: String
    let selector: String
    let readable: Bool
}

struct OlienConfirmation: Codable, Equatable, Sendable, Identifiable {
    let signerId: String
    let address: String?
    let label: String
    /// `offchain` for a stored signature, `onchain` for an `approve` call.
    let kind: String
    let signedAt: Int64

    var id: String { signerId.lowercased() }
    var signedDate: Date { Date(timeIntervalSince1970: TimeInterval(signedAt)) }
}

struct OlienMissingSigner: Codable, Equatable, Sendable, Identifiable {
    let signerId: String
    let label: String
    let mine: Bool

    var id: String { signerId.lowercased() }
}

struct OlienHardRule: Codable, Equatable, Sendable {
    let rule: String
    let seconds: Int64
    let text: String
}

struct OlienSimulation: Codable, Equatable, Sendable {
    let ok: Bool
    let error: String?
    let checkedAt: Int64
}

struct OlienVeto: Codable, Equatable, Sendable, Identifiable {
    let signerId: String
    let label: String
    let tx: String
    let at: Int64

    var id: String { signerId.lowercased() }
}

struct OlienProposer: Codable, Equatable, Sendable {
    let accountId: Int64
    let name: String
}

/// One line of a payment's intent, as the proposer wrote it.
struct OlienRecipient: Equatable, Sendable {
    let to: String
    let amount: String
    let label: String?
    let memo: String?

    var usdc: USDCAmount { USDCAmount(baseUnits: UInt64(amount) ?? 0) }
    var displayName: String {
        if let label, !label.isEmpty { return label }
        return shortened(to)
    }
}

/// Where a proposal stands, in the service's words. Unknown words decode rather
/// than fail, so a status added on the server does not blank the whole queue.
enum OlienProposalStatus: String, Codable, Sendable, Equatable {
    case open
    case ready
    case blocked
    case executing
    case executed
    case scheduled
    case vetoed
    case cancelled
    case replaced
    case stale
    case expired
    case failed
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }

    /// Still able to move: collecting approvals, or waiting for the relayer.
    var isActive: Bool {
        switch self {
        case .open, .ready, .blocked, .executing: true
        default: false
        }
    }

    var word: String {
        switch self {
        case .open: "Open"
        case .ready: "Ready"
        case .blocked: "Blocked"
        case .executing: "Executing"
        case .executed: "Done"
        case .scheduled: "Scheduled"
        case .vetoed: "Vetoed"
        case .cancelled: "Cancelled"
        case .replaced: "Replaced"
        case .stale: "Stale"
        case .expired: "Expired"
        case .failed: "Failed"
        case .unknown: "Unknown"
        }
    }
}

/// A proposal as the service shows it, with what the phone needs to act on it:
/// the decoded calls to read, the confirmations to count, and the typed data to
/// hash before anything is signed.
struct OlienProposal: Codable, Equatable, Sendable, Identifiable {
    let txHash: String
    let account: String
    let nonceKey: String
    let sequence: Int64
    let nonce: String
    let epoch: Int64
    let kind: String
    let intent: JSONValue
    let calls: [OlienCall]
    let decoded: [OlienDecodedCall]
    let validAfter: Int64
    let validUntil: Int64
    let path: String
    let status: OlienProposalStatus
    let confirmations: [OlienConfirmation]
    let required: Int
    let approvals: Int
    let missing: [OlienMissingSigner]
    let blockedBy: Int64?
    let hardRules: [OlienHardRule]
    let simulation: OlienSimulation?
    let scheduledReadyAt: Int64?
    let scheduledWindowEndsAt: Int64?
    let scheduledExcluded: String?
    let vetoes: [OlienVeto]
    let effectiveVetoThreshold: Int
    let executedTx: String?
    let executedAt: Int64?
    let failure: String?
    let proposer: OlienProposer?
    let createdAt: Int64
    /// Kept as JSON rather than a typed struct so the phone hashes exactly what the
    /// service would hand a wallet, field for field.
    let typedData: JSONValue

    var id: String { txHash.lowercased() }
    var createdDate: Date { Date(timeIntervalSince1970: TimeInterval(createdAt)) }
    var scheduledReadyDate: Date? { scheduledReadyAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    var scheduledWindowEndsDate: Date? { scheduledWindowEndsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } }

    /// The typed data as bytes for the EIP-712 parser.
    func typedDataJSON() throws -> Data {
        try typedData.serialized()
    }

    var recipients: [OlienRecipient] {
        guard let rows = intent["recipients"]?.array else { return [] }
        return rows.compactMap { row in
            guard let to = row["to"]?.string, let amount = row["amount"]?.string else { return nil }
            return OlienRecipient(to: to, amount: amount, label: row["label"]?.string, memo: row["memo"]?.string)
        }
    }

    var total: USDCAmount {
        USDCAmount(baseUnits: recipients.reduce(into: UInt64(0)) {
            $0 = $0.addingReportingOverflow($1.usdc.baseUnits).partialValue
        })
    }

    /// The first memo anyone wrote on it.
    var memo: String? {
        recipients.compactMap(\.memo).first { !$0.isEmpty }
    }

    var kindWord: String {
        switch kind {
        case "transfer": "Payment"
        case "batch": "Batch payment"
        case "signer_change": "Member change"
        case "rule_change": "Rule change"
        case "limit_change": "Spending limit"
        case "cancel": "Cancellation"
        case "contract_call": "Contract call"
        default: kind
        }
    }

    /// What the proposal does, in one line a member can approve on sight.
    var intentLine: String {
        let recipients = recipients
        if recipients.count == 1, let only = recipients.first {
            return "Send \(only.usdc.decimalString) USDC to \(only.displayName)"
        }
        if recipients.count > 1 {
            return "Send \(total.decimalString) USDC to \(recipients.count) recipients"
        }
        return kindWord
    }

    var approvalsText: String { "\(approvals) of \(required)" }

    func hasConfirmation(from signerID: String) -> Bool {
        confirmations.contains { $0.signerId.lowercased() == signerID.lowercased() }
    }

    func isMissing(_ signerID: String) -> Bool {
        missing.contains { $0.signerId.lowercased() == signerID.lowercased() }
    }

    func hasVeto(from signerID: String) -> Bool {
        vetoes.contains { $0.signerId.lowercased() == signerID.lowercased() }
    }
}

/// What a member's own wallet sends to veto a scheduled change.
struct VetoCall: Codable, Equatable, Sendable {
    let to: String
    let data: String
    let signerIds: [String]
}

/// JSON kept as JSON. Integers stay integers through a round trip, which is what
/// lets typed data be re-serialised for hashing without a `1` turning into `1.0`.
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    subscript(key: String) -> JSONValue? {
        guard case .object(let fields) = self else { return nil }
        return fields[key]
    }

    var string: String? {
        switch self {
        case .string(let value): value
        case .integer(let value): String(value)
        default: nil
        }
    }

    var array: [JSONValue]? {
        guard case .array(let values) = self else { return nil }
        return values
    }

    /// The Foundation shape `JSONSerialization` writes, with Swift numbers so a bool
    /// stays a bool and an integer an integer.
    var foundationObject: Any {
        switch self {
        case .null: NSNull()
        case .bool(let value): value
        case .integer(let value): value
        case .number(let value): value
        case .string(let value): value
        case .array(let values): values.map(\.foundationObject)
        case .object(let fields): fields.mapValues(\.foundationObject)
        }
    }

    func serialized() throws -> Data {
        try JSONSerialization.data(withJSONObject: foundationObject, options: [.sortedKeys])
    }
}

enum OlienAPIError: Error, Equatable {
    case invalidResponse
    case rejected(status: Int, message: String)

    var message: String {
        switch self {
        case .invalidResponse: "Could not reach your teams."
        case .rejected(_, let message): message
        }
    }
}

protocol OlienAPI: Sendable {
    func accounts(accessToken: String) async throws -> [OlienSummary]
    func account(address: String, accessToken: String) async throws -> OlienAccount
    /// `statuses` nil means every proposal the service keeps (the latest 200).
    func proposals(account: String, statuses: [String]?, accessToken: String) async throws -> [OlienProposal]
    func proposal(account: String, txHash: String, accessToken: String) async throws -> OlienProposal
    func confirm(account: String, txHash: String, signerID: String, signature: String, accessToken: String) async throws -> OlienProposal
    func execute(account: String, txHash: String, accessToken: String) async throws -> OlienProposal
    func vetoCall(account: String, txHash: String, accessToken: String) async throws -> VetoCall
    func executeScheduled(account: String, txHash: String, accessToken: String) async throws -> OlienProposal
}

actor OlienAPIClient: OlienAPI {
    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func accounts(accessToken: String) async throws -> [OlienSummary] {
        try await get("api/treasury/accounts", accessToken: accessToken)
    }

    func account(address: String, accessToken: String) async throws -> OlienAccount {
        try await get("api/treasury/accounts/\(address.lowercased())", accessToken: accessToken)
    }

    func proposals(account: String, statuses: [String]?, accessToken: String) async throws -> [OlienProposal] {
        let query = statuses.map { [URLQueryItem(name: "status", value: $0.joined(separator: ","))] } ?? []
        return try await get("api/treasury/accounts/\(account.lowercased())/proposals", query: query, accessToken: accessToken)
    }

    func proposal(account: String, txHash: String, accessToken: String) async throws -> OlienProposal {
        try await get(proposalPath(account, txHash), accessToken: accessToken)
    }

    func confirm(account: String, txHash: String, signerID: String, signature: String, accessToken: String) async throws -> OlienProposal {
        struct Body: Encodable {
            let signerId: String
            let signature: String
        }
        return try await post(
            proposalPath(account, txHash) + "/confirmations",
            body: try encoder.encode(Body(signerId: signerID, signature: signature)),
            accessToken: accessToken
        )
    }

    func execute(account: String, txHash: String, accessToken: String) async throws -> OlienProposal {
        try await post(proposalPath(account, txHash) + "/execute", body: nil, accessToken: accessToken)
    }

    func vetoCall(account: String, txHash: String, accessToken: String) async throws -> VetoCall {
        try await get(scheduledPath(account, txHash) + "/veto-call", accessToken: accessToken)
    }

    func executeScheduled(account: String, txHash: String, accessToken: String) async throws -> OlienProposal {
        try await post(scheduledPath(account, txHash) + "/execute", body: nil, accessToken: accessToken)
    }

    private func proposalPath(_ account: String, _ txHash: String) -> String {
        "api/treasury/accounts/\(account.lowercased())/proposals/\(txHash.lowercased())"
    }

    private func scheduledPath(_ account: String, _ txHash: String) -> String {
        "api/treasury/accounts/\(account.lowercased())/scheduled/\(txHash.lowercased())"
    }

    private func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = [], accessToken: String) async throws -> Response {
        let data = try await send(path: path, query: query, method: "GET", body: nil, accessToken: accessToken)
        return try decode(data)
    }

    private func post<Response: Decodable>(_ path: String, body: Data?, accessToken: String) async throws -> Response {
        let data = try await send(path: path, query: [], method: "POST", body: body, accessToken: accessToken)
        return try decode(data)
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        guard let decoded = try? decoder.decode(Response.self, from: data) else {
            throw OlienAPIError.invalidResponse
        }
        return decoded
    }

    private func send(path: String, query: [URLQueryItem], method: String, body: Data?, accessToken: String) async throws -> Data {
        var url = baseURL.appending(path: path)
        if !query.isEmpty {
            url.append(queryItems: query)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OlienAPIError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw OlienAPIError.rejected(
                status: http.statusCode,
                message: Self.errorMessage(from: data) ?? "The treasury service refused that (\(http.statusCode))."
            )
        }
        return data
    }

    private static func errorMessage(from data: Data) -> String? {
        struct Failure: Decodable { let error: String }
        return try? JSONDecoder().decode(Failure.self, from: data).error
    }
}

/// `0x1234…abcd`, tolerant of anything that is not an address so a bad row still
/// renders something rather than crashing a list.
private func shortened(_ address: String) -> String {
    guard address.count > 12 else { return address }
    return "\(address.prefix(6))…\(address.suffix(4))"
}

import Foundation
@preconcurrency import BigInt

/// The ERC-4337 bundler that carries the account's operations to the EntryPoint.
///
/// Three calls: price the operation, estimate its gas, send it, then wait for the
/// receipt. The account pays for everything from its own USDC balance, so there is
/// no paymaster field anywhere here.
protocol BundlerTransport: Sendable {
    func gasPrice() async throws -> BundlerGasPrice
    func estimate(_ operation: UserOperation, entryPoint: EthereumAddress) async throws -> UserOperationGas
    func send(_ operation: UserOperation, entryPoint: EthereumAddress) async throws -> ChainHash
    func receipt(operationHash: ChainHash) async throws -> UserOperationReceipt?
}

struct BundlerGasPrice: Hashable, Sendable {
    let maxFeePerGas: BigUInt
    let maxPriorityFeePerGas: BigUInt
}

struct UserOperationGas: Hashable, Sendable {
    let callGasLimit: BigUInt
    let verificationGasLimit: BigUInt
    let preVerificationGas: BigUInt
}

/// An EntryPoint v0.7 operation as the bundler's JSON-RPC takes it: unpacked fields,
/// no factory, no paymaster.
struct UserOperation: Hashable, Sendable {
    let sender: EthereumAddress
    let nonce: BigUInt
    let callData: Data
    var callGasLimit: BigUInt
    var verificationGasLimit: BigUInt
    var preVerificationGas: BigUInt
    var maxFeePerGas: BigUInt
    var maxPriorityFeePerGas: BigUInt
    var signature: Data
}

struct UserOperationReceipt: Hashable, Sendable {
    let success: Bool
    let transactionHash: ChainHash
    let actualGasCost: BigUInt
}

enum BundlerError: Error, Equatable {
    case transport(String)
    case rejected(String)
    case malformed(String)
    case receiptTimedOut
}

actor HTTPBundlerClient: BundlerTransport {
    private let url: URL
    private let session: URLSession

    init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    func gasPrice() async throws -> BundlerGasPrice {
        let result = try await call("pimlico_getUserOperationGasPrice", params: [])
        guard let fast = result["fast"] as? [String: Any],
              let maxFee = Self.quantity(fast["maxFeePerGas"]),
              let priority = Self.quantity(fast["maxPriorityFeePerGas"]) else {
            throw BundlerError.malformed("gas price")
        }
        return BundlerGasPrice(maxFeePerGas: maxFee, maxPriorityFeePerGas: priority)
    }

    func estimate(_ operation: UserOperation, entryPoint: EthereumAddress) async throws -> UserOperationGas {
        let result = try await call("eth_estimateUserOperationGas", params: [Self.encode(operation), entryPoint.value])
        guard let callGas = Self.quantity(result["callGasLimit"]),
              let verification = Self.quantity(result["verificationGasLimit"]),
              let preVerification = Self.quantity(result["preVerificationGas"]) else {
            throw BundlerError.malformed("gas estimate")
        }
        return UserOperationGas(
            callGasLimit: callGas,
            verificationGasLimit: verification,
            preVerificationGas: preVerification
        )
    }

    func send(_ operation: UserOperation, entryPoint: EthereumAddress) async throws -> ChainHash {
        let result = try await callRaw("eth_sendUserOperation", params: [Self.encode(operation), entryPoint.value])
        guard let hash = result as? String else { throw BundlerError.malformed("operation hash") }
        return try ChainHash(hash)
    }

    func receipt(operationHash: ChainHash) async throws -> UserOperationReceipt? {
        let result = try await callRaw("eth_getUserOperationReceipt", params: [operationHash.value])
        guard let object = result as? [String: Any] else { return nil }
        guard let success = object["success"] as? Bool,
              let inner = object["receipt"] as? [String: Any],
              let transactionHash = inner["transactionHash"] as? String,
              let cost = Self.quantity(object["actualGasCost"]) else {
            throw BundlerError.malformed("receipt")
        }
        return UserOperationReceipt(
            success: success,
            transactionHash: try ChainHash(transactionHash),
            actualGasCost: cost
        )
    }

    // MARK: JSON-RPC

    private func call(_ method: String, params: [Any]) async throws -> [String: Any] {
        guard let object = try await callRaw(method, params: params) as? [String: Any] else {
            throw BundlerError.malformed(method)
        }
        return object
    }

    private func callRaw(_ method: String, params: [Any]) async throws -> Any? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params,
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw BundlerError.transport("bundler answered \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BundlerError.malformed("envelope")
        }
        if let error = envelope["error"] as? [String: Any] {
            // The bundler explains simulation failures in the message; it is the one
            // useful thing to show.
            throw BundlerError.rejected((error["message"] as? String) ?? "unknown bundler error")
        }
        return envelope["result"]
    }

    private static func encode(_ operation: UserOperation) -> [String: String] {
        [
            "sender": operation.sender.value,
            "nonce": hex(operation.nonce),
            "callData": operation.callData.hexString,
            "callGasLimit": hex(operation.callGasLimit),
            "verificationGasLimit": hex(operation.verificationGasLimit),
            "preVerificationGas": hex(operation.preVerificationGas),
            "maxFeePerGas": hex(operation.maxFeePerGas),
            "maxPriorityFeePerGas": hex(operation.maxPriorityFeePerGas),
            "signature": operation.signature.hexString,
        ]
    }

    private static func hex(_ value: BigUInt) -> String {
        "0x" + String(value, radix: 16)
    }

    private static func quantity(_ value: Any?) -> BigUInt? {
        guard let text = value as? String, text.hasPrefix("0x") else { return nil }
        return BigUInt(text.dropFirst(2), radix: 16)
    }
}

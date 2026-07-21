import Foundation

protocol ArcRPCTransport: Sendable {
    func call(to address: EthereumAddress, data: Data) async throws -> Data
}

actor HTTPArcRPCTransport: ArcRPCTransport, ArcTransactionTransport {
    private let rpcURL: URL
    private let session: URLSession
    private var nextRequestID = 1

    init(rpcURL: URL, session: URLSession = .shared) {
        self.rpcURL = rpcURL
        self.session = session
    }

    func call(to address: EthereumAddress, data: Data) async throws -> Data {
        let payload = RPCRequest(
            id: takeRequestID(),
            method: "eth_call",
            parameters: [
                .call(to: address.value, data: data.hexString),
                .string("latest")
            ]
        )
        let rpcResponse = try await stringResponse(for: payload)
        guard let result = rpcResponse.result,
              let resultData = Data(hexString: result) else {
            throw ContractReadError.invalidRPCResponse
        }
        return resultData
    }

    func prepareTransaction(
        from: EthereumAddress,
        to: EthereumAddress,
        data: Data,
        chainID: UInt64
    ) async throws -> UnsignedTransaction {
        let nonce = try await quantity(
            method: "eth_getTransactionCount",
            parameters: [.string(from.value), .string("pending")]
        )
        let estimatedGas = try await quantity(
            method: "eth_estimateGas",
            parameters: [.transaction(from: from.value, to: to.value, data: data.hexString)]
        )
        let gasPrice = try await quantity(method: "eth_gasPrice", parameters: [])
        let margin = max(estimatedGas / 5, 1_000)
        let (gasLimit, overflow) = estimatedGas.addingReportingOverflow(margin)
        guard !overflow else {
            throw ContractReadError.integerOverflow(method: "eth_estimateGas")
        }

        return UnsignedTransaction(
            chainID: chainID,
            from: from,
            to: to,
            nonce: nonce,
            gasLimit: gasLimit,
            gasPrice: gasPrice,
            data: data
        )
    }

    func send(rawTransaction: Data) async throws -> ChainHash {
        let response = try await stringResponse(
            for: RPCRequest(
                id: takeRequestID(),
                method: "eth_sendRawTransaction",
                parameters: [.string(rawTransaction.hexString)]
            )
        )
        guard let hash = response.result else {
            throw ContractReadError.invalidRPCResponse
        }
        return try ChainHash(hash)
    }

    func receipt(transactionHash: ChainHash) async throws -> TransactionReceiptRecord? {
        let payload = RPCRequest(
            id: takeRequestID(),
            method: "eth_getTransactionReceipt",
            parameters: [.string(transactionHash.value)]
        )
        let responseData = try await responseData(for: payload)
        let rpcResponse = try JSONDecoder().decode(ReceiptRPCResponse.self, from: responseData)
        if let error = rpcResponse.error {
            throw ContractReadError.rpc(code: error.code, message: error.message)
        }
        guard let receipt = rpcResponse.result else { return nil }

        let logs = try receipt.logs.map { log in
            TransactionLogRecord(
                address: try EthereumAddress(log.address),
                topics: try log.topics.map { try ChainHash($0) }
            )
        }
        return TransactionReceiptRecord(
            transactionHash: try ChainHash(receipt.transactionHash),
            outcome: receipt.status == "0x1" ? .confirmed : .reverted,
            logs: logs
        )
    }

    private func quantity(method: String, parameters: [RPCParameter]) async throws -> UInt64 {
        let response = try await stringResponse(
            for: RPCRequest(id: takeRequestID(), method: method, parameters: parameters)
        )
        guard let result = response.result,
              result.hasPrefix("0x"),
              let value = UInt64(result.dropFirst(2), radix: 16) else {
            throw ContractReadError.integerOverflow(method: method)
        }
        return value
    }

    private func stringResponse(for payload: RPCRequest) async throws -> StringRPCResponse {
        let responseData = try await responseData(for: payload)
        let rpcResponse = try JSONDecoder().decode(StringRPCResponse.self, from: responseData)
        if let error = rpcResponse.error {
            throw ContractReadError.rpc(code: error.code, message: error.message)
        }
        return rpcResponse
    }

    private func responseData(for payload: RPCRequest) async throws -> Data {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else {
            throw ContractReadError.invalidRPCResponse
        }

        return responseData
    }

    private func takeRequestID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }
}

private struct RPCRequest: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let parameters: [RPCParameter]

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method
        case parameters = "params"
    }
}

private enum RPCParameter: Encodable {
    case call(to: String, data: String)
    case transaction(from: String, to: String, data: String)
    case string(String)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .call(let to, let data):
            var container = encoder.container(keyedBy: CallKeys.self)
            try container.encode(to, forKey: .to)
            try container.encode(data, forKey: .data)
        case .transaction(let from, let to, let data):
            var container = encoder.container(keyedBy: CallKeys.self)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
            try container.encode(data, forKey: .data)
            try container.encode("0x0", forKey: .value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        }
    }

    private enum CallKeys: String, CodingKey {
        case from, to, data, value
    }
}

private struct StringRPCResponse: Decodable {
    let result: String?
    let error: RPCError?
}

private struct ReceiptRPCResponse: Decodable {
    let result: RPCTransactionReceipt?
    let error: RPCError?
}

private struct RPCTransactionReceipt: Decodable {
    let transactionHash: String
    let status: String
    let logs: [RPCTransactionLog]
}

private struct RPCTransactionLog: Decodable {
    let address: String
    let topics: [String]
}

private struct RPCError: Decodable {
    let code: Int
    let message: String
}

private extension Data {
    init?(hexString: String) {
        let value = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        guard value.count.isMultiple(of: 2) else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let nextIndex = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index ..< nextIndex], radix: 16) else { return nil }
            bytes.append(byte)
            index = nextIndex
        }
        self.init(bytes)
    }

    var hexString: String {
        "0x" + map { String(format: "%02x", $0) }.joined()
    }
}

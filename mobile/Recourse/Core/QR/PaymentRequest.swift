import Foundation

struct PaymentRequest: Codable, Hashable, Sendable {
    let version: UInt8
    let chainID: UInt64
    let escrow: EthereumAddress
    let policyID: UInt64
    let merchant: EthereumAddress
    let amount: USDCAmount
    let orderReference: ChainHash

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case chainID = "chainId"
        case escrow
        case policyID = "policyId"
        case merchant
        case amount
        case orderReference = "orderRef"
    }

    init(
        version: UInt8,
        chainID: UInt64,
        escrow: EthereumAddress,
        policyID: UInt64,
        merchant: EthereumAddress,
        amount: USDCAmount,
        orderReference: ChainHash
    ) {
        self.version = version
        self.chainID = chainID
        self.escrow = escrow
        self.policyID = policyID
        self.merchant = merchant
        self.amount = amount
        self.orderReference = orderReference
    }

    func validate(against configuration: AppConfiguration) throws {
        guard version == 1 else { throw ValidationError.unsupportedRequestVersion }
        guard chainID == configuration.chainID else { throw ValidationError.wrongChain }
        guard escrow.value.lowercased() == configuration.escrowAddress.value.lowercased() else {
            throw ValidationError.wrongEscrow
        }
    }
}

extension PaymentRequest {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(UInt8.self, forKey: .version)
        let chainID = try container.decode(UInt64.self, forKey: .chainID)
        let escrow = try EthereumAddress(container.decode(String.self, forKey: .escrow))
        let policyID = try container.decode(UInt64.self, forKey: .policyID)
        let merchant = try EthereumAddress(container.decode(String.self, forKey: .merchant))
        let amount = try USDCAmount(baseUnitString: container.decode(String.self, forKey: .amount))
        let orderReference = try ChainHash(container.decode(String.self, forKey: .orderReference))

        self.init(
            version: version,
            chainID: chainID,
            escrow: escrow,
            policyID: policyID,
            merchant: merchant,
            amount: amount,
            orderReference: orderReference
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(chainID, forKey: .chainID)
        try container.encode(escrow.value, forKey: .escrow)
        try container.encode(policyID, forKey: .policyID)
        try container.encode(merchant.value, forKey: .merchant)
        try container.encode(String(amount.baseUnits), forKey: .amount)
        try container.encode(orderReference.value, forKey: .orderReference)
    }
}

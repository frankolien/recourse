import Foundation

enum SendProgress: Equatable, Sendable {
    case validating
    case checkingFunds
    case submitted(ChainHash)
    case confirmed(ChainHash)
}

struct SendResult: Equatable, Sendable {
    let transactionHash: ChainHash
    let recipient: EthereumAddress
    let amount: USDCAmount
}

enum SendError: Error, Equatable {
    case zeroAmount
    case selfTransfer
    case insufficientBalance(available: USDCAmount)
    case transactionReverted(ChainHash)
}

// Direct person-to-person USDC transfer. Deliberately not the escrow path: there is no
// policy, no dispute window, and no recourse, which the UI states plainly. Everything
// else matches the app's transaction discipline: balance checked first, Face ID inside
// the signer boundary, and the receipt awaited before success is claimed.
struct SendWorkflow: Sendable {
    private let gateway: any ContractGateway

    init(gateway: any ContractGateway) {
        self.gateway = gateway
    }

    func execute(
        recipient: EthereumAddress,
        amount: USDCAmount,
        sender: EthereumAddress,
        onProgress: @escaping @Sendable (SendProgress) async -> Void = { _ in }
    ) async throws -> SendResult {
        await onProgress(.validating)
        guard amount.baseUnits > 0 else {
            throw SendError.zeroAmount
        }
        guard recipient.value.lowercased() != sender.value.lowercased() else {
            throw SendError.selfTransfer
        }

        await onProgress(.checkingFunds)
        let balance = try await gateway.usdcBalance(of: sender)
        guard balance >= amount else {
            throw SendError.insufficientBalance(available: balance)
        }

        let transactionHash = try await gateway.transferUSDC(to: recipient, amount: amount)
        await onProgress(.submitted(transactionHash))
        let receipt = try await gateway.waitForReceipt(transactionHash: transactionHash)
        guard receipt.outcome == .confirmed else {
            throw SendError.transactionReverted(transactionHash)
        }

        await onProgress(.confirmed(transactionHash))
        return SendResult(
            transactionHash: transactionHash,
            recipient: recipient,
            amount: amount
        )
    }
}

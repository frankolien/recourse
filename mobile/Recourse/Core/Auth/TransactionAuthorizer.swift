import Foundation
@preconcurrency import LocalAuthentication

protocol TransactionAuthorizing: Sendable {
    func authorizeTransaction() async throws
}

enum TransactionAuthorizationError: Error, Equatable, Sendable {
    case unavailable
    case cancelled
    case denied
}

actor DeviceOwnerTransactionAuthorizer: TransactionAuthorizing {
    private let reason: String

    init(reason: String = "Confirm this protected payment transaction.") {
        self.reason = reason
    }

    func authorizeTransaction() async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            throw TransactionAuthorizationError.unavailable
        }

        do {
            guard try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            ) else {
                throw TransactionAuthorizationError.denied
            }
        } catch let error as LAError {
            switch error.code {
            case .appCancel, .systemCancel, .userCancel:
                throw TransactionAuthorizationError.cancelled
            default:
                throw TransactionAuthorizationError.denied
            }
        }
    }
}

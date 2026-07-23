import Foundation

enum PaymentStatus: UInt8, Codable, Hashable, Sendable {
    case none = 0
    case paid = 1
    case disputed = 2
    case settled = 3
}

enum ClaimType: UInt8, Codable, CaseIterable, Hashable, Sendable {
    case notDelivered = 0
    case damaged = 1
    case notAsDescribed = 2
    case wrongItem = 3
    case other = 4
}

enum EvidenceKind: UInt8, Codable, CaseIterable, Hashable, Sendable {
    case photo = 1
    case description = 2
    case trackingReference = 4
    case video = 8
}

struct PolicyRecord: Codable, Hashable, Sendable {
    let id: UInt64
    let merchant: EthereumAddress
    let disputeWindow: UInt64
    let policyHash: ChainHash
}

struct PaymentRecord: Codable, Hashable, Sendable {
    let id: UInt64
    let buyer: EthereumAddress
    let merchant: EthereumAddress
    let beneficiary: EthereumAddress
    let policyID: UInt64
    let amount: USDCAmount
    let paidAt: UInt64
    let filedAt: UInt64
    let claimType: ClaimType?
    let evidenceMask: UInt16
    let attestationType: UInt8
    let attestationValue: UInt8
    let verdictBPS: UInt16
    let status: PaymentStatus
}

struct VerdictPreview: Codable, Hashable, Sendable {
    let refundBPS: UInt16
    let requiresReturn: Bool
    let ruleIndex: UInt8
    let matched: Bool
    let verdictHash: ChainHash

    func refundAmount(for paymentAmount: USDCAmount) -> USDCAmount {
        let basisPoints = UInt64(refundBPS)
        let quotient = paymentAmount.baseUnits / 10_000
        let remainder = paymentAmount.baseUnits % 10_000
        return USDCAmount(baseUnits: quotient * basisPoints + remainder * basisPoints / 10_000)
    }
}

struct EvidenceDraft: Hashable, Sendable {
    let kind: EvidenceKind
    let content: Data
    let contentType: String

    init(kind: EvidenceKind, content: Data, contentType: String? = nil) throws {
        guard !content.isEmpty else { throw BuyerWorkflowError.emptyEvidence }
        self.kind = kind
        self.content = content
        self.contentType = contentType ?? kind.defaultContentType
    }
}

struct UploadedEvidence: Codable, Hashable, Sendable {
    let kind: EvidenceKind
    let hash: ChainHash
}

struct EvidenceManifestReceipt: Codable, Hashable, Sendable {
    let paymentID: UInt64
    let matches: Bool
    let computedRoot: ChainHash
    let onchainRoot: ChainHash
}

private extension EvidenceKind {
    var defaultContentType: String {
        switch self {
        case .photo:
            "image/jpeg"
        case .description, .trackingReference:
            "text/plain; charset=utf-8"
        case .video:
            "video/mp4"
        }
    }
}

enum DemoPaymentState: String, CaseIterable, Hashable, Sendable {
    case protected = "Protected"
    case actionNeeded = "Action needed"
    case underReview = "Under review"
    case refunded = "Refunded"
    case released = "Completed"

    var systemImage: String {
        switch self {
        case .protected: "shield.checkered"
        case .actionNeeded: "exclamationmark.circle.fill"
        case .underReview: "clock.badge.checkmark"
        case .refunded: "arrow.uturn.backward.circle.fill"
        case .released: "checkmark.circle.fill"
        }
    }
}

struct DemoPayment: Identifiable, Hashable, Sendable {
    let id: UInt64
    let merchant: String
    let item: String
    let merchantSymbol: String
    let merchantImageURL: URL
    let amount: USDCAmount
    let date: Date
    let state: DemoPaymentState
    let policyName: String
    let protectionEnds: Date
    let progress: Double
    let orderReference: String

    var amountText: String { amount.formatted }
}

enum DemoCatalog {
    static let balance = USDCAmount(baseUnits: 2_480_500_000)
    static let escrowEarnings = USDCAmount(baseUnits: 1_240_000)

    static let payments: [DemoPayment] = [
        DemoPayment(
            id: 284,
            merchant: "MegaStore",
            item: "Noise-cancelling headphones",
            merchantSymbol: "shippingbox.fill",
            merchantImageURL: URL(string: "https://images.unsplash.com/photo-1586528116311-ad8dd3c8310d?auto=format&fit=crop&w=240&q=82")!,
            amount: USDCAmount(baseUnits: 186_000_000),
            date: date(daysAgo: 0, hour: 9),
            state: .actionNeeded,
            policyName: "Physical delivery protection",
            protectionEnds: date(daysAgo: -4, hour: 17),
            progress: 0.76,
            orderReference: "RC-284"
        ),
        DemoPayment(
            id: 281,
            merchant: "CloudCompute",
            item: "API Credits Pack",
            merchantSymbol: "cloud.fill",
            merchantImageURL: URL(string: "https://images.unsplash.com/photo-1558494949-ef010cbdcc31?auto=format&fit=crop&w=240&q=82")!,
            amount: USDCAmount(baseUnits: 24_000_000),
            date: date(daysAgo: 1, hour: 11),
            state: .protected,
            policyName: "Digital service protection",
            protectionEnds: date(daysAgo: -13, hour: 16),
            progress: 0.70,
            orderReference: "RC-281"
        ),
        DemoPayment(
            id: 279,
            merchant: "FileStore",
            item: "Pro Plan · Monthly",
            merchantSymbol: "externaldrive.fill",
            merchantImageURL: URL(string: "https://images.unsplash.com/photo-1450101499163-c8848c66ca85?auto=format&fit=crop&w=240&q=82")!,
            amount: USDCAmount(baseUnits: 120_000_000),
            date: date(daysAgo: 4, hour: 14),
            state: .protected,
            policyName: "Subscription protection",
            protectionEnds: date(daysAgo: -25, hour: 10),
            progress: 0.45,
            orderReference: "RC-279"
        ),
        DemoPayment(
            id: 272,
            merchant: "DesignVault",
            item: "Premium Assets",
            merchantSymbol: "paintbrush.pointed.fill",
            merchantImageURL: URL(string: "https://images.unsplash.com/photo-1498050108023-c5249f4df085?auto=format&fit=crop&w=240&q=82")!,
            amount: USDCAmount(baseUnits: 320_000_000),
            date: date(daysAgo: 8, hour: 18),
            state: .underReview,
            policyName: "Digital goods protection",
            protectionEnds: date(daysAgo: -2, hour: 12),
            progress: 0.92,
            orderReference: "RC-272"
        ),
        DemoPayment(
            id: 268,
            merchant: "Northstar Travel",
            item: "Airport transfer",
            merchantSymbol: "airplane.departure",
            merchantImageURL: URL(string: "https://images.unsplash.com/photo-1436491865332-7a61a109cc05?auto=format&fit=crop&w=240&q=82")!,
            amount: USDCAmount(baseUnits: 84_500_000),
            date: date(daysAgo: 15, hour: 7),
            state: .refunded,
            policyName: "Travel service protection",
            protectionEnds: date(daysAgo: 8, hour: 7),
            progress: 1,
            orderReference: "RC-268"
        ),
        DemoPayment(
            id: 261,
            merchant: "Arc Market",
            item: "Developer hardware kit",
            merchantSymbol: "cpu.fill",
            merchantImageURL: URL(string: "https://images.unsplash.com/photo-1518770660439-4636190af475?auto=format&fit=crop&w=240&q=82")!,
            amount: USDCAmount(baseUnits: 410_000_000),
            date: date(daysAgo: 24, hour: 12),
            state: .released,
            policyName: "Physical delivery protection",
            protectionEnds: date(daysAgo: 10, hour: 12),
            progress: 1,
            orderReference: "RC-261"
        )
    ]

    static func payment(id: UInt64) -> DemoPayment {
        payments.first(where: { $0.id == id }) ?? payments[0]
    }

    static func checkoutRequest(configuration: AppConfiguration) -> PaymentRequest {
        PaymentRequest(
            version: 1,
            chainID: configuration.chainID,
            escrow: configuration.escrowAddress,
            policyID: 12,
            merchant: EthereumAddress(trusted: "0x71c8a8e5f5070961e3198b3e8f7077f09d8f1180"),
            amount: USDCAmount(baseUnits: 56_000_000),
            orderReference: ChainHash(trusted: "0x75c13cb6de9d1095f3280c98d713cc511b59489c1e23a627e5c6b493f5c73a20")
        )
    }

    private static func date(daysAgo: Int, hour: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return calendar.date(bySettingHour: hour, minute: 20, second: 0, of: day) ?? day
    }
}

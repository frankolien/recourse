import Foundation
import Observation

/// UserDefaults keys for buyer-adjustable behavior. Central so the settings
/// screens, the send and checkout flows, and the transaction authorizer all
/// read the same names instead of scattering string literals.
enum BuyerSettingKey {
    static let paymentLimitBaseUnits = "recourse.paymentLimitBaseUnits"
    static let confirmPaymentsWithBiometrics = "recourse.confirmPaymentsWithBiometrics"
    static let addressBook = "recourse.addressBook"
}

enum PaymentLimit {
    /// A limit of zero means no limit: the toggle-off state needs a stored
    /// representation and no real cap is ever zero.
    static func exceeded(amount: USDCAmount, limitBaseUnits: Int) -> Bool {
        limitBaseUnits > 0 && amount.baseUnits > UInt64(limitBaseUnits)
    }

    static func formatted(baseUnits: Int) -> String {
        USDCAmount(baseUnits: UInt64(max(0, baseUnits))).formatted
    }
}

struct SavedRecipient: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var label: String
    var address: String
}

/// Named wallet addresses for the raw send flow, persisted on this device.
/// Deliberately not synced to the account: the address book names counterparties
/// of unprotected transfers, and keeping it device-local matches the wallet key
/// it is used with.
@MainActor
@Observable
final class AddressBookStore {
    private(set) var recipients: [SavedRecipient] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: BuyerSettingKey.addressBook),
           let decoded = try? JSONDecoder().decode([SavedRecipient].self, from: data) {
            recipients = decoded
        }
    }

    enum AddError: Error, Equatable {
        case invalidAddress
        case emptyLabel
        case duplicateAddress
    }

    func add(label: String, address: String) throws {
        let cleanedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedLabel.isEmpty else { throw AddError.emptyLabel }
        let cleanedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let validated = try? EthereumAddress(cleanedAddress) else {
            throw AddError.invalidAddress
        }
        guard !contains(address: validated.value) else { throw AddError.duplicateAddress }
        recipients.append(SavedRecipient(id: UUID(), label: cleanedLabel, address: validated.value))
        recipients.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        persist()
    }

    func remove(_ recipient: SavedRecipient) {
        recipients.removeAll { $0.id == recipient.id }
        persist()
    }

    func contains(address: String) -> Bool {
        recipient(for: address) != nil
    }

    func recipient(for address: String) -> SavedRecipient? {
        recipients.first { $0.address.lowercased() == address.lowercased() }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(recipients) {
            defaults.set(data, forKey: BuyerSettingKey.addressBook)
        }
    }
}

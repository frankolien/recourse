import Foundation

struct PaymentRequestDecoder: Sendable {
    private let configuration: AppConfiguration

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    func decode(base64URL value: String) throws -> PaymentRequest {
        var encoded = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)

        guard let data = Data(base64Encoded: encoded) else {
            throw ValidationError.invalidPaymentRequest
        }

        let request = try JSONDecoder().decode(PaymentRequest.self, from: data)
        try request.validate(against: configuration)
        return request
    }
}

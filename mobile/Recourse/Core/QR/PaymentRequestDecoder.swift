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

    /// Accepts every form a checkout arrives in: the bare base64url payload (older
    /// cards), the universal link the QR now encodes, or the custom recourse:// scheme.
    func decode(scanned value: String) throws -> PaymentRequest {
        try decode(base64URL: Self.payload(in: value))
    }

    // The payload may ride in a query item or in the URL fragment (a fragment never
    // reaches any server, so shared links leak nothing into web logs).
    static func payload(in value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed), components.scheme != nil else {
            return trimmed
        }
        let names = ["request", "payload", "code"]
        if let payload = components.queryItems?
            .first(where: { names.contains($0.name.lowercased()) })?
            .value,
            !payload.isEmpty {
            return payload
        }
        if let fragment = components.fragment, !fragment.isEmpty {
            if let equals = fragment.range(of: "=") {
                if names.contains(fragment[..<equals.lowerBound].lowercased()) {
                    return String(fragment[equals.upperBound...])
                }
            } else {
                return fragment
            }
        }
        return trimmed
    }
}

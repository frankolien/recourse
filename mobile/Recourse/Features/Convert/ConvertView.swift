import SwiftUI
@preconcurrency import BigInt

/// Convert USDC into EURC.
///
/// The screen's real job is the refusal. Arc's only public stablecoin pool quotes
/// 100 USDC at about 27 EURC where the market rate implies 87, so a Convert screen
/// that simply showed whatever the chain returned would take most of someone's
/// money while looking like it worked. Every quote here is checked against a
/// reference rate before it can be signed, and a bad one is explained rather than
/// hidden.
struct ConvertView: View {
    let reader: (any ContractReading)?
    /// EURC per USDC. Supplied rather than fetched so the check has an origin the
    /// venue cannot influence.
    var referencePrice: Double = 0.867

    @State private var amountText = ""
    @State private var quote: FXQuote?
    @State private var problem: String?
    @State private var quoting = false
    @FocusState private var amountFocused: Bool

    private var amount: USDCAmount? {
        guard let value = try? USDCAmount(decimalString: amountText), value.baseUnits > 0 else { return nil }
        return value
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(RecourseColor.nightText)
                    Text("USDC")
                        .font(.recourse(14, .bold))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
                .padding(.vertical, 6)
            } header: {
                Text("You convert")
            }

            Section {
                if quoting {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading the pool")
                            .font(.recourse(13))
                            .foregroundStyle(RecourseColor.nightMuted)
                    }
                } else if let quote {
                    HStack {
                        Text(EURCAmount(baseUnits: quote.amountOut).formatted)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(RecourseColor.ledger)
                        Spacer()
                        Text("EURC")
                            .font(.recourse(13, .bold))
                            .foregroundStyle(RecourseColor.nightMuted)
                    }
                    detail("Rate", String(format: "%.4f EURC per USDC", quote.price))
                    detail("Minimum received", EURCAmount(baseUnits: quote.minAmountOut).formatted)
                    if let deviation = quote.deviationBps {
                        detail("Versus market", deviation <= 0
                            ? "better by \(abs(deviation)) bps"
                            : "\(deviation) bps worse")
                    }
                } else {
                    Text("Enter an amount to see a quote.")
                        .font(.recourse(13))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
            } header: {
                Text("You receive")
            }

            if let problem {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(problem)
                            .font(.recourse(12))
                            .foregroundStyle(RecourseColor.nightMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RecourseColor.ledger)
                        .frame(width: 22)
                    Text("Every quote is compared against an independent rate before it can be signed. If the pool is too far off, the conversion is refused rather than filled quietly.")
                        .font(.recourse(12))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RecourseColor.night)
        .navigationTitle("Convert")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: amountText) {
            await refreshQuote()
        }
    }

    private func refreshQuote() async {
        quote = nil
        problem = nil
        guard let amount, let reader else { return }

        // Debounce: the field re-runs this on every keystroke and each pass is a
        // network read.
        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled { return }

        quoting = true
        defer { quoting = false }
        do {
            let out = try await reader.fxAmountOut(amountIn: amount)
            let candidate = try FX.quote(
                amountIn: BigUInt(amount.baseUnits),
                amountOut: out,
                decimalsIn: 6,
                decimalsOut: 6,
                referencePrice: referencePrice
            )
            try FX.assertSane(candidate)
            quote = candidate
        } catch let error as FXQuoteError {
            problem = describe(error)
        } catch {
            problem = "Could not read the pool. Check your connection and try again."
        }
    }

    private func describe(_ error: FXQuoteError) -> String {
        switch error {
        case .offMarket(let bps):
            // Named plainly, because the honest answer to "why can I not convert"
            // is that this pool is too thin for this size.
            return "This pool is \(String(format: "%.1f", Double(bps) / 100))% worse than the market rate at this size. Try a smaller amount."
        case .noLiquidity:
            return "This pool has nothing to give at that size."
        case .zeroAmount:
            return "Enter an amount above zero."
        case .badSlippage:
            return "Slippage tolerance is out of range."
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.recourse(12))
                .foregroundStyle(RecourseColor.nightMuted)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(RecourseColor.nightText)
        }
    }
}

/// EURC shares USDC's 6 decimals on Arc, but is a distinct unit and formatting it
/// through USDCAmount would put a dollar sign on euros.
struct EURCAmount: Equatable, Sendable {
    let baseUnits: UInt64

    init(baseUnits: BigUInt) {
        self.baseUnits = UInt64(clamping: baseUnits.description) ?? 0
    }

    var formatted: String {
        String(format: "%.4f", Double(baseUnits) / 1_000_000)
    }
}

private extension UInt64 {
    init?(clamping description: String) {
        guard let value = UInt64(description) else { return nil }
        self = value
    }
}

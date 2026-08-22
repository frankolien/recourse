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
///
/// Refusing well is a second job, and the first version did it badly. It said "try
/// a smaller amount" against a pool whose real ceiling was 0.40 USDC, which left
/// someone typing 18, 5, 1 and getting the same rejection each time. The ceiling is
/// read from the pool now and offered as one tap, because how deep a venue is
/// belongs on the screen rather than in the user's head.
struct ConvertView: View {
    let reader: (any ContractReading)?
    /// EURC per USDC. Supplied rather than fetched so the check has an origin the
    /// venue cannot influence.
    var referencePrice: Double = 0.867

    @State private var amountText = ""
    @State private var quote: FXQuote?
    @State private var problem: String?
    @State private var quoting = false
    @State private var ceiling: USDCAmount?
    @FocusState private var amountFocused: Bool

    private var amount: USDCAmount? {
        guard let value = try? USDCAmount(decimalString: amountText), value.baseUnits > 0 else { return nil }
        return value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Grouped so the field, the ceiling chip and the glyph blend as one
                // system when they come near each other, rather than as three panes
                // that happen to be adjacent.
                VStack(alignment: .leading, spacing: 0) {
                    converting
                    receiving
                }
                .recourseGlassGroup()

                if let problem {
                    refusal(problem)
                }
                details
                assurance
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(RecourseColor.night)
        .navigationTitle("Convert")
        .navigationBarTitleDisplayMode(.inline)
        .recourseKeyboardDismissal()
        .task {
            await loadCeiling()
        }
        .task(id: amountText) {
            await refreshQuote()
        }
    }

    // MARK: Sections

    private var converting: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldLabel("You convert")

            HStack(spacing: 12) {
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(RecourseColor.nightText)
                Text("USDC")
                    .font(.recourse(14, .bold))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
            .padding(.horizontal, 18)
            .frame(height: 76)
            .recourseGlassField()

            if let ceiling {
                ceilingChip(ceiling)
            }
        }
    }

    private var receiving: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The glyph sits between the two amounts rather than above the second,
            // because it describes the relationship and not the field.
            directionGlyph
                .padding(.leading, 4)

            fieldLabel("You receive")

            HStack(spacing: 12) {
                Group {
                    if quoting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(RecourseColor.nightMuted)
                    } else if let quote {
                        Text(EURCAmount(baseUnits: quote.amountOut).formatted)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(RecourseColor.ledger)
                            .contentTransition(.numericText())
                    } else {
                        Text("0.00")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(RecourseColor.nightMuted.opacity(0.5))
                    }
                }
                Spacer(minLength: 0)
                Text("EURC")
                    .font(.recourse(14, .bold))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
            .padding(.horizontal, 18)
            .frame(height: 76)
            .recourseGlassField()
            .animation(.snappy(duration: 0.24), value: quote)
        }
        .padding(.top, 14)
    }

    @ViewBuilder
    private var details: some View {
        if let quote {
            VStack(spacing: 0) {
                detail("Rate", String(format: "%.4f EURC per USDC", quote.price))
                divider
                detail("Minimum received", EURCAmount(baseUnits: quote.minAmountOut).formatted)
                if let deviation = quote.deviationBps {
                    divider
                    detail("Versus market", deviation <= 0
                        ? "better by \(abs(deviation)) bps"
                        : "\(deviation) bps worse")
                }
            }
            .padding(.top, 28)
        }
    }

    private var assurance: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
                .frame(width: 18)
            Text("Every quote is compared against an independent rate before it can be signed. If the pool is too far off, the conversion is refused rather than filled quietly.")
                .font(.recourse(12))
                .foregroundStyle(RecourseColor.nightMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 32)
    }

    // MARK: Pieces

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.recourse(11, .semibold))
            .kerning(0.8)
            .foregroundStyle(RecourseColor.nightMuted)
    }

    /// The whole point of the screen's second job: the ceiling is a number, so show
    /// the number and let it be tapped.
    private func ceilingChip(_ ceiling: USDCAmount) -> some View {
        Button {
            amountText = ceiling.decimalString
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.up.to.line.compact")
                    .font(.system(size: 10, weight: .bold))
                Text("Max \(ceiling.decimalString)")
                    .font(.recourse(12, .semibold))
            }
            .foregroundStyle(RecourseColor.nightText)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .recourseGlassCapsule()
        .accessibilityLabel("Convert the maximum, \(ceiling.decimalString) USDC")
    }

    private var directionGlyph: some View {
        Image(systemName: "arrow.down")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(RecourseColor.nightMuted)
            .frame(width: 38, height: 38)
            .recourseGlassField(cornerRadius: 19)
    }

    private func refusal(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 18)
            Text(text)
                .font(.recourse(12))
                .foregroundStyle(RecourseColor.nightMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 22)
        .transition(.opacity)
    }

    private var divider: some View {
        Rectangle()
            .fill(RecourseColor.nightLine)
            .frame(height: 1)
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
        .frame(height: 40)
    }

    // MARK: Behaviour

    /// Read once when the screen opens. The ceiling moves only when the pool's
    /// reserves move, which no keystroke does, so refetching it per quote would be
    /// a network read that could not change the answer.
    private func loadCeiling() async {
        guard let reader else { return }
        guard let reserves = try? await reader.fxReserves() else { return }
        let cap = FX.maxAmountIn(
            reserveIn: reserves.usdc,
            reserveOut: reserves.eurc,
            decimalsIn: 6,
            decimalsOut: 6,
            referencePrice: referencePrice
        )
        guard cap > 0, let units = UInt64(cap.description) else { return }
        ceiling = USDCAmount(baseUnits: units)
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
            // is that this pool is too thin for this size. Carrying the ceiling in
            // the sentence matters more than the percentage does: without it the
            // only way forward is to guess downwards.
            let gap = "This pool is \(String(format: "%.1f", Double(bps) / 100))% worse than the market rate at this size."
            guard let ceiling else { return "\(gap) Try a smaller amount." }
            return "\(gap) The most it can fill right now is \(ceiling.decimalString) USDC."
        case .noLiquidity:
            return "This pool has nothing to give at that size."
        case .zeroAmount:
            return "Enter an amount above zero."
        case .badSlippage:
            return "Slippage tolerance is out of range."
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

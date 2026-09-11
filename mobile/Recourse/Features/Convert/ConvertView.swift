import SwiftUI
@preconcurrency import BigInt

/// Convert between USDC and EURC, either way.
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
    /// Absent in previews; Review then shows the quote but cannot fill.
    var environment: AppEnvironment? = nil
    /// EURC per USDC. Supplied rather than fetched so the check has an origin the
    /// venue cannot influence.
    var referencePrice: Double = 0.867

    @State private var amountText = ""
    @State private var quote: FXQuote?
    @State private var problem: String?
    /// Set when this way is off market at every size and the other way is fair.
    @State private var offersFlip = false
    @State private var quoting = false
    /// Read once when the screen opens; both directions' ceilings come from it.
    @State private var reserves: FXReserves?
    @State private var direction: FXDirection = .usdcToEurc
    @State private var showsReview = false

    /// Six decimals either way on Arc, so USDCAmount carries it as a plain amount and
    /// the symbol comes from the direction.
    private var amount: USDCAmount? {
        guard let value = try? USDCAmount(decimalString: amountText), value.baseUnits > 0 else { return nil }
        return value
    }

    /// The most the pool fills at the market rate in `way`, in base units of its input.
    /// Nil when the pool has not been read, zero when it has and no size is fair. Those
    /// are different answers: one means ask again, the other means stop asking.
    private func ceilingUnits(_ way: FXDirection) -> BigUInt? {
        guard let reserves else { return nil }
        let pool = way.reserves(reserves)
        return FX.maxAmountIn(
            reserveIn: pool.input,
            reserveOut: pool.output,
            decimalsIn: 6,
            decimalsOut: 6,
            referencePrice: way.reference(eurcPerUsdc: referencePrice)
        )
    }

    /// The most the pool fills at the market rate in the current direction. Derived
    /// rather than stored, so turning the conversion around cannot leave the other
    /// side's ceiling on screen.
    private var poolCeiling: USDCAmount? {
        guard let cap = ceilingUnits(direction), cap > 0, let units = UInt64(cap.description) else { return nil }
        return USDCAmount(baseUnits: units)
    }

    /// What the account holds of the currency being paid in, when the screen knows.
    private var held: USDCAmount? {
        guard let store = environment?.paymentStore else { return nil }
        switch direction {
        case .usdcToEurc: return store.balance
        case .eurcToUsdc: return store.eurcBalance.map { USDCAmount(baseUnits: $0.baseUnits) }
        }
    }

    /// The pool's ceiling, or the balance if that is smaller: MAX should never offer
    /// money the account does not have.
    private var maxFill: USDCAmount? {
        guard let poolCeiling else { return nil }
        guard let held else { return poolCeiling }
        let units = min(poolCeiling.baseUnits, held.baseUnits)
        return units > 0 ? USDCAmount(baseUnits: units) : nil
    }

    // The layout is the one every swap screen has settled on: what you pay, what
    // you get, a keypad on the ground, one button. The ground is flat; the amounts
    // are the design.
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    paying
                    separator
                    receiving
                    if let problem {
                        refusal(problem)
                        if offersFlip {
                            flipOffer
                        }
                    } else {
                        details
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 14) {
                AmountKeypad(text: $amountText)
                reviewButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(RecourseColor.night)
        .navigationTitle("Convert")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsReview) {
            if let amount, let quote {
                ConvertReviewSheet(amount: amount, quote: quote, reader: reader, environment: environment, referencePrice: referencePrice, direction: direction) {
                    amountText = ""
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
        }
        .task {
            await loadReserves()
        }
        .task(id: "\(direction)|\(amountText)") {
            await refreshQuote()
        }
    }

    // MARK: Sections

    private var paying: some View {
        VStack(alignment: .leading, spacing: 10) {
            sideLabel("You pay")
            HStack(alignment: .center, spacing: 12) {
                Text(amountText.isEmpty ? "0" : amountText)
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .foregroundStyle(amountText.isEmpty ? RecourseColor.nightMuted.opacity(0.45) : RecourseColor.nightText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.18), value: amountText)
                Spacer(minLength: 8)
                token(direction.inputMark, direction.inputSymbol)
            }
            if held != nil || maxFill != nil {
                HStack {
                    // What there is to spend, so nobody has to leave the screen to find
                    // out whether they hold the currency they are converting.
                    if let held {
                        Text("Balance \(held.decimalString) \(direction.inputSymbol)")
                            .font(.recourse(13))
                            .foregroundStyle(RecourseColor.nightMuted)
                    }
                    Spacer()
                    // The most that fills at the market rate, or what is held if that is
                    // less: the number that decides whether typing further is worth it.
                    if let maxFill {
                        Button {
                            amountText = maxFill.decimalString
                        } label: {
                            HStack(spacing: 6) {
                                Text("MAX")
                                    .font(.recourse(15, .bold))
                                    .foregroundStyle(RecourseColor.nightText)
                                Text(maxFill.decimalString)
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(RecourseColor.nightMuted)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Convert the maximum, \(maxFill.decimalString) \(direction.inputSymbol)")
                    }
                }
            }
        }
    }

    private var receiving: some View {
        VStack(alignment: .leading, spacing: 10) {
            sideLabel("You receive")
            HStack(alignment: .center, spacing: 12) {
                Group {
                    if quoting {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(RecourseColor.nightMuted)
                            .frame(height: 62)
                    } else if let quote {
                        Text(fourPlaces(quote.amountOut))
                            .font(.system(size: 52, weight: .semibold, design: .rounded))
                            .foregroundStyle(RecourseColor.ledger)
                            .contentTransition(.numericText())
                    } else {
                        Text("0")
                            .font(.system(size: 52, weight: .semibold, design: .rounded))
                            .foregroundStyle(RecourseColor.nightMuted.opacity(0.45))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                Spacer(minLength: 8)
                token(direction.outputMark, direction.outputSymbol)
            }
            .animation(.snappy(duration: 0.24), value: quote)
        }
    }

    /// The line between the two sides. Tapping the arrows turns the conversion around:
    /// the pool is one pair and fills either way, so which side is paid in is the
    /// person's choice rather than the venue's. It used to be a bare glyph, which left
    /// someone holding euros with no way to spend them.
    private var separator: some View {
        HStack(spacing: 14) {
            Rectangle().fill(RecourseColor.nightLine).frame(height: 1)
            Button(action: flip) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                    .frame(width: 40, height: 40)
                    .background(RecourseColor.nightChip, in: Circle())
                    .rotationEffect(.degrees(direction == .usdcToEurc ? 0 : 180))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Convert \(direction.outputSymbol) to \(direction.inputSymbol) instead")
            Rectangle().fill(RecourseColor.nightLine).frame(height: 1)
        }
        .padding(.vertical, 22)
    }

    private func flip() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.snappy(duration: 0.3)) {
            direction = direction.flipped
        }
        // An amount typed in one currency is not an amount in the other.
        amountText = ""
        quote = nil
        problem = nil
        offersFlip = false
    }

    @ViewBuilder
    private var details: some View {
        if let quote {
            VStack(spacing: 0) {
                detail("Rate", String(format: "%.4f %@ per %@", quote.price, direction.outputSymbol, direction.inputSymbol))
                detail("Minimum received", "\(fourPlaces(quote.minAmountOut)) \(direction.outputSymbol)")
                if let deviation = quote.deviationBps {
                    detail("Versus market", deviation <= 0
                        ? "better by \(abs(deviation)) bps"
                        : "\(deviation) bps worse")
                }
            }
            .padding(.top, 22)
            .transition(.opacity)
        }
    }

    private var reviewButton: some View {
        Button {
            showsReview = true
        } label: {
            Text("Review")
                .font(.recourse(17, .semibold))
                .foregroundStyle(quote == nil ? RecourseColor.nightMuted : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(quote == nil ? RecourseColor.nightChip : RecourseColor.ledger, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(quote == nil)
        .animation(.snappy(duration: 0.2), value: quote == nil)
    }

    // MARK: Pieces

    private func sideLabel(_ text: String) -> some View {
        Text(text)
            .font(.recourse(16, .medium))
            .foregroundStyle(RecourseColor.nightText)
    }

    private func token(_ mark: BrandMark, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            BrandMarkView(mark: mark, height: 26)
            Text(symbol)
                .font(.recourse(17, .semibold))
                .foregroundStyle(RecourseColor.nightText)
        }
    }

    private func refusal(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 18)
            Text(text)
                .font(.recourse(13))
                .foregroundStyle(RecourseColor.nightMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 22)
        .transition(.opacity)
    }

    /// When this way is off market at every size and the other way is fair, the one
    /// useful thing left is to turn around, so it is a button rather than advice.
    private var flipOffer: some View {
        Button(action: flip) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                Text("Convert \(direction.outputSymbol) to \(direction.inputSymbol) instead")
                    .font(.recourse(13, .semibold))
            }
            .foregroundStyle(RecourseColor.nightText)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(RecourseColor.nightChip, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .padding(.leading, 28)
        .transition(.opacity)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.recourse(13))
                .foregroundStyle(RecourseColor.nightMuted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(RecourseColor.nightText)
        }
        .frame(height: 34)
    }

    // MARK: Behaviour

    /// Read once when the screen opens. The ceiling moves only when the pool's
    /// reserves move, which no keystroke does, so refetching it per quote would be
    /// a network read that could not change the answer. Kept as reserves rather than
    /// as a ceiling so turning the conversion around needs no second read.
    private func loadReserves() async {
        guard let reader else { return }
        reserves = try? await reader.fxReserves()
    }

    private func refreshQuote() async {
        quote = nil
        problem = nil
        offersFlip = false
        guard let amount, let reader else { return }
        // Refused before the pool is asked: a quote for money the account does not
        // have is a quote that can only fail at the last step.
        if let held, amount.baseUnits > held.baseUnits {
            problem = "You have \(held.decimalString) \(direction.inputSymbol)."
            return
        }

        // Debounce: the pad re-runs this on every key and each pass is a network read.
        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled { return }

        let way = direction
        quoting = true
        defer { quoting = false }
        do {
            let out = try await reader.fxAmountOut(amountIn: BigUInt(amount.baseUnits), direction: way)
            // Turned around while the read was in flight: this answer is for the other side.
            if Task.isCancelled || way != direction { return }
            let candidate = try FX.quote(
                amountIn: BigUInt(amount.baseUnits),
                amountOut: out,
                decimalsIn: 6,
                decimalsOut: 6,
                referencePrice: way.reference(eurcPerUsdc: referencePrice)
            )
            try FX.assertSane(candidate)
            quote = candidate
        } catch let error as FXQuoteError {
            problem = describe(error)
            if case .offMarket = error, ceilingUnits(way) == 0, let other = ceilingUnits(way.flipped), other > 0 {
                offersFlip = true
            }
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
            let worse = "\(String(format: "%.1f", Double(bps) / 100))% worse than the market rate"
            // A pool priced off market is off at every size, and "try a smaller amount"
            // sends someone down to zero a keystroke at a time for nothing. Say so, and
            // name the direction that does work when there is one.
            if ceilingUnits(direction) == 0 {
                var text = "This pool is \(worse) at any size right now, so no amount is worth converting this way."
                if let other = ceilingUnits(direction.flipped), other > 0 {
                    text += " \(direction.outputSymbol) to \(direction.inputSymbol) fills at a fair rate."
                }
                return text
            }
            guard let poolCeiling else { return "This pool is \(worse) at this size. Try a smaller amount." }
            return "This pool is \(worse) at this size. The most it can fill right now is \(poolCeiling.decimalString) \(direction.inputSymbol)."
        case .noLiquidity:
            return "This pool has nothing to give at that size."
        case .zeroAmount:
            return "Enter an amount above zero."
        case .badSlippage:
            return "Slippage tolerance is out of range."
        }
    }
}

/// Review, in the shape every swap app has settled on: the two legs with their
/// marks, the terms of the fill, and one button. The fill is simulated when the
/// sheet opens; a failed simulation is a red pill at the top and a grey button,
/// never a signed transaction.
private struct ConvertReviewSheet: View {
    let amount: USDCAmount
    let quote: FXQuote
    let reader: (any ContractReading)?
    let environment: AppEnvironment?
    let referencePrice: Double
    let direction: FXDirection
    let onConverted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var simulation: Simulation = .running
    @State private var stage: String?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var result: ChainHash?

    enum Simulation: Equatable {
        case running
        case passed
        case failed
    }

    private var canConfirm: Bool {
        simulation == .passed && environment != nil && !isWorking && result == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    leg(mark: direction.inputMark, label: "Convert", amount: amount.decimalString, symbol: direction.inputSymbol)
                    leg(mark: direction.outputMark, label: "To", amount: fourPlaces(quote.amountOut), symbol: direction.outputSymbol)
                        .padding(.top, 18)
                    rule.padding(.vertical, 22)
                    row("Slippage") {
                        Text(String(format: "%.2f %%", Double(FX.defaultSlippageBps) / 100))
                            .font(.recourse(15, .semibold))
                            .foregroundStyle(RecourseColor.nightText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(RecourseColor.nightChip, in: Capsule())
                    }
                    row("Receive at least", value: fourPlaces(quote.minAmountOut), unit: direction.outputSymbol)
                    row("Route", value: "Arc Swap")
                    row("Price impact", value: impactText, tint: impactTint)
                    rule.padding(.vertical, 22)
                    row("Platform fee", value: "Free", tint: RecourseColor.ledger)
                    row("Onchain fees", value: "Paid in USDC")
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.recourse(13))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 18)
                    }
                    if let result {
                        Text("Converted. Transaction \(result.value.prefix(10))... is on Arc, and your balances are up to date.")
                            .font(.recourse(13))
                            .foregroundStyle(RecourseColor.ledger)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
            confirmButton
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .background(RecourseColor.night)
        .overlay(alignment: .top) {
            if simulation == .failed {
                toast
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: simulation)
        .task { await simulate() }
    }

    private var header: some View {
        ZStack {
            Text("Review")
                .font(.recourse(17, .semibold))
                .foregroundStyle(RecourseColor.nightText)
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .frame(width: 34, height: 34)
                        .background(RecourseColor.nightChip, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var toast: some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
            Text("Swap simulation failed")
                .font(.recourse(14, .semibold))
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(Color.red.opacity(0.25), lineWidth: 1))
    }

    private func leg(mark: BrandMark, label: String, amount: String, symbol: String) -> some View {
        HStack(spacing: 16) {
            BrandMarkView(mark: mark, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.recourse(14))
                    .foregroundStyle(RecourseColor.nightMuted)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(amount)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(RecourseColor.nightText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(symbol)
                        .font(.recourse(20, .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
            }
            Spacer()
        }
    }

    private var rule: some View {
        Rectangle().fill(RecourseColor.nightLine).frame(height: 1)
    }

    private func row(_ label: String, value: String, unit: String? = nil, tint: Color = RecourseColor.nightText) -> some View {
        row(label) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                if let unit {
                    Text(unit)
                        .font(.recourse(15))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
            }
        }
    }

    private func row<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(label)
                .font(.recourse(15))
                .foregroundStyle(RecourseColor.nightMuted)
            Spacer()
            trailing()
        }
        .frame(minHeight: 44)
    }

    // Fuse shows impact against the pool's own mid price; ours is against the
    // market, which is the number that decides whether the trade is worth making.
    private var impactText: String {
        guard let bps = quote.deviationBps else { return "Unknown" }
        if abs(bps) < 10 { return "< 0.1 %" }
        return String(format: "%@%.1f %%", bps < 0 ? "+" : "-", abs(Double(bps)) / 100)
    }

    private var impactTint: Color {
        guard let bps = quote.deviationBps else { return RecourseColor.nightMuted }
        return bps <= 50 ? RecourseColor.ledger : .orange
    }

    private var confirmButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView().tint(.white)
                } else if result == nil, canConfirm {
                    Image(systemName: "faceid")
                }
                Text(buttonLabel)
            }
            .font(.recourse(17, .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(canConfirm || isWorking ? RecourseColor.ledger : Color.gray.opacity(0.55), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canConfirm && result == nil)
    }

    private var buttonLabel: String {
        if let stage, isWorking { return stage }
        if result != nil { return "Done" }
        if environment == nil { return "Preview only" }
        return "Confirm"
    }

    // MARK: Behaviour

    /// The router is asked once more, right now, for the same trade. A quote that
    /// no longer clears the floor the user was shown is a trade that would revert.
    private func simulate() async {
        guard let reader else {
            simulation = .failed
            return
        }
        do {
            let out = try await reader.fxAmountOut(amountIn: BigUInt(amount.baseUnits), direction: direction)
            simulation = out >= quote.minAmountOut ? .passed : .failed
        } catch {
            simulation = .failed
        }
    }

    private func submit() {
        if result != nil {
            dismiss()
            return
        }
        guard canConfirm, let environment else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                let gateway = try environment.makeContractGateway()
                stage = "Approving \(direction.inputSymbol)"
                let approval = try await gateway.approveFXRouter(amount: BigUInt(amount.baseUnits), direction: direction)
                guard try await gateway.waitForReceipt(transactionHash: approval).outcome == .confirmed else {
                    throw ConvertError.reverted
                }
                stage = "Converting on Arc"
                let deadline = UInt64(Date().timeIntervalSince1970) + 600
                let hash = try await gateway.swapFX(
                    amountIn: BigUInt(amount.baseUnits),
                    minAmountOut: quote.minAmountOut,
                    direction: direction,
                    deadline: deadline
                )
                guard try await gateway.waitForReceipt(transactionHash: hash).outcome == .confirmed else {
                    throw ConvertError.reverted
                }
                await environment.paymentStore.refreshBuyer()
                result = hash
                onConverted()
            } catch {
                errorMessage = failureMessage(error)
            }
            isWorking = false
            stage = nil
        }
    }

    private func failureMessage(_ error: any Error) -> String {
        switch error {
        case ConvertError.reverted:
            "Arc reverted the conversion. Nothing moved."
        case TransactionAuthorizationError.cancelled:
            "The conversion was cancelled."
        case BundlerError.rejected(let reason):
            "Arc's bundler refused it: \(reason)"
        case SafeSubmitError.operationFailed:
            "Arc ran the conversion and it failed. Nothing moved."
        default:
            SmartAccountStore.describe(error)
        }
    }

    private enum ConvertError: Error {
        case reverted
    }
}

/// The marks belong to the screen rather than the domain, which knows directions but
/// not what anything looks like.
fileprivate extension FXDirection {
    var inputMark: BrandMark { self == .usdcToEurc ? .usdc : .eurc }
    var outputMark: BrandMark { self == .usdcToEurc ? .eurc : .usdc }
}

/// Four places for a quote in either token: both have six decimals on Arc, and a quote
/// is where the last digits are the point.
fileprivate func fourPlaces(_ baseUnits: BigUInt) -> String {
    String(format: "%.4f", (Double(baseUnits.description) ?? 0) / 1_000_000)
}

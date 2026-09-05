import SwiftUI

/// Earn, laid out the way Fuse lays it out: the position and its rate, two figures
/// for what it has made, and the one product underneath. The product is the
/// settlement vault: idle USDC pays merchants at T+0 and takes the advance fees and
/// the float yield. Every number is a live read from Arc or this phone's own record
/// of what it put in; deposits and withdrawals are real transactions signed here.
struct EarnView: View {
    let environment: AppEnvironment

    @State private var vaultState: VaultState?
    @State private var ledger = EarnLedger.load()
    @State private var loadError: String?
    @State private var showsProduct = false
    @State private var action: EarnAction?
    @Environment(\.dismiss) private var dismiss

    static let productName = "Settlement Yield"
    static let productBlurb = "Put USDC into the settlement vault. It pays merchants at T+0 and earns the advance fees plus float yield while it waits."
    static let earnTint = Color(red: 0.55, green: 0.36, blue: 0.96)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                balance
                    .padding(.top, 26)
                statCards
                    .padding(.top, 20)
                Text("Available products")
                    .font(.recourse(15, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                    .padding(.top, 28)
                    .padding(.bottom, 10)
                productCard
                if let loadError {
                    Text(loadError)
                        .font(.recourse(12, .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
        .background(RecourseColor.night)
        .navigationTitle("Earn")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) { actionBar }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showsProduct) {
            EarnProductSheet(environment: environment, apy: apy, vaultState: vaultState) {
                await load()
            }
        }
        .sheet(item: $action) { action in
            EarnActionView(environment: environment, mode: action, vaultState: vaultState) {
                await load()
            }
        }
    }

    /// The position as last read, then the chain. A failed read keeps the last
    /// position on screen and says the figures are old.
    private func load() async {
        if vaultState == nil {
            vaultState = SnapshotCache.shared.load(VaultState.self, key: "earn", scope: ActiveAccount.scope)
        }
        ledger = EarnLedger.load()
        do {
            let owner = try await environment.buyerSigner.address()
            let gateway = try environment.makeContractGateway()
            let state = try await gateway.vaultState(of: owner)
            vaultState = state
            SnapshotCache.shared.save(state, key: "earn", scope: ActiveAccount.scope)
            ledger.record(price: state.sharePrice)
            ledger.save()
            loadError = nil
        } catch {
            loadError = vaultState == nil
                ? "Live vault data is unavailable right now. Pull to refresh."
                : "Arc is not answering. These figures are from the last read."
        }
    }

    private var apy: Double? {
        guard let vaultState else { return nil }
        return ledger.estimatedAPY(priceNow: vaultState.sharePrice)
    }

    // MARK: Header and balance

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Self.earnTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("Earn")
                .font(.recourse(19, .semibold))
                .foregroundStyle(RecourseColor.nightText)
            Spacer()
        }
        .padding(.top, 8)
    }

    private var balance: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Balance")
                Text("·")
                Text(apy.map { String(format: "APY %.2f%%", $0 * 100) } ?? "APY measuring")
            }
            .font(.recourse(12.5, .medium))
            .foregroundStyle(RecourseColor.nightMuted)

            Dollars(baseUnits: vaultState?.myValue.baseUnits ?? 0, size: 38)
                .opacity(vaultState == nil ? 0.35 : 1)
        }
    }

    // MARK: Cards

    private var statCards: some View {
        HStack(spacing: 12) {
            statCard("Earned so far", icon: "sparkles", tint: Color(red: 0.36, green: 0.55, blue: 0.96)) {
                if let vaultState, let earned = ledger.earnedSoFar(position: vaultState.myValue) {
                    Dollars(baseUnits: earned.baseUnits, size: 18)
                } else {
                    Text("Counts from your next deposit")
                        .font(.recourse(11, .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
            }
            statCard("Last 7D", icon: "calendar", tint: Color(red: 0.94, green: 0.46, blue: 0.23)) {
                if let vaultState, let week = ledger.earnedLastWeek(shares: vaultState.myShares, priceNow: vaultState.sharePrice) {
                    Dollars(baseUnits: week.baseUnits, size: 18)
                } else {
                    Text("Measuring this week")
                        .font(.recourse(11, .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
            }
        }
    }

    private func statCard<Value: View>(_ title: String, icon: String, tint: Color, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(title)
                    .font(.recourse(13, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 16)
            value()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var productCard: some View {
        Button {
            showsProduct = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ProductMark(size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Recourse")
                                .foregroundStyle(RecourseColor.nightMuted)
                            Text("·")
                                .foregroundStyle(RecourseColor.nightMuted)
                            Text(apy.map { String(format: "%.2f%% APY", $0 * 100) } ?? "APY measuring")
                                .foregroundStyle(apy == nil ? RecourseColor.nightMuted : RecourseColor.ledger)
                        }
                        .font(.recourse(12.5, .medium))
                        Text(Self.productName)
                            .font(.recourse(17, .semibold))
                            .foregroundStyle(RecourseColor.nightText)
                    }
                    Spacer(minLength: 0)
                }
                Text(Self.productBlurb)
                    .font(.recourse(12.5))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private var hasPosition: Bool { (vaultState?.myShares ?? 0) > 0 }

    // The way out sits with the actions, where Fuse puts it: the navigation bar is
    // hidden so the page can carry its own title.
    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(RecourseColor.nightText)
                    .frame(width: 52, height: 52)
                    .background(RecourseColor.nightChip, in: Circle())
                    .overlay(Circle().stroke(RecourseColor.nightLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            HStack(spacing: 0) {
                actionButton("Deposit", icon: "plus", enabled: true) { action = .deposit }
                actionButton("Withdraw", icon: "arrow.up", enabled: hasPosition) { action = .withdraw }
            }
            .padding(.horizontal, 6)
            .frame(height: 52)
            .background(RecourseColor.nightChip, in: Capsule())
            .overlay(Capsule().stroke(RecourseColor.nightLine, lineWidth: 1))
        }
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private func actionButton(_ title: String, icon: String, enabled: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.recourse(15, .semibold))
            }
            .foregroundStyle(enabled ? RecourseColor.nightText : RecourseColor.nightMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

enum EarnAction: String, Identifiable {
    case deposit
    case withdraw
    var id: String { rawValue }
}

/// Dollars with the cents dimmed, the way the Home balance is set.
private struct Dollars: View {
    let baseUnits: UInt64
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("$\(whole)")
                .foregroundStyle(RecourseColor.nightText)
            Text(String(format: ".%02llu", (baseUnits % USDCAmount.base) / 10_000))
                .foregroundStyle(RecourseColor.nightMuted)
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .minimumScaleFactor(0.6)
        .lineLimit(1)
    }

    private var whole: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: baseUnits / USDCAmount.base)) ?? "0"
    }
}

/// The product's mark: the app icon, which is the one picture of Recourse a phone
/// already has, in a rounded tile.
private struct ProductMark: View {
    let size: CGFloat

    var body: some View {
        Image("RecourseMark")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

// MARK: - Product sheet

/// What the product is and what a deposit could become, before any amount is typed.
private struct EarnProductSheet: View {
    let environment: AppEnvironment
    let apy: Double?
    let vaultState: VaultState?
    let onFinished: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsLearnMore = false
    @State private var showsDeposit = false

    private static let exampleDeposit = USDCAmount(baseUnits: 1_000_000_000)

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 3) {
                    Text(EarnView.productName)
                        .font(.recourse(16, .semibold))
                        .foregroundStyle(RecourseColor.nightText)
                    HStack(spacing: 6) {
                        Text("Provided by")
                            .foregroundStyle(RecourseColor.nightMuted)
                        ProductMark(size: 18)
                        Text("Recourse")
                            .foregroundStyle(RecourseColor.nightText)
                    }
                    .font(.recourse(13, .medium))
                }
                .frame(maxWidth: .infinity)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 10) {
                    card
                    Text(EarnView.productBlurb)
                        .font(.recourse(11))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, 36)
                    Button {
                        showsLearnMore = true
                    } label: {
                        Label("Learn more", systemImage: "globe")
                            .font(.recourse(12, .semibold))
                            .foregroundStyle(RecourseColor.ledger)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)

            Button {
                showsDeposit = true
            } label: {
                Text("Deposit")
                    .font(.recourse(15, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(RecourseColor.ledger, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 6)
        }
        .background(RecourseColor.night.ignoresSafeArea())
        .presentationDetents([.fraction(0.58), .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showsLearnMore) {
            SafariWebView(url: URL(string: "https://recourse-arc.vercel.app/support")!)
        }
        .sheet(isPresented: $showsDeposit) {
            EarnActionView(environment: environment, mode: .deposit, vaultState: vaultState, onFinished: onFinished)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("How it works")
                    .font(.recourse(13.5, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                Spacer()
                rateChip
            }
            dashed
            HStack(alignment: .firstTextBaseline) {
                Text("You deposit")
                    .font(.recourse(13.5, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                Spacer()
                Dollars(baseUnits: Self.exampleDeposit.baseUnits, size: 17)
                BrandMarkView(mark: .usdc, height: 18)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
            }
            dashed
            Text("Your potential earn")
                .font(.recourse(13.5, .semibold))
                .foregroundStyle(RecourseColor.nightText)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(monthLabel(0))
                        .font(.recourse(11.5, .medium))
                        .foregroundStyle(RecourseColor.nightText)
                    Dollars(baseUnits: Self.exampleDeposit.baseUnits, size: 13.5)
                        .opacity(0.6)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(monthLabel(12))
                        .font(.recourse(11.5, .medium))
                        .foregroundStyle(RecourseColor.nightText)
                    HStack(spacing: 5) {
                        Text(endValueText)
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(RecourseColor.ledger)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(RecourseColor.ledger, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
            }
            bars
        }
        .padding(14)
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // Until the phone has measured the vault's own rate, the chart runs at an
    // illustrative one and the chip says so. A flat chart says nothing, and a bare
    // number with no label would be a promise.
    private static let illustrativeAPY = 0.04

    private var chartRate: Double { apy ?? Self.illustrativeAPY }

    private var rateChip: some View {
        HStack(spacing: 5) {
            Text(String(format: "%.2f%%", chartRate * 100))
                .font(.recourse(11.5, .semibold))
            Text(apy == nil ? "Illustrative APY" : "Estimated APY")
                .font(.recourse(11.5, .medium))
        }
        .foregroundStyle(RecourseColor.ledger)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(RecourseColor.ledger.opacity(0.14), in: Capsule())
    }

    private var dashed: some View {
        Line()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
            .foregroundStyle(RecourseColor.nightLine)
            .frame(height: 1)
    }

    // Thirteen bars, one per month, at the value a deposit would reach if the rate
    // held. With no rate yet the bars sit flat rather than pretend.
    private var bars: some View {
        let values = (0 ... 12).map { value(afterMonths: $0) }
        let start = Double(Self.exampleDeposit.baseUnits)
        let span = max((values.last ?? start) - start, 1)
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let fraction = (value - start) / span
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(index == 12 ? RecourseColor.ledger : RecourseColor.ledger.opacity(0.2))
                    .frame(height: 6 + 64 * fraction)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 70, alignment: .bottom)
    }

    private func value(afterMonths months: Int) -> Double {
        let start = Double(Self.exampleDeposit.baseUnits)
        return start * pow(1 + chartRate, Double(months) / 12)
    }

    private var endValueText: String {
        let units = UInt64(value(afterMonths: 12))
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "$" + (formatter.string(from: NSNumber(value: Double(units) / Double(USDCAmount.base))) ?? "0.00")
    }

    private func monthLabel(_ offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .month, value: offset, to: .now) ?? .now
        return date.formatted(.dateTime.month(.abbreviated).year())
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Deposit and withdraw

private enum VaultActionError: Error {
    case reverted
}

/// One amount, typed or dragged, then Face ID. The ruler under the amount is the
/// same control as MAX with more positions: a share of what is available.
private struct EarnActionView: View {
    let environment: AppEnvironment
    let mode: EarnAction
    let vaultState: VaultState?
    let onFinished: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var isWorking = false
    @State private var stage: String?
    @State private var errorMessage: String?
    @State private var succeeded = false
    @State private var celebrationRevealed = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(mode == .deposit ? "Deposit" : "Withdraw")
                    .font(.recourse(17, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                HStack(spacing: 8) {
                    ProductMark(size: 22)
                    Text(EarnView.productName)
                        .font(.recourse(15, .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
            }
            .padding(.top, 22)

            if succeeded {
                successBody
            } else {
                entryBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RecourseColor.night.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }

    private var successBody: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
                .scaleEffect(celebrationRevealed ? 1 : 0.4)
            Text(mode == .deposit ? "Deposited on Arc" : "Withdrawn on Arc")
                .font(.recourse(17, .semibold))
                .foregroundStyle(RecourseColor.nightText)
                .opacity(celebrationRevealed ? 1 : 0)
            Spacer()
            Button("Done") { dismiss() }
                .font(.recourse(17, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(RecourseColor.ledger, in: Capsule())
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .task {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                celebrationRevealed = true
            }
        }
    }

    private var entryBody: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    BrandMarkView(mark: .usdc, height: 28)
                    Text("USDC")
                        .font(.recourse(20, .semibold))
                        .foregroundStyle(RecourseColor.nightText)
                }
                HStack(alignment: .center) {
                    Text(amountText.isEmpty ? "0" : amountText)
                        .font(.system(size: 52, weight: .semibold, design: .rounded))
                        .foregroundStyle(amountText.isEmpty ? RecourseColor.nightMuted : RecourseColor.nightText)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Button {
                        amountText = cap.decimalString
                    } label: {
                        Text("MAX")
                            .font(.recourse(14, .semibold))
                            .foregroundStyle(RecourseColor.nightMuted)
                            .padding(.horizontal, 16)
                            .frame(height: 38)
                            .background(RecourseColor.nightChip, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Text(String(format: "$%.2f", Double(amount?.baseUnits ?? 0) / Double(USDCAmount.base)))
                    Spacer()
                    Text(capLabel)
                }
                .font(.recourse(14, .medium))
                .foregroundStyle(RecourseColor.nightMuted)

                ruler
                    .padding(.top, 10)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)

            AmountKeypad(text: $amountText)
                .padding(.horizontal, 8)

            footer
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
    }

    // MARK: The ruler

    private var ruler: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach([0, 25, 50, 75, 100], id: \.self) { mark in
                    Text("\(mark)%")
                        .font(.recourse(14, .semibold))
                        .foregroundStyle(RecourseColor.nightText)
                    if mark < 100 { Spacer() }
                }
            }
            GeometryReader { proxy in
                let width = proxy.size.width
                let filled = fraction
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0 ..< 41, id: \.self) { tick in
                        let major = tick % 10 == 0
                        let lit = Double(tick) / 40 <= filled + 0.0001
                        RoundedRectangle(cornerRadius: 1)
                            .fill(lit ? RecourseColor.ledger : RecourseColor.nightMuted.opacity(0.6))
                            .frame(width: major ? 3 : 2, height: major ? 30 : 16)
                        if tick < 40 { Spacer(minLength: 0) }
                    }
                }
                .frame(width: width, height: 30, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let raw = min(max(drag.location.x / width, 0), 1)
                            let stepped = (raw * 40).rounded() / 40
                            setFraction(stepped)
                        }
                )
            }
            .frame(height: 30)
        }
    }

    private var fraction: Double {
        guard cap.baseUnits > 0, let amount else { return 0 }
        return min(Double(amount.baseUnits) / Double(cap.baseUnits), 1)
    }

    private func setFraction(_ value: Double) {
        guard cap.baseUnits > 0 else { return }
        let units = UInt64((Double(cap.baseUnits) * value).rounded(.down))
        let next = USDCAmount(baseUnits: units).decimalString
        if next != amountText {
            UISelectionFeedbackGenerator().selectionChanged()
            amountText = units == 0 ? "" : next
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        if let problem {
            Text(problem)
                .font(.recourse(16, .semibold))
                .foregroundStyle(Color(red: 0.93, green: 0.35, blue: 0.35))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color(red: 0.93, green: 0.35, blue: 0.35).opacity(0.14), in: Capsule())
        } else {
            Button {
                submit()
            } label: {
                HStack(spacing: 10) {
                    if isWorking { ProgressView().tint(.white) }
                    Text(isWorking ? (stage ?? "Working") : confirmLabel)
                    if !isWorking, canSubmit { Image(systemName: "faceid") }
                }
                .font(.recourse(17, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(RecourseColor.ledger, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .opacity(canSubmit || isWorking ? 1 : 0.5)
        }
    }

    private var amount: USDCAmount? {
        try? USDCAmount(decimalString: amountText)
    }

    private var cap: USDCAmount {
        switch mode {
        case .deposit: environment.paymentStore.balance ?? USDCAmount(baseUnits: 0)
        case .withdraw: vaultState?.myValue ?? USDCAmount(baseUnits: 0)
        }
    }

    private var capLabel: String {
        switch mode {
        case .deposit: environment.paymentStore.balance == nil ? "Checking balance" : cap.decimalString
        case .withdraw: vaultState == nil ? "Reading your position" : cap.decimalString
        }
    }

    /// Why the button is not there. Nil means the amount is fine, or empty.
    private var problem: String? {
        if let errorMessage { return errorMessage }
        guard let amount, amount.baseUnits > 0 else { return nil }
        if amount.baseUnits > cap.baseUnits {
            return mode == .deposit ? "Not enough USDC in your balance" : "More than you have in Earn"
        }
        if mode == .withdraw, let vaultState, vaultState.shares(for: amount) == 0 {
            return "Too small to withdraw"
        }
        return nil
    }

    private var confirmLabel: String {
        let verb = mode == .deposit ? "Deposit" : "Withdraw"
        guard let amount, amount.baseUnits > 0 else { return verb }
        return "\(verb) \(amount.decimalString) USDC"
    }

    private var canSubmit: Bool {
        guard let amount, amount.baseUnits > 0, !isWorking, problem == nil else { return false }
        return true
    }

    private func submit() {
        guard let amount, !isWorking else { return }
        isWorking = true
        errorMessage = nil

        Task {
            do {
                let gateway = try environment.makeContractGateway()
                var ledger = EarnLedger.load()
                switch mode {
                case .deposit:
                    stage = "Approving USDC"
                    let approval = try await gateway.approveVaultUSDC(amount: amount)
                    guard try await gateway.waitForReceipt(transactionHash: approval).outcome == .confirmed else {
                        throw VaultActionError.reverted
                    }
                    stage = "Depositing on Arc"
                    let deposit = try await gateway.vaultDeposit(amount: amount)
                    guard try await gateway.waitForReceipt(transactionHash: deposit).outcome == .confirmed else {
                        throw VaultActionError.reverted
                    }
                    ledger.noteDeposit(amount)
                case .withdraw:
                    guard let vaultState else { throw VaultActionError.reverted }
                    stage = "Withdrawing on Arc"
                    let withdrawal = try await gateway.vaultWithdraw(shares: vaultState.shares(for: amount))
                    guard try await gateway.waitForReceipt(transactionHash: withdrawal).outcome == .confirmed else {
                        throw VaultActionError.reverted
                    }
                    ledger.noteWithdrawal(amount)
                }
                ledger.save()
                await environment.paymentStore.refreshBuyer()
                await onFinished()
                succeeded = true
            } catch {
                errorMessage = failureMessage(error)
            }
            isWorking = false
            stage = nil
        }
    }

    private func failureMessage(_ error: any Error) -> String {
        switch error {
        case VaultActionError.reverted:
            "Arc reverted the transaction. Nothing moved."
        case TransactionAuthorizationError.cancelled:
            "The transaction was cancelled."
        case TransactionAuthorizationError.unavailable:
            "Set a device passcode or Face ID first."
        case ContractReadError.rpc(let code, let message):
            "Arc RPC error \(code): \(message)"
        default:
            "The transaction could not be completed. Try again."
        }
    }
}

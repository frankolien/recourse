import SwiftUI

/// The screen that decides whether someone keeps the app.
///
/// It used to lead with "Nothing protected yet", which was the first line a new account
/// read and described a feature this app no longer has. What replaces it is the only
/// pair of numbers a money app owes you on sight: what you hold, and what is in motion.
/// Money in motion is cheques written to you that you have not taken, and cheques you
/// have written that nobody has cashed. Neither is visible on chain, which is exactly
/// why the app has to say it.
struct HomeView: View {
    let environment: AppEnvironment
    let onScrollTowardTopChanged: (Bool) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var previousScrollOffset: CGFloat = 0
    @State private var showsReceive = false
    @State private var earnVaultState: VaultState?
    @AppStorage("recourse.hidesBalance") private var hidesBalance = false
    // Once. A guide that reappears on every launch until the first transaction is a
    // nag, and the person it nags is the one who has not decided to trust the app yet.
    @AppStorage("recourse.dismissedGettingStarted") private var dismissedGettingStarted = false
    @AppStorage("recourse.dismissedEarnPromo") private var dismissedEarnPromo = false
    @State private var range: HistoryRange = .week

    init(
        environment: AppEnvironment,
        onScrollTowardTopChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.environment = environment
        self.onScrollTowardTopChanged = onScrollTowardTopChanged
    }

    // Profile names live on the account session (persisted via the backend profile
    // endpoint), so the greeting updates the moment an edit saves, on every device.
    private var displayName: String {
        environment.accountSession.account?.displayName
            ?? environment.accountSession.account?.email?.split(separator: "@").first.map(String.init)
            ?? "there"
    }

    private var book: ChequeBook { environment.chequeBook }
    private var invoices: InvoiceBook { environment.invoiceBook }
    private var history: TransferHistory { environment.transferHistory }

    var body: some View {
        ZStack {
            homeCanvas
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    scrollPositionReader
                    balanceHero
                    balanceChart
                    primaryActions
                    featureGrid
                    if showsEarnPromo {
                        earnPromo
                    }
                    if book.cashableCount > 0 {
                        chequeLead
                    }
                    if !invoices.readyToCollect.isEmpty {
                        collectLead
                    }
                    if isNewHere && !dismissedGettingStarted {
                        firstStepsCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 164)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await environment.paymentStore.refreshBuyer()
                await book.refresh(force: true)
                await invoices.refresh(force: true)
                await history.refresh(force: true)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // No opaque fill: the canvas glow must run uninterrupted behind the
            // header, otherwise the boundary reads as a seam.
            identityHeader
                .padding(.horizontal, 20)
                .frame(height: 72)
        }
        .coordinateSpace(name: "recourse-home-scroll")
        .onPreferenceChange(RecourseScrollOffsetPreferenceKey.self) { newOffset in
            reportScrollDirection(newOffset)
        }
        .sheet(isPresented: $showsReceive) {
            DepositSheet(environment: environment)
                // Opens as a drop-down over Home. The cards are sized so both rows and
                // the footnote fit at medium; large is there for anyone who pulls.
                .presentationDetents([.medium, .large])
        }
        .task {
            while !Task.isCancelled {
                await environment.paymentStore.refreshBuyer()
                // Polled alongside the balance so a cheque someone writes you appears
                // without opening the screen, which is the whole point of an inbox.
                await book.refresh()
                await invoices.refresh()
                await history.refresh()
                environment.publishWalletSnapshot()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .task {
            // One live snapshot for the Earn teaser; the Earn screen itself
            // refreshes on every visit.
            guard let owner = try? await environment.buyerSigner.address(),
                  let gateway = try? environment.makeContractGateway() else { return }
            earnVaultState = try? await gateway.vaultState(of: owner)
        }
    }

    // Flat ground; in the dark appearance a soft brand glow bleeds from the top.
    private var homeCanvas: some View {
        ZStack(alignment: .top) {
            RecourseColor.night
            if colorScheme == .dark {
                LinearGradient(
                    colors: [RecourseColor.ledgerDeep.opacity(0.32), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 320)
            }
        }
    }

    private var scrollPositionReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: RecourseScrollOffsetPreferenceKey.self,
                value: proxy.frame(in: .named("recourse-home-scroll")).minY
            )
        }
        .frame(height: 0)
    }

    private func reportScrollDirection(_ newOffset: CGFloat) {
        let delta = newOffset - previousScrollOffset
        guard abs(delta) > 2 else { return }
        onScrollTowardTopChanged(delta > 0)
        previousScrollOffset = newOffset
    }

    private var identityHeader: some View {
        HStack(spacing: 10) {
            Button {
                environment.router.push(.account)
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 38, weight: .regular))
                    .foregroundStyle(RecourseColor.nightText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open profile")

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                HStack(spacing: 5) {
                    Image("ArcMark")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 10)
                    Text("USDC on Arc Testnet")
                        .font(.recourse(10, .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
            }

            Spacer()

            Button {
                environment.router.push(.support)
            } label: {
                headerAction(title: "Help", systemImage: "questionmark.circle")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Help")
        }
    }

    private func headerAction(title: String, systemImage: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(height: 19)
            Text(title)
                .font(.system(size: 8, weight: .medium))
        }
        .frame(width: 38)
        .foregroundStyle(RecourseColor.nightText)
    }

    // The balance owns the screen, and the line under it is money in motion rather
    // than a daily delta: a wallet whose only movement is deliberate has no market to
    // report. Tapping toggles privacy, and the number swaps through a blur so hiding
    // feels like a shutter rather than a flicker.
    private var balanceHero: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.smooth(duration: 0.75)) {
                hidesBalance.toggle()
            }
        } label: {
            VStack(spacing: 7) {
                HStack(spacing: 5) {
                    Text("Balance")
                    Image(systemName: hidesBalance ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(RecourseColor.nightMuted)

                ZStack {
                    if hidesBalance {
                        Text("$••••")
                            .foregroundStyle(RecourseColor.nightText)
                            .transition(.blurReplace)
                    } else {
                        // Cents dimmed. The dollars are the number; the cents are the
                        // precision, and a wallet that shouts its cents reads as fussier
                        // than it is.
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(balanceWhole)
                                .foregroundStyle(RecourseColor.nightText)
                            Text(balanceCents)
                                .foregroundStyle(RecourseColor.nightMuted)
                        }
                        .transition(.blurReplace)
                    }
                }
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.55)
                .lineLimit(1)

                Text(motionSubtitle)
                    .font(.recourse(13, .medium))
                    .foregroundStyle(hasIncoming ? RecourseColor.ledger : RecourseColor.nightMuted)
                    .contentTransition(.opacity)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hidesBalance ? "Show balance" : "Hide balance")
        .padding(.bottom, 2)
    }

    private var balanceWhole: String {
        guard let balance = environment.paymentStore.balance else { return "$" }
        return "$\(balance.baseUnits / USDCAmount.base)"
    }

    private var balanceCents: String {
        guard let balance = environment.paymentStore.balance else { return "0.00" }
        return String(format: ".%02llu", (balance.baseUnits % USDCAmount.base) / 10_000)
    }

    // The balance as it was over the chosen range, worked back from the balance as it
    // is. Bars rather than a line because a wallet's balance is a staircase: it holds
    // still and then steps, and a line would draw slopes that never happened.
    private var balanceChart: some View {
        VStack(spacing: 14) {
            BalanceBars(samples: history.balanceSamples(current: environment.paymentStore.balance, range: range, count: 44))
                .frame(height: 84)
                .animation(.snappy(duration: 0.3), value: range)

            HStack(spacing: 6) {
                ForEach(HistoryRange.allCases) { option in
                    Button {
                        guard range != option else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        range = option
                    } label: {
                        Text(option.rawValue)
                            .font(.recourse(12, .semibold))
                            .foregroundStyle(range == option ? RecourseColor.nightText : RecourseColor.nightMuted)
                            .frame(width: 44, height: 30)
                            .background {
                                if range == option {
                                    Capsule().fill(RecourseColor.nightChip)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 6)
    }

    /// What is moving, in the order it matters: money waiting for you first, because
    /// that is the one with something to do about it.
    private var motionSubtitle: String {
        let collectable = invoices.readyToCollectTotal
        if collectable.baseUnits > 0 {
            return "\(hidden(collectable)) invoiced and ready to collect"
        }
        let waiting = book.cashableTotal
        if waiting.baseUnits > 0 {
            return "\(hidden(waiting)) waiting for you to cash"
        }
        let owed = invoices.owedToYou
        if owed.baseUnits > 0 {
            return "\(hidden(owed)) owed to you"
        }
        let promised = book.committed
        if promised.baseUnits > 0 {
            return "\(hidden(promised)) promised in cheques you wrote"
        }
        return "Nothing in motion"
    }

    /// Green only when the money is coming toward you. What you have promised away is
    /// a fact, not good news.
    private var hasIncoming: Bool {
        book.cashableCount > 0 || !invoices.readyToCollect.isEmpty || invoices.owedToYou.baseUnits > 0
    }

    private func hidden(_ amount: USDCAmount) -> String {
        hidesBalance ? "$••••" : currency(amount)
    }

    // The two verbs a money app is opened for, as a pair the width of the screen.
    // Five squares in a row spread the same two thin and made them equals of
    // things people do once a month.
    private var primaryActions: some View {
        HStack(spacing: 10) {
            Button {
                showsReceive = true
            } label: {
                Label("Add money", systemImage: "plus")
                    .font(.recourse(15, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(RecourseColor.nightChip, in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                environment.router.push(.send)
            } label: {
                Label("Send", systemImage: "paperplane.fill")
                    .font(.recourse(15, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(RecourseColor.ledger, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    // Everything else, two across, each with its own colour so the four read as four
    // things rather than as a row of the same glyph in green.
    private var featureGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
            spacing: 12
        ) {
            HomeFeatureCard(
                icon: "doc.text.fill",
                tint: RecourseColor.ledger,
                title: "Cheques",
                detail: "Write, cash or void",
                figure: chequesFigure
            ) { environment.router.push(.cheques) }

            HomeFeatureCard(
                icon: "arrow.down.left",
                tint: Color(red: 0.94, green: 0.46, blue: 0.23),
                title: "Request",
                detail: "Bill someone by name",
                figure: requestFigure
            ) { environment.router.push(.invoices) }

            // Only where an FX venue is deployed. A chain without one has no
            // Convert rather than one that fails when tapped.
            if Deployment.fxRouter != nil {
                HomeFeatureCard(
                    icon: "arrow.left.arrow.right",
                    tint: Color(red: 0.23, green: 0.51, blue: 0.96),
                    title: "Convert",
                    detail: "USDC to EURC",
                    figure: nil
                ) { environment.router.push(.convert) }
            }

            HomeFeatureCard(
                icon: "chart.bar.fill",
                tint: Color(red: 0.55, green: 0.36, blue: 0.96),
                title: "Earn",
                detail: "Yield on idle USDC",
                figure: earnFigure
            ) { environment.router.push(.earn) }
        }
    }

    /// The live number, when the feature has one. Nil means the card is empty and says
    /// what it is for instead.
    private var chequesFigure: USDCAmount? {
        if book.cashableCount > 0 { return book.cashableTotal }
        if book.liveWrittenCount > 0 { return book.committed }
        return nil
    }

    private var requestFigure: USDCAmount? {
        if !invoices.readyToCollect.isEmpty { return invoices.readyToCollectTotal }
        if invoices.owedToYou.baseUnits > 0 { return invoices.owedToYou }
        return nil
    }

    private var earnFigure: USDCAmount? {
        guard let earnVaultState, earnVaultState.myShares > 0 else { return nil }
        return earnVaultState.myValue
    }

    /// Shown until dismissed, and never to someone who already has money in the vault.
    private var showsEarnPromo: Bool {
        !dismissedEarnPromo && (earnVaultState?.myShares ?? 0) == 0
    }

    private var earnPromo: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color(red: 0.55, green: 0.36, blue: 0.96), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            Button {
                environment.router.push(.earn)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Earn on idle USDC")
                        .font(.recourse(14, .semibold))
                        .foregroundStyle(RecourseColor.nightText)
                    Text("Put USDC into Earn")
                        .font(.recourse(11.5, .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                withAnimation(.snappy(duration: 0.24)) { dismissedEarnPromo = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(RecourseColor.nightLine, lineWidth: 1)
        }
    }

    // Someone has already promised this money; the only thing between it and the
    // wallet is a tap. That earns a place above Earn.
    private var chequeLead: some View {
        Button {
            environment.router.push(.cheques)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RecourseColor.ledger)
                    .frame(width: 38, height: 38)
                    .background(RecourseColor.nightChip, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        book.cashableCount == 1
                            ? "A cheque is waiting for you"
                            : "\(book.cashableCount) cheques are waiting for you"
                    )
                    .font(.recourse(13, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                    Text("\(currency(book.cashableTotal)) ready to cash")
                        .font(.recourse(11))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
            .padding(14)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // An invoice someone has signed is money already agreed, sitting behind one
    // transaction. That is a stronger claim on attention than anything else here.
    private var collectLead: some View {
        Button {
            environment.router.push(.invoices)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.left.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RecourseColor.ledger)
                    .frame(width: 38, height: 38)
                    .background(RecourseColor.nightChip, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        invoices.readyToCollect.count == 1
                            ? "An invoice has been paid"
                            : "\(invoices.readyToCollect.count) invoices have been paid"
                    )
                    .font(.recourse(13, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                    Text("\(currency(invoices.readyToCollectTotal)) ready to collect")
                        .font(.recourse(11))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
            .padding(14)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Nothing held, nothing written, nothing received. A balance alone is not enough
    /// to call someone settled in: money arrives before anything else can happen.
    private var isNewHere: Bool {
        (environment.paymentStore.balance?.baseUnits ?? 0) == 0
            && book.received.isEmpty
            && book.written.isEmpty
            && invoices.issued.isEmpty
            && invoices.received.isEmpty
    }

    private var firstStepsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Getting started")
                    .font(.recourse(15, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.24)) { dismissedGettingStarted = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .frame(width: 28, height: 28)
                        .background(RecourseColor.nightChip, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss getting started")
            }
            firstStep("at", "Claim your name", "People pay @you instead of a wallet address they have to copy.")
            firstStep("plus.circle.fill", "Add USDC", "Receive to your address. Fees are paid in USDC too, so there is no second token to hold.")
            firstStep("doc.text.fill", "Send, request or write a cheque", "A send is instant and final. A request bills someone on terms you fix. A cheque is theirs to collect whenever they like.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
    }

    private func firstStep(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RecourseColor.nightText)
                .frame(width: 34, height: 34)
                .background(RecourseColor.nightChip, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.recourse(13, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                Text(detail)
                    .font(.recourse(11.5))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func currency(_ amount: USDCAmount) -> String {
        let value = Double(amount.baseUnits) / Double(USDCAmount.base)
        return String(format: "$%.2f", value)
    }
}

/// One of the four things on Home that are not sending or adding money.
///
/// Two states, told apart by the border. Live, with a figure to show, the card is solid
/// and the number leads; empty, it is dashed and the title leads, the way an outline
/// says "nothing here yet" without a sentence. The icon tile carries the colour so the
/// four read at a glance whichever state they are in.
private struct HomeFeatureCard: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let figure: USDCAmount?
    let action: () -> Void

    private var live: Bool { figure != nil }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Spacer(minLength: 16)

                if let figure {
                    Text(title)
                        .font(.recourse(14, .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("$\(figure.baseUnits / USDCAmount.base)")
                            .foregroundStyle(RecourseColor.nightText)
                        Text(String(format: ".%02llu", (figure.baseUnits % USDCAmount.base) / 10_000))
                            .foregroundStyle(RecourseColor.nightMuted)
                    }
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .padding(.top, 3)
                } else {
                    Text(title)
                        .font(.recourse(15, .semibold))
                        .foregroundStyle(RecourseColor.nightText)
                    Text(detail)
                        .font(.recourse(11.5, .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .lineLimit(1)
                        .padding(.top, 3)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(RecourseColor.nightChip.opacity(live ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(RecourseColor.nightLine, style: StrokeStyle(lineWidth: 1, dash: live ? [] : [5, 5]))
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(live ? "\(title), \(figure!.formatted)" : "\(title). \(detail)")
    }
}

/// Thin grey bars, one per sample, heights proportional to the tallest.
private struct BalanceBars: View {
    let samples: [UInt64]

    var body: some View {
        GeometryReader { proxy in
            let peak = Double(samples.max() ?? 0)
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, value in
                    // A floor of four points so an empty wallet still draws a baseline
                    // rather than nothing, which reads as a chart that failed to load.
                    let height = peak > 0 ? max(4, proxy.size.height * Double(value) / peak) : 4
                    Capsule()
                        .fill(RecourseColor.nightLine)
                        .frame(width: 2.5, height: height)
                        .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: proxy.size.height, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Home") {
    NavigationStack {
        AppShellView(environment: .preview())
    }
    .tint(RecourseColor.ledger)
}
#endif

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

    var body: some View {
        ZStack {
            homeCanvas
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    scrollPositionReader
                    balanceHero
                    primaryActions
                    featureGrid
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
                            .transition(.blurReplace)
                    } else {
                        Text(balanceHeadline)
                            .transition(.blurReplace)
                    }
                }
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .foregroundStyle(RecourseColor.nightText)
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

    private var balanceHeadline: String {
        guard let balance = environment.paymentStore.balance else { return "$—" }
        return currency(balance)
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
                detail: chequesDetail
            ) { environment.router.push(.cheques) }

            HomeFeatureCard(
                icon: "arrow.down.left",
                tint: Color(red: 0.94, green: 0.46, blue: 0.23),
                title: "Request",
                detail: requestDetail
            ) { environment.router.push(.invoices) }

            // Only where an FX venue is deployed. A chain without one has no
            // Convert rather than one that fails when tapped.
            if Deployment.fxRouter != nil {
                HomeFeatureCard(
                    icon: "arrow.left.arrow.right",
                    tint: Color(red: 0.23, green: 0.51, blue: 0.96),
                    title: "Convert",
                    detail: "USDC to EURC"
                ) { environment.router.push(.convert) }
            }

            HomeFeatureCard(
                icon: "chart.bar.fill",
                tint: Color(red: 0.55, green: 0.36, blue: 0.96),
                title: "Earn",
                detail: earnDetail
            ) { environment.router.push(.earn) }
        }
    }

    /// Live where there is something live to say, otherwise what the thing is for.
    private var chequesDetail: String {
        if book.cashableCount > 0 {
            return "\(currency(book.cashableTotal)) to cash"
        }
        if book.liveWrittenCount > 0 {
            return "\(currency(book.committed)) outstanding"
        }
        return "Write, cash or void"
    }

    private var requestDetail: String {
        if !invoices.readyToCollect.isEmpty {
            return "\(currency(invoices.readyToCollectTotal)) to collect"
        }
        if invoices.owedToYou.baseUnits > 0 {
            return "\(currency(invoices.owedToYou)) owed to you"
        }
        return "Bill someone by name"
    }

    private var earnDetail: String {
        guard let earnVaultState else { return "Yield on idle USDC" }
        if earnVaultState.myShares > 0 {
            return "\(currency(earnVaultState.myValue)) at work"
        }
        return "Yield on idle USDC"
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
/// The icon tile carries the colour, the way a home-screen icon does, so the four read
/// at a glance; the detail line is live where there is something live to say.
private struct HomeFeatureCard: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(tint, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                Spacer(minLength: 14)

                Text(title)
                    .font(.recourse(15, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                Text(detail)
                    .font(.recourse(11.5, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .lineLimit(1)
                    .padding(.top, 3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
            .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(detail)")
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

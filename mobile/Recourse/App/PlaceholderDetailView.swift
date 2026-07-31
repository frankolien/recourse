import PhotosUI
import SwiftUI

struct CheckoutReviewView: View {
    let request: PaymentRequest
    let environment: AppEnvironment
    @State private var isPaying = false
    @State private var paid = false
    @State private var progress: CheckoutProgress?
    @State private var errorMessage: String?
    @State private var orderReview: OrderReview = .verifying
    @AppStorage(BuyerSettingKey.paymentLimitBaseUnits) private var limitBaseUnits = 0
    @AppStorage(BuyerSettingKey.confirmPaymentsWithBiometrics) private var confirmWithBiometrics = true

    // The buyer's view of the scanned order. A v2 QR carries the manifest hash, so the
    // app fetches the document, rehashes it, and cross-checks every economic field;
    // payment stays blocked unless that verification succeeds. v1 QRs predate manifests
    // and continue as a plain protected checkout.
    private enum OrderReview {
        case verifying
        case legacy
        case verified(OrderManifest, UIImage?)
        case blocked(String)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                checkoutHero
                if case .blocked(let reason) = orderReview {
                    blockedOrderCard(reason)
                }
                policyCard
                paymentBreakdown
                safetyNote
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RecourseColor.ledger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(RecourseColor.night)
        .navigationTitle("Confirm payment")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            checkoutActionBar
        }
        .fullScreenCover(isPresented: $paid) {
            PaymentSuccessView(amount: request.amount, paidToLabel: successLabel) {
                paid = false
                environment.router.reset()
            }
        }
        .task {
            await loadOrder()
        }
    }

    private var successLabel: String {
        if case .verified(let manifest, _) = orderReview {
            return manifest.itemName
        }
        return request.merchant.shortened
    }

    private var canPay: Bool {
        switch orderReview {
        case .legacy, .verified: !exceedsLimit
        case .verifying, .blocked: false
        }
    }

    private var exceedsLimit: Bool {
        PaymentLimit.exceeded(amount: request.amount, limitBaseUnits: limitBaseUnits)
    }

    private func loadOrder() async {
        guard request.carriesOrderManifest else {
            orderReview = .legacy
            return
        }
        orderReview = .verifying
        do {
            let api = environment.makeOrderAPIClient()
            let bytes = try await api.fetchManifestBytes(orderReference: request.orderReference)
            let manifest = try OrderManifest.decode(
                verifying: bytes,
                orderReference: request.orderReference
            )
            try manifest.crossCheck(against: request)

            var image: UIImage?
            if let hash = manifest.imageHash {
                do {
                    image = UIImage(data: try await api.fetchImage(hash: hash))
                } catch OrderManifestError.imageHashMismatch {
                    // A wrong image is tampering, not an outage: block like any mismatch.
                    throw OrderManifestError.imageHashMismatch
                } catch {
                    // Missing image is a degraded view; the economic terms verified above.
                    image = nil
                }
            }
            orderReview = .verified(manifest, image)
        } catch let error as OrderManifestError {
            orderReview = .blocked(blockedReason(error))
        } catch {
            orderReview = .blocked(
                "The order details could not be loaded. Recourse will not pay until the order is verified."
            )
        }
    }

    private func blockedReason(_ error: OrderManifestError) -> String {
        switch error {
        case .hashMismatch:
            "The order details do not match the scanned code. Do not pay: ask the merchant for a fresh checkout."
        case .fieldMismatch(let field):
            "The order's \(field) does not match the scanned code. Do not pay: ask the merchant for a fresh checkout."
        case .invalidManifest:
            "The order details are incomplete or malformed. Ask the merchant for a fresh checkout."
        case .imageHashMismatch:
            "The product photo does not match this order. Do not pay: ask the merchant for a fresh checkout."
        }
    }

    private func blockedOrderCard(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Payment blocked", systemImage: "hand.raised.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(RecourseColor.nightText)
            Text(reason)
                .font(.system(size: 12))
                .foregroundStyle(RecourseColor.nightMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") {
                Task { await loadOrder() }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(RecourseColor.ledger)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(RecourseColor.nightLine, lineWidth: 1)
        }
    }

    private var progressLabel: String {
        switch progress {
        case .validating:
            "Validating checkout…"
        case .loadingPolicy:
            "Loading protection policy…"
        case .checkingFunds:
            "Checking USDC balance…"
        case .approvalSubmitted:
            "Approving protected spend…"
        case .approvalConfirmed:
            "Approval confirmed…"
        case .paymentSubmitted:
            "Submitting protected payment…"
        case .paymentConfirmed:
            "Payment confirmed"
        case nil:
            "Protecting payment…"
        }
    }

    private func submitPayment() {
        // Same rule as the disabled button: no payment without a verified (or legacy v1)
        // order, even if another code path calls this directly.
        guard !isPaying, canPay else { return }
        isPaying = true
        errorMessage = nil
        progress = .validating

        Task {
            do {
                let gateway = try environment.makeContractGateway()
                let buyer = try await environment.buyerSigner.address()
                let result = try await CheckoutWorkflow(
                    gateway: gateway,
                    configuration: environment.configuration
                ).execute(request: request, buyer: buyer) { update in
                    await MainActor.run {
                        progress = update
                    }
                }
                var manifest: OrderManifest?
                if case .verified(let verifiedManifest, _) = orderReview {
                    manifest = verifiedManifest
                }
                environment.paymentStore.record(
                    payment: result.payment,
                    request: request,
                    manifest: manifest
                )
                paid = true
            } catch {
                errorMessage = checkoutErrorMessage(error)
            }
            isPaying = false
        }
    }

    private func checkoutErrorMessage(_ error: any Error) -> String {
        switch error {
        case BuyerWorkflowError.insufficientBalance:
            "Your Arc wallet does not have enough USDC for this payment."
        case BuyerWorkflowError.merchantMismatch:
            "The checkout does not match the merchant's protected policy."
        case TransactionAuthorizationError.cancelled:
            "Payment confirmation was cancelled."
        case TransactionAuthorizationError.unavailable:
            "Set a device passcode or Face ID before paying."
        case ContractReadError.rpc(let code, let message):
            "Arc RPC error \(code): \(message)"
        default:
            "The protected payment could not be completed. Please try again."
        }
    }

    private var checkoutHero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                orderArtwork
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paying")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
                    Text(orderTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(RecourseColor.nightText)
                        .lineLimit(2)
                    Text(request.merchant.shortened)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
                Spacer()
                orderStatusBadge
            }

            if case .verified(let manifest, _) = orderReview {
                Text(manifest.description)
                    .font(.system(size: 13))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(manifest.orderReference)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(RecourseColor.nightMuted)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("TOTAL")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(RecourseColor.nightMuted)
                Text(currencyAmount)
                    .font(.system(size: 46, weight: .medium, design: .rounded))
                    .foregroundStyle(RecourseColor.nightText)
                Text("\(request.amount.formatted) · Arc Testnet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
            }

            HStack(spacing: 9) {
                Image(systemName: "shield.checkered")
                Text("Protection terms lock before money moves")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(RecourseColor.ledger)
            .padding(14)
            .background(RecourseColor.ledger.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(18)
        .background(RecourseColor.night)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(RecourseColor.nightLine, lineWidth: 1)
        }
    }

    // The verified order's image or a neutral placeholder; never stock artwork.
    @ViewBuilder
    private var orderArtwork: some View {
        if case .verified(_, let image) = orderReview, let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        } else {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
                .frame(width: 58, height: 58)
                .background(RecourseColor.ledger.opacity(0.18), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
    }

    private var orderTitle: String {
        switch orderReview {
        case .verified(let manifest, _):
            manifest.itemName
        case .verifying:
            "Verifying order…"
        case .legacy:
            "Protected checkout"
        case .blocked:
            "Order not verified"
        }
    }

    @ViewBuilder
    private var orderStatusBadge: some View {
        switch orderReview {
        case .verifying:
            ProgressView()
                .tint(RecourseColor.ledger)
        case .verified:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 19))
                .foregroundStyle(RecourseColor.ledger)
                .accessibilityLabel("Order verified")
        case .legacy:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 19))
                .foregroundStyle(RecourseColor.ledger)
        case .blocked:
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 19))
                .foregroundStyle(RecourseColor.nightText)
                .accessibilityLabel("Payment blocked")
        }
    }

    private var checkoutActionBar: some View {
        VStack(spacing: 9) {
            if exceedsLimit {
                Label(
                    "Above your \(PaymentLimit.formatted(baseUnits: limitBaseUnits)) per-payment limit. Change it in Settings.",
                    systemImage: "gauge.with.dots.needle.100percent"
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
            }

            Button {
                submitPayment()
            } label: {
                HStack(spacing: 10) {
                    if isPaying { ProgressView().tint(.white) }
                    Text(payButtonTitle)
                    if !isPaying, canPay, confirmWithBiometrics {
                        Image(systemName: "faceid")
                    }
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(RecourseColor.ledgerDeep, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isPaying || !canPay)
            .opacity(canPay || isPaying ? 1 : 0.5)

            Text(
                confirmWithBiometrics
                    ? "Face ID confirms this protected Arc payment"
                    : "Face ID confirmation is off. Turn it on in Settings."
            )
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(RecourseColor.nightMuted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(RecourseColor.night)
    }

    private var payButtonTitle: String {
        if isPaying { return progressLabel }
        switch orderReview {
        case .verifying: return "Verifying order…"
        case .blocked: return "Payment blocked"
        case .legacy, .verified: return "Pay \(currencyAmount)"
        }
    }

    private var currencyAmount: String {
        let amount = Double(request.amount.baseUnits) / Double(USDCAmount.base)
        return String(format: "$%.2f", amount)
    }

    private var policyCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR PROTECTION").recourseEyebrow()
                    Text("Digital service delivery")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(RecourseColor.nightText)
                }
                Spacer()
                Text("POLICY #\(request.policyID)")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(RecourseColor.ledger)
            }
            policyTerm("Full refund", "If access is not delivered within 10 minutes", "timer")
            Divider()
            policyTerm("14-day window", "Report an eligible service problem", "calendar")
            Divider()
            policyTerm("Verifiable verdict", "The first matching policy rule decides", "checkmark.seal")
        }
        .padding(.vertical, 4)
    }

    private func policyTerm(_ title: String, _ text: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RecourseColor.nightText)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(RecourseColor.nightText)
                Text(text).font(.system(size: 12)).foregroundStyle(RecourseColor.nightMuted)
            }
        }
    }

    private var paymentBreakdown: some View {
        VStack(spacing: 14) {
            breakdownRow("Payment", currencyAmount)
            breakdownRow("Network fee", "Sponsored")
            breakdownRow("Settlement", "Instant to merchant")
        }
        .padding(18)
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func breakdownRow(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(bold ? RecourseColor.nightText : RecourseColor.nightMuted)
            Spacer()
            Text(value).fontWeight(bold ? .bold : .medium).foregroundStyle(RecourseColor.nightText)
        }
        .font(.system(size: 14))
    }

    private var safetyNote: some View {
        Label("Recourse cannot change the policy after you confirm.", systemImage: "lock.fill")
            .font(.system(size: 12))
            .foregroundStyle(RecourseColor.nightMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// A choreographed confirmation, not a static screen: haptic + shield spring with a
// one-shot pulse ring, the amount counting up, detail rows cascading in, and the brand
// aurora breathing along the bottom. Reduce Motion collapses the sequence to a still.
private struct PaymentSuccessView: View {
    let amount: USDCAmount
    let paidToLabel: String
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsShield = false
    @State private var pulses = false
    @State private var shownCents: UInt64 = 0
    @State private var showsCaption = false
    @State private var visibleRows = 0
    @State private var showsFooter = false

    // Display cents (2 decimals) derived from 6-decimal base units; the count-up
    // animates over these so every intermediate frame is a real currency value.
    private var totalCents: UInt64 {
        amount.baseUnits / 10_000
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 22) {
                shieldHero

                VStack(spacing: 8) {
                    Text("Payment protected")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(RecourseColor.nightText)
                        .opacity(showsShield ? 1 : 0)
                    Text(countedAmount)
                        .font(.system(size: 54, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(RecourseColor.nightText)
                        .opacity(showsShield ? 1 : 0)
                    Text("Paid for \(paidToLabel) on Arc Testnet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .lineLimit(1)
                        .opacity(showsCaption ? 1 : 0)
                        .offset(y: showsCaption ? 0 : 6)
                }

                VStack(spacing: 0) {
                    successRow("Payment", "Confirmed", "checkmark.circle.fill", index: 1)
                    Divider().padding(.leading, 42)
                    successRow("Protection", "14 days active", "shield.checkered", index: 2)
                    Divider().padding(.leading, 42)
                    successRow("Receipt", "Reproducible on Arc", "checkmark.seal", index: 3)
                }
                .padding(.horizontal, 16)
                .background(
                    RecourseColor.nightChip,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
            }

            Spacer()

            VStack(spacing: 10) {
                Button("View protected payments", action: onDone)
                    .buttonStyle(RecoursePrimaryButtonStyle())
                Text("Your receipt and policy are saved together.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
            .opacity(showsFooter ? 1 : 0)
            .offset(y: showsFooter ? 0 : 10)
        }
        .padding(24)
        .background {
            successAurora
                .ignoresSafeArea()
        }
        .task {
            await runChoreography()
        }
    }

    private var shieldHero: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [RecourseColor.ledger.opacity(0.16), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 110
                    )
                )
                .frame(width: 220, height: 220)
                .opacity(showsShield ? 1 : 0)

            // One-shot ripple: expands and fades exactly once at the reveal.
            Circle()
                .stroke(RecourseColor.ledger.opacity(pulses ? 0 : 0.35), lineWidth: 1.5)
                .frame(width: 120, height: 120)
                .scaleEffect(pulses ? 2.05 : 0.8)

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
                .scaleEffect(showsShield ? 1 : 0.35)
                .opacity(showsShield ? 1 : 0)
        }
        .frame(height: 180)
    }

    // The brand aurora, dialed down: two soft green blooms breathing along the bottom
    // edge on unsynchronized clocks, behind the footer.
    private var successAurora: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                RecourseColor.night
                bloom(RecourseColor.ledger, size: 460)
                    .opacity(0.22 + 0.05 * sin(t * 0.19))
                    .offset(x: -130 + 30 * sin(t * 0.23), y: 430 + 18 * cos(t * 0.17))
                bloom(Color(red: 0.38, green: 0.68, blue: 0.31), size: 280)
                    .opacity(0.16 + 0.04 * cos(t * 0.27))
                    .offset(x: 70 + 40 * sin(t * 0.13 + 2.2), y: 470 + 14 * sin(t * 0.21 + 0.9))
            }
        }
    }

    private func bloom(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: color, location: 0),
                        .init(color: color, location: 0.22),
                        .init(color: color.opacity(0), location: 1)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
    }

    private func successRow(
        _ label: String,
        _ value: String,
        _ icon: String,
        index: Int
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RecourseColor.ledger)
                .frame(width: 30)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(RecourseColor.nightMuted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RecourseColor.nightText)
        }
        .frame(height: 52)
        .opacity(visibleRows >= index ? 1 : 0)
        .offset(y: visibleRows >= index ? 0 : 14)
    }

    private var countedAmount: String {
        String(format: "$%llu.%02llu", shownCents / 100, shownCents % 100)
    }

    @MainActor
    private func runChoreography() async {
        guard !reduceMotion else {
            showsShield = true
            pulses = true
            shownCents = totalCents
            showsCaption = true
            visibleRows = 3
            showsFooter = true
            return
        }

        try? await Task.sleep(for: .milliseconds(150))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) {
            showsShield = true
        }
        withAnimation(.easeOut(duration: 1.0)) {
            pulses = true
        }

        try? await Task.sleep(for: .milliseconds(320))
        // Eased count-up: fast start, soft landing, every frame a real value.
        let steps = 26
        for step in 1 ... steps {
            let progress = Double(step) / Double(steps)
            let eased = 1 - pow(1 - progress, 3)
            shownCents = UInt64((Double(totalCents) * eased).rounded())
            if step < steps {
                try? await Task.sleep(for: .milliseconds(34))
            }
        }
        shownCents = totalCents

        withAnimation(.easeOut(duration: 0.3)) {
            showsCaption = true
        }
        try? await Task.sleep(for: .milliseconds(140))
        for row in 1 ... 3 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                visibleRows = row
            }
            try? await Task.sleep(for: .milliseconds(110))
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.4)) {
            showsFooter = true
        }
    }
}

struct PaymentDetailView: View {
    let payment: DemoPayment
    let router: AppRouter
    @State private var shareCard: Image?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                statusHero
                protectionWindow
                timeline
                details
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .background(RecourseColor.night)
        .navigationTitle("Protected payment")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            actions
        }
        .task {
            shareCard = PaymentShareCard.render(for: payment)
        }
        .toolbar {
            if let shareCard {
                ToolbarItem(placement: .topBarTrailing) {
                    // The receipt goes back into the chat where the deal
                    // happened: a branded card with the public verifier QR.
                    ShareLink(
                        item: shareCard,
                        preview: SharePreview("Payment #\(payment.id) · Recourse", image: shareCard)
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private var statusHero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                MerchantArtwork(payment: payment, size: 58, cornerRadius: 17)
                VStack(alignment: .leading, spacing: 4) {
                    Text(payment.merchant)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(RecourseColor.nightText)
                    Text(payment.item)
                        .font(.system(size: 12))
                        .foregroundStyle(RecourseColor.nightMuted)
                        .lineLimit(1)
                    Text(payment.orderReference)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
                Spacer()
                Label(payment.state.rawValue, systemImage: payment.state.systemImage)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 38, height: 38)
                    .background(statusColor.opacity(0.10), in: Circle())
            }

            Divider()

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(currencyAmount)
                        .font(.system(size: 42, weight: .medium, design: .rounded))
                        .foregroundStyle(RecourseColor.nightText)
                    Text("\(payment.amountText) paid \(payment.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
                Spacer()
                Text(payment.state.rawValue.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.9)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .frame(height: 27)
                    .background(statusColor.opacity(0.10), in: Capsule())
            }
        }
        .padding(18)
        .background(RecourseColor.night)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(RecourseColor.nightLine, lineWidth: 1)
        }
    }

    private var protectionWindow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PROTECTION").recourseEyebrow()
                    Text(payment.policyName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(RecourseColor.nightText)
                }
                Spacer()
                Image(systemName: "shield.checkered")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(RecourseColor.ledger)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(protectionStatusTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(RecourseColor.nightText)
                Spacer()
                Text(protectionStatusDetail)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(RecourseColor.ledger)
            }

            ProgressView(value: max(0.04, min(payment.progress, 1)))
                .tint(RecourseColor.ledger)
        }
        .padding(18)
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var protectionStatusTitle: String {
        switch payment.state {
        case .protected:
            "Protection window open"
        case .actionNeeded:
            "Your response is required"
        case .underReview:
            "Evidence is under review"
        case .refunded:
            "Refund returned to you"
        case .released:
            "Payment completed"
        }
    }

    private var protectionStatusDetail: String {
        switch payment.state {
        case .protected, .actionNeeded:
            "Ends \(payment.protectionEnds.formatted(date: .abbreviated, time: .omitted))"
        case .underReview:
            "Decision pending"
        case .refunded, .released:
            "Outcome recorded"
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("PAYMENT JOURNEY").recourseEyebrow()
            timelineRow("Paid", payment.date.formatted(date: .abbreviated, time: .shortened), true)
            timelineRow("Protection activated", payment.policyName, true)
            timelineRow(
                payment.state == .protected ? "Protection window open" : payment.state.rawValue,
                payment.state == .protected
                    ? "Ends \(payment.protectionEnds.formatted(date: .abbreviated, time: .omitted))"
                    : "Recorded on Arc",
                payment.state != .actionNeeded
            )
        }
        .padding(.horizontal, 4)
    }

    private func timelineRow(_ title: String, _ subtitle: String, _ complete: Bool) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(RecourseColor.ledger)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(RecourseColor.nightText)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(RecourseColor.nightMuted)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var details: some View {
        VStack(spacing: 14) {
            detailRow("Order", payment.orderReference)
            Divider()
            detailRow("Policy", payment.policyName)
            Divider()
            detailRow("Network", "Arc Testnet")
            Divider()
            detailRow("Payment ID", "#\(payment.id)")
        }
        .padding(18)
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(RecourseColor.nightMuted)
            Spacer()
            Text(value).fontWeight(.medium).foregroundStyle(RecourseColor.nightText).multilineTextAlignment(.trailing)
        }
        .font(.system(size: 13))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if payment.state == .actionNeeded || payment.state == .protected {
                Button(payment.state == .actionNeeded ? "Add evidence" : "Report a problem") {
                    router.push(.dispute(payment.id))
                }
                .buttonStyle(RecoursePrimaryButtonStyle())
            }
            Button {
                router.push(.verdict(payment.id))
            } label: {
                Label("Verify onchain proof", systemImage: "checkmark.seal")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(RecourseColor.nightText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RecourseColor.nightChip, in: Capsule())
                    .overlay(Capsule().stroke(RecourseColor.nightLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(RecourseColor.night)
    }

    private var statusColor: Color {
        switch payment.state {
        case .actionNeeded: RecourseColor.ledger
        case .underReview: RecourseColor.ledger
        default: RecourseColor.ledger
        }
    }

    private var currencyAmount: String {
        let amount = Double(payment.amount.baseUnits) / Double(USDCAmount.base)
        return String(format: "$%.2f", amount)
    }
}

struct DisputeFilingView: View {
    let payment: DemoPayment
    let environment: AppEnvironment
    @State private var selectedClaim: ClaimType = .notDelivered
    @State private var description = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isSubmitting = false
    @State private var progress: DisputeProgress?
    @State private var errorMessage: String?
    @State private var submitted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                intro
                claimPicker
                evidence
                descriptionField
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RecourseColor.ledger)
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(RecourseColor.night)
        .navigationTitle("Add evidence")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            disputeActionBar
        }
        .alert("Evidence submitted", isPresented: $submitted) {
            Button("View status") { environment.router.push(.verdict(payment.id)) }
        } message: {
            Text("Your evidence is linked to payment #\(payment.id). The policy engine will produce a verifiable outcome.")
        }
    }

    private var intro: some View {
        HStack(spacing: 14) {
            MerchantArtwork(payment: payment, size: 52, cornerRadius: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(payment.merchant).font(.system(size: 16, weight: .bold))
                Text("\(currencyAmount) · \(payment.orderReference)")
                    .font(.system(size: 12)).foregroundStyle(RecourseColor.nightMuted)
            }
            Spacer()
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 20))
                .foregroundStyle(RecourseColor.ledger)
        }
        .padding(16)
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var claimPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What went wrong?").font(.system(size: 21, weight: .bold)).foregroundStyle(RecourseColor.nightText)
            VStack(spacing: 0) {
                ForEach(Array(ClaimType.allCases.enumerated()), id: \.element) { index, claim in
                    Button {
                        selectedClaim = claim
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: claimIcon(claim))
                                .foregroundStyle(selectedClaim == claim ? RecourseColor.ledger : RecourseColor.nightMuted)
                                .frame(width: 24)
                            Text(claimTitle(claim))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(RecourseColor.nightText)
                            Spacer()
                            Image(systemName: selectedClaim == claim ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedClaim == claim ? RecourseColor.ledger : RecourseColor.nightLine)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 52)
                        .background(selectedClaim == claim ? RecourseColor.ledger.opacity(0.18) : Color.clear)
                    }
                    .buttonStyle(.plain)
                    if index < ClaimType.allCases.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(RecourseColor.nightLine))
        }
    }

    private var evidence: some View {
        let hasPhoto = photoData != nil

        return VStack(alignment: .leading, spacing: 12) {
            Text("Add evidence").font(.system(size: 21, weight: .bold)).foregroundStyle(RecourseColor.nightText)
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                PhotoEvidencePickerLabel(hasPhoto: hasPhoto)
            }
            .buttonStyle(.plain)
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    photoData = try? await item?.loadTransferable(type: Data.self)
                }
            }
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tell us more").font(.system(size: 16, weight: .bold))
            TextEditor(text: $description)
                .frame(minHeight: 110)
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(RecourseColor.nightLine))
        }
    }

    private func claimTitle(_ claim: ClaimType) -> String {
        switch claim {
        case .notDelivered: "Not delivered"
        case .damaged: "Damaged"
        case .notAsDescribed: "Not as described"
        case .wrongItem: "Wrong item"
        case .other: "Something else"
        }
    }

    private func claimIcon(_ claim: ClaimType) -> String {
        switch claim {
        case .notDelivered: "shippingbox"
        case .damaged: "exclamationmark.triangle"
        case .notAsDescribed: "text.magnifyingglass"
        case .wrongItem: "arrow.left.arrow.right"
        case .other: "ellipsis.circle"
        }
    }

    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currencyAmount: String {
        let amount = Double(payment.amount.baseUnits) / Double(USDCAmount.base)
        return String(format: "$%.2f", amount)
    }

    private var disputeActionBar: some View {
        VStack(spacing: 8) {
            Button {
                submitEvidence()
            } label: {
                HStack(spacing: 10) {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    }
                    Text(isSubmitting ? progressLabel : "Submit evidence")
                    if !isSubmitting {
                        Image(systemName: "faceid")
                    }
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(RecourseColor.ledgerDeep, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || (photoData == nil && trimmedDescription.isEmpty))
            .opacity(photoData == nil && trimmedDescription.isEmpty ? 0.48 : 1)

            Text("Your device key signs the evidence manifest")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(RecourseColor.nightMuted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(RecourseColor.night)
    }

    private var progressLabel: String {
        switch progress {
        case .validating:
            "Checking payment…"
        case .uploading(let completed, let total):
            "Uploading evidence \(completed)/\(total)…"
        case .filing:
            "Filing on Arc…"
        case .submitted:
            "Confirming transaction…"
        case .publishingManifest:
            "Publishing proof manifest…"
        case .confirmed:
            "Evidence confirmed"
        case nil:
            "Submitting evidence…"
        }
    }

    private func submitEvidence() {
        guard !isSubmitting else { return }
        guard environment.paymentStore.payment(id: payment.id) != nil else {
            errorMessage = "Use a receipt created by a completed Arc checkout to submit live evidence."
            return
        }

        do {
            let drafts = try evidenceDrafts()
            isSubmitting = true
            errorMessage = nil
            progress = .validating

            Task {
                do {
                    let buyer = try await environment.buyerSigner.address()
                    let gateway = try environment.makeContractGateway()
                    _ = try await DisputeWorkflow(
                        gateway: gateway,
                        evidenceRepository: environment.makeEvidenceRepository(),
                        timeProvider: SystemUnixTimeProvider()
                    ).execute(
                        paymentID: payment.id,
                        buyer: buyer,
                        claimType: selectedClaim,
                        evidence: drafts
                    ) { update in
                        await MainActor.run {
                            progress = update
                        }
                    }
                    environment.paymentStore.markDisputed(paymentID: payment.id)
                    submitted = true
                } catch {
                    errorMessage = disputeErrorMessage(error)
                }
                isSubmitting = false
            }
        } catch {
            errorMessage = "Add a description or photo before submitting."
        }
    }

    private func evidenceDrafts() throws -> [EvidenceDraft] {
        var drafts: [EvidenceDraft] = []
        if !trimmedDescription.isEmpty {
            drafts.append(
                try EvidenceDraft(
                    kind: .description,
                    content: Data(trimmedDescription.utf8)
                )
            )
        }
        if let photoData {
            drafts.append(
                try EvidenceDraft(
                    kind: .photo,
                    content: photoData,
                    contentType: "image/jpeg"
                )
            )
        }
        guard !drafts.isEmpty else { throw BuyerWorkflowError.emptyEvidence }
        return drafts
    }

    private func disputeErrorMessage(_ error: any Error) -> String {
        switch error {
        case BuyerWorkflowError.disputeWindowClosed:
            "The protection window for this payment has closed."
        case BuyerWorkflowError.notBuyer:
            "This device wallet is not the buyer for this payment."
        case TransactionAuthorizationError.cancelled:
            "Evidence submission was cancelled."
        case EvidenceAPIError.httpStatus:
            "The evidence service rejected this upload. Check the backend connection."
        default:
            "Evidence could not be submitted. Please try again."
        }
    }
}

private struct PhotoEvidencePickerLabel: View {
    let hasPhoto: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: hasPhoto ? "photo.fill" : "camera.fill")
                .font(.system(size: 20))
                .foregroundStyle(RecourseColor.ledger)
            VStack(alignment: .leading, spacing: 3) {
                Text(hasPhoto ? "Evidence photo selected" : "Add a photo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                Text(hasPhoto ? "Ready for encrypted upload" : "Show what happened clearly")
                    .font(.system(size: 12))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
            Spacer()
            Image(systemName: hasPhoto ? "checkmark.circle.fill" : "plus.circle")
                .foregroundStyle(RecourseColor.ledger)
        }
        .padding(18)
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(RecourseColor.nightLine))
    }
}

struct VerdictDetailView: View {
    let payment: DemoPayment

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                verdictHero
                proofCard
                policyMatch
                sourceCard
            }
            .padding(20)
            .padding(.bottom, 50)
        }
        .background(RecourseColor.night)
        .navigationTitle("Verify outcome")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isRefunded: Bool { payment.state == .refunded || payment.id == 268 }

    private var verdictHero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                MerchantArtwork(payment: payment, size: 54, cornerRadius: 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text(payment.merchant)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(RecourseColor.nightText)
                    Text(payment.orderReference)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(RecourseColor.nightMuted)
                }
                Spacer()
                Image(systemName: isRefunded ? "arrow.uturn.backward.circle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(RecourseColor.ledger)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(isRefunded ? "REFUNDED" : payment.state == .underReview ? "UNDER REVIEW" : "VERIFIED")
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(RecourseColor.ledger)
                Text(isRefunded ? "The policy returned your payment." : "The receipt matches Arc state.")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(RecourseColor.nightText)
                Text(isRefunded ? "100% buyer refund · \(currencyAmount)" : "\(currencyAmount) independently reproducible")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
            }
        }
        .padding(18)
        .background(RecourseColor.night)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(RecourseColor.nightLine, lineWidth: 1)
        }
    }

    private var proofCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CRYPTOGRAPHIC PROOF")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.52))
                    Text("Two engines, one result")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "touchid")
                    .font(.system(size: 25))
                    .foregroundStyle(Color(red: 0.46, green: 0.88, blue: 0.66))
            }

            proofHashRow("Onchain eth_call", "0x683e3c…bc650f", "Solidity")
            HStack {
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                Image(systemName: "equal.circle.fill")
                    .foregroundStyle(Color(red: 0.46, green: 0.88, blue: 0.66))
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            }
            proofHashRow("In-app recompute", "0x683e3c…bc650f", "Swift")

            Label("Hashes match exactly", systemImage: "checkmark.shield.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.46, green: 0.88, blue: 0.66))
        }
        .padding(20)
        .background(Color(red: 0.055, green: 0.065, blue: 0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func proofHashRow(_ title: String, _ hash: String, _ source: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                Text(hash)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            Spacer()
            Text(source)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.74))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.white.opacity(0.10), in: Capsule())
        }
    }

    private var policyMatch: some View {
        ProtectedCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("FIRST MATCH WINS").recourseEyebrow()
                    Spacer()
                    Label("ONCHAIN", systemImage: "lock.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(RecourseColor.ledger)
                }
                rule("1", "Not delivered", "100% refund", isRefunded)
                rule("2", "Damaged", "100% refund", false)
                rule("3", "Not as described", "50% refund", false)
            }
        }
    }

    private func rule(_ number: String, _ title: String, _ result: String, _ matched: Bool) -> some View {
        HStack(spacing: 12) {
            Text(number).font(.system(size: 12, weight: .bold)).foregroundStyle(matched ? .white : RecourseColor.nightMuted).frame(width: 28, height: 28).background(matched ? RecourseColor.ledger : RecourseColor.ledger.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(RecourseColor.nightText)
                Text(result).font(.system(size: 11)).foregroundStyle(RecourseColor.nightMuted)
            }
            Spacer()
            if matched { Label("Matched", systemImage: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(RecourseColor.ledger) }
        }
        .padding(12)
        .background(matched ? RecourseColor.ledger.opacity(0.18) : RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(RecourseColor.nightLine))
    }

    private var sourceCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "link.circle.fill").font(.system(size: 24)).foregroundStyle(RecourseColor.ledger)
            VStack(alignment: .leading, spacing: 3) {
                Text("Public proof").font(.system(size: 14, weight: .bold)).foregroundStyle(RecourseColor.nightText)
                Text("Anyone can recompute this verdict from Arc state.").font(.system(size: 12)).foregroundStyle(RecourseColor.nightMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
    }

    private var currencyAmount: String {
        let amount = Double(payment.amount.baseUnits) / Double(USDCAmount.base)
        return String(format: "$%.2f", amount)
    }
}

struct SupportView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Help when money\nfeels uncertain.")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(RecourseColor.nightText)
                Text("Start with the payment. Recourse keeps its policy, proof, and support context together.")
                    .foregroundStyle(RecourseColor.nightMuted)
                    .lineSpacing(4)
                ProtectedCard {
                    VStack(spacing: 0) {
                        supportRow("Message support", "Usually replies in a few minutes", "message.fill")
                        Divider().padding(.leading, 48)
                        supportRow("Payment help", "Find an answer by receipt", "doc.text.magnifyingglass")
                        Divider().padding(.leading, 48)
                        supportRow("How protection works", "Policies, evidence, and verdicts", "shield.checkered")
                    }
                }
                Text("EMERGENCY CONTROLS").recourseEyebrow()
                ProtectedCard {
                    supportRow("Secure my account", "Review this iPhone and signing key", "lock.shield.fill")
                }
            }
            .padding(20)
        }
        .background(RecourseColor.night)
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func supportRow(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).foregroundStyle(RecourseColor.ledger).frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(RecourseColor.nightText)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(RecourseColor.nightMuted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(RecourseColor.nightMuted)
        }
        .padding(.vertical, 14)
    }
}

#if DEBUG
#Preview("Checkout review") {
    NavigationStack {
        CheckoutReviewView(
            request: DemoCatalog.checkoutRequest(configuration: .live),
            environment: .preview()
        )
    }
    .tint(RecourseColor.ledger)
}

#Preview("Payment receipt") {
    NavigationStack {
        PaymentDetailView(
            payment: DemoCatalog.payment(id: 281),
            router: AppRouter()
        )
    }
    .tint(RecourseColor.ledger)
}

#Preview("File dispute") {
    NavigationStack {
        DisputeFilingView(
            payment: DemoCatalog.payment(id: 284),
            environment: .preview()
        )
    }
    .tint(RecourseColor.ledger)
}

#Preview("Verified refund") {
    NavigationStack {
        VerdictDetailView(payment: DemoCatalog.payment(id: 268))
    }
    .tint(RecourseColor.ledger)
}

#Preview("Support") {
    NavigationStack {
        SupportView()
    }
    .tint(RecourseColor.ledger)
}
#endif

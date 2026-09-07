import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Adding money from a chain that is not Arc, without connecting anything.
///
/// The person is shown a plain address and sends USDC to it from an exchange, or from
/// whatever wallet they already keep dollars in. There is nothing to connect and nothing
/// to sign, which is the whole point: asking somebody to connect a wallet turns a money
/// app back into a crypto app.
///
/// The address is a contract whose only power is paying this account on Arc, and where
/// it pays is part of the code it was built from, so the address itself is the promise.
struct BridgeDepositView: View {
    let environment: AppEnvironment

    @State private var deposit: DepositAddress?
    @State private var loadFailed = false
    @State private var copied: String?

    var body: some View {
        ScrollView {
            content
        }
        .scrollIndicators(.hidden)
        .background(RecourseColor.night)
        .navigationTitle("From another chain")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 20) {
            if let deposit, deposit.isOpen {
                header(deposit)
                qr(for: deposit)
                addressBlock(deposit)
                chainList(deposit)
                steps(deposit)
            } else if loadFailed {
                unavailable
            } else {
                ProgressView().frame(height: 240)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity)
    }

    private func header(_ deposit: DepositAddress) -> some View {
        VStack(spacing: 6) {
            Text("Your deposit address")
                .font(.recourse(17, .semibold))
                .foregroundStyle(RecourseColor.nightText)
            Text("Send USDC here from any of these chains and it arrives in your Recourse balance.")
                .font(.recourse(12, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
        }
    }

    private func qr(for deposit: DepositAddress) -> some View {
        Group {
            if let image = qrImage(for: deposit.address) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 190, height: 190)
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(RecourseColor.nightLine, lineWidth: 1)
                    }
            }
        }
    }

    private func addressBlock(_ deposit: DepositAddress) -> some View {
        VStack(spacing: 14) {
            Text(deposit.address)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(RecourseColor.nightText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)

            Button {
                UIPasteboard.general.string = deposit.address
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.snappy(duration: 0.2)) { copied = deposit.address }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.snappy(duration: 0.2)) { copied = nil }
                }
            } label: {
                let done = copied == deposit.address
                Label(done ? "Copied" : "Copy address", systemImage: done ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RecourseColor.ledger, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 26)
        }
    }

    /// One address on every chain is the unusual part, so it is shown rather than
    /// claimed: the chains are named, and the sentence says the address is the same
    /// on all of them.
    private func chainList(_ deposit: DepositAddress) -> some View {
        VStack(spacing: 10) {
            FlowChips(names: deposit.chains.map(\.chainName))
            Text("The same address on every one of them.")
                .font(.recourse(11.5, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
        }
        .padding(.horizontal, 22)
    }

    /// The two things that lose people money here are sending the wrong token and
    /// sending on the wrong chain, so both are said plainly rather than in a footnote.
    private func steps(_ deposit: DepositAddress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            rule("USDC only", detail: "On the chains above. Anything else sent here cannot be recovered.", icon: "exclamationmark.triangle.fill", tint: RecourseColor.nightText)
            rule("At least \(deposit.minimum) USDC", detail: "Less than that waits here until you add more.", icon: "arrow.down.circle.fill", tint: RecourseColor.nightMuted)
            rule("Arrives in about a minute", detail: "Circle moves it to Arc. You are told when it lands.", icon: "clock.fill", tint: RecourseColor.nightMuted)
            rule("Nobody holds it but you", detail: "This address can only pay your Recourse account, and nothing else.", icon: "lock.fill", tint: RecourseColor.nightMuted)
        }
        .padding(16)
        .background(RecourseColor.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(RecourseColor.nightLine, lineWidth: 1)
        }
        .padding(.horizontal, 22)
    }

    private func rule(_ title: String, detail: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.recourse(13, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                Text(detail)
                    .font(.recourse(11.5, .medium))
                    .foregroundStyle(RecourseColor.nightMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(RecourseColor.nightMuted)
            Text("Not open yet")
                .font(.recourse(15, .semibold))
                .foregroundStyle(RecourseColor.nightText)
            Text("Deposits from another chain are not switched on for this build. Add money on Arc for now.")
                .font(.recourse(12, .medium))
                .foregroundStyle(RecourseColor.nightMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
        }
        .padding(.top, 50)
    }

    @MainActor
    private func load() async {
        guard deposit == nil else { return }
        do {
            let found = try await environment.accountSession.withAccessToken { token in
                try await environment.depositAPI.addresses(accessToken: token)
            }
            deposit = found
            loadFailed = !found.isOpen
        } catch {
            loadFailed = true
        }
    }

    private func qrImage(for content: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Chain names that wrap onto as many rows as they need. A fixed grid would leave a
/// ragged gap when eight names of different lengths meet a narrow phone.
private struct FlowChips: View {
    let names: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(.recourse(12, .semibold))
                    .foregroundStyle(RecourseColor.nightText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RecourseColor.nightChip, in: Capsule())
                    .overlay(Capsule().stroke(RecourseColor.nightLine, lineWidth: 1))
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, width: width)
        let height = rows.reduce(CGFloat.zero) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width == .infinity ? rows.map(\.width).max() ?? 0 : width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, width: bounds.width)
        var y = bounds.minY
        for row in rows {
            // Centred, because a left aligned last row of two chips reads as a mistake.
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if next > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
                row.indices = [index]
                row.width = size.width
                row.height = size.height
            } else {
                row.indices.append(index)
                row.width = next
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

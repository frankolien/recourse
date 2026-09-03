import SwiftUI

/// A cheque drawn as a cheque.
///
/// Deliberately literal. Every other screen in this app renders a payment as a row,
/// which is right for something that already happened; a cheque has not happened yet,
/// and the whole reason it is worth having is that it is an object you hand to someone.
/// Drawing the payee line, the amount box and the signature makes the mental model
/// arrive without a paragraph explaining it.
///
/// The stamp is the same idea. A settled cheque is not greyed out, it is cancelled
/// across the face, because that is what cancelling a cheque has always looked like and
/// it reads instantly at a glance a status pill never will.
struct ChequePaper: View {
    let entry: ChequeEntry
    /// The name to print on the payee line, resolved by whoever built the list.
    let counterpartyName: String
    /// True when this account wrote it, which decides whose name is on the payee line.
    let mine: Bool
    var compact = false

    @Environment(\.colorScheme) private var colorScheme

    private var stored: StoredCheque { entry.stored }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 14 : 20) {
            header
            payeeLine
            amountRow
            if !compact {
                Divider().overlay(edgeInk.opacity(0.25))
                footer
            }
        }
        .padding(compact ? 18 : 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(paper)
        .overlay(alignment: .leading) { perforation }
        .overlay(alignment: .center) { stamp }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(edgeInk.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.1), radius: 20, y: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(mine ? "PAY TO" : "PAY TO THE ORDER OF")
                    .font(.recourse(9, .semibold))
                    .kerning(1.3)
                    .foregroundStyle(faintInk)
                Text(mine ? "You wrote this" : "Written to you")
                    .font(.recourse(11, .medium))
                    .foregroundStyle(faintInk)
            }
            Spacer()
            standingBadge
        }
    }

    private var payeeLine: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(counterpartyName)
                .font(.recourse(compact ? 18 : 22, .bold))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // The ruled line under the payee is what makes a cheque a cheque, and it
            // costs one rectangle.
            Rectangle()
                .fill(edgeInk.opacity(0.22))
                .frame(height: 1)
        }
    }

    private var amountRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("AMOUNT")
                    .font(.recourse(9, .semibold))
                    .kerning(1.3)
                    .foregroundStyle(faintInk)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(stored.usdc.decimalString)
                        .font(.system(size: compact ? 28 : 36, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("USDC")
                        .font(.recourse(12, .bold))
                        .foregroundStyle(faintInk)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let memo = stored.memo, !memo.isEmpty {
                labelled("MEMO", memo)
            }
            HStack(alignment: .top, spacing: 18) {
                labelled("EXPIRES", expiryText)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 5) {
                    Text("SIGNED")
                        .font(.recourse(9, .semibold))
                        .kerning(1.3)
                        .foregroundStyle(faintInk)
                    // The last four bytes of the signature, used the way a cheque uses
                    // a signature: not to be read, but so two cheques can be told apart
                    // and one can be quoted over the phone.
                    Text(signatureTail)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(ink.opacity(0.8))
                }
            }
        }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.recourse(9, .semibold))
                .kerning(1.3)
                .foregroundStyle(faintInk)
            Text(value)
                .font(.recourse(12, .medium))
                .foregroundStyle(ink.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    private var standingBadge: some View {
        Text(badgeText)
            .font(.recourse(10, .semibold))
            .kerning(0.4)
            .foregroundStyle(badgeInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(badgeInk.opacity(0.12), in: Capsule())
    }

    /// The tear line a cheque carries where it left the book. One dashed rule, inset,
    /// which is the whole of the stub gesture and costs nothing to draw.
    private var perforation: some View {
        TearLine()
            .stroke(edgeInk.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            .frame(width: 1)
            .padding(.vertical, 14)
            .padding(.leading, 9)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var stamp: some View {
        if let text = stampText {
            Text(text)
                .font(.recourse(compact ? 24 : 34, .bold))
                .kerning(4)
                .foregroundStyle(stampInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(stampInk, lineWidth: 3)
                }
                .rotationEffect(.degrees(-14))
                .opacity(0.65)
                .allowsHitTesting(false)
        }
    }

    // MARK: Copy

    private var badgeText: String {
        switch entry.standing {
        case .cashable: mine ? "Outstanding" : "Ready to cash"
        case .notYet: "Not yet"
        case .expired: "Expired"
        case .cashed: "Cashed"
        case .voided: "Voided"
        }
    }

    private var stampText: String? {
        switch entry.standing {
        case .cashed: "CASHED"
        case .voided: "VOID"
        case .expired: "EXPIRED"
        case .cashable, .notYet: nil
        }
    }

    private var expiryText: String {
        entry.standing == .expired
            ? stored.expiresAt.formatted(date: .abbreviated, time: .shortened)
            : Self.relative.localizedString(for: stored.expiresAt, relativeTo: Date())
    }

    private var signatureTail: String {
        String(stored.signature.suffix(8))
    }

    private var accessibilityText: String {
        "\(stored.usdc.formatted) cheque, \(mine ? "written to" : "from") \(counterpartyName), \(badgeText)"
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    // MARK: Ink

    /// The paper stays the same near-white in both appearances on purpose. A cheque is
    /// a physical object in the metaphor, and a cheque that inverts with the system
    /// theme stops being one.
    private var paper: some View {
        LinearGradient(
            colors: [Color(red: 0.98, green: 0.98, blue: 0.97), Color(red: 0.93, green: 0.94, blue: 0.93)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var ink: Color { RecourseColor.ink }
    private var faintInk: Color { RecourseColor.ink.opacity(0.45) }
    private var edgeInk: Color { RecourseColor.ink }

    private var badgeInk: Color {
        switch entry.standing {
        case .cashable: RecourseColor.ledger
        case .notYet: RecourseColor.ink.opacity(0.55)
        case .expired, .voided: RecourseColor.ink.opacity(0.55)
        case .cashed: RecourseColor.ledger
        }
    }

    private var stampInk: Color {
        entry.standing == .cashed ? RecourseColor.ledger : RecourseColor.ink.opacity(0.55)
    }
}

/// One vertical rule, dashed by the caller.
private struct TearLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

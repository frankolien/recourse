import SwiftUI

struct ProtectedCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RecourseColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(RecourseColor.line, lineWidth: 1)
            }
    }
}

struct MerchantArtwork: View {
    let payment: DemoPayment
    var size: CGFloat = 44
    var cornerRadius: CGFloat = 13

    var body: some View {
        AsyncImage(url: payment.merchantImageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .empty:
                ZStack {
                    Color(red: 0.94, green: 0.94, blue: 0.92)
                    ProgressView()
                        .controlSize(.small)
                        .tint(RecourseColor.ledger)
                }
            case .failure:
                fallback
            @unknown default:
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.72), lineWidth: 0.7)
        }
    }

    private var fallback: some View {
        Image(systemName: payment.merchantSymbol)
            .font(.system(size: size * 0.34, weight: .semibold))
            .foregroundStyle(RecourseColor.ledger)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.94, green: 0.96, blue: 0.93))
    }
}

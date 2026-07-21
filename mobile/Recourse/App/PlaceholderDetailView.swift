import SwiftUI

struct PlaceholderDetailView: View {
    let eyebrow: String
    let title: String
    let message: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(eyebrow)
                    .recourseEyebrow()

                Text(title)
                    .font(RecourseTypography.display(size: 42))
                    .foregroundStyle(RecourseColor.ink)

                Text(message)
                    .font(.body)
                    .foregroundStyle(RecourseColor.muted)
                    .lineSpacing(5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .background(RecourseColor.canvas)
        .navigationBarTitleDisplayMode(.inline)
    }
}

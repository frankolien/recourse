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

// Product images are content-addressed and immutable, so a decoded image is cached
// for the app's lifetime and any URL is worth retrying. NSCache is thread-safe,
// hence the unchecked Sendable.
private final class ArtworkCache: @unchecked Sendable {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url.absoluteString as NSString)
    }
}

struct MerchantArtwork: View {
    let payment: DemoPayment
    var size: CGFloat = 44
    var cornerRadius: CGFloat = 13

    // Not AsyncImage: scrolling or a busy first refresh cancels its in-flight load and
    // the phase sticks at .failure with no retry, leaving rows on the fallback icon
    // forever. This loader retries on every fresh appearance and caches successes.
    @State private var loaded: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let url = payment.merchantImageURL {
                if let loaded {
                    Image(uiImage: loaded)
                        .resizable()
                        .scaledToFill()
                } else if failed {
                    fallback
                } else {
                    ZStack {
                        Color(red: 0.94, green: 0.94, blue: 0.92)
                        ProgressView()
                            .controlSize(.small)
                            .tint(RecourseColor.ledger)
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.72), lineWidth: 0.7)
        }
        .task(id: payment.merchantImageURL) {
            guard let url = payment.merchantImageURL, loaded == nil else { return }
            failed = false
            await load(url)
        }
    }

    private func load(_ url: URL) async {
        if let cached = ArtworkCache.shared.image(for: url) {
            loaded = cached
            return
        }
        for attempt in 0..<2 {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse,
                      http.statusCode == 200,
                      let image = UIImage(data: data) else {
                    throw URLError(.badServerResponse)
                }
                ArtworkCache.shared.store(image, for: url)
                loaded = image
                return
            } catch let error as URLError where error.code == .cancelled {
                // The view went away; the next appearance restarts the task.
                return
            } catch {
                if attempt == 0 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
        failed = true
    }

    private var fallback: some View {
        Image(systemName: payment.merchantSymbol)
            .font(.system(size: size * 0.34, weight: .semibold))
            .foregroundStyle(RecourseColor.ledger)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.94, green: 0.96, blue: 0.93))
    }
}

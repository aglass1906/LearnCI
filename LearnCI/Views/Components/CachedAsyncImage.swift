import SwiftUI

/// A drop-in replacement for AsyncImage that caches downloaded images in memory.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var uiImage: UIImage?
    @State private var isLoading = false

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
                    .onAppear { loadImage() }
            }
        }
    }

    private func loadImage() {
        guard let url, !isLoading else { return }

        // Check memory cache
        if let cached = ImageCacheStore.shared.get(for: url) {
            uiImage = cached
            return
        }

        isLoading = true
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    ImageCacheStore.shared.set(image, for: url)
                    await MainActor.run {
                        uiImage = image
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run { isLoading = false }
            }
        }
    }
}

/// Thread-safe in-memory image cache backed by NSCache.
private final class ImageCacheStore {
    static let shared = ImageCacheStore()

    private let cache = NSCache<NSURL, UIImage>()

    init() {
        cache.countLimit = 200
    }

    func get(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func set(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

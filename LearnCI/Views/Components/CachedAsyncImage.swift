import SwiftUI

/// A drop-in replacement for AsyncImage that caches downloaded images in memory and on disk.
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

        if let cached = ImageCacheStore.shared.get(for: url) {
            uiImage = cached
            return
        }

        isLoading = true
        Task {
            defer {
                Task { @MainActor in isLoading = false }
            }

            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad

            do {
                let (data, response) = try await ImageCacheStore.shared.session.data(for: request)
                guard let image = UIImage(data: data) else { return }

                ImageCacheStore.shared.set(image, for: url)

                if let httpResponse = response as? HTTPURLResponse {
                    let cachedResponse = CachedURLResponse(response: httpResponse, data: data)
                    ImageCacheStore.shared.urlCache.storeCachedResponse(cachedResponse, for: request)
                }

                await MainActor.run {
                    uiImage = image
                }
            } catch {
                // Keep placeholder on failure.
            }
        }
    }
}

/// Thread-safe image cache with in-memory and URLSession disk backing.
private final class ImageCacheStore {
    static let shared = ImageCacheStore()

    let urlCache: URLCache
    let session: URLSession

    private let memoryCache = NSCache<NSURL, UIImage>()

    init() {
        memoryCache.countLimit = 200

        urlCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )

        let config = URLSessionConfiguration.default
        config.urlCache = urlCache
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    func get(for url: URL) -> UIImage? {
        memoryCache.object(forKey: url as NSURL)
    }

    func set(_ image: UIImage, for url: URL) {
        memoryCache.setObject(image, forKey: url as NSURL)
    }
}

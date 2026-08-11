import UIKit

actor NowPlayingArtworkLoader {
    static let shared = NowPlayingArtworkLoader()

    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: URL, maximumDimension: CGFloat = 600) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) != false,
              let original = UIImage(data: data) else { return nil }

        let scale = min(1, maximumDimension / max(original.size.width, original.size.height))
        let size = CGSize(width: original.size.width * scale, height: original.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in original.draw(in: CGRect(origin: .zero, size: size)) }
        cache.setObject(resized, forKey: url as NSURL)
        return resized
    }
}

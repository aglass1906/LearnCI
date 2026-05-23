import SwiftUI
import SafariServices
import Combine

struct InAppBrowserView: View {
    let url: URL
    let onDismiss: () -> Void

    @State private var startTime = Date()
    @State private var elapsed: TimeInterval = 0

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var youtubeVideoId: String? {
        FavoritesManager.resolveVideoId(from: url.absoluteString)
    }
    
    var body: some View {
        NavigationStack {
            SafariView(url: url, onDismiss: onDismiss)
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 6) {
                            Image(systemName: "timer")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Text(formatElapsed(elapsed))
                                .font(.subheadline.monospacedDigit())
                                .fontWeight(.semibold)
                            Text("input")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    if let videoId = youtubeVideoId {
                        ToolbarItem(placement: .topBarLeading) {
                            FavoriteButton(
                                consumptionUrl: "https://www.youtube.com/watch?v=\(videoId)",
                                type: .youtube,
                                title: "YouTube Video",
                                author: nil,
                                imageUrl: "https://img.youtube.com/vi/\(videoId)/mqdefault.jpg"
                            )
                            .font(.title3)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            onDismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
        }
        .onReceive(timer) { _ in
            elapsed = Date().timeIntervalSince(startTime)
        }
    }

    private func formatElapsed(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Safari UIViewControllerRepresentable

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let safariVC = SFSafariViewController(url: url)
        safariVC.modalPresentationStyle = .pageSheet
        safariVC.delegate = context.coordinator
        return safariVC
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        var onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onDismiss()
        }
    }
}

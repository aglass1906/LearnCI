import SwiftUI
import WebKit

struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    
    @Binding var watchDuration: TimeInterval
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        // Add Script Handler
        configuration.userContentController.add(context.coordinator, name: "playbackHandler")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .black
        webView.isOpaque = false
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Prevent reloading if the video is already loaded
        guard context.coordinator.currentVideoID != videoID else { return }
        context.coordinator.currentVideoID = videoID
        
        let embedHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body { margin: 0; background-color: black; }
        .video-container { position: relative; padding-bottom: 56.25%; height: 0; overflow: hidden; }
        .video-container iframe { position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
        </style>
        </head>
        <body>
        <div class="video-container">
        <div id="player"></div>
        </div>
        <script>
        var tag = document.createElement('script');
        tag.src = "https://www.youtube.com/iframe_api";
        var firstScriptTag = document.getElementsByTagName('script')[0];
        firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

        var player;
        function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
                height: '100%',
                width: '100%',
                videoId: '\(videoID)',
                playerVars: {
                    'playsinline': 1,
                    'controls': 1,
                    'rel': 0,
                    'fs': 1,
                    'origin': 'https://learnci.app'
                },
                events: {
                    'onStateChange': onPlayerStateChange
                }
            });
        }
        
        function onPlayerStateChange(event) {
            // Send state to Swift (1 = Playing, 2 = Paused, 0 = Ended)
            window.webkit.messageHandlers.playbackHandler.postMessage(event.data);
        }
        </script>
        </body>
        </html>
        """
        
        uiView.loadHTMLString(embedHTML, baseURL: URL(string: "https://learnci.app"))
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: YouTubePlayerView
        var timer: Timer?
        var currentVideoID: String?
        
        init(_ parent: YouTubePlayerView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let state = message.body as? Int {
                if state == 1 { // Playing
                    startTimer()
                } else {
                    stopTimer()
                }
            }
        }
        
        func startTimer() {
            stopTimer() // Ensure no duplicates
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.parent.watchDuration += 1
                }
            }
        }
        
        func stopTimer() {
            timer?.invalidate()
            timer = nil
        }
    }
}

#Preview {
    YouTubePlayerView(videoID: "dQw4w9WgXcQ", watchDuration: .constant(0))
        .frame(height: 220)
}

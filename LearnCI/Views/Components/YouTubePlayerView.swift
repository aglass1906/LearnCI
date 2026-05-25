import SwiftUI
import WebKit

struct YouTubePlayerPlaybackSnapshot: Equatable {
    let currentTime: Double
    let duration: Double
    let playbackRate: Float
    let isPlaying: Bool
}

struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    var videoURL: String? = nil // Optional direct URL

    @Binding var watchDuration: TimeInterval
    @Binding private var seekRequest: Double?
    @Binding private var playbackRateRequest: Float?

    var onPlaybackSnapshot: ((YouTubePlayerPlaybackSnapshot) -> Void)?

    init(
        videoID: String,
        videoURL: String? = nil,
        watchDuration: Binding<TimeInterval>,
        seekRequest: Binding<Double?> = .constant(nil),
        playbackRateRequest: Binding<Float?> = .constant(nil),
        onPlaybackSnapshot: ((YouTubePlayerPlaybackSnapshot) -> Void)? = nil
    ) {
        self.videoID = videoID
        self.videoURL = videoURL
        self._watchDuration = watchDuration
        self._seekRequest = seekRequest
        self._playbackRateRequest = playbackRateRequest
        self.onPlaybackSnapshot = onPlaybackSnapshot
    }

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
        if context.coordinator.currentVideoID != videoID {
            context.coordinator.currentVideoID = videoID

            if let videoURL = videoURL, let url = URL(string: videoURL) {
                // Render HTML5 Video Player
                let html = """
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body { margin: 0; background-color: black; display: flex; align-items: center; justify-content: center; height: 100vh; }
video { width: 100%; height: 100%; object-fit: contain; }
</style>
</head>
<body>
<video id="player" controls playsinline autoplay>
<source src="\(videoURL)" type="video/mp4">
Your browser does not support the video tag.
</video>
<script>
var video = document.getElementById('player');
var snapshotTimer = null;

function postSnapshot() {
window.webkit.messageHandlers.playbackHandler.postMessage({
type: 'snapshot',
currentTime: video.currentTime || 0,
duration: video.duration || 0,
playbackRate: video.playbackRate || 1,
isPlaying: !video.paused && !video.ended
});
}

function startSnapshotTimer() {
stopSnapshotTimer();
snapshotTimer = setInterval(postSnapshot, 100);
}

function stopSnapshotTimer() {
if (snapshotTimer) {
clearInterval(snapshotTimer);
snapshotTimer = null;
}
}

video.addEventListener('play', function() {
window.webkit.messageHandlers.playbackHandler.postMessage(1);
startSnapshotTimer();
postSnapshot();
});
video.addEventListener('pause', function() {
window.webkit.messageHandlers.playbackHandler.postMessage(2);
stopSnapshotTimer();
postSnapshot();
});
video.addEventListener('ended', function() {
window.webkit.messageHandlers.playbackHandler.postMessage(0);
stopSnapshotTimer();
postSnapshot();
});
video.addEventListener('timeupdate', postSnapshot);
video.addEventListener('loadedmetadata', postSnapshot);
video.addEventListener('ratechange', postSnapshot);
video.addEventListener('seeked', postSnapshot);

function seekToTime(seconds) {
video.currentTime = seconds;
postSnapshot();
}

function setPlaybackRateValue(rate) {
video.playbackRate = rate;
postSnapshot();
}
</script>
</body>
</html>
"""
                uiView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())

            } else {
                // Render YouTube Player
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
var snapshotTimer = null;
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
'onReady': onPlayerReady,
'onStateChange': onPlayerStateChange
}
});
}

function onPlayerReady() {
postSnapshot();
}

function startSnapshotTimer() {
stopSnapshotTimer();
snapshotTimer = setInterval(postSnapshot, 100);
}

function stopSnapshotTimer() {
if (snapshotTimer) {
clearInterval(snapshotTimer);
snapshotTimer = null;
}
}

function postSnapshot() {
if (!player || !player.getCurrentTime) { return; }
window.webkit.messageHandlers.playbackHandler.postMessage({
type: 'snapshot',
currentTime: player.getCurrentTime ? player.getCurrentTime() : 0,
duration: player.getDuration ? player.getDuration() : 0,
playbackRate: player.getPlaybackRate ? player.getPlaybackRate() : 1,
isPlaying: player.getPlayerState ? player.getPlayerState() === YT.PlayerState.PLAYING : false
});
}

function onPlayerStateChange(event) {
// Send state to Swift (1 = Playing, 2 = Paused, 0 = Ended)
window.webkit.messageHandlers.playbackHandler.postMessage(event.data);
if (event.data === YT.PlayerState.PLAYING) {
startSnapshotTimer();
} else {
stopSnapshotTimer();
}
postSnapshot();
}

function seekToTime(seconds) {
if (player && player.seekTo) {
player.seekTo(seconds, true);
postSnapshot();
}
}

function setPlaybackRateValue(rate) {
if (player && player.setPlaybackRate) {
player.setPlaybackRate(rate);
postSnapshot();
}
}
</script>
</body>
</html>
"""
                uiView.loadHTMLString(embedHTML, baseURL: URL(string: "https://learnci.app"))
            }
        }

        if let seekRequest {
            context.coordinator.seek(to: seekRequest, in: uiView)
            DispatchQueue.main.async {
                self.seekRequest = nil
            }
        }

        if let playbackRateRequest {
            context.coordinator.setPlaybackRate(playbackRateRequest, in: uiView)
            DispatchQueue.main.async {
                self.playbackRateRequest = nil
            }
        }
    }

    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: YouTubePlayerView
        var watchTimer: Timer?
        var currentVideoID: String?

        init(_ parent: YouTubePlayerView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let state = message.body as? Int {
                if state == 1 { // Playing
                    startWatchTimer()
                } else {
                    stopWatchTimer()
                }
                return
            }

            if let payload = message.body as? [String: Any] {
                handlePlaybackPayload(payload)
            }
        }

        func seek(to time: Double, in webView: WKWebView) {
            let js = "seekToTime(\(max(0, time)));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func setPlaybackRate(_ rate: Float, in webView: WKWebView) {
            let clampedRate = max(0.25, min(rate, 2.0))
            let js = "setPlaybackRateValue(\(clampedRate));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func handlePlaybackPayload(_ payload: [String: Any]) {
            let currentTime = Self.doubleValue(payload["currentTime"]) ?? 0
            let duration = Self.doubleValue(payload["duration"]) ?? 0
            let playbackRate = Float(Self.doubleValue(payload["playbackRate"]) ?? 1)
            let isPlaying = payload["isPlaying"] as? Bool ?? false

            let snapshot = YouTubePlayerPlaybackSnapshot(
                currentTime: currentTime,
                duration: duration,
                playbackRate: playbackRate,
                isPlaying: isPlaying
            )

            DispatchQueue.main.async {
                self.parent.onPlaybackSnapshot?(snapshot)
            }

            if isPlaying {
                startWatchTimer()
            } else {
                stopWatchTimer()
            }
        }

        private func startWatchTimer() {
            guard watchTimer == nil else { return }
            watchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.parent.watchDuration += 1
                }
            }
        }

        private func stopWatchTimer() {
            watchTimer?.invalidate()
            watchTimer = nil
        }

        deinit {
            stopWatchTimer()
        }

        private static func doubleValue(_ raw: Any?) -> Double? {
            if let value = raw as? Double { return value }
            if let value = raw as? Int { return Double(value) }
            if let value = raw as? NSNumber { return value.doubleValue }
            if let value = raw as? String { return Double(value) }
            return nil
        }
    }
}

#Preview {
    YouTubePlayerView(videoID: "dQw4w9WgXcQ", watchDuration: .constant(0))
        .frame(height: 220)
}

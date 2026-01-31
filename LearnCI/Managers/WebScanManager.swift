import Foundation
import WebKit
import Observation

@MainActor
@Observable
class WebScanManager: NSObject, WKNavigationDelegate {
    static let shared = WebScanManager()
    
    private var webView: WKWebView!
    private var continuation: CheckedContinuation<[YouTubeVideo], Error>?
    private var isScanning = false
    
    override init() {
        super.init()
        // Initialize headless WebView
        let config = WKWebViewConfiguration()
        // Fake a desktop user agent if needed, or default mobile
        config.applicationNameForUserAgent = "LearnCI/1.0" 
        
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.navigationDelegate = self
    }
    
    /// Scans a URL for YouTube videos by loading it in a WebView
    func scan(url: URL) async throws -> [YouTubeVideo] {
        guard !isScanning else {
            throw NSError(domain: "WebScanManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Scan already in progress"])
        }
        
        isScanning = true
        print("🔍 WebScanManager (SPA): Starting scan for \(url.absoluteString)")
        
        // Use continuation to bridge delegate pattern to async/await
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = URLRequest(url: url)
            self.webView.load(request)
            
            // Set a timeout
            Task {
                try? await Task.sleep(nanoseconds: 15 * 1_000_000_000) // 15s timeout
                if self.isScanning {
                    print("❌ WebScanManager: Timeout reached")
                    self.finishScan(with: NSError(domain: "WebScanManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Scan timed out"]), results: nil)
                }
            }
        }
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Check where we ended up
        webView.evaluateJavaScript("document.title + ' | ' + window.location.href") { (result, error) in
            if let info = result as? String {
                 print("🔍 WebScanManager: Loaded Page -> \(info)")
            }
        }
        
        print("🔍 WebScanManager: Page loaded. Waiting for JS execution...")
        
        // Wait a brief moment for dynamic content to render (SPAs often render after 'load')
        // Then extract
        Task {
            try? await Task.sleep(nanoseconds: 2 * 1_000_000_000) // 2s wait for React/Vue
            await extractVideosFromDOM()
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ WebScanManager: Navigation failed: \(error)")
        finishScan(with: error, results: nil)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("❌ WebScanManager: Provisional navigation failed: \(error)")
        finishScan(with: error, results: nil)
    }
    
    // MARK: - Extraction Logic
    
    // MARK: - Extraction Logic
    
    /// Public extraction method for external WebViews (Interactive Mode)
    func extractVideos(from externalWebView: WKWebView) async throws -> [YouTubeVideo] {
        return try await performExtraction(on: externalWebView)
    }
    
    private func extractVideosFromDOM() async {
        do {
            let videos = try await performExtraction(on: self.webView)
            finishScan(with: nil, results: videos)
        } catch {
            print("❌ WebScanManager: JS Error: \(error)")
            finishScan(with: error, results: nil)
        }
    }
    
    private func performExtraction(on targetWebView: WKWebView) async throws -> [YouTubeVideo] {
        // JS to find links, iframes, and video tags
        let js = """
        (function() {
            const results = [];
            const seen = new Set();
            
            function add(url, type) {
                if (!url) return;
                // Resolve relative URLs
                const fullUrl = new URL(url, document.baseURI).href;
                if (seen.has(fullUrl)) return;
                seen.add(fullUrl);
                results.push({ url: fullUrl, type: type });
            }

            // 1. YouTube Links (Anchors)
            document.querySelectorAll('a').forEach(a => {
                if (a.href && (a.href.includes('youtube.com/watch') || a.href.includes('youtu.be/'))) {
                    add(a.href, 'youtube');
                }
                // Video Files
                if (a.href && (a.href.match(/\\.(mp4|mov|m4v|webm|mkv)$/i))) {
                    add(a.href, 'file');
                }
            });

            // 2. Iframes (YouTube Embeds)
            document.querySelectorAll('iframe').forEach(f => {
                if (f.src && (f.src.includes('youtube.com/embed') || f.src.includes('youtube.com/watch'))) {
                    add(f.src, 'youtube');
                }
            });
            
            // 3. Video Tags
            document.querySelectorAll('video').forEach(v => {
                if (v.src) add(v.src, 'file');
                v.querySelectorAll('source').forEach(s => {
                    if (s.src) add(s.src, 'file');
                });
            });
            
            // 4. YouTube Thumbnails (img tags) - BEST for Gallery/Browse pages
            // Pattern: https://i.ytimg.com/vi/VIDEO_ID/hqdefault.jpg
            document.querySelectorAll('img').forEach(img => {
                if (img.src && (img.src.includes('ytimg.com/vi/') || img.src.includes('youtube.com/vi/'))) {
                    // We extract the ID later on the Swift side, just pass the URL
                    add(img.src, 'youtube');
                }
            });

            return results;
        })();
        """
        
        let result = try await targetWebView.evaluateJavaScript(js)
        
        if let items = result as? [[String: String]] {
            print("🔍 WebScanManager: Found \(items.count) items via JS")
            var videos: [YouTubeVideo] = []
            
            // Process items
            for item in items {
                guard let url = item["url"], let type = item["type"] else { continue }
                
                if type == "youtube" {
                    let ids = extractVideoIds(from: [url])
                    if let id = ids.first {
                        videos.append(createPlaceholderVideo(id: id))
                    }
                } else if type == "file" {
                    videos.append(createFileVideo(url: url))
                }
            }
            
            // Deduplicate by ID
            let uniqueVideos = Array(Dictionary(grouping: videos, by: { $0.id }).values.compactMap { $0.first })
            return uniqueVideos
        }
        
        return []
    }
    
    private func finishScan(with error: Error?, results: [YouTubeVideo]?) {
        guard isScanning else { return }
        isScanning = false
        
        // Reset webview
        webView.loadHTMLString("", baseURL: nil)
        
        if let error = error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume(returning: results ?? [])
        }
        continuation = nil
    }
    
    private func extractVideoIds(from urls: [String]) -> [String] {
        var ids = Set<String>()
        
        let watchPattern = "v=([a-zA-Z0-9_-]{11})"
        let shortPattern = "youtu\\.be/([a-zA-Z0-9_-]{11})"
        let embedPattern = "embed/([a-zA-Z0-9_-]{11})"
        let thumbnailPattern = "/vi/([a-zA-Z0-9_-]{11})/" // for i.ytimg.com/vi/ID/...
        
        for url in urls {
             ids.formUnion(performRegex(pattern: watchPattern, in: url))
             ids.formUnion(performRegex(pattern: shortPattern, in: url))
             ids.formUnion(performRegex(pattern: embedPattern, in: url))
             ids.formUnion(performRegex(pattern: thumbnailPattern, in: url))
        }
        
        return Array(ids)
    }
    
    private func performRegex(pattern: String, in text: String) -> [String] {
        var results: [String] = []
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                if match.numberOfRanges > 1 {
                    results.append(nsString.substring(with: match.range(at: 1)))
                }
            }
        } catch {}
        return results
    }
    
    private func createPlaceholderVideo(id: String) -> YouTubeVideo {
        YouTubeVideo(
            id: id,
            title: "YouTube Video",
            description: "",
            thumbnailURL: "https://img.youtube.com/vi/\(id)/mqdefault.jpg",
            channelTitle: "YouTube",
            duration: "PT0M0S",
            publishedAt: Date()
        )
    }
    
    private func createFileVideo(url: String) -> YouTubeVideo {
        // Generate a fake ID from the hash of the URL
        let id = String(url.hashValue).replacingOccurrences(of: "-", with: "N")
        let filename = URL(string: url)?.lastPathComponent ?? "Video File"
        
        var video = YouTubeVideo(
            id: id,
            title: filename,
            description: url,
            thumbnailURL: "", // No thumbnail for generic files unless we generate one
            channelTitle: "Web Video",
            duration: "PT0M0S",
            publishedAt: Date()
        )
        video.videoStreamURL = url
        return video
    }
}

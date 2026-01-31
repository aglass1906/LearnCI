import SwiftUI
import SwiftData
import WebKit

struct WebScanView: View {
    let url: URL
    let title: String
    
    @State private var webView: WKWebView? = nil
    @State private var canGoBack = false
    @State private var canGoForward = false
    
    // Found Videos State
    @State private var foundVideos: [YouTubeVideo] = []
    @State private var isScanning = false
    @State private var showResults = false
    @State private var selectedVideo: YouTubeVideo? = nil
    
    // Alert State
    @State private var showNoResultsAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Browser
            InternalWebScanBrowserView(
                url: url,
                webView: $webView,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward
            )
            .edgesIgnoringSafeArea(.bottom) // We have our own toolbar
            
            // Custom Toolbar
            VStack(spacing: 0) {
                Divider()
                HStack {
                    // Navigation
                    Button {
                         webView?.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                    }
                    .disabled(!canGoBack)
                    
                    Button {
                        webView?.goForward()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title2)
                    }
                    .disabled(!canGoForward)
                    .padding(.leading, 20)
                    
                    Spacer()
                    
                    // Scan Action
                    Button {
                        Task {
                            await scanCurrentPage()
                        }
                    } label: {
                        HStack {
                            if isScanning {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "doc.text.viewfinder")
                            }
                            Text(isScanning ? "Scanning..." : "Scan Page")
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                    .disabled(isScanning || webView == nil)
                }
                .padding()
                .background(Color(UIColor.systemBackground))
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("No Videos Found", isPresented: $showNoResultsAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("No YouTube videos or compatible video files were detected on this page.")
        }
        .sheet(isPresented: $showResults) {
            ScanResultsSheet(videos: foundVideos, onSelect: { video in
                selectedVideo = video
                showResults = false // Close results to show player
            })
        }
        .sheet(item: $selectedVideo) { video in
            VideoDetailSheet(
                video: video,
                onWatch: {
                    // Open in YouTube app
                    if let url = URL(string: "youtube://\(video.id)") {
                         if UIApplication.shared.canOpenURL(url) {
                             UIApplication.shared.open(url)
                         } else if let webURL = URL(string: "https://www.youtube.com/watch?v=\(video.id)") {
                             UIApplication.shared.open(webURL)
                         }
                     }
                    selectedVideo = nil
                },
                onLogTime: { _ in
                    selectedVideo = nil
                }
            )
        }
    }
    
    private func scanCurrentPage() async {
        guard let webView = webView else { return }
        
        isScanning = true
        
        do {
            // Use the NEW public method to scan the EXISTING webview
            let videos = try await WebScanManager.shared.extractVideos(from: webView)
            
            await MainActor.run {
                self.foundVideos = videos
                self.isScanning = false
                
                if !videos.isEmpty {
                    self.showResults = true
                } else {
                    self.showNoResultsAlert = true
                }
            }
        } catch {
            print("Scan error: \(error)")
            await MainActor.run {
                self.isScanning = false
            }
        }
    }
}

// Sub-view for results list
struct ScanResultsSheet: View {
    let videos: [YouTubeVideo]
    let onSelect: (YouTubeVideo) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(videos) { video in
                        Button {
                            onSelect(video)
                        } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: video.thumbnailURL)) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                }
                                .frame(width: 120, height: 67.5)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(video.title)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(2)
                                    
                                    Text(video.id)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospaced()
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Found \(videos.count) Videos")
                }
            }
            .navigationTitle("Scan Results")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                         dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}


// Wrapper for WKWebView (Internal to avoid file linking issues)
struct InternalWebScanBrowserView: UIViewRepresentable {
    let url: URL
    // Binding to expose the WKWebView instance to the parent
    // This allows the parent to read the current URL or execute JS
    @Binding var webView: WKWebView?
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "LearnCI/1.0"
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        // Load initial Request
        webView.load(URLRequest(url: url))
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Report the view back to the parent
        DispatchQueue.main.async {
            // Only update if changed to avoid loops, though binding usually safe
            if self.webView != uiView {
                self.webView = uiView
            }
        }
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: InternalWebScanBrowserView
        
        init(_ parent: InternalWebScanBrowserView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // Handle error logic if needed
        }
    }
}


// Wrapper for WKWebView






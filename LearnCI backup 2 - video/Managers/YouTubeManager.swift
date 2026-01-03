import Foundation
import Observation
import GoogleSignIn
import UIKit

@Observable
class YouTubeManager {
    var isAuthenticated: Bool = false
    var youtubeAccount: String?
    var videos: [YouTubeVideo] = []
    var channels: [YouTubeChannel] = []
    var isLoading: Bool = false
    var errorMessage: String?
    
    private let defaults = UserDefaults.standard
    private let accountKey = "youtube_account"
    private let tokenKey = "youtube_access_token"
    
    private var accessToken: String? {
        defaults.string(forKey: tokenKey)
    }
    
    init() {
        // Check if previously authenticated
        if let account = defaults.string(forKey: accountKey) {
            youtubeAccount = account
            isAuthenticated = true
        }
    }
    
    // MARK: - OAuth Authentication
    
    @MainActor
    func signInWithGoogle() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "Unable to find root view controller"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Configure sign-in with YouTube scope
        let signInConfig = GIDConfiguration(clientID: getClientID())
        
        GIDSignIn.sharedInstance.configuration = signInConfig
        
        GIDSignIn.sharedInstance.signIn(
            withPresenting: rootViewController,
            hint: nil,
            additionalScopes: ["https://www.googleapis.com/auth/youtube.readonly"]
        ) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = "Sign in failed: \(error.localizedDescription)"
                    print("Google Sign-In Error: \(error)")
                    return
                }
                
                guard let user = result?.user,
                      let email = user.profile?.email else {
                    self?.errorMessage = "Failed to get user information"
                    return
                }
                
                // Successfully signed in
                self?.youtubeAccount = email
                self?.isAuthenticated = true
                self?.defaults.set(email, forKey: self?.accountKey ?? "")
                
                // Store access token for API calls
                let accessToken = user.accessToken.tokenString
                self?.defaults.set(accessToken, forKey: self?.tokenKey ?? "")
                
                print("Successfully signed in as: \(email)")
                print("Access token stored")
                self?.loadVideosFromAPI()
            }
        }
    }
    
    func disconnect() {
        GIDSignIn.sharedInstance.signOut()
        isAuthenticated = false
        youtubeAccount = nil
        videos = []
        channels = []
        defaults.removeObject(forKey: accountKey)
        defaults.removeObject(forKey: tokenKey)
    }
    
    // MARK: - Helper Methods
    
    private func getClientID() -> String {
        // Try to get from Info.plist
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty else {
            print("WARNING: GIDClientID not found in Info.plist")
            return ""
        }
        return clientID
    }
    
    // MARK: - YouTube API Data Fetching
    
    func loadVideosFromAPI() {
        guard isAuthenticated, let token = accessToken else {
            print("Not authenticated or no access token")
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Fetch subscriptions first, then get videos from those channels
        fetchSubscriptions(token: token) { [weak self] channelIds in
            if channelIds.isEmpty {
                print("No subscriptions found, loading sample videos")
                DispatchQueue.main.async {
                    self?.videos = self?.createSampleVideos() ?? []
                    self?.isLoading = false
                }
            } else {
                self?.fetchVideosFromChannels(token: token, channelIds: channelIds)
            }
        }
    }
    
    private func fetchSubscriptions(token: String, completion: @escaping ([String]) -> Void) {
        let urlString = "https://www.googleapis.com/youtube/v3/subscriptions?part=snippet&mine=true&maxResults=10"
        
        guard let url = URL(string: urlString) else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error fetching subscriptions: \(error)")
                completion([])
                return
            }
            
            guard let data = data else {
                completion([])
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let items = json["items"] as? [[String: Any]] {
                    let channelIds = items.compactMap { item -> String? in
                        if let snippet = item["snippet"] as? [String: Any],
                           let resourceId = snippet["resourceId"] as? [String: Any],
                           let channelId = resourceId["channelId"] as? String {
                            return channelId
                        }
                        return nil
                    }
                    print("Found \(channelIds.count) subscribed channels")
                    completion(channelIds)
                } else {
                    completion([])
                }
            } catch {
                print("Error parsing subscriptions: \(error)")
                completion([])
            }
        }.resume()
    }
    
    private func fetchVideosFromChannels(token: String, channelIds: [String]) {
        // Fetch videos from each channel individually (YouTube API doesn't support multiple channelIds)
        var allVideos: [[String: Any]] = []
        let dispatchGroup = DispatchGroup()
        
        // Limit to first 3 channels to avoid too many API calls
        let channelsToFetch = Array(channelIds.prefix(3))
        
        for channelId in channelsToFetch {
            dispatchGroup.enter()
            
            let urlString = "https://www.googleapis.com/youtube/v3/search?part=snippet&channelId=\(channelId)&maxResults=10&order=date&type=video"
            
            guard let url = URL(string: urlString) else {
                dispatchGroup.leave()
                continue
            }
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                defer { dispatchGroup.leave() }
                
                if let error = error {
                    print("Error fetching videos for channel \(channelId): \(error)")
                    return
                }
                
                guard let data = data else { return }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let items = json["items"] as? [[String: Any]] {
                        allVideos.append(contentsOf: items)
                        print("Found \(items.count) videos from channel \(channelId)")
                    }
                } catch {
                    print("Error parsing videos for channel \(channelId): \(error)")
                }
            }.resume()
        }
        
        // Wait for all requests to complete
        dispatchGroup.notify(queue: .main) { [weak self] in
            let videoIds = allVideos.compactMap { item -> String? in
                if let id = item["id"] as? [String: Any],
                   let videoId = id["videoId"] as? String {
                    return videoId
                }
                return nil
            }
            
            print("Total videos found: \(videoIds.count)")
            if videoIds.isEmpty {
                print("No videos found, showing sample videos")
                self?.videos = self?.createSampleVideos() ?? []
                self?.isLoading = false
            } else {
                // Fetch video details (including duration)
                self?.fetchVideoDetails(token: token, videoIds: videoIds)
            }
        }
    }
    
    private func fetchVideoDetails(token: String, videoIds: [String]) {
        let urlString = "https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails&id=\(videoIds.joined(separator: ","))"
        
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.isLoading = false
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("Error fetching video details: \(error)")
                DispatchQueue.main.async {
                    self?.isLoading = false
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self?.isLoading = false
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let items = json["items"] as? [[String: Any]] {
                    
                    let videos = items.compactMap { item -> YouTubeVideo? in
                        guard let id = item["id"] as? String,
                              let snippet = item["snippet"] as? [String: Any],
                              let contentDetails = item["contentDetails"] as? [String: Any],
                              let title = snippet["title"] as? String,
                              let description = snippet["description"] as? String,
                              let channelTitle = snippet["channelTitle"] as? String,
                              let thumbnails = snippet["thumbnails"] as? [String: Any],
                              let medium = thumbnails["medium"] as? [String: Any],
                              let thumbnailURL = medium["url"] as? String,
                              let duration = contentDetails["duration"] as? String,
                              let publishedAtString = snippet["publishedAt"] as? String else {
                            return nil
                        }
                        
                        let dateFormatter = ISO8601DateFormatter()
                        let publishedAt = dateFormatter.date(from: publishedAtString) ?? Date()
                        
                        return YouTubeVideo(
                            id: id,
                            title: title,
                            description: description,
                            thumbnailURL: thumbnailURL,
                            channelTitle: channelTitle,
                            duration: duration,
                            publishedAt: publishedAt
                        )
                    }
                    
                    DispatchQueue.main.async {
                        self?.videos = videos
                        self?.isLoading = false
                        print("Loaded \(videos.count) videos from YouTube API")
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.isLoading = false
                    }
                }
            } catch {
                print("Error parsing video details: \(error)")
                DispatchQueue.main.async {
                    self?.isLoading = false
                }
            }
        }.resume()
    }
    
    // MARK: - Legacy method for compatibility
    
    func loadVideos() {
        loadVideosFromAPI()
    }
    
    // MARK: - Sample Data (Fallback)
    
    private func createSampleVideos() -> [YouTubeVideo] {
        return [
            YouTubeVideo(
                id: "1",
                title: "Learn Spanish - Basic Greetings",
                description: "Master common Spanish greetings in 10 minutes",
                thumbnailURL: "https://via.placeholder.com/320x180/FF6B6B/FFFFFF?text=Spanish+Greetings",
                channelTitle: "SpanishPod101",
                duration: "PT10M30S",
                publishedAt: Date().addingTimeInterval(-86400 * 2)
            ),
            YouTubeVideo(
                id: "2",
                title: "Japanese Hiragana in 20 Minutes",
                description: "Complete guide to reading hiragana",
                thumbnailURL: "https://via.placeholder.com/320x180/4ECDC4/FFFFFF?text=Hiragana+Guide",
                channelTitle: "JapanesePod101",
                duration: "PT20M15S",
                publishedAt: Date().addingTimeInterval(-86400 * 5)
            ),
            YouTubeVideo(
                id: "3",
                title: "Korean Alphabet - Hangul Basics",
                description: "Learn to read Korean in one lesson",
                thumbnailURL: "https://via.placeholder.com/320x180/95E1D3/FFFFFF?text=Hangul+Basics",
                channelTitle: "Talk To Me In Korean",
                duration: "PT15M45S",
                publishedAt: Date().addingTimeInterval(-86400 * 1)
            ),
            YouTubeVideo(
                id: "4",
                title: "Spanish Pronunciation Guide",
                description: "Perfect your Spanish accent",
                thumbnailURL: "https://via.placeholder.com/320x180/F38181/FFFFFF?text=Pronunciation",
                channelTitle: "Butterfly Spanish",
                duration: "PT12M20S",
                publishedAt: Date().addingTimeInterval(-86400 * 7)
            )
        ]
    }
}

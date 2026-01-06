import Foundation
import Observation
import GoogleSignIn
import UIKit

@Observable
class YouTubeManager {
    var isAuthenticated: Bool = false
    var youtubeAccount: String?
    var videos: [YouTubeVideo] = []
    var channelVideos: [YouTubeVideo] = [] // Dedicated list for selected channel
    var discoveryVideos: [YouTubeVideo] = []
    var recommendedVideos: [YouTubeVideo] = []
    var channels: [YouTubeChannel] = []
    var isLoading: Bool = false
    var isChannelLoading: Bool = false // Separate loading state for channel details
    var isDiscoveryLoading: Bool = false
    var discoveryNextPageToken: String?
    private var currentDiscoveryQuery: (language: Language, level: LearningLevel, category: String)?
    var isRecommendedLoading: Bool = false
    var errorMessage: String?
    
    private let defaults = UserDefaults.standard
    private let accountKey = "youtube_account"
    private let tokenKey = "youtube_access_token"
    
    // Cache Keys
    private let subsVideosKey = "yt_subs_videos"
    private let discoveryVideosKey = "yt_discovery_videos"
    private let recommendedVideosKey = "yt_recommended_videos"
    private let channelsKey = "yt_channels"
    
    private var accessToken: String? {
        defaults.string(forKey: tokenKey)
    }
    
    // Optional: Set a public YouTube Data API Key here to allow discovery without login
    var publicApiKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "YouTubeAPIKey") as? String
    }
    
    init() {
        // Check if previously authenticated
        if let account = defaults.string(forKey: accountKey) {
            youtubeAccount = account
            isAuthenticated = true
        }
        
        // Restore session to ensure token is fresh
        restoreSession()
        
        // Load from cache initially
        loadFromCache()
    }
    
    private func restoreSession() {
        let signInConfig = GIDConfiguration(clientID: getClientID())
        GIDSignIn.sharedInstance.configuration = signInConfig
        
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            if let error = error {
                print("DEBUG: Session restore failed or no previous sign-in: \(error.localizedDescription)")
                // Optionally handle specific errors, but for now we keep local state 
                // allowing user to rely on cache or manually sign in if needed.
                return
            }
            
            guard let user = user else { return }
            
            DispatchQueue.main.async {
                self?.youtubeAccount = user.profile?.email
                self?.isAuthenticated = true
                
                // CRITICAL: Update the stored token with the potentially refreshed value
                let accessToken = user.accessToken.tokenString
                self?.defaults.set(accessToken, forKey: self?.tokenKey ?? "")
                
                // Refresh data with valid token
                self?.loadVideosFromAPI()
            }
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
    
    // MARK: - Caching Logic
    
    private func saveToCache() {
        guard !videos.isEmpty || !discoveryVideos.isEmpty || !recommendedVideos.isEmpty else { return }
        
        let encoder = JSONEncoder()
        if let encodedSubs = try? encoder.encode(videos) {
            defaults.set(encodedSubs, forKey: subsVideosKey)
        }
        if let encodedDiscovery = try? encoder.encode(discoveryVideos) {
            defaults.set(encodedDiscovery, forKey: discoveryVideosKey)
        }
        if let encodedRecommended = try? encoder.encode(recommendedVideos) {
            defaults.set(encodedRecommended, forKey: recommendedVideosKey)
        }
        if let encodedChannels = try? encoder.encode(channels) {
            defaults.set(encodedChannels, forKey: channelsKey)
        }
    }
    
    private func loadFromCache() {
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: subsVideosKey),
           let decoded = try? decoder.decode([YouTubeVideo].self, from: data) {
            videos = decoded
            print("DEBUG: [YouTubeManager] Loaded \(videos.count) videos from cache")
        }
        if let data = defaults.data(forKey: discoveryVideosKey),
           let decoded = try? decoder.decode([YouTubeVideo].self, from: data) {
            discoveryVideos = decoded
        }
        if let data = defaults.data(forKey: recommendedVideosKey),
           let decoded = try? decoder.decode([YouTubeVideo].self, from: data) {
            recommendedVideos = decoded
        }
        if let data = defaults.data(forKey: channelsKey),
           let decoded = try? decoder.decode([YouTubeChannel].self, from: data) {
            channels = decoded
        }
    }
    
    // MARK: - YouTube API Data Fetching
    
    func loadVideosFromAPI(isRefresh: Bool = false) {
        guard isAuthenticated, let token = accessToken else {
            print("Not authenticated or no access token")
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Fetch subscriptions first, then get videos from those channels
        fetchSubscriptions(token: token) { [weak self] channelIds in
            if channelIds.isEmpty {
                // Check if we already have videos from cache before using samples
                if self?.videos.isEmpty ?? true {
                    print("No subscriptions and no cache, loading sample videos")
                    DispatchQueue.main.async {
                        self?.videos = self?.createSampleVideos() ?? []
                        self?.isLoading = false
                    }
                } else {
                    print("No subscriptions found, keeping current cached videos")
                    DispatchQueue.main.async { self?.isLoading = false }
                }
            } else {
                self?.fetchVideosFromChannels(token: token, channelIds: channelIds, isRefresh: isRefresh)
            }
        }
    }
    
    func fetchVideosForChannel(_ channelId: String) {
        guard let token = accessToken else { return }
        channelVideos = [] // Clear previous results
        isChannelLoading = true
        fetchVideosFromChannels(token: token, channelIds: [channelId], target: .singleChannel)
    }
    
    func loadMoreChannelVideos() {
        guard let token = accessToken,
              let playlistId = channelUploadsPlaylistId,
              let pageToken = channelNextPageToken,
              !isChannelLoading else { return }
        
        isChannelLoading = true
        
        let urlString = "https://www.googleapis.com/youtube/v3/playlistItems?part=contentDetails&playlistId=\(playlistId)&maxResults=50&pageToken=\(pageToken)"
        
        guard let url = URL(string: urlString) else {
            isChannelLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else {
                DispatchQueue.main.async { self?.isChannelLoading = false }
                return
            }
            
            // Capture the NEXT page token
            DispatchQueue.main.async {
                self?.channelNextPageToken = json["nextPageToken"] as? String
            }
            
            let ids = items.compactMap { ($0["contentDetails"] as? [String: Any])?["videoId"] as? String }
            
            if ids.isEmpty {
                DispatchQueue.main.async { self?.isChannelLoading = false }
                return
            }
            
            self?.fetchVideoDetails(token: token, videoIds: ids, target: .singleChannelAppend)
            
        }.resume()
    }
    
    func loadMoreFeedVideos() {
        guard let token = accessToken, !isLoading else { return }
        
        // Fix: If activeFeedChannelIds is empty (e.g. valid cache but no API call yet), hydrate from cached channels
        if activeFeedChannelIds.isEmpty && !channels.isEmpty {
            activeFeedChannelIds = channels.map { $0.id }.shuffled()
        }
        
        // Only load more if we haven't exhausted our channel list
        guard feedChannelIndex < activeFeedChannelIds.count else { return }
        
        isLoading = true
        fetchVideosFromChannels(token: token, channelIds: [], target: .feedAppend)
    }
    
    private func fetchSubscriptions(token: String, pageToken: String? = nil, accumulatedChannels: [YouTubeChannel] = [], completion: @escaping ([String]) -> Void) {
        var urlString = "https://www.googleapis.com/youtube/v3/subscriptions?part=snippet&mine=true&maxResults=50"
        if let pageToken = pageToken {
            urlString += "&pageToken=\(pageToken)"
        }
        
        guard let url = URL(string: urlString) else {
            completion(accumulatedChannels.map { $0.id })
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("DEBUG: [YouTubeManager] Subscriptions fetch failed: \(error.localizedDescription)")
                completion(accumulatedChannels.map { $0.id })
                return
            }
            
            guard let data = data else {
                completion(accumulatedChannels.map { $0.id })
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let items = json["items"] as? [[String: Any]] {
                    
                    let fetchedChannels = items.compactMap { item -> YouTubeChannel? in
                        guard let snippet = item["snippet"] as? [String: Any],
                              let resourceId = snippet["resourceId"] as? [String: Any],
                              let channelId = resourceId["channelId"] as? String,
                              let title = snippet["title"] as? String,
                              let thumbnails = snippet["thumbnails"] as? [String: Any],
                              let medium = thumbnails["medium"] as? [String: Any],
                              let thumbnailURL = medium["url"] as? String else {
                            return nil
                        }
                        return YouTubeChannel(id: channelId, title: title, thumbnailURL: thumbnailURL)
                    }
                    
                    let newAccumulated = accumulatedChannels + fetchedChannels
                    let nextPageToken = json["nextPageToken"] as? String
                    
                    DispatchQueue.main.async {
                        self?.channels = newAccumulated
                        print("Fetched page. Total channels so far: \(newAccumulated.count)")
                    }
                    
                    if let nextToken = nextPageToken {
                        // Recurse for next page
                        self?.fetchSubscriptions(token: token, pageToken: nextToken, accumulatedChannels: newAccumulated, completion: completion)
                    } else {
                        // All done
                        completion(newAccumulated.map { $0.id })
                    }
                } else {
                    completion(accumulatedChannels.map { $0.id })
                }
            } catch {
                completion(accumulatedChannels.map { $0.id })
            }
        }.resume()
    }
    
    var channelNextPageToken: String?
    var channelUploadsPlaylistId: String?
    var feedChannelIndex: Int = 0 // Track which channels we've already fetched for the feed
    var activeFeedChannelIds: [String] = [] // Store the shuffled order for the current feed session
    
    // Recs Pagination
    var recsNextPageToken: String?
    var recsUsingMostPopular: Bool = false
    
    enum FetchTarget {
        case feed
        case feedAppend
        case singleChannel
        case singleChannelAppend
    }

    private func fetchVideosFromChannels(token: String, channelIds: [String], isRefresh: Bool = false, target: FetchTarget = .feed) {
        // QUOTA OPTIMIZATION: Instead of searching (100 units), 
        // we fetch the "Uploads" playlist ID for each channel (1 unit)
        // and then fetch the playlist items (1 unit).
        
        var allVideoIds: [String] = []
        let dispatchGroup = DispatchGroup()
        let lock = NSLock()
        
        // For single channel, we fetch up to 20. For feed, we fetch from 5 channels.
        var channelsToFetch: [String] = []
        
        if target == .singleChannel {
            channelsToFetch = channelIds // Should be just one
        } else if target == .singleChannelAppend {
             channelsToFetch = channelIds // We act on the stored playlist ID, so this list might be empty or ignored, 
                                          // BUT for singleChannelAppend we actually skip this function usually and call fetchVideoDetails directly? 
                                          // WAIT. loadMoreChannelVideos calls fetchVideoDetails DIRECTLY. 
                                          // So this function is NOT used for singleChannelAppend. Correct.
                                          // However, for consistency, let's leave it safe.
             channelsToFetch = []
        } else {
             // Feed Logic
             if target == .feed {
                 // Reset / New Session
                 if isRefresh || activeFeedChannelIds.isEmpty {
                     activeFeedChannelIds = channelIds.shuffled()
                 } else if activeFeedChannelIds.isEmpty && !channelIds.isEmpty {
                     activeFeedChannelIds = channelIds // Initial load fallback
                 }
                 feedChannelIndex = 0
             }
             
             // Safely batch next 5
             let endIndex = min(feedChannelIndex + 5, activeFeedChannelIds.count)
             if feedChannelIndex < endIndex {
                 channelsToFetch = Array(activeFeedChannelIds[feedChannelIndex..<endIndex])
                 feedChannelIndex = endIndex
             } else {
                 channelsToFetch = [] // No more channels to fetch
             }
        }
        

        
        for channelId in channelsToFetch {
            dispatchGroup.enter()
            
            // Step 1: Get the 'uploads' playlist ID for the channel
            let channelUrl = "https://www.googleapis.com/youtube/v3/channels?part=contentDetails&id=\(channelId)"
            guard let url = URL(string: channelUrl) else {

                dispatchGroup.leave()
                continue
            }
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in

                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let items = json["items"] as? [[String: Any]],
                      let firstChannel = items.first,
                      let contentDetails = firstChannel["contentDetails"] as? [String: Any],
                      let relatedPlaylists = contentDetails["relatedPlaylists"] as? [String: Any],
                      let uploadsPlaylistId = relatedPlaylists["uploads"] as? String else {
                    
                    // Quota exceeded or channel not found
                    dispatchGroup.leave()
                    return
                }
                

                
                // Step 2: Fetch videos from that playlist
                // Fetch more results for a single channel view
                let maxResults = target == .singleChannel ? 50 : 10
                let playlistUrl = "https://www.googleapis.com/youtube/v3/playlistItems?part=contentDetails&playlistId=\(uploadsPlaylistId)&maxResults=\(maxResults)"
                
                guard let pUrl = URL(string: playlistUrl) else {

                    dispatchGroup.leave()
                    return
                }
                
                var pRequest = URLRequest(url: pUrl)
                pRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                URLSession.shared.dataTask(with: pRequest) { pData, pResponse, pError in
                    defer { dispatchGroup.leave() }
                    

                    
                    guard let pData = pData,
                          let pJson = try? JSONSerialization.jsonObject(with: pData) as? [String: Any],
                          let pItems = pJson["items"] as? [[String: Any]] else { return }
                          
                    // Capture pagination info if this is a single channel fetch
                    if target == .singleChannel {
                        DispatchQueue.main.async {
                            self?.channelUploadsPlaylistId = uploadsPlaylistId
                            self?.channelNextPageToken = pJson["nextPageToken"] as? String
                        }
                    }
                          
                    let ids = pItems.compactMap { ($0["contentDetails"] as? [String: Any])?["videoId"] as? String }
                    
                    lock.lock()
                    allVideoIds.append(contentsOf: ids)
                    lock.unlock()
                    
                }.resume()
            }.resume()
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            print("DEBUG: [YouTubeManager] Finished fetching channel IDs. Total collected: \(allVideoIds.count)")
            
            if target == .singleChannel {
                if allVideoIds.isEmpty {
                     // Leave channelVideos empty if nothing found
                     self?.isChannelLoading = false
                } else {
                    self?.fetchVideoDetails(token: token, videoIds: allVideoIds, target: target)
                }
                return
            }
            
            // Existing logic for feed
            if allVideoIds.isEmpty {
                // Keep cached videos if we have them, only fallback to samples if totally empty
                if self?.videos.isEmpty ?? true {
                    print("DEBUG: [YouTubeManager] No videos and no cache, using samples")
                    self?.videos = self?.createSampleVideos() ?? []
                } else {
                    print("DEBUG: [YouTubeManager] No new videos found, maintaining existing cache")
                }
                self?.isLoading = false
            } else {
                self?.fetchVideoDetails(token: token, videoIds: allVideoIds, target: target)
            }
        }
    }
    
    private func fetchVideoDetails(token: String, videoIds: [String], target: FetchTarget = .feed) {
        // Chunk video IDs into groups of 50 to respect API limits
        let chunks = videoIds.chunked(into: 50)
        var allFetchedVideos: [YouTubeVideo] = []
        let dispatchGroup = DispatchGroup()
        
        let lock = NSLock()
        
        for chunk in chunks {
            dispatchGroup.enter()
            
            let urlString = "https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails&id=\(chunk.joined(separator: ","))"
            
            guard let url = URL(string: urlString) else {
                dispatchGroup.leave()
                continue
            }
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                defer { dispatchGroup.leave() }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let items = json["items"] as? [[String: Any]] else { return }
                
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
                    let publishedAt = dateFormatter.date(from: publishedAtString) 
                        ?? ISO8601DateFormatter.fractionalSecondsFormatter.date(from: publishedAtString)
                        ?? Date()
                    
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
                
                lock.lock()
                allFetchedVideos.append(contentsOf: videos)
                lock.unlock()
                
            }.resume()
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            // Sort merged results from all chunks
            let sortedVideos = allFetchedVideos.sorted { $0.publishedAt > $1.publishedAt }
            
            if target == .feed {
                self?.videos = sortedVideos
                self?.isLoading = false
                self?.saveToCache()
            } else if target == .singleChannel {
                self?.channelVideos = sortedVideos
                self?.isChannelLoading = false
            } else if target == .singleChannelAppend {
                // Append unique videos (avoiding duplicates)
                let existingIds = Set(self?.channelVideos.map { $0.id } ?? [])
                let newVideos = sortedVideos.filter { !existingIds.contains($0.id) }
                
                self?.channelVideos.append(contentsOf: newVideos)
                // Re-sort the entire list just to be safe
                self?.channelVideos.sort { $0.publishedAt > $1.publishedAt }
                self?.isChannelLoading = false
            } else if target == .feedAppend {
                // Same logic for main feed
                let existingIds = Set(self?.videos.map { $0.id } ?? [])
                let newVideos = sortedVideos.filter { !existingIds.contains($0.id) }
                
                self?.videos.append(contentsOf: newVideos)
                self?.videos.sort { $0.publishedAt > $1.publishedAt }
                self?.isLoading = false
            }
        }
    }
    
    // MARK: - Discovery API
    
    func loadMoreDiscoveryVideos() {
        guard !isDiscoveryLoading, let token = discoveryNextPageToken, let query = currentDiscoveryQuery else { return }
        searchVideos(for: query.language, level: query.level, category: query.category, pageToken: token)
    }
    
    func searchVideos(for language: Language, level: LearningLevel, category: String = "All", pageToken: String? = nil) {
        if pageToken == nil {
            currentDiscoveryQuery = (language, level, category)
            discoveryNextPageToken = nil
        }
        
        let categoryQuery = category == "All" ? "" : " \(category)"
        let query = "\(language.rawValue) \(level.rawValue) language learning\(categoryQuery)"
        
        #if targetEnvironment(simulator)
        if !isAuthenticated && accessToken == nil {
            print("Simulator detected: Using mock discovery data")
            searchVideosMock(for: language, level: level, category: category)
            return
        }
        #endif
        
        guard let token = accessToken else {
            // If we have a public API key, we can use that instead of the bearer token for search
            if let apiKey = publicApiKey {
                searchVideosWithApiKey(query: query, apiKey: apiKey, language: language, level: level, pageToken: pageToken)
            }
            return
        }
        
        isDiscoveryLoading = true
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        var urlString = "https://www.googleapis.com/youtube/v3/search?part=snippet&q=\(encodedQuery)&maxResults=50&type=video&videoCaption=closedCaption"
        if let pageToken = pageToken {
            urlString += "&pageToken=\(pageToken)"
        }
        
        guard let url = URL(string: urlString) else {
            isDiscoveryLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer { 
               // logic moved to fetchDiscoveryDetails or explicit set to false on error
               if self?.discoveryVideos.isEmpty == true && error != nil {
                   DispatchQueue.main.async { self?.isDiscoveryLoading = false }
               }
            }
            
            if let error = error {
                print("Discovery search failed: \(error)")
                DispatchQueue.main.async { self?.isDiscoveryLoading = false }
                return
            }
            
            guard let data = data else { 
                DispatchQueue.main.async { self?.isDiscoveryLoading = false }
                return 
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let items = json["items"] as? [[String: Any]] {
                    
                    let nextPageToken = json["nextPageToken"] as? String
                    DispatchQueue.main.async {
                        self?.discoveryNextPageToken = nextPageToken
                    }
                    
                    let videoIds = items.compactMap { item -> String? in
                        if let id = item["id"] as? [String: Any] {
                            return id["videoId"] as? String
                        }
                        return nil
                    }
                    
                    if !videoIds.isEmpty {
                        self?.fetchDiscoveryDetails(token: token, videoIds: videoIds, language: language, level: level, isAppend: pageToken != nil)
                    } else {
                        DispatchQueue.main.async { self?.isDiscoveryLoading = false }
                    }
                } else {
                    DispatchQueue.main.async { self?.isDiscoveryLoading = false }
                }
            } catch {
                print("Error parsing discovery results: \(error)")
                DispatchQueue.main.async { self?.isDiscoveryLoading = false }
            }
        }.resume()
    }
    
    private func searchVideosWithApiKey(query: String, apiKey: String, language: Language, level: LearningLevel, pageToken: String? = nil) {
        isDiscoveryLoading = true
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var urlString = "https://www.googleapis.com/youtube/v3/search?part=snippet&q=\(encodedQuery)&maxResults=50&type=video&videoCaption=closedCaption&key=\(apiKey)"
        if let pageToken = pageToken {
            urlString += "&pageToken=\(pageToken)"
        }
        
        guard let url = URL(string: urlString) else {
            isDiscoveryLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if error != nil { DispatchQueue.main.async { self?.isDiscoveryLoading = false }; return }
            guard let data = data else { DispatchQueue.main.async { self?.isDiscoveryLoading = false }; return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let items = json["items"] as? [[String: Any]] {
                   
                    let nextPageToken = json["nextPageToken"] as? String
                    DispatchQueue.main.async {
                        self?.discoveryNextPageToken = nextPageToken
                    }
                    
                    let videoIds = items.compactMap { ($0["id"] as? [String: Any])?["videoId"] as? String }
                    if !videoIds.isEmpty {
                        self?.fetchDiscoveryDetailsWithApiKey(apiKey: apiKey, videoIds: videoIds, language: language, level: level, isAppend: pageToken != nil)
                    } else {
                        DispatchQueue.main.async { self?.isDiscoveryLoading = false }
                    }
                } else {
                    DispatchQueue.main.async { self?.isDiscoveryLoading = false }
                }
            } catch {
                print("API Key Search Error: \(error)")
                DispatchQueue.main.async { self?.isDiscoveryLoading = false }
            }
        }.resume()
    }
    
    private func fetchDiscoveryDetailsWithApiKey(apiKey: String, videoIds: [String], language: Language, level: LearningLevel, isAppend: Bool = false) {
        let urlString = "https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails&id=\(videoIds.joined(separator: ","))&key=\(apiKey)"
        guard let url = URL(string: urlString) else { 
            DispatchQueue.main.async { self.isDiscoveryLoading = false }
            return 
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            defer { DispatchQueue.main.async { self?.isDiscoveryLoading = false } }
            guard let data = data else { return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let items = json["items"] as? [[String: Any]] {
                    let videos = self?.parseVideos(items: items, language: language, level: level) ?? []
                    DispatchQueue.main.async { 
                        if isAppend {
                            self?.discoveryVideos.append(contentsOf: videos)
                        } else {
                            self?.discoveryVideos = videos 
                        }
                        self?.saveToCache()
                    }
                }
            } catch {
                print("API Key Details Error: \(error)")
            }
        }.resume()
    }
    
    private func searchVideosMock(for language: Language, level: LearningLevel, category: String) {
        isDiscoveryLoading = true
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let mockVideos = [
                YouTubeVideo(id: "mock1", 
                             title: "[Mock] Comprehensive Input \(language.rawValue) - \(category)", 
                             description: "This is a simulated video for testing in the Xcode Simulator.", 
                             thumbnailURL: "https://via.placeholder.com/320x180/FF6B6B/FFFFFF?text=\(language.rawValue)+\(category)", 
                             channelTitle: "Language Master \(language.rawValue)", 
                             duration: "PT15M30S", 
                             publishedAt: Date()),
                YouTubeVideo(id: "mock2", 
                             title: "[Mock] Daily \(language.rawValue) Vlogs", 
                             description: "Simulated immersion content.", 
                             thumbnailURL: "https://via.placeholder.com/320x180/4ECDC4/FFFFFF?text=Immersion+Vlog", 
                             channelTitle: "Native Speaker", 
                             duration: "PT08M45S", 
                             publishedAt: Date().addingTimeInterval(-3600)),
                YouTubeVideo(id: "mock3", 
                             title: "[Mock] Basics of \(language.rawValue) for \(level.rawValue)s", 
                             description: "Learn the fundamentals.", 
                             thumbnailURL: "https://via.placeholder.com/320x180/95E1D3/FFFFFF?text=Language+Basics", 
                             channelTitle: "Learn Now", 
                             duration: "PT22M10S", 
                             publishedAt: Date().addingTimeInterval(-86400))
            ].map { mutVideo -> YouTubeVideo in
                var v = mutVideo
                v.language = language
                v.level = level
                return v
            }
            
            self.discoveryVideos = mockVideos
            self.isDiscoveryLoading = false
        }
    }
    
    private func parseVideos(items: [[String: Any]], language: Language? = nil, level: LearningLevel? = nil) -> [YouTubeVideo] {
        items.compactMap { item -> YouTubeVideo? in
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
            
            var video = YouTubeVideo(
                id: id,
                title: title,
                description: description,
                thumbnailURL: thumbnailURL,
                channelTitle: channelTitle,
                duration: duration,
                publishedAt: publishedAt
            )
            video.language = language
            video.level = level
            return video
        }
    }
    
    private func fetchDiscoveryDetails(token: String, videoIds: [String], language: Language, level: LearningLevel, isAppend: Bool = false) {
        let urlString = "https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails&id=\(videoIds.joined(separator: ","))"
        
        guard let url = URL(string: urlString) else { 
            DispatchQueue.main.async { self.isDiscoveryLoading = false }
            return 
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer { DispatchQueue.main.async { self?.isDiscoveryLoading = false } }
            guard let data = data else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let items = json["items"] as? [[String: Any]] {
                    let videos = self?.parseVideos(items: items, language: language, level: level) ?? []
                    DispatchQueue.main.async {
                        if isAppend {
                            self?.discoveryVideos.append(contentsOf: videos)
                        } else {
                            self?.discoveryVideos = videos
                        }
                        self?.saveToCache()
                    }
                }
            } catch {
                print("Error parsing discovery details: \(error)")
            }
        }.resume()
    }
    
    func loadVideos() {
        loadVideosFromAPI()
        fetchRecommendedVideos()
    }
    
    func refreshVideos() {
        // Clear cache-related flags if necessary or just force API calls
        // This is a user-initiated action, so we want to be aggressive
        isLoading = true
        loadVideosFromAPI(isRefresh: true)
        fetchRecommendedVideos()
    }
    
    // MARK: - Recommended Videos API
    
    func loadMoreRecommendedVideos() {
        guard !isRecommendedLoading else { return }
        guard let token = recsNextPageToken else { return }
        
        isRecommendedLoading = true
        if recsUsingMostPopular {
            fetchMostPopularVideos(pageToken: token)
        } else {
            fetchRecommendedVideos(pageToken: token)
        }
    }
    
    func fetchRecommendedVideos(pageToken: String? = nil) {
        #if targetEnvironment(simulator)
        if !isAuthenticated && accessToken == nil {
            fetchRecommendedVideosMock()
            return
        }
        #endif
        
        guard let token = accessToken else {
            // If not authenticated, fetch most popular as a guest
            fetchMostPopularVideos()
            return
        }
        
        isRecommendedLoading = true
        if pageToken == nil {
            recsUsingMostPopular = false // Reset source
        }
        
        var urlString = "https://www.googleapis.com/youtube/v3/activities?part=snippet,contentDetails&home=true&maxResults=50"
        if let pageToken = pageToken {
            urlString += "&pageToken=\(pageToken)"
        }
        
        guard let url = URL(string: urlString) else {
            isRecommendedLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("DEBUG: [YouTubeManager] Activity fetch failed: \(error.localizedDescription)")
                DispatchQueue.main.async { self?.isRecommendedLoading = false }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("DEBUG: [YouTubeManager] Activity response code: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                DispatchQueue.main.async { self?.isRecommendedLoading = false }
                return 
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let items = json["items"] as? [[String: Any]] {
                    
                    // Capture next page token
                    DispatchQueue.main.async {
                        self?.recsNextPageToken = json["nextPageToken"] as? String
                    }
                    
                    // Filter for various video-related activities
                    let videoIds = items.compactMap { item -> String? in
                        guard let snippet = item["snippet"] as? [String: Any],
                              let itemType = snippet["type"] as? String,
                              let contentDetails = item["contentDetails"] as? [String: Any] else { 
                            return nil 
                        }
                        
                        // Robust ID extraction for different activity types
                        switch itemType {
                        case "recommendation":
                            if let rec = contentDetails["recommendation"] as? [String: Any],
                               let resourceId = rec["resourceId"] as? [String: Any] {
                                return resourceId["videoId"] as? String
                            }
                        case "upload":
                            return (contentDetails["upload"] as? [String: Any])?["videoId"] as? String
                        case "like":
                            if let like = contentDetails["like"] as? [String: Any],
                               let resourceId = like["resourceId"] as? [String: Any] {
                                return resourceId["videoId"] as? String
                            }
                        case "playlistItem":
                            if let pi = contentDetails["playlistItem"] as? [String: Any],
                               let resourceId = pi["resourceId"] as? [String: Any] {
                                return resourceId["videoId"] as? String
                            }
                        case "bulletin": // Often has a resourceId pointing to a video
                            if let bulletin = contentDetails["bulletin"] as? [String: Any],
                               let resourceId = bulletin["resourceId"] as? [String: Any] {
                                return resourceId["videoId"] as? String
                            }
                        case "comment": // Ignore
                            break
                        case "subscription": // Ignore for video grid
                            break
                        default:
                            break
                        }
                        return nil
                    }
                    
                    let uniqueIds = Array(Set(videoIds))
                    if !uniqueIds.isEmpty {
                        self?.fetchRecommendedDetails(token: token, videoIds: uniqueIds, isAppend: pageToken != nil)
                    } else {
                        // If no videos found in activities (e.g. only comments), just stop.
                        DispatchQueue.main.async { self?.isRecommendedLoading = false }
                    }
                } else {
                    DispatchQueue.main.async { self?.isRecommendedLoading = false }
                }
            } catch {
                print("DEBUG: [YouTubeManager] JSON Parse Error (Activities): \(error)")
                DispatchQueue.main.async { self?.isRecommendedLoading = false }
            }
        }.resume()
    }
    
    private func fetchMostPopularVideos(pageToken: String? = nil) {
        // Mark that we are using most popular source
        if pageToken == nil {
            recsUsingMostPopular = true
        }
        
        var urlString = "https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails&chart=mostPopular&maxResults=50"
        if let key = publicApiKey {
            urlString += "&key=\(key)"
        }
        if let pageToken = pageToken {
            urlString += "&pageToken=\(pageToken)"
        }
        
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { self.isRecommendedLoading = false }
            return
        }
        
        isRecommendedLoading = true
        
        var request = URLRequest(url: url)
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer { DispatchQueue.main.async { self?.isRecommendedLoading = false } }
            
            guard let data = data else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let items = json["items"] as? [[String: Any]] {
                    
                    // Capture next page token for Most Popular
                    DispatchQueue.main.async {
                        self?.recsNextPageToken = json["nextPageToken"] as? String
                    }
                    
                    let videos = self?.parseVideos(items: items) ?? []
                    DispatchQueue.main.async {
                        if pageToken != nil {
                            // Append if loading more
                            let existingIds = Set(self?.recommendedVideos.map { $0.id } ?? [])
                            let newVideos = videos.filter { !existingIds.contains($0.id) }
                            self?.recommendedVideos.append(contentsOf: newVideos)
                        } else {
                            self?.recommendedVideos = videos
                        }
                        
                        self?.saveToCache()
                    }
                }
            } catch {
                print("JSON Parse Error (Most Popular): \(error)")
            }
        }.resume()
    }
    
    private func fetchRecommendedDetails(token: String, videoIds: [String], isAppend: Bool = false) {
        let urlString = "https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails&id=\(videoIds.joined(separator: ","))"
        
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { self.isRecommendedLoading = false }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer { DispatchQueue.main.async { self?.isRecommendedLoading = false } }
            
            guard let data = data else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let items = json["items"] as? [[String: Any]] {
                    
                    let videos = self?.parseVideos(items: items) ?? []
                    DispatchQueue.main.async {
                        if isAppend {
                            let existingIds = Set(self?.recommendedVideos.map { $0.id } ?? [])
                            let newVideos = videos.filter { !existingIds.contains($0.id) }
                            self?.recommendedVideos.append(contentsOf: newVideos)
                        } else {
                            self?.recommendedVideos = videos
                        }
                        self?.saveToCache()
                    }
                }
            } catch {
                print("DEBUG: [YouTubeManager] JSON Parse Error (Rec Details): \(error)")
            }
        }.resume()
    }
    
    private func fetchRecommendedVideosMock() {
        isRecommendedLoading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.recommendedVideos = [
                YouTubeVideo(id: "rec1", title: "[Mock] Recommendations for You", description: "Trending content.", thumbnailURL: "https://via.placeholder.com/320x180/6C5CE7/FFFFFF?text=Recommended+1", channelTitle: "Recommender", duration: "PT10M", publishedAt: Date()),
                YouTubeVideo(id: "rec2", title: "[Mock] Popular in Language Learning", description: "Most viewed today.", thumbnailURL: "https://via.placeholder.com/320x180/A29BFE/FFFFFF?text=Recommended+2", channelTitle: "Trending", duration: "PT15M", publishedAt: Date())
            ]
            self.isRecommendedLoading = false
        }
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

// Helper for chunking array
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

// Helper for date formatting
extension ISO8601DateFormatter {
    static var fractionalSecondsFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}



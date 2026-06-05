//
//  LearnCIApp.swift
//  LearnCI
//
//  Created by Alan Glass on 1/2/26.
//

import SwiftUI
import SwiftData

@main
struct LearnCIApp: App {
    @State private var dataManager = DataManager()
    @State private var youtubeManager = YouTubeManager()
    @State private var authManager: AuthManager
    @State private var syncManager: SyncManager
    @State private var locationManager = LocationManager()
    @State private var audioManager = AudioManager()
    @State private var ambientSoundManager: AmbientSoundManager

    init() {
        let auth = AuthManager()
        _authManager = State(initialValue: auth)
        _syncManager = State(initialValue: SyncManager(authManager: auth))
        _ambientSoundManager = State(initialValue: AmbientSoundManager(authManager: auth))
        print("Documents Directory: \(URL.documentsDirectory.path)")
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserActivity.self,
            UserProfile.self,
            DailyFeedback.self,
            CoachingCheckIn.self,
            Favorite.self,
            YouTubeCaptionCache.self,
            YouTubeCaptionTranslationCache.self,
            YouTubeWordLookupCache.self,
            StudySessionRecord.self,
            StudyNote.self,
            MarkedStudyWord.self,
            MediaTranscriptCache.self,
            Story.self,
            PodcastShow.self,
            PodcastEpisode.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView(loadingText: loadingStatus)
                        .transition(.opacity)
                        .zIndex(1)
                } else {
                    ContentView()
                        .environment(dataManager)
                        .environment(youtubeManager)
                        .environment(authManager)
                        .environment(syncManager)
                        .environment(locationManager)
                        .environment(audioManager)
                        .environment(ambientSoundManager)
                        .onOpenURL { url in
                            print("DEBUG: LearnCIApp received URL: \(url.absoluteString)")
                            Task {
                                try? await authManager.handleIncomingURL(url)
                            }
                        }
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: showSplash)
            .animation(.easeInOut(duration: 0.5), value: showSplash)
            .onAppear {
                performInitialization()
            }
        }
        .modelContainer(sharedModelContainer)
    }
    
    @State private var loadingStatus = "Initializing..."
    
    private func performInitialization() {
        Task {
            // 1. Authentication Check
            loadingStatus = "Checking authentication..."
            try? await Task.sleep(nanoseconds: 500_000_000) // Small delay for UX so text is readable
            
            // 2. Data Manager Prep
            loadingStatus = "Loading content..."
            // Ensure any critical data is loaded here if needed
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // 3. Sync Check (Optional/Background)
            if authManager.isAuthenticated {
                loadingStatus = "Syncing profile..."
                // syncManager.syncUserProfile() // Example: trigger a sync if needed immediately
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            
            // 4. Finalizing
            loadingStatus = "Ready!"
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            withAnimation {
                showSplash = false
            }
        }
    }
}

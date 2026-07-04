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
    @State private var savedStudyWordManager: SavedStudyWordManager

    init() {
        let auth = AuthManager()
        _authManager = State(initialValue: auth)
        _syncManager = State(initialValue: SyncManager(authManager: auth))
        _ambientSoundManager = State(initialValue: AmbientSoundManager(authManager: auth))
        _savedStudyWordManager = State(initialValue: SavedStudyWordManager(authManager: auth))
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
            SavedStudyWord.self,
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
                        .environment(savedStudyWordManager)
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
            .onAppear {
                performInitialization()
            }
        }
        .modelContainer(sharedModelContainer)
    }
    
    @State private var loadingStatus = "Initializing..."
    
    private func performInitialization() {
        Task {
            // No real work happens here — auth restoration and sync are driven by
            // AuthManager/ContentView. Keep the splash just long enough for the
            // transition to feel intentional instead of stacking fake delays.
            loadingStatus = "Loading..."
            try? await Task.sleep(nanoseconds: 400_000_000)

            withAnimation {
                showSplash = false
            }
        }
    }
}

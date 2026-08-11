//
//  LearnCIApp.swift
//  LearnCI
//
//  Created by Alan Glass on 1/2/26.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct LearnCIApp: App {
    @UIApplicationDelegateAdaptor(LearnCIAppDelegate.self) private var appDelegate
    @State private var dataManager = DataManager()
    @State private var youtubeManager = YouTubeManager()
    @State private var authManager: AuthManager
    @State private var syncManager: SyncManager
    @State private var locationManager = LocationManager()
    @State private var audioManager = AudioManager.shared
    @State private var playbackQueueManager = PlaybackQueueManager.shared
    @State private var mediaDownloadManager = MediaDownloadManager.shared
    @State private var ambientSoundManager: AmbientSoundManager
    @State private var savedStudyWordManager: SavedStudyWordManager
    @State private var nextSessionPlanManager = NextSessionPlanManager()
    @State private var storyPathProgressStore = StoryPathProgressStore()
    @State private var mediaStudyStore = MediaStudyStore()

    init() {
        let auth = AuthManager()
        _authManager = State(initialValue: auth)
        _syncManager = State(initialValue: SyncManager(authManager: auth))
        _ambientSoundManager = State(initialValue: AmbientSoundManager(authManager: auth))
        _savedStudyWordManager = State(initialValue: SavedStudyWordManager(authManager: auth))
        CarPlayEnvironment.shared.configure(modelContainer: Self.sharedModelContainer)
        print("Documents Directory: \(URL.documentsDirectory.path)")
    }
    
    static let sharedModelContainer: ModelContainer = {
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
            PodcastEpisode.self,
            NextSessionPlan.self,
            StoryPathProgress.self,
            StoryStudyState.self,
            MediaStudyState.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var sharedModelContainer: ModelContainer { Self.sharedModelContainer }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dataManager)
                .environment(youtubeManager)
                .environment(authManager)
                .environment(syncManager)
                .environment(locationManager)
                .environment(audioManager)
                .environment(playbackQueueManager)
                .environment(mediaDownloadManager)
                .environment(ambientSoundManager)
                .environment(savedStudyWordManager)
                .environment(nextSessionPlanManager)
                .environment(storyPathProgressStore)
                .environment(mediaStudyStore)
                .onOpenURL { url in
                    print("DEBUG: LearnCIApp received URL: \(url.absoluteString)")
                    Task {
                        try? await authManager.handleIncomingURL(url)
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

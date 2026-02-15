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
    
    init() {
        let auth = AuthManager()
        _authManager = State(initialValue: auth)
        _syncManager = State(initialValue: SyncManager(authManager: auth))
        print("Documents Directory: \(URL.documentsDirectory.path)")
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserActivity.self,
            UserProfile.self,
            DailyFeedback.self,
            CoachingCheckIn.self,
            Favorite.self,
            Story.self
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
                    SplashView()
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
                // Simulate initialization delay or wait for essential services
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation {
                        showSplash = false
                    }
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}

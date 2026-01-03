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
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserActivity.self,
            UserProfile.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dataManager)
                .environment(youtubeManager)
        }
        .modelContainer(sharedModelContainer)
    }
}

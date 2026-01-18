//
//  ContentView.swift
//  LearnCI
//
//  Created by Alan Glass on 1/2/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncManager.self) private var syncManager
    @Environment(AuthManager.self) private var authManager
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        MainTabView()
            .task {
                // Initial sync if already logged in
                await syncManager.syncNow(modelContext: modelContext)
            }
            .onChange(of: authManager.currentUser) { _, newValue in
                if newValue != nil {
                    Task {
                        await syncManager.syncNow(modelContext: modelContext)
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    print("App entered foreground - Triggering Sync")
                    Task {
                        await syncManager.syncNow(modelContext: modelContext)
                    }
                }
            }
    }
}

#Preview {
    ContentView()
        .environment(DataManager())
        .environment(YouTubeManager())
        .environment(AuthManager())
        .environment(SyncManager(authManager: AuthManager()))
}

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    @Environment(SyncManager.self) private var syncManager
    @Environment(AuthManager.self) private var authManager
    @Query private var allProfiles: [UserProfile]
    @State private var showDeleteConfirmation = false
    @State private var showClearFavoritesConfirmation = false
    @State private var showClearStoriesConfirmation = false
    @State private var showClearStoryMediaConfirmation = false
    @State private var isRefreshingStories = false
    
    var profiles: [UserProfile] {
        allProfiles.filter { $0.userID == authManager.currentUser }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if let profile = profiles.first {
                    Section {
                        NavigationLink(destination: ProfileAccountSettingsView(profile: profile)) {
                            Label("Account", systemImage: "person.circle")
                        }
                        
                        NavigationLink(destination: ProfileLanguageSettingsView(profile: profile)) {
                            Label("Language Learning", systemImage: "globe")
                        }
                        
                        NavigationLink(destination: ProfileGameSettingsView(profile: profile)) {
                            Label("Game Settings", systemImage: "gamecontroller")
                        }
                        
                        NavigationLink(destination: ProfileAudioSettingsView(profile: profile)) {
                            Label("Audio Settings", systemImage: "speaker.wave.3")
                        }
                        
                        NavigationLink(destination: ProfileAISettingsView(profile: profile)) {
                            Label("AI Settings", systemImage: "sparkles")
                        }
                        
                        NavigationLink(destination: ProfileConnectionsView()) {
                            Label("App Connections", systemImage: "link")
                        }
                    }
                } else {
                    if !syncManager.hasInitialSyncCompleted {
                        ContentUnavailableView("Syncing Profile...", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        ContentUnavailableView("Loading Profile...", systemImage: "person.circle")
                    }
                }
                
                Section("Development") {
                    Button("Remove All Profiles", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    Button("Clear All Favorites", role: .destructive) {
                        showClearFavoritesConfirmation = true
                    }
                    Button(role: .destructive) {
                        showClearStoryMediaConfirmation = true
                    } label: {
                        Label("Clear Downloaded Story Media", systemImage: "externaldrive.badge.xmark")
                    }
                    Button(role: .destructive) {
                        showClearStoriesConfirmation = true
                    } label: {
                        if isRefreshingStories {
                            Label("Refreshing Stories...", systemImage: "arrow.triangle.2.circlepath")
                        } else {
                            Label("Clear Local Stories & Refresh", systemImage: "book.closed")
                        }
                    }
                    .disabled(isRefreshingStories || syncManager.isSyncing)
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .task(id: authManager.currentUser) {
               ensureProfileExists()
            }
            .onChange(of: syncManager.hasInitialSyncCompleted) { _, completed in
                if completed {
                    ensureProfileExists()
                }
            }
            .alert("Reset All Profiles?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    deleteAllProfiles()
                }
            } message: {
                Text("This will delete ALL local profiles, including hidden ones. This cannot be undone.")
            }
            .alert("Clear All Favorites?", isPresented: $showClearFavoritesConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    deleteAllFavorites()
                }
            } message: {
                Text("This will verify the YouTube fix by resetting your database. All saved items will be removed.")
            }
            .alert("Clear Downloaded Story Media?", isPresented: $showClearStoryMediaConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear Media", role: .destructive) {
                    clearDownloadedStoryMedia()
                }
            } message: {
                Text("This keeps your stories but removes downloaded audio, covers, and remote video caches. Story readers will download fresh media next time.")
            }
            .alert("Refresh Stories From Database?", isPresented: $showClearStoriesConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear & Refresh", role: .destructive) {
                    clearLocalStoriesAndRefresh()
                }
            } message: {
                Text("This deletes only local story copies for your signed-in account, then pulls fresh stories from Supabase. Remote database rows are not deleted.")
            }
        }
    }
    
    func ensureProfileExists() {
        // Wait for sync to complete before creating a default profile
        // This prevents overwriting server data with a blank profile
        guard syncManager.hasInitialSyncCompleted else { return }
        
        if profiles.isEmpty {
            // Create profile associated with current user
            if let userID = authManager.currentUser {
                let newProfile = UserProfile(userID: userID)
                newProfile.fullName = authManager.currentUserFullName
                newProfile.email = authManager.currentUserEmail
                newProfile.avatarUrl = authManager.currentUserAvatar
                if let googleName = authManager.currentUserFullName {
                    newProfile.name = googleName // Default display name to full name
                }
                
                modelContext.insert(newProfile)
            }
        }
    }
    
    private func deleteAllProfiles() {
        do {
            try modelContext.delete(model: UserProfile.self)
            dismiss()
        } catch {
            print("Failed to delete profiles: \(error)")
        }
    }
    
    private func deleteAllFavorites() {
        do {
             try modelContext.delete(model: Favorite.self)
             dismiss()
        } catch {
             print("Failed to delete favorites: \(error)")
        }
    }

    private func clearLocalStoriesAndRefresh() {
        guard let userID = authManager.currentUser else { return }

        isRefreshingStories = true
        do {
            let descriptor = FetchDescriptor<Story>(
                predicate: #Predicate { $0.userID == userID }
            )
            let localStories = try modelContext.fetch(descriptor)
            for story in localStories {
                StoryReaderDataAdapter.deleteCachedStoryMedia(storyID: story.id)
                modelContext.delete(story)
            }
            try modelContext.save()
        } catch {
            isRefreshingStories = false
            print("Failed to clear local stories: \(error)")
            return
        }

        Task {
            await syncManager.syncNow(modelContext: modelContext)
            await MainActor.run {
                isRefreshingStories = false
            }
        }
    }

    private func clearDownloadedStoryMedia() {
        guard let userID = authManager.currentUser else { return }

        do {
            let descriptor = FetchDescriptor<Story>(
                predicate: #Predicate { $0.userID == userID }
            )
            let localStories = try modelContext.fetch(descriptor)
            let deletedCount = localStories.reduce(0) { count, story in
                count + StoryReaderDataAdapter.deleteCachedStoryMedia(storyID: story.id)
            }
            print("[Profile] Cleared \(deletedCount) downloaded story media files.")
        } catch {
            print("Failed to clear downloaded story media: \(error)")
        }
    }
}

#Preview {
    ProfileView()
        .environment(YouTubeManager())
        .environment(AuthManager())
}

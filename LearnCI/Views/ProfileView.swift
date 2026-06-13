import SwiftUI
import SwiftData
import Supabase
import PostgREST

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
    @State private var isClearingFavorites = false
    @State private var isRefreshingStories = false
    
    var profiles: [UserProfile] {
        allProfiles.filter { $0.userID == authManager.currentUser }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if let profile = profiles.first {
                    settingsSection(profile: profile)
                    favoritesTestingSection
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.bold)
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
                    Task {
                        await deleteAllFavorites()
                    }
                }
            } message: {
                Text("This will remove all favorites for your signed-in account from this device and Supabase.")
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
    
    @ViewBuilder
    private func settingsSection(profile: UserProfile) -> some View {
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
    }

    private var favoritesTestingSection: some View {
        Section {
            Button(role: .destructive) {
                showClearFavoritesConfirmation = true
            } label: {
                if isClearingFavorites {
                    Label("Resetting Favorites...", systemImage: "arrow.triangle.2.circlepath")
                } else {
                    Label("Reset Favorites", systemImage: "heart.slash")
                }
            }
            .disabled(isClearingFavorites || syncManager.isSyncing)
        } header: {
            Text("Testing")
        } footer: {
            Text("Clears favorites for your signed-in account locally and in Supabase so you can test from a clean state.")
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
    
    @MainActor
    private func deleteAllFavorites() async {
        guard !isClearingFavorites else { return }
        guard let userID = authManager.currentUser,
              let userUUID = UUID(uuidString: userID) else { return }

        isClearingFavorites = true
        do {
            try await authManager.supabase.from("favorites")
                .delete()
                .eq("user_id", value: userUUID)
                .execute()

            let descriptor = FetchDescriptor<Favorite>(
                predicate: #Predicate { $0.userID == userID }
            )
            let favorites = try modelContext.fetch(descriptor)
            for favorite in favorites {
                modelContext.delete(favorite)
            }
            try modelContext.save()
        } catch {
            print("Failed to delete favorites: \(error)")
        }
        isClearingFavorites = false
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

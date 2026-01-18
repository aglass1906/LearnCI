import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    @Environment(SyncManager.self) private var syncManager
    @Environment(AuthManager.self) private var authManager
    @Query private var allProfiles: [UserProfile]
    @State private var showDeleteConfirmation = false
    
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
}

#Preview {
    ProfileView()
        .environment(YouTubeManager())
        .environment(AuthManager())
}

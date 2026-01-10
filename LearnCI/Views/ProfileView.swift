import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    @Environment(AuthManager.self) private var authManager
    @Query private var allProfiles: [UserProfile]
    
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
                    ContentUnavailableView("Loading Profile...", systemImage: "person.circle")
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
        }
    }
    
    func ensureProfileExists() {
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
}

#Preview {
    ProfileView()
        .environment(YouTubeManager())
        .environment(AuthManager())
}

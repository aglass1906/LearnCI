import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SyncManager.self) private var syncManager
    @Environment(AuthManager.self) private var authManager

    @Query private var allProfiles: [UserProfile]
    @AppStorage("hasSeenOnboardingPreview") private var hasSeenOnboardingPreview = false

    @State private var preparedUserID: String?
    @State private var onboardingUserID: String?

    var body: some View {
        Group {
            switch authManager.state {
            case .checking:
                ProgressView("Checking session...")

            case .unauthenticated:
                if hasSeenOnboardingPreview {
                    AuthView()
                } else {
                    OnboardingPreviewView {
                        hasSeenOnboardingPreview = true
                    }
                }

            case .authenticated(let userID, _, _, _):
                authenticatedContent(userID: userID)
            }
        }
        .onChange(of: authManager.currentUser) { _, userID in
            if userID == nil {
                preparedUserID = nil
                onboardingUserID = nil
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, authManager.currentUser != nil else { return }
            Task {
                await syncManager.syncNow(modelContext: modelContext)
            }
        }
        .sheet(isPresented: Bindable(authManager).isPasswordResetRequired) {
            ChangePasswordSheet()
        }
    }

    @ViewBuilder
    private func authenticatedContent(userID: String) -> some View {
        if preparedUserID != userID {
            LoadingView(message: "Preparing your learning space...")
                .task(id: userID) {
                    await prepareAuthenticatedUser(userID)
                }
        } else if let profile = profile(for: userID) {
            if onboardingUserID == userID || !profile.hasCompletedOnboarding {
                OnboardingSetupView(profile: profile) {
                    onboardingUserID = nil
                }
            } else {
                MainTabView()
            }
        } else {
            ContentUnavailableView(
                "Unable to Load Profile",
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text("Sign out and try again.")
            )
        }
    }

    @MainActor
    private func prepareAuthenticatedUser(_ userID: String) async {
        // Returning user with a local profile: enter the app immediately and let
        // the sync run in the background instead of blocking on the network.
        if let existingProfile = profile(for: userID) {
            onboardingUserID = existingProfile.hasCompletedOnboarding == false ? userID : nil
            preparedUserID = userID
            Task {
                await syncManager.syncNow(modelContext: modelContext)
            }
            return
        }

        // First launch for this user on this device: sync first so an existing
        // server profile is pulled down before we create a fresh one.
        await syncManager.syncNow(modelContext: modelContext)

        var profile = profile(for: userID)
        if profile == nil {
            let newProfile = UserProfile(userID: userID)
            newProfile.fullName = authManager.currentUserFullName
            newProfile.email = authManager.currentUserEmail
            newProfile.avatarUrl = authManager.currentUserAvatar
            if let fullName = authManager.currentUserFullName, !fullName.isEmpty {
                newProfile.name = fullName
            }
            modelContext.insert(newProfile)
            try? modelContext.save()
            profile = newProfile
        }

        onboardingUserID = profile?.hasCompletedOnboarding == false ? userID : nil
        preparedUserID = userID
    }

    private func profile(for userID: String) -> UserProfile? {
        allProfiles.first { $0.userID == userID }
    }
}

#Preview {
    ContentView()
        .environment(DataManager())
        .environment(YouTubeManager())
        .environment(AuthManager())
        .environment(SyncManager(authManager: AuthManager()))
}

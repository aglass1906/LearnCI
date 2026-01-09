import SwiftUI

enum AppTab: String, CaseIterable {
    case dashboard
    case learn
    case videos
    case library
    case history
    case profile
    case coach
}

struct MainTabView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(DataManager.self) private var dataManager
    @State private var selectedTab: AppTab = .dashboard
    @State private var showProfile = false
    
    var body: some View {
        Group {
            switch authManager.state {
            case .checking:
                ProgressView("Checking session...")
            case .authenticated:
                VStack(spacing: 0) {
                    if !dataManager.isFullScreen {
                        UserHeader(showProfile: $showProfile, currentTab: $selectedTab)
                    }
                    
                    TabView(selection: $selectedTab) {
                        DashboardView()
                            .tabItem {
                                Label("Dashboard", systemImage: "chart.bar.fill")
                            }
                            .tag(AppTab.dashboard)
                        
                        GameView()
                            .tabItem {
                                Label("Learn", systemImage: "gamecontroller.fill")
                            }
                            .tag(AppTab.learn)
                        
                        VideoView()
                            .tabItem {
                                Label("Videos", systemImage: "play.rectangle.fill")
                            }
                            .tag(AppTab.videos)

                        ResourceLibraryView()
                            .tabItem {
                                Label("Library", systemImage: "books.vertical.fill")
                            }
                            .tag(AppTab.library)
                        
                        HistoryView()
                            .tabItem {
                                Label("Activity", systemImage: "clock.arrow.circlepath")
                            }
                            .tag(AppTab.history)
                        
                        CoachingHistoryView()
                            .tabItem {
                                Label("Coach", systemImage: "person.bust.fill")
                            }
                            .tag(AppTab.coach)
                        
                        // Profile is now accessed via the Header Sheet
                        // but we keep the tab for alternative navigation if desired.
                        ProfileView()
                            .tabItem {
                                Label("Profile", systemImage: "person.circle.fill")
                            }
                            .tag(AppTab.profile)
                    }
                }
                .sheet(isPresented: $showProfile) {
                    ProfileView()
                }
            case .unauthenticated:
                AuthView()
            }
        }
    }
}

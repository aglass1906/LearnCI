import SwiftUI

enum AppTab: String, CaseIterable {
    case dashboard
    case learn
    case discovery
    case history
}

struct MainTabView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(DataManager.self) private var dataManager
    @State private var selectedTab: AppTab = .dashboard
    @State private var showProfile = false
    
    var body: some View {
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
                
                InputDiscoveryView()
                    .tabItem {
                        Label("Input", systemImage: "sparkles")
                    }
                    .tag(AppTab.discovery)
                
                InsightsView()
                    .tabItem {
                        Label("Insights", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .tag(AppTab.history)
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
    }
}

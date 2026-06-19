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
    @Environment(AudioManager.self) private var audioManager
    @State private var selectedTab: AppTab = .dashboard
    @State private var showProfile = false
    @State private var dashboardResetID = UUID()
    @State private var learnResetID = UUID()
    @State private var discoveryResetID = UUID()
    @State private var historyResetID = UUID()
    
    var body: some View {
        VStack(spacing: 0) {
            if !dataManager.isFullScreen {
                UserHeader(
                    showProfile: $showProfile,
                    currentTab: $selectedTab,
                    onSelectTab: selectTab
                )
            }
            
            TabView(selection: $selectedTab) {
                DashboardView()
                    .id(dashboardResetID)
                    .tabItem {
                        Label("Dashboard", systemImage: "chart.bar.fill")
                    }
                    .tag(AppTab.dashboard)
                
                LearnHubView()
                    .id(learnResetID)
                    .tabItem {
                        Label("Learn", systemImage: "book.closed.fill")
                    }
                    .tag(AppTab.learn)
                
                InputDiscoveryView()
                    .id(discoveryResetID)
                    .tabItem {
                        Label("Input", systemImage: "brain.head.profile.fill")
                    }
                    .tag(AppTab.discovery)
                
                InsightsView()
                    .id(historyResetID)
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

    private func selectTab(_ tab: AppTab) {
        audioManager.stopAudio()
        dataManager.isFullScreen = false

        switch tab {
        case .dashboard:
            dashboardResetID = UUID()
        case .learn:
            learnResetID = UUID()
        case .discovery:
            discoveryResetID = UUID()
        case .history:
            historyResetID = UUID()
        }

        selectedTab = tab
    }
}

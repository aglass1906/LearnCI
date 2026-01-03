import SwiftUI

struct MainTabView: View {
    @Environment(AuthManager.self) private var authManager
    
    var body: some View {
        Group {
            switch authManager.state {
            case .checking:
                ProgressView("Checking session...")
            case .authenticated:
                TabView {
                    DashboardView()
                        .tabItem {
                            Label("Dashboard", systemImage: "chart.bar.fill")
                        }
                    
                    GameView()
                        .tabItem {
                            Label("Learn", systemImage: "gamecontroller.fill")
                        }
                    
                    VideoView()
                        .tabItem {
                            Label("Videos", systemImage: "play.rectangle.fill")
                        }
                    
                    HistoryView()
                        .tabItem {
                            Label("Activity", systemImage: "clock.arrow.circlepath")
                        }
                    
                    ProfileView()
                        .tabItem {
                            Label("Profile", systemImage: "person.circle.fill")
                        }
                }
            case .unauthenticated:
                AuthView()
            }
        }
    }
}

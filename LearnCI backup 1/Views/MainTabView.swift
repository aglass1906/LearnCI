import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }
            
            GameView()
                .tabItem {
                    Label("Learn", systemImage: "gamecontroller.fill")
                }
            
            
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle.fill")
                }
                
            HistoryView()
                .tabItem {
                    Label("Activity", systemImage: "clock.arrow.circlepath")
                }
        }
    }
}

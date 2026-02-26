import SwiftUI
import SwiftData

struct CoachingHubView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncManager.self) private var syncManager
    
    @Query(sort: \UserActivity.date, order: .reverse) private var activities: [UserActivity]
    
    private var filteredActivities: [UserActivity] {
        activities.filter { $0.userID == authManager.currentUser }
    }
    
    private var totalMinutes: Int {
        filteredActivities.reduce(0) { $0 + $1.minutes }
    }
    
    private var topActivity: String {
        let counts = Dictionary(grouping: filteredActivities, by: { $0.activityTypeRaw })
        return counts.max(by: { a, b in 
            a.value.reduce(0, { $0 + $1.minutes }) < b.value.reduce(0, { $0 + $1.minutes }) 
        })?.key ?? "None"
    }

    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero Panel: Activity Tracking
                NavigationLink(destination: ActivityHistoryContent().navigationTitle("Activity History")) {
                    HubPanelHero(
                        title: "Activity Tracking",
                        subtitle: "\(totalMinutes / 60)h total • Top: \(topActivity)",
                        icon: "clock.arrow.circlepath",
                        gradient: Gradient(colors: [.orange, .red])
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                // Grid for other insights
                LazyVGrid(columns: columns, spacing: 16) {
                    NavigationLink(destination: CoachingProgressDetailView()) {
                        HubPanel(
                            title: "Progress",
                            subtitle: "Stats & Roadmap",
                            icon: "chart.line.uptrend.xyaxis",
                            gradient: Gradient(colors: [.blue, .indigo])
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    NavigationLink(destination: CoachingMoodView()) {
                        HubPanel(
                            title: "Moods",
                            subtitle: "Learning Vibes",
                            icon: "brain.head.profile",
                            gradient: Gradient(colors: [.purple, .pink])
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    NavigationLink(destination: CoachingProgressView()) {
                        HubPanel(
                            title: "Milestones",
                            subtitle: "Check-in History",
                            icon: "trophy.fill",
                            gradient: Gradient(colors: [.yellow, .orange])
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Coaching")
        .task {
            await syncManager.syncNow(modelContext: modelContext)
        }
    }
}

#Preview {
    NavigationStack {
        CoachingHubView()
            .environment(AuthManager())
            .environment(SyncManager(authManager: AuthManager()))
            .modelContainer(for: UserActivity.self, inMemory: true)
    }
}

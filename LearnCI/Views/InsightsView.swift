import SwiftUI
import SwiftData

enum InsightsTab: String, CaseIterable, Identifiable {
    case activity = "Activity"
    case moods = "Moods"
    case milestones = "Milestones"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .activity: return "clock.arrow.circlepath"
        case .moods: return "brain.head.profile"
        case .milestones: return "trophy.fill"
        }
    }
}

struct InsightsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncManager.self) private var syncManager
    
    @State private var selectedTab: InsightsTab
    
    init(initialTab: InsightsTab = .activity) {
        _selectedTab = State(initialValue: initialTab)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Insights Tab", selection: $selectedTab) {
                    ForEach(InsightsTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .background(Color(UIColor.systemGroupedBackground))
                
                Group {
                    switch selectedTab {
                    case .activity:
                        ActivityHistoryContent()
                    case .moods:
                        CoachingMoodView()
                    case .milestones:
                        CoachingProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Coaching Insights")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await syncManager.syncNow(modelContext: modelContext)
            }
        }
    }
}

#Preview {
    let auth = AuthManager()
    return InsightsView()
        .environment(auth)
        .environment(SyncManager(authManager: auth))
        .environment(DataManager())
}

import SwiftUI
import SwiftData

struct InsightsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncManager.self) private var syncManager
    
    var body: some View {
        NavigationStack {
            CoachingHubView()
                .navigationTitle("Coaching")
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

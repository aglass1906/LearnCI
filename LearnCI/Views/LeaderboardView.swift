import SwiftUI
import SwiftData

struct LeaderboardView: View {
    @Environment(SyncManager.self) private var syncManager
    @Environment(AuthManager.self) private var authManager
    
    @State private var leaders: [ProfileDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            List {
                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .listRowBackground(Color.clear)
                }
                
                ForEach(Array(leaders.enumerated()), id: \.offset) { index, leader in
                    LeaderboardRow(rank: index + 1, leader: leader, isCurrentUser: isCurrentUser(leader))
                }
            }
            .navigationTitle("Global Leaders 🏆")
            .refreshable {
                await loadLeaderboard()
            }
            .overlay {
                if isLoading && leaders.isEmpty {
                    ProgressView()
                } else if leaders.isEmpty && !isLoading {
                    ContentUnavailableView("No Leaders Yet", systemImage: "trophy.slash", description: Text("Start learning to populate the board!"))
                }
            }
        }
        .task {
            await loadLeaderboard()
        }
    }
    
    private func isCurrentUser(_ leader: ProfileDTO) -> Bool {
        guard let currentID = authManager.currentUser else { return false }
        return leader.user_id.uuidString == currentID
    }
    
    private func loadLeaderboard() async {
        isLoading = true
        errorMessage = nil
        do {
            leaders = try await syncManager.fetchLeaderboard()
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

struct LeaderboardRow: View {
    let rank: Int
    let leader: ProfileDTO
    let isCurrentUser: Bool
    
    var body: some View {
        HStack {
            Text("\(rank)")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 30)
            
            VStack(alignment: .leading) {
                Text(leader.name)
                    .font(.headline)
                Text(leader.current_language.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text("\(leader.total_minutes ?? 0) min")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.blue)
        }
        .listRowBackground(
            isCurrentUser ? Color.blue.opacity(0.1) : nil
        )
    }
}

#Preview {
    LeaderboardView()
        .environment(SyncManager(authManager: AuthManager()))
        .environment(AuthManager())
}

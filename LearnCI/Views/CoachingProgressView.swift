import SwiftUI
import SwiftData

struct CoachingProgressView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(DataManager.self) private var dataManager
    
    @Query(sort: \CoachingCheckIn.date, order: .reverse) private var allCheckIns: [CoachingCheckIn]
    
    var checkIns: [CoachingCheckIn] {
        allCheckIns.filter { $0.userID == authManager.currentUser }
    }
    
    @State private var editingCheckIn: CoachingCheckIn?
    @State private var inspirationalQuote: InspirationalQuote?
    
    var body: some View {
        VStack(spacing: 0) {
            // Inspirational Quote
            if let quote = inspirationalQuote {
                VStack(spacing: 8) {
                    Text("\"\(quote.text)\"")
                        .font(.system(.body, design: .serif))
                        .italic()
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                    
                    Text("- \(quote.author)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.horizontal)
                .padding(.top, 8)
            }
            
            List {
                if checkIns.isEmpty {
                    ContentUnavailableView(
                        "No Milestones Yet",
                        systemImage: "trophy",
                        description: Text("Complete 25 hours of learning to unlock a check-in.")
                    )
                } else {
                    ForEach(checkIns) { item in
                        Button(action: { editingCheckIn = item }) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "trophy.fill")
                                        .foregroundStyle(.yellow)
                                    Text("\(item.hoursMilestone)h Check-in")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(item.date, format: .relative(presentation: .named))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Text("Sentiment: \(item.progressSentiment)")
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                
                                Text("Next: \(item.nextCyclePlan)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                modelContext.delete(item)
                                try? modelContext.save()
                            }
                        }
                    }
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .sheet(item: $editingCheckIn) { item in
            CoachingCheckInEditSheet(checkIn: item)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    let newCheckIn = CoachingCheckIn(hoursMilestone: 0, userID: authManager.currentUser)
                    modelContext.insert(newCheckIn)
                    editingCheckIn = newCheckIn
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            if inspirationalQuote == nil {
                inspirationalQuote = dataManager.getRandomQuote()
            }
        }
    }
}

#Preview {
    let auth = AuthManager()
    return CoachingProgressView()
        .environment(auth)
        .environment(SyncManager(authManager: auth))
        .environment(DataManager())
}

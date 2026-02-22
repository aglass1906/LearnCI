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
                            HStack(spacing: 16) {
                                // Date Column
                                VStack(alignment: .center) {
                                    Text(item.date.formatted(.dateTime.day()))
                                        .font(.title3)
                                        .fontWeight(.bold)
                                    Text(item.date.formatted(.dateTime.month(.abbreviated)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 40)
                                
                                Divider()
                                    .frame(height: 30)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: "trophy.fill")
                                            .foregroundStyle(.yellow)
                                            .font(.subheadline)
                                        Text("Milestone: \(item.hoursMilestone)h")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
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
                                
                                Spacer()
                                
                                Text(item.date, format: .relative(presentation: .named))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
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

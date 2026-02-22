import SwiftUI
import SwiftData

struct CoachingMoodView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(DataManager.self) private var dataManager
    
    @Query(sort: \DailyFeedback.date, order: .reverse) private var allFeedback: [DailyFeedback]
    
    var feedback: [DailyFeedback] {
        allFeedback.filter { $0.userID == authManager.currentUser }
    }
    
    @State private var editingFeedback: DailyFeedback?
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
                if feedback.isEmpty {
                    ContentUnavailableView(
                        "No Daily Feedback",
                        systemImage: "cloud.sun",
                        description: Text("Check in on the Dashboard to track your learning mood daily.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(feedback) { item in
                        Button(action: { editingFeedback = item }) {
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
                                
                                // Content
                                VStack(alignment: .leading, spacing: 4) {
                                    if let note = item.note, !note.isEmpty {
                                        Text(note)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                    } else {
                                        Text("No notes")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .italic()
                                    }
                                    
                                    Text(item.date, format: .relative(presentation: .named))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                // Mood
                                VStack(alignment: .trailing) {
                                    Image(systemName: DailyFeedback.moodIconName(for: item.rating))
                                        .foregroundStyle(DailyFeedback.moodColor(for: item.rating))
                                        .font(.title2)
                                    Text(item.moodDescription)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
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
            .listStyle(.plain)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .sheet(item: $editingFeedback) { item in
            DailyFeedbackEditSheet(feedback: item)
                .presentationDetents([.medium])
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    let newFeedback = DailyFeedback(rating: 3, userID: authManager.currentUser)
                    modelContext.insert(newFeedback)
                    editingFeedback = newFeedback
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
    return CoachingMoodView()
        .environment(auth)
        .environment(SyncManager(authManager: auth))
        .environment(DataManager())
}

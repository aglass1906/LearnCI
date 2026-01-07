import SwiftUI
import SwiftData

struct CoachingHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(DataManager.self) private var dataManager
    
    @Query(sort: \DailyFeedback.date, order: .reverse) private var allFeedback: [DailyFeedback]
    @Query(sort: \CoachingCheckIn.date, order: .reverse) private var allCheckIns: [CoachingCheckIn]
    
    var feedback: [DailyFeedback] {
        allFeedback.filter { $0.userID == authManager.currentUser }
    }
    
    var checkIns: [CoachingCheckIn] {
        allCheckIns.filter { $0.userID == authManager.currentUser }
    }
    
    @State private var selectedFilter = 0 // 0: Daily, 1: Milestones
    
    @State private var feedbackToEdit: DailyFeedback?
    @State private var checkInToEdit: CoachingCheckIn?
    @State private var inspirationalQuote: InspirationalQuote?
    
    var body: some View {
        NavigationStack {
            VStack {
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
                Picker("Filter", selection: $selectedFilter) {
                    Text("Daily Moods").tag(0)
                    Text("Milestones").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if selectedFilter == 0 {
                    dailyFeedbackList
                } else {
                    checkInList
                }
            }
            .navigationTitle("Coaching History")
            .background(Color(UIColor.systemGroupedBackground))
            .sheet(item: $feedbackToEdit) { item in
                DailyFeedbackEditSheet(feedback: item)
                    .presentationDetents([.medium])
            }
            .sheet(item: $checkInToEdit) { item in
                CoachingCheckInEditSheet(checkIn: item)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Add Daily Learning Mood", systemImage: "cloud") {
                            let newFeedback = DailyFeedback(rating: 3, userID: authManager.currentUser)
                            modelContext.insert(newFeedback)
                            feedbackToEdit = newFeedback
                        }
                        Button("Add Milestone", systemImage: "trophy") {
                            // Default to next likely milestone or just 0/custom
                            let newCheckIn = CoachingCheckIn(hoursMilestone: 0, userID: authManager.currentUser)
                            modelContext.insert(newCheckIn)
                            checkInToEdit = newCheckIn
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task {
            if inspirationalQuote == nil {
                inspirationalQuote = dataManager.getRandomQuote()
            }
        }
    }
    
    private var dailyFeedbackList: some View {
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
                    Button(action: { feedbackToEdit = item }) {
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
    
    private var checkInList: some View {
        List {
            if checkIns.isEmpty {
                ContentUnavailableView("No Milestones Yet", systemImage: "trophy", description: Text("Complete 25 hours of learning to unlock a check-in."))
            } else {
                ForEach(checkIns) { item in
                    Button(action: { checkInToEdit = item }) {
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
    

}

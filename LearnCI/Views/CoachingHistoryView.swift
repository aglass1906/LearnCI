import SwiftUI
import SwiftData

struct CoachingHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    
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
    
    var body: some View {
        NavigationStack {
            VStack {
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
    }
    
    private var dailyFeedbackList: some View {
        List {
            if feedback.isEmpty {
                ContentUnavailableView("No Daily Feedback", systemImage: "cloud", description: Text("Check in on the Dashboard to see entries here."))
            } else {
                ForEach(feedback) { item in
                    Button(action: { feedbackToEdit = item }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if let note = item.note, !note.isEmpty {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                moodIcon(for: item.rating)
                                Text(item.moodDescription)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
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
                                Text("\(item.hoursMilestone)h Mock Check-in")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(item.date.formatted(date: .abbreviated, time: .omitted))
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
    
    private func moodIcon(for rating: Int) -> some View {
        let iconName: String
        let color: Color
        switch rating {
        case 1: iconName = "cloud.rain.fill"; color = .gray
        case 2: iconName = "cloud.fill"; color = .blue.opacity(0.6)
        case 3: iconName = "cloud.sun.fill"; color = .orange.opacity(0.7)
        case 4: iconName = "sun.max.fill"; color = .yellow
        case 5: iconName = "sparkles"; color = .yellow
        default: iconName = "questionmark.circle"; color = .gray
        }
        
        return Image(systemName: iconName)
            .foregroundStyle(color)
    }
}

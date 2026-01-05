import SwiftUI
import SwiftData

struct CoachingCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    var userProfile: UserProfile
    var currentHours: Int
    var milestone: Int
    
    @State private var activityRatings: [String: Double] = [:]
    @State private var progressSentiment: String = ""
    @State private var nextCyclePlan: String = ""
    @State private var notes: String = ""
    
    // Define activities to rate (subset of all types for simplicity, or all)
    let activitiesToRate: [ActivityType] = [.appLearning, .listening, .watchingVideos, .reading, .speaking]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "trophy.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.yellow)
                        
                        Text("\(milestone) Hour Check-in")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("You've reached a major milestone! Let's reflect on your progress to keep moving forward.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                    .padding(.top)
                    
                    Divider()
                    
                    // 1. Activity Ratings
                    VStack(alignment: .leading, spacing: 16) {
                        Text("1. How helpful have these been?")
                            .font(.headline)
                        
                        ForEach(activitiesToRate) { type in
                            VStack(alignment: .leading) {
                                HStack {
                                    Image(systemName: type.icon)
                                        .foregroundStyle(type.color)
                                    Text(type.rawValue)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(ratingDescription(for: activityRatings[type.rawValue] ?? 3))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Slider(value: Binding(
                                    get: { activityRatings[type.rawValue] ?? 3 },
                                    set: { activityRatings[type.rawValue] = $0 }
                                ), in: 1...5, step: 1)
                                .tint(type.color)
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    // 2. Reflection
                    VStack(alignment: .leading, spacing: 16) {
                        Text("2. Reflection")
                            .font(.headline)
                        
                        VStack(alignment: .leading) {
                            Text("How do you feel about your progress?")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            TextField("I feel...", text: $progressSentiment, axis: .vertical)
                                .lineLimit(3...5)
                                .padding()
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .cornerRadius(12)
                        }
                        
                        VStack(alignment: .leading) {
                            Text("What will you focus on next?")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            TextField("I will focus on...", text: $nextCyclePlan, axis: .vertical)
                                .lineLimit(3...5)
                                .padding()
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Save Button
                    Button(action: saveCheckIn) {
                        Text("Complete Check-in")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(16)
                    }
                    .padding()
                    .disabled(progressSentiment.isEmpty)
                }
                .padding(.bottom, 40)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func ratingDescription(for value: Double) -> String {
        switch Int(value) {
        case 1: return "Not helpful"
        case 2: return "A little helpful"
        case 3: return "Okay"
        case 4: return "Very helpful"
        case 5: return "Game changer!"
        default: return ""
        }
    }
    
    private func saveCheckIn() {
        // Convert Doubles to Ints
        let finalRatings = activityRatings.mapValues { Int($0) }
        
        let checkIn = CoachingCheckIn(
            hoursMilestone: milestone,
            userID: userProfile.userID,
            activityRatings: finalRatings,
            progressSentiment: progressSentiment,
            nextCyclePlan: nextCyclePlan,
            notes: notes
        )
        
        modelContext.insert(checkIn)
        
        // Update user profile to postpone next check-in
        userProfile.lastCheckInHours = milestone
        
        dismiss()
    }
}

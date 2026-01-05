import SwiftUI
import SwiftData

struct CoachingCheckInEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var checkIn: CoachingCheckIn
    
    // Define activities to rate (matches check-in view)
    let activitiesToRate: [ActivityType] = [.appLearning, .listening, .watchingVideos, .reading, .speaking]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Milestone") {
                    HStack {
                        Text("Hours Reached:")
                        Spacer()
                        TextField("Hours", value: $checkIn.hoursMilestone, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("Date", selection: $checkIn.date, displayedComponents: .date)
                }
                
                Section("Activity Ratings") {
                    ForEach(activitiesToRate) { type in
                        VStack(alignment: .leading) {
                            HStack {
                                Image(systemName: type.icon)
                                    .foregroundStyle(type.color)
                                Text(type.rawValue)
                                Spacer()
                                Text("\(checkIn.activityRatings[type.rawValue] ?? 3)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Slider(value: Binding(
                                get: { Double(checkIn.activityRatings[type.rawValue] ?? 3) },
                                set: { 
                                    checkIn.activityRatings[type.rawValue] = Int($0)
                                    checkIn.isSynced = false
                                    try? modelContext.save()
                                }
                            ), in: 1...5, step: 1)
                            .tint(type.color)
                        }
                    }
                }
                
                Section("Reflections") {
                    VStack(alignment: .leading) {
                        Text("Sentiment")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Sentiment", text: $checkIn.progressSentiment, axis: .vertical)
                            .lineLimit(3...5)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Next Cycle Plan")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Plan", text: $checkIn.nextCyclePlan, axis: .vertical)
                            .lineLimit(3...5)
                    }
                }
                
                Section("Notes") {
                    TextField("Additional notes...", text: Binding(
                        get: { checkIn.notes ?? "" },
                        set: { checkIn.notes = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                }
            }
            .navigationTitle("Edit Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { 
                        try? modelContext.save()
                        dismiss() 
                    }
                }
            }
            .onChange(of: checkIn.progressSentiment) { _, _ in 
                checkIn.isSynced = false 
                try? modelContext.save()
            }
            .onChange(of: checkIn.nextCyclePlan) { _, _ in 
                checkIn.isSynced = false 
                try? modelContext.save()
            }
            .onChange(of: checkIn.notes) { _, _ in 
                checkIn.isSynced = false 
                try? modelContext.save()
            }
            .onChange(of: checkIn.hoursMilestone) { _, _ in 
                checkIn.isSynced = false 
                try? modelContext.save()
            }
            // Observe activity ratings change if possible, or assume slider updates trigger sync flag manually if needed (bindable should handle it for simple properties, dictionary might be tricky but let's see)
        }
    }
}

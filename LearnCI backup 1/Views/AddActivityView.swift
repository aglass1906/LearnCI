import SwiftUI
import SwiftData

struct AddActivityView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    
    @State private var selectedActivity: ActivityType = .appLearning
    @State private var minutes: Double = 15
    @State private var selectedDate: Date = Date()
    @State private var selectedLanguage: Language = .spanish
    
    var userProfile: UserProfile? {
        profiles.first
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Activity Details")) {
                    Picker("Activity Type", selection: $selectedActivity) {
                        ForEach(ActivityType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    
                    DatePicker("Date", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                    
                    VStack(alignment: .leading) {
                        Text("Duration: \(Int(minutes)) minutes")
                        Slider(value: $minutes, in: 5...120, step: 5)
                    }
                }
                
                Section(header: Text("Language")) {
                    Picker("Language", selection: $selectedLanguage) {
                        ForEach(Language.allCases) { lang in
                            Text(lang.rawValue).tag(lang)
                        }
                    }
                }
            }
            .navigationTitle("Log Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveActivity()
                    }
                }
            }
            .onAppear {
                if let profile = userProfile {
                    selectedLanguage = profile.currentLanguage
                }
            }
        }
    }
    
    func saveActivity() {
        let newActivity = UserActivity(date: selectedDate, minutes: Int(minutes), activityType: selectedActivity, language: selectedLanguage)
        modelContext.insert(newActivity)
        dismiss()
    }
}

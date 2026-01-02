import SwiftUI
import SwiftData

struct TrackerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    
    @State private var selectedActivity: ActivityType = .appLearning
    @State private var minutes: Double = 15
    @State private var selectedDate: Date = Date()
    @State private var showAlert = false
    
    var userProfile: UserProfile? {
        profiles.first
    }
    
    var body: some View {
        NavigationView {
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
                
                Section {
                    Button(action: saveActivity) {
                        Text("Log Activity")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color.blue)
                }
            }
            .navigationTitle("Track Learning")
            .alert("Activity Logged!", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            }
        }
    }
    
    func saveActivity() {
        let language = userProfile?.currentLanguage ?? .spanish
        let newActivity = UserActivity(date: selectedDate, minutes: Int(minutes), activityType: selectedActivity, language: language)
        modelContext.insert(newActivity)
        showAlert = true
    }
}

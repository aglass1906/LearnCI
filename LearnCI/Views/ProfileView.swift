import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    
    @State private var name: String = ""
    @State private var selectedLanguage: Language = .spanish
    @State private var selectedLevel: LearningLevel = .superBeginner
    @State private var dailyGoal: Double = 30
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("User Info")) {
                    TextField("Name", text: $name)
                    
                    Picker("Target Language", selection: $selectedLanguage) {
                        ForEach(Language.allCases) { lang in
                            Text("\(lang.flag) \(lang.rawValue)").tag(lang)
                        }
                    }
                    
                    Picker("Current Level", selection: $selectedLevel) {
                        ForEach(LearningLevel.allCases) { level in
                            Text("\(level.rawValue) (\(level.cerCode))").tag(level)
                        }
                    }
                }
                
                Section(header: Text("Goals")) {
                    VStack(alignment: .leading) {
                        Text("Daily Goal: \(Int(dailyGoal)) minutes")
                        Slider(value: $dailyGoal, in: 10...120, step: 5)
                    }
                }
                
                Section {
                    Button("Save Changes") {
                        saveProfile()
                    }
                    .disabled(profiles.isEmpty) // Disable if we haven't loaded yet? Actually we should just create one.
                }
            }
            .navigationTitle("Profile")
            .onAppear {
                if let profile = profiles.first {
                    name = profile.name
                    selectedLanguage = profile.currentLanguage
                    selectedLevel = profile.currentLevel
                    dailyGoal = Double(profile.dailyGoalMinutes)
                } else {
                    // Create default if none exists
                    let newProfile = UserProfile()
                    modelContext.insert(newProfile)
                    // We'll let the query update refresh the view on next loop or manually set it?
                    // SwiftData query updates immediately usually.
                }
            }
        }
    }
    
    func saveProfile() {
        if let profile = profiles.first {
            profile.name = name
            profile.currentLanguage = selectedLanguage
            profile.currentLevel = selectedLevel
            profile.dailyGoalMinutes = Int(dailyGoal)
            
            // Should auto-save context in SwiftData, but explicit sometimes helps debugging.
        }
    }
}

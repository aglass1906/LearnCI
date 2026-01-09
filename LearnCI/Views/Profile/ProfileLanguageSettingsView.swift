import SwiftUI
import SwiftData

struct ProfileLanguageSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    let profile: UserProfile
    
    @State private var selectedLanguage: Language = .spanish
    @State private var selectedLevel: LearningLevel = .superBeginner
    @State private var dailyGoal: Double = 30
    @State private var startingHours: Int = 0
    @State private var isEditing: Bool = false
    
    var body: some View {
        Form {
            Section(header: Text("Language Learning")) {
                if isEditing {
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
                    
                    VStack(alignment: .leading) {
                        Text("Daily Time Goal: \(Int(dailyGoal)) minutes")
                        Slider(value: $dailyGoal, in: 10...120, step: 5)
                            .tint(.blue)
                    }
                    
                    HStack {
                        Text("Starting Hours")
                        Spacer()
                        TextField("Hours", value: $startingHours, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    LabeledContent("Target Language", value: "\(selectedLanguage.flag) \(selectedLanguage.rawValue)")
                    LabeledContent("Current Level", value: "\(selectedLevel.rawValue) (\(selectedLevel.cerCode))")
                    LabeledContent("Daily Goal", value: "\(Int(dailyGoal)) minutes")
                    LabeledContent("Starting Hours", value: "\(startingHours) hours")
                }
                
                if isEditing {
                    Text("Add your previous learning time to your total.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Language Learning")
        .navigationBarBackButtonHidden(isEditing)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                 if isEditing {
                     Button("Save") {
                         saveData()
                         withAnimation { isEditing = false }
                     }
                     .fontWeight(.bold)
                 } else {
                     Button("Edit") {
                         withAnimation { isEditing = true }
                     }
                 }
            }
            
            if isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        loadData()
                        withAnimation { isEditing = false }
                    }
                }
            }
        }
        .onAppear {
            loadData()
        }
    }
    
    private func loadData() {
        selectedLanguage = profile.currentLanguage
        selectedLevel = profile.currentLevel
        dailyGoal = Double(profile.dailyGoalMinutes)
        startingHours = profile.startingHours
    }
    
    private func saveData() {
        profile.currentLanguage = selectedLanguage
        profile.currentLevel = selectedLevel
        profile.dailyGoalMinutes = Int(dailyGoal)
        profile.startingHours = startingHours
        profile.updatedAt = Date()
    }
}

import SwiftUI
import SwiftData

struct ProfileLanguageSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    let profile: UserProfile
    
    @State private var selectedLanguage: Language = .spanish
    @State private var proficiencyLevel: Int = 1
    @State private var selectedScale: ProficiencyScale = .simple
    @State private var dailyGoal: Double = 30
    @State private var startingHours: Int = 0
    @State private var originalStartDate: Date = Date()
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
                    
                    Picker("Proficiency Scale", selection: $selectedScale) {
                        ForEach(ProficiencyScale.allCases) { scale in
                            Text(scale.rawValue).tag(scale)
                        }
                    }
                    
                    Picker("Current Level", selection: $proficiencyLevel) {
                        ForEach(1...6, id: \.self) { level in
                            let label = LevelManager.shared.displayString(level: level, language: selectedLanguage.code, preferredScale: selectedScale)
                            Text(label).tag(level)
                        }
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Daily Time Goal: \(Int(dailyGoal)) minutes")
                        Slider(value: $dailyGoal, in: 10...120, step: 5)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Study Hours")
                            Spacer()
                            TextField("0", value: $startingHours, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 96)
                        }

                        Stepper("Adjust Study Hours", value: $startingHours, in: 0...10_000)
                    }

                    Text("Include any hours you studied before using LearnCI.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    DatePicker("Original Start Date", selection: $originalStartDate, in: ...Date(), displayedComponents: .date)
                } else {
                    LabeledContent("Target Language", value: "\(selectedLanguage.flag) \(selectedLanguage.rawValue)")
                    LabeledContent("Level System", value: selectedScale.rawValue)
                    let levelLabel = LevelManager.shared.displayString(level: proficiencyLevel, language: selectedLanguage.code, preferredScale: selectedScale)
                    LabeledContent("Current Level", value: levelLabel)
                    LabeledContent("Daily Goal", value: "\(Int(dailyGoal)) minutes")
                    LabeledContent("Study Hours", value: "\(startingHours) hours")
                    LabeledContent("Started Learning", value: originalStartDate.formatted(date: .abbreviated, time: .omitted))
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
        proficiencyLevel = profile.proficiencyLevel
        selectedScale = profile.preferredScale
        dailyGoal = Double(profile.dailyGoalMinutes)
        startingHours = profile.startingHours
        originalStartDate = profile.originalStartDate ?? Date()
    }
    
    private func saveData() {
        profile.currentLanguage = selectedLanguage
        profile.proficiencyLevel = proficiencyLevel
        profile.preferredScale = selectedScale
        profile.dailyGoalMinutes = Int(dailyGoal)
        profile.startingHours = startingHours
        profile.originalStartDate = originalStartDate
        profile.updatedAt = Date()
    }
}

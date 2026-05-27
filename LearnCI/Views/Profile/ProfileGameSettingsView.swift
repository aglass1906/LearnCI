import SwiftUI
import SwiftData

struct ProfileGameSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    let profile: UserProfile
    
    @State private var dailyCardGoal: Double = 20
    @State private var selectedGamePreset: GameConfiguration.Preset = .inputFocus
    @State private var soundEffectsEnabled: Bool = true
    @State private var hapticsEnabled: Bool = true
    @State private var isEditing: Bool = false
    
    var body: some View {
        Form {
            Section(header: Text("Game Settings")) {
                if isEditing {
                    Stepper("Daily Card Goal: \(Int(dailyCardGoal))", value: $dailyCardGoal, in: 5...100, step: 5)
                    
                    Picker("Default Card Display", selection: $selectedGamePreset) {
                        ForEach(GameConfiguration.Preset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                } else {
                    LabeledContent("Daily Card Goal", value: "\(Int(dailyCardGoal))")
                    LabeledContent("Default Card Display", value: selectedGamePreset.rawValue)
                }
            }

            Section(header: Text("Game Feedback")) {
                if isEditing {
                    Toggle(isOn: $soundEffectsEnabled) {
                        Label("Sound Effects", systemImage: "speaker.wave.2")
                    }

                    Toggle(isOn: $hapticsEnabled) {
                        Label("Haptics", systemImage: "iphone.radiowaves.left.and.right")
                    }
                } else {
                    LabeledContent("Sound Effects", value: soundEffectsEnabled ? "On" : "Off")
                    LabeledContent("Haptics", value: hapticsEnabled ? "On" : "Off")
                }
            }
        }
        .navigationTitle("Game Settings")
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
        dailyCardGoal = Double(profile.dailyCardGoal ?? 20)
        selectedGamePreset = profile.defaultGamePreset
        soundEffectsEnabled = profile.gameSoundEffectsEnabled
        hapticsEnabled = profile.gameHapticsEnabled
    }
    
    private func saveData() {
        profile.dailyCardGoal = Int(dailyCardGoal)
        profile.defaultGamePreset = selectedGamePreset
        profile.gameSoundEffectsEnabled = soundEffectsEnabled
        profile.gameHapticsEnabled = hapticsEnabled
        GameFeedbackManager.shared.configure(
            soundEffectsEnabled: soundEffectsEnabled,
            hapticsEnabled: hapticsEnabled
        )
        try? modelContext.save()
    }
}

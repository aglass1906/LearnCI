import SwiftUI
import SwiftData

struct ProfileAudioSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    let profile: UserProfile
    
    @State private var ttsRate: Float = 0.5
    @State private var isEditing: Bool = false
    
    var body: some View {
        Form {
            Section(header: Text("Audio Settings")) {
                if isEditing {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Robot Voice Speed")
                            Spacer()
                            Text(String(format: "%.1fx", ttsRate * 2))
                                .foregroundColor(.secondary)
                                .font(.callout)
                                .monospacedDigit()
                        }
                        
                        Slider(value: $ttsRate, in: 0.1...1.0, step: 0.1) {
                            Text("Confirm")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise.fill")
                        } maximumValueLabel: {
                            Image(systemName: "hare.fill")
                        }
                        .tint(.blue)
                    }
                } else {
                    LabeledContent("Robot Voice Speed", value: String(format: "%.1fx", ttsRate * 2))
                }
            }
        }
        .navigationTitle("Audio Settings")
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
        ttsRate = profile.ttsRate
    }
    
    private func saveData() {
        profile.ttsRate = ttsRate
        profile.updatedAt = Date()
    }
}

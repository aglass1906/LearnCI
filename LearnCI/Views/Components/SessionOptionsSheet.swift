import SwiftUI

struct SessionOptionsSheet: View {
    @Binding var sessionDuration: Int
    @Binding var sessionCardGoal: Int
    @Binding var isRandomOrder: Bool
    @Binding var useTTSFallback: Bool
    @Binding var ttsRate: Float
    var gameType: GameConfiguration.GameType = .flashcards // Default for preview/fallback
    
    @Environment(\.dismiss) private var dismiss
    
    // Computed properties for step logic
    var stepAmount: Int {
        gameType == .memoryMatch ? 8 : 5
    }
    
    var minAmount: Int {
        gameType == .memoryMatch ? 8 : 5
    }
    
    var maxAmount: Int {
        100
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Time Limit")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.blue)
                            Text("\(sessionDuration) minutes")
                                .font(.headline)
                        }
                        
                        Slider(value: Binding(get: { Double(sessionDuration) }, set: { sessionDuration = Int($0) }), in: 1...60, step: 1)
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Card Goal")) {
                    Stepper(value: $sessionCardGoal, in: minAmount...maxAmount, step: stepAmount) {
                        HStack {
                            Image(systemName: "target")
                                .foregroundColor(.red)
                            Text("Review \(sessionCardGoal) cards")
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if gameType == .memoryMatch {
                         Text("Multiples of 8 for 4x4 Grid")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Audio Options")) {
                    Toggle("System Voice Fallback", isOn: $useTTSFallback)
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Voice Speed")
                            Spacer()
                            Text(String(format: "%.1fx", ttsRate * 2))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $ttsRate, in: 0.1...1.0, step: 0.1) {
                            Text("Speed")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise.fill").font(.caption2)
                        } maximumValueLabel: {
                            Image(systemName: "hare.fill").font(.caption2)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section {
                    Toggle(isOn: $isRandomOrder) {
                        Label("Randomize Order", systemImage: "shuffle")
                            .foregroundColor(.orange)
                    }
                } footer: {
                    Text("Randomizing changes the order of cards for this session.")
                }
                
                Section {
                    Button(action: { dismiss() }) {
                        Text("Done")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle("Session Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                 ToolbarItem(placement: .confirmationAction) {
                     Button("Done") { dismiss() }
                 }
            }
        }
        .onAppear {
            if gameType == .memoryMatch {
                // Snap to nearest multiple of 8
                let remainder = sessionCardGoal % 8
                if remainder != 0 {
                    if remainder >= 4 {
                        sessionCardGoal += (8 - remainder)
                    } else {
                        sessionCardGoal -= remainder
                    }
                    // Ensure min
                    if sessionCardGoal < 8 { sessionCardGoal = 8 }
                }
            }
        }
    }
}

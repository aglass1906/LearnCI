import SwiftUI

struct SessionOptionsView: View {
    @Binding var sessionDuration: Int
    @Binding var sessionCardGoal: Int
    @Binding var navigationStyle: NavigationStyle
    @Binding var autoNextDelay: TimeInterval
    @Binding var confirmationStyle: ConfirmationStyle
    @Binding var useTTSFallback: Bool
    @Binding var ttsRate: Float
    @Binding var order: GameConfiguration.OrderStrategy

    let gameType: GameConfiguration.GameType
    let maxCards: Int?
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkipToSummary: () -> Void
    
    var body: some View {
        Form {
            // Time Limit
            Section("Time Limit") {
                HStack {
                    Text("\(sessionDuration) min")
                    Spacer()
                    Stepper("", value: $sessionDuration, in: 1...60)
                }
            }
            
            // Card Options (Goal & Order merged)
            Section("Card Options") {
                // Goal
                if let maxCards = maxCards {
                    HStack {
                        Text("\(sessionCardGoal) cards")
                        Spacer()
                        Stepper("", value: $sessionCardGoal, in: min(5, maxCards)...maxCards)
                    }
                    Text("Max \(maxCards) cards available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    HStack {
                        Text("\(sessionCardGoal) cards")
                        Spacer()
                        Stepper("", value: $sessionCardGoal, in: 5...100)
                    }
                }
                

                // Order
                Picker("Card Order", selection: $order) {
                    ForEach(GameConfiguration.OrderStrategy.allCases) { orderType in
                        Text(orderType.rawValue).tag(orderType)
                    }
                }
                .pickerStyle(.menu) // Using menu to be compact in the same section
            }
            
            
            // Input & Flow (Flashcards Only)
            if gameType == .flashcards {
                Section(header: Text("Flashcard Controls"), footer: order == .smart ? Text("SRS order requires SRS grading.") : nil) {
                    Picker("Navigation", selection: $navigationStyle) {
                        ForEach(NavigationStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Picker("Grading", selection: $confirmationStyle) {
                        ForEach(ConfirmationStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(order == .smart)
                    .opacity(order == .smart ? 0.6 : 1.0)
                }
            }
            
            // Audio Options
            Section("Audio Options") {
                Toggle("Voice Fallback", isOn: $useTTSFallback)
                
                if useTTSFallback {
                    VStack(alignment: .leading) {
                        Text("Voice Speed: \(String(format: "%.1f", ttsRate * 2))x")
                        Slider(value: $ttsRate, in: 0.1...1.0, step: 0.1)
                    }
                }
            }
        }
        .onAppear {
            if let max = maxCards {
                if sessionCardGoal > max {
                    sessionCardGoal = max
                }
                if sessionCardGoal < min(5, max) {
                    sessionCardGoal = min(5, max)
                }
            }
        }
        .onChange(of: order) { _, newValue in
            if newValue == .smart {
                confirmationStyle = .srs
            }
        }
    }
}

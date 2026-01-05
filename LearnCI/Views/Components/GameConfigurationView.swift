import SwiftUI

struct GameConfigurationView: View {
    @Binding var sessionLanguage: Language
    @Binding var sessionLevel: LearningLevel
    @Binding var selectedDeck: DeckMetadata?
    @Binding var sessionDuration: Int
    @Binding var sessionCardGoal: Int
    @Binding var isRandomOrder: Bool
    @Binding var selectedPreset: GameConfiguration.Preset
    @Binding var customConfig: GameConfiguration
    
    let availableDecks: [DeckMetadata]
    let startAction: () -> Void
    
    // Sheet State
    @State private var showDeckSelection = false
    @State private var showDisplayConfig = false
    @State private var showSessionOptions = false
    
    // Callback to save default preset
    var onSavePreset: ((GameConfiguration.Preset) -> Void)?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                deckSelectionSection
                configurationSection
                adjustmentsSection
                
                SessionSummaryView(
                    deckTitle: selectedDeck?.title ?? "Select Deck",
                    language: sessionLanguage,
                    level: sessionLevel,
                    preset: selectedPreset,
                    duration: sessionDuration,
                    cardGoal: sessionCardGoal,
                    isRandom: isRandomOrder
                )
                .padding(.horizontal)
                .padding(.top, 10)
                
                Spacer()
                
                Button(action: startAction) {
                    Text("Start Learn Session")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedDeck == nil ? Color.gray : Color.blue)
                        .cornerRadius(15)
                        .shadow(radius: selectedDeck == nil ? 0 : 5)
                }
                .disabled(selectedDeck == nil)
                .padding(.horizontal)
                .padding(.top, 40)
            }
            .padding(.vertical)
        }
        .sheet(isPresented: $showDeckSelection) {
            DeckSelectionSheet(
                availableDecks: availableDecks,
                selectedDeck: $selectedDeck,
                language: $sessionLanguage,
                level: $sessionLevel
            )
        }
        .sheet(isPresented: $showDisplayConfig) {
            DisplayConfigurationSheet(
                selectedPreset: $selectedPreset,
                customConfig: $customConfig,
                onSave: {
                    onSavePreset?(selectedPreset)
                }
            )
        }
        .sheet(isPresented: $showSessionOptions) {
            SessionOptionsSheet(
                sessionDuration: $sessionDuration,
                sessionCardGoal: $sessionCardGoal,
                isRandomOrder: $isRandomOrder
            )
        }
    }
    
    // Removed focusSelectionSection as language/level are now in the sheet
    
    private var deckSelectionSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Select Deck")
                .font(.headline)
            
            Button(action: { showDeckSelection = true }) {
                HStack {
                    if let deck = selectedDeck {
                        VStack(alignment: .leading) {
                            Text(deck.title)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("\(deck.level.rawValue) • \(deck.language.rawValue)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Choose a Deck...")
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding(.horizontal)
    }
    
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Card Display")
                .font(.headline)
            
            Button(action: { showDisplayConfig = true }) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(selectedPreset.rawValue)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        if selectedPreset == .customize {
                            Text("Custom Settings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "slider.horizontal.3")
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding(.horizontal)
    }

    private var adjustmentsSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Session Options")
                .font(.headline)
            
            Button(action: { showSessionOptions = true }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(sessionDuration) min • \(sessionCardGoal) cards")
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        if isRandomOrder {
                            Text("Random Order")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text("Sequential Order")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding(.horizontal)
    }
}

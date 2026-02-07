import SwiftUI

struct FlashcardConfigView: View {
    let deck: CardDeck
    let sessionCards: [LearningCard]
    let currentCardIndex: Int
    let learnedCount: Int
    let sessionCardGoal: Int
    let sessionConfig: GameConfiguration
    @Binding var isFlipped: Bool
    
    let onRelearn: () -> Void
    let onLearned: () -> Void
    let onNext: () -> Void
    let onPrev: () -> Void
    let onGrade: ((SmartSessionManager.Grade) -> Void)?
    
    @State private var selectedPreset: GameConfiguration.Preset = .inputFocus
    @State private var customConfig: GameConfiguration = GameConfiguration.from(preset: .inputFocus)
    @State private var showGame: Bool = false
    @State private var showCustomize: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Title
                VStack(spacing: 8) {
                    Text("Flashcards")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Choose your card layout")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                // Preset Selection Cards
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(GameConfiguration.Preset.allCases, id: \.self) { preset in
                            PresetOptionCard(
                                preset: preset,
                                isSelected: selectedPreset == preset
                            )
                            .onTapGesture {
                                if preset == .customize {
                                    showCustomize = true
                                } else {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedPreset = preset
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Start Button
                Button(action: {
                    showGame = true
                }) {
                    Text("Start Game")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .cornerRadius(12)
                }
                .padding()
            }
            .navigationDestination(isPresented: $showGame) {
                FlashcardGameView(
                    deck: deck,
                    sessionCards: sessionCards,
                    currentCardIndex: currentCardIndex,
                    learnedCount: learnedCount,
                    sessionCardGoal: sessionCardGoal,
                    sessionConfig: configForPreset(selectedPreset),
                    isFlipped: $isFlipped,
                    onRelearn: onRelearn,
                    onLearned: onLearned,
                    onNext: onNext,
                    onPrev: onPrev,
                    onGrade: onGrade
                )
            }
            .sheet(isPresented: $showCustomize) {
                DisplayConfigurationSheet(
                    selectedPreset: $selectedPreset,
                    customConfig: $customConfig,
                    onSave: {
                        // Configuration saved
                    }
                )
            }
        }
    }
    
    private func configForPreset(_ preset: GameConfiguration.Preset) -> GameConfiguration {
        if preset == .customize {
            var config = customConfig
            config.ttsVoiceGender = sessionConfig.ttsVoiceGender
            config.ttsRate = sessionConfig.ttsRate
            return config
        } else {
            var config = GameConfiguration.from(preset: preset)
            config.ttsVoiceGender = sessionConfig.ttsVoiceGender
            config.ttsRate = sessionConfig.ttsRate
            return config
        }
    }
}

struct PresetOptionCard: View {
    let preset: GameConfiguration.Preset
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: presetIcon)
                .font(.title)
                .foregroundColor(presetColor)
                .frame(width: 44)
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.rawValue)
                    .font(.headline)
                Text(presetDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Selection Indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .purple : .gray)
                .font(.title2)
                .padding(.trailing)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.purple.opacity(0.1) : Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
        )
    }
    
    private var presetIcon: String {
        switch preset {
        case .inputFocus: return "text.bubble.fill"
        case .audioCards: return "speaker.wave.3.fill"
        case .pictureCard: return "photo.fill"
        case .flashcard: return "rectangle.portrait.fill"
        case .story: return "book.fill"
        case .customize: return "slider.horizontal.3"
        }
    }
    
    private var presetColor: Color {
        switch preset {
        case .inputFocus: return .blue
        case .audioCards: return .orange
        case .pictureCard: return .green
        case .flashcard: return .purple
        case .story: return .brown
        case .customize: return .gray
        }
    }
    
    private var presetDescription: String {
        switch preset {
        case .inputFocus: return "Text & Audio (Immersion)"
        case .audioCards: return "Audio Only (Listening)"
        case .pictureCard: return "Image & Text (Visual)"
        case .flashcard: return "Text Only (Drill)"
        case .story: return "Read & Listen (Immersion)"
        case .customize: return "Custom Display"
        }
    }
}

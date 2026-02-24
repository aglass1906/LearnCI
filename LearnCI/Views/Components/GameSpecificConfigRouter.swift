import SwiftUI

/// Routes to appropriate game-specific configuration view based on game type
struct GameSpecificConfigRouter: View {
    let gameType: GameConfiguration.GameType
    let deck: DeckMetadata
    @Binding var selectedPreset: GameConfiguration.Preset
    @Binding var customConfig: GameConfiguration
    @Binding var memoryMatchMode: GameConfiguration.MemoryMatchMode
    
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkipToSummary: () -> Void
    
    var body: some View {
        Group {
            switch gameType {
            case .flashcards, .story:
                // Flashcard Layout Preset Selection
                FlashcardConfigView(
                    gameType: gameType,
                    deck: deck,
                    selectedPreset: $selectedPreset,
                    customConfig: $customConfig,
                    onNext: onNext,
                    onBack: onBack,
                    onSkipToSummary: onSkipToSummary
                )
            case .memoryMatch:
                // Memory Match Mode Selection
                MemoryConfigView(
                    deck: deck,
                    selectedMode: $memoryMatchMode,
                    onNext: onNext,
                    onBack: onBack,
                    onSkipToSummary: onSkipToSummary
                )
            case .linker:
                LinkerConfigView(
                    deck: deck,
                    customConfig: $customConfig,
                    onNext: onNext,
                    onBack: onBack,
                    onSkipToSummary: onSkipToSummary
                )
            case .wordCrush:
                WordCrushConfigView(
                    deck: deck,
                    customConfig: $customConfig,
                    onNext: onNext,
                    onBack: onBack,
                    onSkipToSummary: onSkipToSummary
                )
            case .multipleChoice, .audioCloze:
                // Games without specific configuration use placeholder
                PlaceholderConfigView(
                    gameType: gameType,
                    onNext: onNext,
                    onBack: onBack,
                    onSkipToSummary: onSkipToSummary
                )
            }
        }
    }
}

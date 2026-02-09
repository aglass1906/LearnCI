import SwiftUI

/// Stage 3: Flashcard Layout Preset Selection
struct FlashcardLayoutSelector: View {
    let deck: DeckMetadata
    @Binding var selectedPreset: GameConfiguration.Preset
    @Binding var customConfig: GameConfiguration
    
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkipToSummary: () -> Void
    
    @State private var showCustomize: Bool = false
    
    var body: some View {
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
            
            // Next Button
            Button(action: onNext) {
                HStack {
                    Text("Next")
                    Image(systemName: "chevron.right")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple)
                .cornerRadius(12)
            }
            .padding()
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

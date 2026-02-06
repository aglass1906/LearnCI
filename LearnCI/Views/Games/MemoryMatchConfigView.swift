import SwiftUI

struct MemoryMatchConfigView: View {
    let sessionCards: [LearningCard]
    let deck: CardDeck
    let sessionConfig: GameConfiguration
    let onGameComplete: () -> Void
    let onMatchFound: () -> Void
    
    @State private var selectedMode: MemoryMatchMode = .pictureToWord
    @State private var showGame = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Title
                VStack(spacing: 8) {
                    Text("Memory Match")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Choose your matching mode")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                // Mode Selection Cards
                VStack(spacing: 16) {
                    ForEach(MemoryMatchMode.allCases, id: \.self) { mode in
                        ModeOptionCard(
                            mode: mode,
                            isSelected: selectedMode == mode
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                selectedMode = mode
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
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
                MemoryGameView(
                    sessionCards: sessionCards,
                    deck: deck,
                    sessionConfig: sessionConfig,
                    matchMode: selectedMode,
                    onGameComplete: onGameComplete,
                    onMatchFound: onMatchFound
                )
            }
        }
    }
}

struct ModeOptionCard: View {
    let mode: MemoryMatchMode
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Visual Preview
            HStack(spacing: 8) {
                CardPreview(content: nativeContent, isImage: nativeIsImage)
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                CardPreview(content: targetContent, isImage: targetIsImage)
            }
            .padding(.leading)
            
            Spacer()
            
            // Mode Label
            VStack(alignment: .trailing) {
                Text(mode.rawValue)
                    .font(.headline)
                Text(modeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.trailing)
            
            // Selection Indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .purple : .gray)
                .font(.title2)
                .padding(.trailing)
        }
        .frame(height: 100)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.purple.opacity(0.1) : Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
        )
    }
    
    private var nativeContent: String {
        mode == .wordToWord || mode == .wordToPicture ? "Hello" : "🖼️"
    }
    
    private var nativeIsImage: Bool {
        mode == .pictureToWord
    }
    
    private var targetContent: String {
        mode == .wordToWord ? "Hola" : mode == .wordToPicture ? "🖼️" : "Hola"
    }
    
    private var targetIsImage: Bool {
        mode == .wordToPicture
    }
    
    private var modeDescription: String {
        switch mode {
        case .wordToWord:
            return "Match translations"
        case .wordToPicture:
            return "Match words to images"
        case .pictureToWord:
            return "Match images to words"
        }
    }
}

struct CardPreview: View {
    let content: String
    let isImage: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)
                .frame(width: 60, height: 80)
                .shadow(radius: 2)
            
            if isImage {
                Text(content)
                    .font(.system(size: 32))
            } else {
                Text(content)
                    .font(.system(size: 12, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
        }
    }
}

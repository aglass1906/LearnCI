import SwiftUI

struct PlaceholderConfigView: View {
    let gameType: GameConfiguration.GameType
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkipToSummary: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Icon
                Image(systemName: gameType.icon)
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                    .padding(.top, 40)
                
                // Title
                Text(gameType.rawValue)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // Description
                VStack(alignment: .leading, spacing: 15) {
                    Text("About This Game")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text(gameDescription)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineSpacing(6)
                }
                .padding(.horizontal)
                .padding()
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Spacer()
                
                // Next Button
                Button(action: onNext) {
                    HStack {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(15)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Game Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    var gameDescription: String {
        switch gameType {
        case .flashcards:
            return "Review vocabulary with traditional flashcards. See the word, try to recall it, then flip to check your answer."
        case .memoryMatch:
            return "Match pairs of cards by finding the word and its translation or image. Test your memory and vocabulary recognition."
        case .multipleChoice:
            return "Choose the correct answer from multiple options. Great for testing your comprehension and vocabulary recognition."
        case .audioCloze:
            return "Listen to a sentence and fill in the missing word. Perfect for improving your listening skills and context understanding."
        case .linker:
            return "Connect words or phrases to form correct sentences or associations. Test your understanding of relationships between words."
        case .story:
            return "Read through stories in your target language with audio support. Immerse yourself in contextual learning."
        case .wordCrush:
            return "Match word pairs in a cascading grid. Tap matching target and native language tiles to clear them and earn streak bonuses."
        }
    }
}

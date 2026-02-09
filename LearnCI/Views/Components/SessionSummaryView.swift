import SwiftUI

/// Reusable session summary component showing game configuration details
struct SessionSummaryView: View {
    let deckTitle: String
    let language: Language
    let level: Int
    let preset: GameConfiguration.Preset
    let gameType: GameConfiguration.GameType
    let duration: Int
    let cardGoal: Int
    let order: GameConfiguration.OrderStrategy
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session Summary")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            VStack(spacing: 0) {
                // Focus Row (Language & Level)
                HStack {
                    Text(language.flag)
                        .font(.title3)
                    Text(language.rawValue)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    // We need preferred scale here, but simple fallback is fine for summary logic for now
                    // Or we can grab it from UserProfile if available, or just display generic normalized string
                    Text(LevelManager.shared.displayString(level: level, language: language.code, preferredScale: .simple)) 
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding()
                
                Divider()
                
                // Deck Row
                HStack {
                    Image(systemName: "menucard.fill")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    Text(deckTitle)
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding()
                
                Divider()
                
                // Mode Row
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.purple)
                        .frame(width: 24)
                    VStack(alignment: .leading) {
                        Text(gameType.rawValue)
                            .fontWeight(.medium)
                        Text(preset.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding()
                
                Divider()
                
                // Session Row
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.orange)
                        .frame(width: 24)
                    VStack(alignment: .leading) {
                        Text("\(duration) min · \(cardGoal) cards")
                            .fontWeight(.medium)
                        Text(order.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding()
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
}

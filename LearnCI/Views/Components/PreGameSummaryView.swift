import SwiftUI

/// Pre-game summary view (Stage 4) - Shows final confirmation before starting game
struct PreGameSummaryView: View {
    let deckTitle: String
    let coverImage: String?
    let folderName: String?
    let language: Language
    let level: Int
    let preset: GameConfiguration.Preset
    let gameType: GameConfiguration.GameType
    let duration: Int
    let cardGoal: Int
    let order: GameConfiguration.OrderStrategy
    var customConfig: GameConfiguration? = nil

    let onStartGame: () -> Void
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Selected Game - first and prominent
                gameHeroSection
                    .padding(.top, 20)
                    .padding(.horizontal)

                // 2. Session summary (deck, language, session details)
                SessionSummaryView(
                    deckTitle: deckTitle,
                    coverImage: coverImage,
                    folderName: folderName,
                    language: language,
                    level: level,
                    duration: duration,
                    cardGoal: cardGoal,
                    order: order
                )
                .padding(.horizontal)

                // 3. Game-specific configuration (if applicable)
                if let config = customConfig {
                    let items = gameConfigItems(config)
                    if !items.isEmpty {
                        gameConfigSection(items: items)
                            .padding(.horizontal)
                    }
                }

                Spacer(minLength: 16)

                // 4. Action buttons
                VStack(spacing: 12) {
                    Button(action: onStartGame) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Start Game")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(gameType.tileColor)
                        .cornerRadius(15)
                    }

                    Button(action: onBack) {
                        Text("Go Back")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onStartGame) {
                    Text("Start")
                        .fontWeight(.bold)
                }
                .buttonStyle(.borderedProminent)
                .tint(gameType.tileColor)
            }
        }
    }

    // MARK: - Game Hero

    private var gameHeroSection: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(gameType.tileColor.gradient)
                    .frame(width: 88, height: 88)
                    .shadow(color: gameType.tileColor.opacity(0.35), radius: 12, y: 6)

                Image(systemName: gameType.icon)
                    .font(.system(size: 40))
                    .foregroundColor(.white)
            }

            VStack(spacing: 4) {
                Text(gameType.rawValue)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(gameType.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Game-Specific Config Section

    struct ConfigItem: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let value: String
        let color: Color
    }

    private func gameConfigItems(_ config: GameConfiguration) -> [ConfigItem] {
        switch gameType {
        case .wordRain:
            return [
                ConfigItem(icon: "wind", label: "Speed", value: config.wordRainSpeed.rawValue, color: .teal),
                ConfigItem(icon: "brain", label: "Difficulty", value: config.wordRainDifficulty.rawValue, color: .red),
                ConfigItem(icon: "square.grid.2x2", label: "Words on Screen", value: "\(config.wordRainWordCount)", color: .blue),
            ]
        case .wordCrush:
            return [
                ConfigItem(icon: "square.grid.3x3.fill", label: "Grid Size", value: config.wordCrushGridSize.rawValue, color: .indigo),
                ConfigItem(icon: "arrow.left.arrow.right", label: "Match Mode", value: config.wordCrushDisplayMode.rawValue, color: .purple),
            ]
        case .memoryMatch:
            return [
                ConfigItem(icon: "square.grid.2x2", label: "Match Mode", value: config.memoryMatchMode.rawValue, color: .purple),
            ]
        case .linker:
            return [
                ConfigItem(icon: "text.alignleft", label: "Right Column", value: config.linkerTargetMode.rawValue, color: .cyan),
            ]
        case .multipleChoice:
            return [
                ConfigItem(icon: "list.number", label: "Options", value: "\(config.multipleChoiceOptionCount)", color: .green),
                ConfigItem(icon: "text.bubble", label: "Show Translation", value: config.multipleChoiceShowTranslation ? "On" : "Off", color: .teal),
            ]
        case .audioCloze:
            return [
                ConfigItem(icon: "list.number", label: "Options", value: "\(config.audioClozeOptionCount)", color: .pink),
                ConfigItem(icon: "text.bubble", label: "Show Translation", value: config.audioClozeShowTranslation ? "On" : "Off", color: .teal),
            ]
        case .flashcards:
            return [
                ConfigItem(icon: "rectangle.stack.fill", label: "Preset", value: preset.rawValue, color: .blue),
                ConfigItem(icon: "hand.draw", label: "Navigation", value: config.navigation.displayName, color: .indigo),
                ConfigItem(icon: "checkmark.circle", label: "Grading", value: config.confirmation.displayName, color: .green),
            ]
        default:
            return []
        }
    }

    @ViewBuilder
    private func gameConfigSection(items: [ConfigItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Game Settings")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider() }
                    HStack {
                        Image(systemName: item.icon)
                            .foregroundColor(item.color)
                            .frame(width: 24)
                        Text(item.label)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(item.value)
                            .fontWeight(.medium)
                    }
                    .padding()
                }
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
}

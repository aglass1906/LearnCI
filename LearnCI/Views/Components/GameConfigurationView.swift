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
    @Binding var selectedGameType: GameConfiguration.GameType
    @Binding var useTTSFallback: Bool
    @Binding var ttsRate: Float
    
    let availableDecks: [DeckMetadata]
    let startAction: () -> Void
    
    // Sheet State
    @State private var showDeckSelection = false
    @State private var showDisplayConfig = false
    @State private var showSessionOptions = false
    
    // Callback to save default preset
    var onSavePreset: ((GameConfiguration.Preset) -> Void)?
    
    private var effectiveConfig: GameConfiguration {
        selectedPreset == .customize ? customConfig : GameConfiguration.from(preset: selectedPreset)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                // Unified Settings Card (Mimics Session Summary)
                VStack(spacing: 0) {
                    // Row 1: Deck Selection (Merged)
                    Button(action: { showDeckSelection = true }) {
                        SettingsRow(
                            icon: "menucard.fill",
                            iconColor: .blue,
                            text: selectedDeck?.title ?? "Select a Deck...",
                            subText: "\(sessionLanguage.flag) \(sessionLanguage.rawValue) · \(sessionLevel.rawValue)"
                        )
                    }
                    
                    Divider()
                        .padding(.leading, 50)
                    
                    // Row 1.5: Game Mode
                    Menu {
                        Picker("Game Mode", selection: $selectedGameType) {
                            ForEach(GameConfiguration.GameType.allCases) { type in
                                Label(type.rawValue, systemImage: type.icon)
                                    .tag(type)
                            }
                        }
                    } label: {
                        SettingsRow(
                            icon: selectedGameType.icon,
                            iconColor: .indigo,
                            text: selectedGameType.rawValue,
                            subText: "Tap to change game mode"
                        )
                    }
                    
                    Divider()
                        .padding(.leading, 50)

                    // Row 2: Display Mode
                    if selectedGameType == .flashcards {
                        Button(action: { showDisplayConfig = true }) {
                            SettingsRow(
                                icon: "slider.horizontal.3",
                                iconColor: .purple,
                                text: selectedPreset.rawValue == "Customize" ? "Custom Display" : selectedPreset.rawValue
                            ) {
                                DisplayConfigurationSummaryView(config: effectiveConfig)
                            }
                        }
                        
                        Divider()
                            .padding(.leading, 50)
                    }
                    
                    // Row 3: Session Options
                    Button(action: { showSessionOptions = true }) {
                        SettingsRow(
                            icon: "gearshape.fill",
                            iconColor: .orange,
                            text: "\(sessionDuration) min · \(sessionCardGoal) cards",
                            subText: nil // Use subContent for multi-line
                        ) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isRandomOrder ? "Random Order" : "Sequential")
                                
                                if useTTSFallback {
                                    Text("Voice On · \(String(format: "%.1fx", ttsRate * 2)) Speed")
                                } else {
                                    Text("Voice Off")
                                }
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                    }
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Helper text
                Text("Tap any row to change settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: startAction) {
                    Text("Start Learn Session")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedDeck == nil ? Color.gray : Color.blue)
                        .cornerRadius(15)
                        .shadow(color: .blue.opacity(0.3), radius: selectedDeck == nil ? 0 : 8, y: 4)
                }
                .disabled(selectedDeck == nil)
                .padding(.horizontal)
                .padding(.top, 20)
            }
            .padding(.vertical)
        }
        .background(Color(UIColor.systemGroupedBackground)) // Better background for the card style
        .sheet(isPresented: $showDeckSelection) {
            DeckSelectionSheet(
                availableDecks: availableDecks,
                selectedDeck: $selectedDeck,
                language: $sessionLanguage,
                level: $sessionLevel,
                selectedGameType: $selectedGameType
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
                isRandomOrder: $isRandomOrder,
                useTTSFallback: $useTTSFallback,
                ttsRate: $ttsRate,
                gameType: selectedGameType
            )
        }
        // React to changes to apply deck defaults
        .onChange(of: selectedDeck) { _, newDeck in
            applyDeckDefaults(from: newDeck, for: selectedGameType)
        }
        .onChange(of: selectedGameType) { _, newType in
            applyDeckDefaults(from: selectedDeck, for: newType)
            
            // Auto-switch preset for Story Mode
            if newType == .story {
                selectedPreset = .story
            } else if selectedPreset == .story {
                // If switching away from Story, revert to a default (e.g. Input Focus)
                selectedPreset = .inputFocus
            }
        }
    }
    
    // Extract defaults from metadata without loading full deck
    private func applyDeckDefaults(from deck: DeckMetadata?, for type: GameConfiguration.GameType) {
        guard let deck = deck, let config = deck.gameConfiguration else { return }
        
        // Find matching key (case-insensitive)
        let typeKey = type.rawValue // "Flashcards"
        
        var defaults: DeckDefaults?
        
        // Iterate keys to find case-insensitive match
        for (jsonKey, val) in config {
            if jsonKey.caseInsensitiveCompare(typeKey) == .orderedSame {
                defaults = val
                break
            }
        }
        
        if let defaults = defaults {
            if let random = defaults.randomize {
                isRandomOrder = random
            }
            // Add other defaults here as needed (e.g. autoplay)
        }
    }
    
    private func displayDescription(for preset: GameConfiguration.Preset, config: GameConfiguration) -> String {
        switch preset {
        case .customize:
            return "Tap to configure elements" // Fallback if needed, though viewbuilder handles it
        case .inputFocus:
            return "Text & Audio (Immersion)"
        case .audioCards:
            return "Audio Only (Listening)"
        case .pictureCard:
            return "Image & Text (Visual)"
        case .flashcard:
            return "Text Only (Drill)"
        case .story:
            return "Read & Listen (Immersion)"
        }
    }
}

// Reusable Row Component matching Summary Style
struct SettingsRow<Content: View>: View {
    var icon: String
    var iconColor: Color = .primary
    var text: String
    var subText: String?
    var isEmojiIcon: Bool
    var subContent: Content
    
    init(icon: String, iconColor: Color = .primary, text: String, subText: String? = nil, isEmojiIcon: Bool = false, @ViewBuilder subContent: () -> Content = { EmptyView() }) {
        self.icon = icon
        self.iconColor = iconColor
        self.text = text
        self.subText = subText
        self.isEmojiIcon = isEmojiIcon
        self.subContent = subContent()
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon Area
            if isEmojiIcon {
                Text(icon)
                    .font(.title2)
                    .frame(width: 24)
            } else {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(iconColor)
                    .frame(width: 24)
            }
            
            // Text Area
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                if let sub = subText {
                    Text(sub)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                } else {
                    subContent
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .contentShape(Rectangle()) // Full row clickable
    }
}

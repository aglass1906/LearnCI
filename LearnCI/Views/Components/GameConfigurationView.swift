import SwiftUI

struct GameConfigurationView: View {
    @Binding var sessionLanguage: Language

    @Binding var sessionLevel: Int // 1-6
    var preferredScale: ProficiencyScale
    @Binding var selectedDeck: DeckMetadata?
    @Binding var sessionDuration: Int
    @Binding var sessionCardGoal: Int
    @Binding var isRandomOrder: Bool
    @Binding var selectedPreset: GameConfiguration.Preset
    @Binding var customConfig: GameConfiguration
    @Binding var selectedGameType: GameConfiguration.GameType
    @Binding var useTTSFallback: Bool
    @Binding var ttsRate: Float
    
    @Binding var navigationStyle: NavigationStyle
    @Binding var autoNextDelay: TimeInterval
    @Binding var confirmationStyle: ConfirmationStyle
    
    let availableDecks: [DeckMetadata]
    let startAction: () -> Void
    var onSavePreset: (GameConfiguration.Preset) -> Void
    
    @Environment(DataManager.self) private var dataManager
    
    // Sheet State
    @State private var showDeckPicker = false
    @State private var showTagSelection = false
    @State private var showDisplayConfig = false
    @State private var showSessionOptions = false
    @State private var currentDeckCount: Int?
    
    
    private var effectiveConfig: GameConfiguration {
        selectedPreset == .customize ? customConfig : GameConfiguration.from(preset: selectedPreset)
    }
    
    private var deckImage: UIImage? {
        guard let deck = selectedDeck, let cover = deck.coverImage else { return nil }
        return dataManager.loadImage(folderName: deck.folderName, filename: cover)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                // Unified Settings Card (Mimics Session Summary)
                VStack(spacing: 0) {
                    // Row 1: Game Mode
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

                    // Row 2: Deck Selection (Merged)
                    Button(action: { showDeckPicker = true }) {
                        SettingsRow(
                            icon: "menucard.fill",
                            iconColor: .blue,
                            text: selectedDeck?.folderName == "Virtual" ? "Deck: Custom" : (selectedDeck?.title ?? "Select a Deck..."),
                            subText: selectedDeck == nil ? "Compatible with \(selectedGameType.rawValue)" : "\(sessionLanguage.flag) \(sessionLanguage.rawValue) · \(LevelManager.shared.displayString(level: sessionLevel, language: sessionLanguage.code, preferredScale: preferredScale))",
                            customImage: deckImage
                        )
                    }
                    
                    Divider()
                        .padding(.leading, 50)
                    
                    // Row 3: Tag Selection (Virtual Decks)
                    Button(action: { showTagSelection = true }) {
                        SettingsRow(
                            icon: "tag.fill",
                            iconColor: .mint,
                            text: selectedDeck?.folderName == "Virtual" ? (selectedDeck?.title ?? "Filter by Tag") : "Filter by Tag",
                            subText: selectedDeck?.folderName == "Virtual" ? (currentDeckCount != nil ? "\(currentDeckCount!) cards available" : "Loading...") : "Create a custom deck from all cards"
                        )
                    }
                    
                    Divider()
                        .padding(.leading, 50)

                    // Row 4: Display Mode
                    if selectedGameType == .flashcards {
                        Button(action: { showDisplayConfig = true }) {
                            SettingsRow(
                                icon: "slider.horizontal.3",
                                iconColor: .purple,
                                text: "Card Layout",
                                subText: selectedPreset.rawValue == "Customize" ? "Custom Display" : selectedPreset.rawValue
                            )
                        }
                        
                        Divider()
                            .padding(.leading, 50)
                    }
                    
                    // Row 5: Session Options
                    Button(action: { showSessionOptions = true }) {
                        SettingsRow(
                            icon: "gearshape.fill",
                            iconColor: .orange,
                            text: "Session Options"
                        ) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(sessionDuration) min · \(sessionCardGoal) cards")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                Text(isRandomOrder ? "Random Order" : "Sequential")
                                
                                HStack(spacing: 4) {
                                    Text(navigationStyle.displayName)
                                    Text("·")
                                    Text(confirmationStyle.displayName)
                                }
                                
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
                
                // Deck selection reminder when none selected
                if selectedDeck == nil {
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.orange)
                        Text("Select a deck to start")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.vertical)
        }
        .background(Color(UIColor.systemGroupedBackground)) // Better background for the card style
        .sheet(isPresented: $showDeckPicker) {
            DeckSelectionSheet(
                availableDecks: availableDecks.filter { $0.supportedModes.contains(selectedGameType) },
                selectedDeck: $selectedDeck,
                language: $sessionLanguage,
                level: $sessionLevel,
                preferredScale: preferredScale,
                selectedGameType: $selectedGameType
            )
        }
        .sheet(isPresented: $showTagSelection) {
            TagSelectionSheet(
                language: sessionLanguage,
                selectedDeck: $selectedDeck
            )
        }
        .sheet(isPresented: $showDisplayConfig) {
            DisplayConfigurationSheet(
                selectedPreset: $selectedPreset,
                customConfig: $customConfig,
                onSave: {
                    onSavePreset(selectedPreset)
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
                navigationStyle: $navigationStyle,
                autoNextDelay: $autoNextDelay,
                confirmationStyle: $confirmationStyle,
                gameType: selectedGameType,
                maxCards: currentDeckCount // Pass this to limit max options
            )
        }
        .onChange(of: selectedPreset) { newPreset in
            if newPreset != .customize {
                // Load defaults from Layouts (DataManager)
                let config = dataManager.configuration(for: newPreset)
                navigationStyle = config.navigation
                autoNextDelay = config.autoNextDelay
                confirmationStyle = config.confirmation
            }
        }
        // React to changes to apply deck defaults
        .onChange(of: selectedDeck) { _, newDeck in
            applyDeckDefaults(from: newDeck, for: selectedGameType)
        }
        .onChange(of: selectedGameType) { _, newType in
            // Validate deck compatibility
            if let deck = selectedDeck, !deck.supportedModes.contains(newType) {
                selectedDeck = nil // Clear if incompatible
            }
            
            applyDeckDefaults(from: selectedDeck, for: newType)
            
            // Auto-switch preset for Story Mode
            if newType == .story {
                selectedPreset = .story
            } else if selectedPreset == .story {
                // If switching away from Story, revert to a default (e.g. Input Focus)
                selectedPreset = .inputFocus
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: startAction) {
                    Text("Start")
                        .fontWeight(.semibold)
                }
                .disabled(selectedDeck == nil)
            }
        }
    }
    
    // Extract defaults from metadata without loading full deck
    private func applyDeckDefaults(from deck: DeckMetadata?, for type: GameConfiguration.GameType) {
        guard let deck = deck else { return }
        
        // Apply defaults if available
        if let config = deck.gameConfiguration {
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
        
        // Reset count to show loading state and prevent stale data
        currentDeckCount = nil
        
        // Also update card goal cap based on actual deck size
        print("DEBUG: applyDeckDefaults - Starting load for \(deck.title)")
        Task {
            if let loaded = dataManager.loadDeck(from: deck) {
                let totalCards = loaded.cards.count
                print("DEBUG: Loaded deck \(deck.title) with \(totalCards) cards")
                await MainActor.run {
                    self.currentDeckCount = totalCards // Store for UI
                    
                    // Update goal to match exactly if it's a virtual deck (per user request)
                    if deck.folderName == "Virtual" {
                        print("DEBUG: Virtual deck detected. Setting goal from \(sessionCardGoal) to \(totalCards)")
                        sessionCardGoal = totalCards
                    } else if sessionCardGoal > totalCards {
                        print("DEBUG: Normal deck. Capping goal from \(sessionCardGoal) to \(totalCards)")
                        // Cap for normal decks
                        sessionCardGoal = totalCards
                    } else {
                        print("DEBUG: Goal \(sessionCardGoal) valid for deck size \(totalCards)")
                    }
                    
                    // Optional: If you want to force it to max for virtual decks?
                    // For now, capping it is safer.
                    // Also ensure we don't go below 1
                    if sessionCardGoal < 5 && totalCards >= 5 {
                         // Keep user preference, but ensure reasonable minimum if possible
                    }
                }
            }
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
    var customImage: UIImage?
    var subContent: Content
    
    init(icon: String, iconColor: Color = .primary, text: String, subText: String? = nil, isEmojiIcon: Bool = false, customImage: UIImage? = nil, @ViewBuilder subContent: () -> Content = { EmptyView() }) {
        self.icon = icon
        self.iconColor = iconColor
        self.text = text
        self.subText = subText
        self.isEmojiIcon = isEmojiIcon
        self.customImage = customImage
        self.subContent = subContent()
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon Area
            if let image = customImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40) // Square for cover
                    .cornerRadius(8)
                    .clipped()
            } else if isEmojiIcon {
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
                    .lineLimit(1) // Avoid overflow
                
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

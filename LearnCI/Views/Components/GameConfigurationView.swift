import SwiftUI

struct GameConfigurationView: View {
    @Binding var sessionLanguage: Language
    @Binding var sessionLevel: Int // 1-6
    var preferredScale: ProficiencyScale
    @Binding var selectedDeck: DeckMetadata?
    @Binding var selectedGameType: GameConfiguration.GameType
    
    let availableDecks: [DeckMetadata]
    let onNext: () -> Void
    let onSkipToSummary: () -> Void
    
    @Environment(DataManager.self) private var dataManager
    
    // Sheet State
    @State private var showDeckPicker = false
    @State private var showTagSelection = false
    @State private var currentDeckCount: Int?
    
    private var deckImage: UIImage? {
        guard let deck = selectedDeck, let cover = deck.coverImage else { return nil }
        return dataManager.loadImage(folderName: deck.folderName, filename: cover)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                // Stage 1: Deck Selection Only
                VStack(spacing: 16) {
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
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                    
                    // Row 2: Deck Selection
                    Button(action: { showDeckPicker = true }) {
                        SettingsRow(
                            icon: "menucard.fill",
                            iconColor: .blue,
                            text: deckTitleText,
                            subText: deckSubtitleText,
                            customImage: deckImage
                        )
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                    
                    // Row 3: Tag Selection
                    Button(action: { showTagSelection = true }) {
                        SettingsRow(
                            icon: "tag.fill",
                            iconColor: .mint,
                            text: tagRowTitle,
                            subText: tagRowSubtitle
                        )
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                
                // Deck selection reminder
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
                defaultLevel: mapLevel(sessionLevel),
                selectedDeck: $selectedDeck
            )
        }
        .onChange(of: selectedDeck, perform: { newDeck in
            // Handle virtual deck card counts
            if let deck = newDeck, deck.folderName == "Virtual" {
                // TODO: Implement dynamic card count in DeckMetadata or via DataManager
                currentDeckCount = nil
            } else {
                currentDeckCount = nil
            }
        })
        .onChange(of: selectedGameType, perform: { newType in
            // Validate deck compatibility
            if let deck = selectedDeck, !deck.supportedModes.contains(newType) {
                selectedDeck = nil
            }
        })
    }
    
    // MARK: - Helper Properties for Text
    
    private var deckTitleText: String {
        guard let deck = selectedDeck else { return "Select a Deck..." }
        return deck.folderName == "Virtual" ? "Deck: Custom" : deck.title
    }
    
    private var deckSubtitleText: String {
        guard let _ = selectedDeck else { return "Compatible with \(selectedGameType.rawValue)" }
        return "\(sessionLanguage.flag) \(sessionLanguage.rawValue) · \(LevelManager.shared.displayString(level: sessionLevel, language: sessionLanguage.code, preferredScale: preferredScale))"
    }
    
    private var tagRowTitle: String {
        guard let deck = selectedDeck, deck.folderName == "Virtual" else { return "Filter by Tag" }
        return deck.title
    }
    
    private var tagRowSubtitle: String {
        guard let deck = selectedDeck, deck.folderName == "Virtual" else { return "Create a custom deck from all cards" }
        if let count = currentDeckCount {
            return "\(count) cards available"
        } else {
            return "Loading..."
        }
    }

    private func mapLevel(_ level: Int) -> LearningLevel {
        switch level {
        case 1: return .superBeginner
        case 2: return .beginner
        case 3, 4: return .intermediate
        case 5, 6: return .advanced
        default: return .intermediate
        }
    }
}

// Reusable Row Component
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

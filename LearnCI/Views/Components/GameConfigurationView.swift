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
                    
                    // Row 2: Display Mode
                    Button(action: { showDisplayConfig = true }) {
                        SettingsRow(
                            icon: "slider.horizontal.3",
                            iconColor: .purple,
                            text: selectedPreset.rawValue == "Customize" ? "Custom Display" : selectedPreset.rawValue
                        ) {
                            let config = effectiveConfig
                            HStack(spacing: 16) {
                                // Word
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "textformat")
                                            .foregroundColor(.blue)
                                        Text("Word")
                                            .fontWeight(.medium)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    
                                    // Text Status
                                    Text(config.word.text == .visible ? "Visible" : (config.word.text == .hidden ? "Hidden" : "Hint"))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    
                                    // Audio Status
                                    HStack(spacing: 2) {
                                        Image(systemName: config.word.audio == .hidden ? "speaker.slash" : "speaker.wave.2.fill")
                                        Text(config.word.audio == .visible ? "Auto" : (config.word.audio == .hidden ? "Off" : "Manual"))
                                    }
                                    .font(.caption2)
                                    .foregroundColor(config.word.audio == .hidden ? .secondary.opacity(0.7) : .blue)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                // Sentence
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "text.bubble")
                                            .foregroundColor(.purple)
                                        Text("Sent.")
                                            .fontWeight(.medium)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    
                                    // Text Status
                                    Text(config.sentence.text == .visible ? "Visible" : (config.sentence.text == .hidden ? "Hidden" : "Hint"))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    // Audio Status
                                    HStack(spacing: 2) {
                                        Image(systemName: config.sentence.audio == .hidden ? "speaker.slash" : "speaker.wave.2.fill")
                                        Text(config.sentence.audio == .visible ? "Auto" : (config.sentence.audio == .hidden ? "Off" : "Manual"))
                                    }
                                    .font(.caption2)
                                    .foregroundColor(config.sentence.audio == .hidden ? .secondary.opacity(0.7) : .purple)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                // Image
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "photo")
                                            .foregroundColor(.orange)
                                        Text("Image")
                                            .fontWeight(.medium)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    
                                    Text(config.image == .visible ? "Visible" : (config.image == .hidden ? "Hidden" : "Hint"))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    
                                    // Spacer to align with audio rows
                                    Text(" ") 
                                        .font(.caption2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            // Back of Card Section
                            Divider()
                                .padding(.vertical, 4)
                            
                            HStack(spacing: 16) {
                                // Translation
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "character.book.closed")
                                            .foregroundColor(.gray)
                                        Text("Trans.")
                                            .fontWeight(.medium)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    
                                    Text(config.back.translation == .visible ? "Visible" : (config.back.translation == .hidden ? "Hidden" : "Hint"))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                // Meaning
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "text.quote")
                                            .foregroundColor(.gray)
                                        Text("Mean.")
                                            .fontWeight(.medium)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    
                                    Text(config.back.sentenceMeaning == .visible ? "Visible" : (config.back.sentenceMeaning == .hidden ? "Hidden" : "Hint"))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                // Links
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "link")
                                            .foregroundColor(.gray)
                                        Text("Links")
                                            .fontWeight(.medium)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    
                                    Text(config.back.studyLinks == .visible ? "Visible" : (config.back.studyLinks == .hidden ? "Hidden" : "Hint"))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.bottom, 2)
                        }
                    }
                    
                    Divider()
                        .padding(.leading, 50)
                    
                    // Row 3: Session Options
                    Button(action: { showSessionOptions = true }) {
                        SettingsRow(
                            icon: "gearshape.fill",
                            iconColor: .orange,
                            text: "\(sessionDuration) min · \(sessionCardGoal) cards",
                            subText: isRandomOrder ? "Random Order" : "Sequential"
                        )
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
                level: $sessionLevel
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
                isRandomOrder: $isRandomOrder
            )
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

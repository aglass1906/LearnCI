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
    
    private var deckImage: UIImage? {
        guard let deck = selectedDeck, let cover = deck.coverImage else { return nil }
        return dataManager.loadImage(folderName: deck.folderName, filename: cover)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                // Stage 1: Deck Selection Only
                VStack(spacing: 16) {
                    // Row 1: Deck Selection
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
                
                // Virtual deck tag summary
                if let deck = selectedDeck, deck.folderName == "Virtual" {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.subheadline)
                                .foregroundColor(.mint)
                            Text("Custom Deck")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Spacer()
                            if let desc = deck.description {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Tag chips from the title ("Focus: A, B, C" -> ["A", "B", "C"])
                        let tagNames = extractTags(from: deck.title)
                        if !tagNames.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(tagNames, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Image(systemName: "tag.fill")
                                            .font(.caption2)
                                        Text(tag)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.mint.opacity(0.12))
                                    .foregroundColor(.mint)
                                    .cornerRadius(16)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

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

                VStack(spacing: 12) {
                    Button(action: onSkipToSummary) {
                        Label("Start Now", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedDeck == nil ? Color.gray : selectedGameType.tileColor)
                            .cornerRadius(12)
                    }
                    .disabled(selectedDeck == nil)

                    Button(action: onNext) {
                        Label("Continue to Game Options", systemImage: "slider.horizontal.3")
                            .font(.headline)
                            .foregroundColor(selectedDeck == nil ? .secondary : selectedGameType.tileColor)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background((selectedDeck == nil ? Color.gray : selectedGameType.tileColor).opacity(0.12))
                            .cornerRadius(12)
                    }
                    .disabled(selectedDeck == nil)
                }
                .padding(.horizontal)
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
        .onChange(of: selectedGameType) { _, newType in
            // Validate deck compatibility
            if let deck = selectedDeck, !deck.supportedModes.contains(newType) {
                selectedDeck = nil
            }
        }
    }
    
    // MARK: - Helper Properties for Text
    
    private var deckTitleText: String {
        guard let deck = selectedDeck else { return "Select a Deck..." }
        return deck.folderName == "Virtual" ? "Deck: Custom" : deck.title
    }
    
    private var deckSubtitleText: String {
        guard let deck = selectedDeck else { return "Compatible with \(selectedGameType.rawValue)" }
        var sub = "\(sessionLanguage.flag) \(sessionLanguage.rawValue) · \(LevelManager.shared.displayString(level: sessionLevel, language: sessionLanguage.code, preferredScale: preferredScale))"
        if let desc = deck.description {
            sub += "\n\(desc)"
        }
        return sub
    }
    
    private var tagRowTitle: String {
        guard let deck = selectedDeck, deck.folderName == "Virtual" else { return "Filter by Tags" }
        return deck.title
    }

    private var tagRowSubtitle: String {
        guard let deck = selectedDeck, deck.folderName == "Virtual" else { return "Create a custom deck from all cards" }
        if let desc = deck.description {
            return desc
        }
        return "Custom tag deck"
    }

    private func extractTags(from title: String) -> [String] {
        // Title format: "Focus: Tag1, Tag2, Tag3"
        guard title.hasPrefix("Focus: ") else { return [] }
        let raw = String(title.dropFirst("Focus: ".count))
        return raw.components(separatedBy: ", ").filter { !$0.isEmpty }
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
                    .lineLimit(2)
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

// Wrapping layout for tag chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

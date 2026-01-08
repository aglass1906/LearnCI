import SwiftUI

struct DeckSelectionSheet: View {
    let availableDecks: [DeckMetadata]
    @Binding var selectedDeck: DeckMetadata?
    @Binding var language: Language
    @Binding var level: LearningLevel
    @Binding var selectedGameType: GameConfiguration.GameType
    
    @Environment(\.dismiss) private var dismiss
    
    var filteredDecks: [DeckMetadata] {
        availableDecks.filter { deck in
            // Filter by language and level is implicit in availableDecks (passed from GameView),
            // BUT GameView currently passes `dataManager.availableDecks` which *is* filtered by discoverDecks.
            // However, we now want to ensure the deck supports the current GAME MODE.
            deck.supportedModes.contains(selectedGameType)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filters (Language/Level)
                VStack(spacing: 12) {
                    HStack {
                         // Language Selector
                        Menu {
                            ForEach(Language.allCases) { lang in
                                Button(action: { language = lang }) {
                                    HStack {
                                        Text("\(lang.flag) \(lang.rawValue)")
                                        if language == lang { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("\(language.flag) \(language.rawValue)")
                                    .fontWeight(.medium)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        
                        // Level Selector
                        Menu {
                            ForEach(LearningLevel.allCases) { lvl in
                                Button(action: { level = lvl }) {
                                    HStack {
                                        Text(lvl.rawValue)
                                        if level == lvl { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(level.rawValue)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }
                    .foregroundColor(.primary)
                }
                .padding()
                .background(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 5, y: 5)
                .zIndex(1)
                
                List {
                    if filteredDecks.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            Text("No decks found.")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("No decks match \(language.rawValue) \(level.rawValue) for \(selectedGameType.rawValue).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredDecks) { deck in
                            DeckSelectionRow(deck: deck, selectedDeckId: selectedDeck?.id) {
                                selectedDeck = deck
                                dismiss()
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Select Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

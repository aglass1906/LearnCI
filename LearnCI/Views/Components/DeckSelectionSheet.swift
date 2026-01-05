import SwiftUI

struct DeckSelectionSheet: View {
    let availableDecks: [DeckMetadata]
    @Binding var selectedDeck: DeckMetadata?
    @Binding var language: Language
    @Binding var level: LearningLevel
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filters
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
                    if availableDecks.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            Text("No decks found for this selection.")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Try changing the level or language.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(availableDecks) { deck in
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

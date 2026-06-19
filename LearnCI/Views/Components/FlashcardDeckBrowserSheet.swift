import SwiftUI
import SwiftData

struct FlashcardDeckBrowserSheet: View {
    let deckMetadata: DeckMetadata

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(DataManager.self) private var dataManager
    @Environment(SavedStudyWordManager.self) private var savedStudyWordManager

    @State private var deck: CardDeck?
    @State private var searchText = ""

    private var filteredCards: [LearningCard] {
        let cards = deck?.cards ?? []
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return cards }
        return cards.filter {
            $0.wordTarget.localizedCaseInsensitiveContains(query) ||
            $0.wordNative.localizedCaseInsensitiveContains(query) ||
            $0.sentenceTarget.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let deck {
                    List(filteredCards) { card in
                        FlashcardBrowserRow(
                            card: card,
                            deck: deck,
                            isSaved: isSaved(card, in: deck),
                            onSave: { save(card, from: deck) }
                        )
                    }
                    .searchable(text: $searchText, prompt: "Search cards")
                } else {
                    ProgressView("Loading cards...")
                }
            }
            .navigationTitle(deckMetadata.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                deck = dataManager.loadDeck(from: deckMetadata)
            }
        }
    }

    private func isSaved(_ card: LearningCard, in deck: CardDeck) -> Bool {
        guard let userID = authManager.currentUser else { return false }
        return savedStudyWordManager.isSaved(
            word: card.wordTarget,
            userID: userID,
            languageCode: deck.language.code,
            sourceType: .flashcard,
            sourceId: "\(deck.id):\(card.id)",
            in: modelContext
        )
    }

    private func save(_ card: LearningCard, from deck: CardDeck) {
        guard let userID = authManager.currentUser else { return }
        let capture = SavedStudyWordCapture(
            userID: userID,
            word: card.wordTarget,
            translation: card.wordNative,
            lemma: nil,
            sentenceTarget: card.sentenceTarget,
            sentenceNative: card.sentenceNative,
            languageCode: deck.language.code,
            level: deck.level?.cerCode ?? deck.proficiencyLevel.map { String($0) },
            partOfSpeech: nil,
            verbTense: nil,
            grammarNotes: nil,
            sourceType: .flashcard,
            sourceId: "\(deck.id):\(card.id)",
            sourceTitle: deck.title,
            sourceUrl: nil,
            blockIndex: nil,
            mediaStart: nil,
            mediaEnd: nil,
            audioWordFile: card.audioWordFile,
            audioSentenceFile: card.audioSentenceFile,
            deckFolderName: deck.baseFolderName
        )
        savedStudyWordManager.save(capture: capture, in: modelContext)
    }
}

private struct FlashcardBrowserRow: View {
    let card: LearningCard
    let deck: CardDeck
    let isSaved: Bool
    let onSave: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(card.wordTarget)
                    .font(.headline)
                if !card.wordNative.isEmpty {
                    Text(card.wordNative)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !card.sentenceTarget.isEmpty {
                    Text(card.sentenceTarget)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button(action: onSave) {
                Image(systemName: isSaved ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(isSaved ? .yellow : .secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
            .disabled(isSaved)
            .accessibilityLabel(isSaved ? "Saved" : "Save for study")
        }
        .padding(.vertical, 4)
    }
}

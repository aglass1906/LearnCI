import SwiftUI
import SwiftData

struct FlashcardDeckBrowserView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(DataManager.self) private var dataManager
    @Query private var allProfiles: [UserProfile]

    @State private var selectedLanguage: Language = .spanish
    @State private var selectedLevel: Int?
    @State private var decks: [DeckMetadata] = []

    private var userProfile: UserProfile? {
        allProfiles.first { $0.userID == authManager.currentUser }
    }

    private var groupedDecks: [(level: Int, decks: [DeckMetadata])] {
        let filteredDecks = decks.filter { deck in
            guard let selectedLevel else { return true }
            let deckLevel = deck.proficiencyLevel ?? (deck.level.map { LevelManager.shared.normalize($0) } ?? 1)
            return deckLevel == selectedLevel
        }

        let grouped = Dictionary(grouping: filteredDecks) { deck in
            deck.proficiencyLevel ?? (deck.level.map { LevelManager.shared.normalize($0) } ?? 1)
        }

        return grouped
            .map { (level: $0.key, decks: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.level < $1.level }
    }

    var body: some View {
        List {
            Section {
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(Language.allCases) { language in
                        Text("\(language.flag) \(language.displayName)").tag(language)
                    }
                }
                .pickerStyle(.menu)

                Picker("Level", selection: $selectedLevel) {
                    Text("All").tag(Optional<Int>.none)
                    ForEach(1...6, id: \.self) { level in
                        Text(levelTitle(level)).tag(Optional(level))
                    }
                }
                .pickerStyle(.menu)
            }

            if groupedDecks.isEmpty {
                ContentUnavailableView(
                    "No Flashcard Decks",
                    systemImage: "rectangle.stack",
                    description: Text("Try another language or add decks that support flashcards.")
                )
            } else {
                ForEach(groupedDecks, id: \.level) { group in
                    Section(levelTitle(group.level)) {
                        ForEach(group.decks) { deck in
                            NavigationLink(destination: FlashcardDeckDetailView(deck: deck)) {
                                DeckBrowserRow(deck: deck)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Flashcards")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            selectedLanguage = userProfile?.currentLanguage ?? selectedLanguage
            refreshDecks()
        }
        .onChange(of: selectedLanguage) { _, _ in
            refreshDecks()
        }
    }

    private func refreshDecks() {
        decks = dataManager
            .discoverDecks(language: selectedLanguage)
            .filter { $0.supportedModes.contains(.flashcards) }
    }

    private func levelTitle(_ level: Int) -> String {
        LevelManager.shared.displayString(
            level: level,
            language: selectedLanguage.code,
            preferredScale: userProfile?.preferredScale ?? .simple
        )
    }
}

private struct DeckBrowserRow: View {
    let deck: DeckMetadata

    @Environment(DataManager.self) private var dataManager

    var body: some View {
        HStack(spacing: 12) {
            if let coverName = deck.coverImage,
               let uiImage = dataManager.loadImage(folderName: deck.folderName, filename: coverName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "rectangle.stack.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 54, height: 54)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(deck.title)
                    .font(.headline)
                    .lineLimit(1)

                if let description = deck.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct FlashcardDeckDetailView: View {
    let deck: DeckMetadata

    @Environment(AuthManager.self) private var authManager
    @Environment(DataManager.self) private var dataManager
    @Environment(SavedStudyWordManager.self) private var savedStudyWordManager
    @Environment(\.modelContext) private var modelContext
    @State private var loadedDeck: CardDeck?
    @State private var savedRevision = 0

    var body: some View {
        List {
            Section {
                DeckDetailHeader(deck: deck, loadedDeck: loadedDeck)
            }

            if let loadedDeck {
                Section("Cards") {
                    ForEach(loadedDeck.cards) { card in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(card.wordTarget)
                                    .font(.headline)
                                SaveCardForStudyButton(
                                    isSaved: isSaved(card, in: loadedDeck),
                                    action: { toggleSave(card, from: loadedDeck) }
                                )
                                CardAudioButton(
                                    filename: card.audioWordFile,
                                    text: card.wordTarget,
                                    language: loadedDeck.language,
                                    folderName: loadedDeck.baseFolderName ?? deck.folderName,
                                    accessibilityLabel: "Play word audio"
                                )
                                Spacer()
                                Text(card.wordNative)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            if !card.sentenceTarget.isEmpty {
                                HStack(alignment: .top, spacing: 6) {
                                    Text(card.sentenceTarget)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)

                                    CardAudioButton(
                                        filename: card.audioSentenceFile,
                                        text: card.sentenceTarget,
                                        language: loadedDeck.language,
                                        folderName: loadedDeck.baseFolderName ?? deck.folderName,
                                        accessibilityLabel: "Play sentence audio"
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else if dataManager.errorMessage != nil {
                Section {
                    Text(dataManager.errorMessage ?? "Unable to load deck.")
                        .foregroundColor(.secondary)
                }
            } else {
                Section {
                    ProgressView("Loading cards...")
                }
            }
        }
        .navigationTitle(deck.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            NavigationLink {
                GameView(
                    availableGameTypes: [.flashcards],
                    initialGameType: .flashcards,
                    initialDeck: deck
                )
            } label: {
                Label("Study Deck", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()
                    .background(.bar)
            }
            .buttonStyle(.plain)
            .disabled(loadedDeck == nil)
        }
        .onAppear {
            loadedDeck = dataManager.loadDeck(from: deck)
        }
    }

    private func isSaved(_ card: LearningCard, in loadedDeck: CardDeck) -> Bool {
        _ = savedRevision
        guard let userID = authManager.currentUser else { return false }
        return savedStudyWordManager.isSaved(
            word: card.wordTarget,
            userID: userID,
            languageCode: loadedDeck.language.code,
            sourceType: .flashcard,
            sourceId: "\(loadedDeck.id):\(card.id)",
            in: modelContext
        )
    }

    private func toggleSave(_ card: LearningCard, from loadedDeck: CardDeck) {
        guard let userID = authManager.currentUser else { return }
        let capture = SavedStudyWordCapture(
            userID: userID,
            word: card.wordTarget,
            translation: card.wordNative,
            lemma: nil,
            sentenceTarget: card.sentenceTarget,
            sentenceNative: card.sentenceNative,
            languageCode: loadedDeck.language.code,
            level: loadedDeck.level?.cerCode ?? loadedDeck.proficiencyLevel.map { String($0) },
            partOfSpeech: nil,
            verbTense: nil,
            grammarNotes: nil,
            sourceType: .flashcard,
            sourceId: "\(loadedDeck.id):\(card.id)",
            sourceTitle: loadedDeck.title,
            sourceUrl: nil,
            blockIndex: nil,
            mediaStart: nil,
            mediaEnd: nil,
            audioWordFile: card.audioWordFile,
            audioSentenceFile: card.audioSentenceFile,
            deckFolderName: loadedDeck.baseFolderName ?? deck.folderName
        )
        savedStudyWordManager.toggleSave(capture: capture, in: modelContext)
        savedRevision += 1
    }
}

private struct SaveCardForStudyButton: View {
    let isSaved: Bool
    let action: () -> Void

    var body: some View {
        SaveForStudyControl(isSaved: isSaved, style: .compactStar, action: action)
    }
}

private struct CardAudioButton: View {
    let filename: String?
    let text: String
    let language: Language
    let folderName: String?
    let accessibilityLabel: String

    @Environment(AudioManager.self) private var audioManager

    private var canPlay: Bool {
        filename != nil || !text.isEmpty
    }

    var body: some View {
        Button {
            audioManager.playAudio(
                named: filename ?? "",
                folderName: folderName,
                text: text,
                language: language,
                useFallback: true
            )
        } label: {
            Image(systemName: "play.circle.fill")
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .disabled(!canPlay)
        .opacity(canPlay ? 1 : 0.35)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct DeckDetailHeader: View {
    let deck: DeckMetadata
    let loadedDeck: CardDeck?

    @Environment(DataManager.self) private var dataManager

    var body: some View {
        HStack(spacing: 14) {
            if let coverName = deck.coverImage,
               let uiImage = dataManager.loadImage(folderName: deck.folderName, filename: coverName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 74, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "menucard.fill")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
                    .frame(width: 74, height: 74)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(deck.title)
                    .font(.headline)

                if let description = deck.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("\(loadedDeck?.cards.count ?? 0) cards")
                    .font(.caption.bold())
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack {
        FlashcardDeckBrowserView()
            .environment(AuthManager())
            .environment(DataManager())
    }
}

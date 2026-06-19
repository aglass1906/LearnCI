import SwiftUI
import SwiftData

struct SavedStudyWordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(DataManager.self) private var dataManager
    @Environment(AudioManager.self) private var audioManager
    @Query(sort: \SavedStudyWord.createdAt, order: .reverse) private var savedWords: [SavedStudyWord]
    @Query(sort: \MarkedStudyWord.createdAt, order: .reverse) private var legacyMarkedWords: [MarkedStudyWord]

    @State private var sourceFilter: SavedStudyWordSourceType?
    @State private var searchText = ""
    @State private var reviewDeck: DeckMetadata?

    private var currentUserID: String? {
        authManager.currentUser
    }

    private var userSavedWords: [SavedStudyWord] {
        guard let currentUserID else { return [] }
        return savedWords.filter { $0.userID == currentUserID }
    }

    private var filteredWords: [SavedStudyWord] {
        userSavedWords.filter { word in
            if let sourceFilter, word.sourceType != sourceFilter { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return word.word.localizedCaseInsensitiveContains(query) ||
                (word.translation?.localizedCaseInsensitiveContains(query) == true) ||
                (word.sentenceTarget?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    var body: some View {
        List {
            if userSavedWords.isEmpty {
                ContentUnavailableView(
                    "No Saved Study Words",
                    systemImage: "star",
                    description: Text("Save words from flashcards, stories, YouTube Study mode, and podcast Study mode.")
                )
                .listRowBackground(Color.clear)
            } else {
                reviewSection
                filtersSection
                wordsSection
            }
        }
        .navigationTitle("Saved Study Words")
        .searchable(text: $searchText, prompt: "Search words")
        .onAppear(perform: migrateLegacyMarkedWordsIfNeeded)
        .navigationDestination(item: $reviewDeck) { deck in
            GameView(
                availableGameTypes: [.flashcards],
                initialGameType: .flashcards,
                initialDeck: deck
            )
        }
    }

    private var reviewSection: some View {
        Section {
            Button {
                startReview(with: filteredWords)
            } label: {
                Label("Review \(filteredWords.count) Word\(filteredWords.count == 1 ? "" : "s")", systemImage: "play.fill")
                    .font(.headline)
            }
            .disabled(filteredWords.isEmpty)
        }
    }

    private var filtersSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(title: "All", isSelected: sourceFilter == nil) {
                        sourceFilter = nil
                    }
                    ForEach(SavedStudyWordSourceType.allCases.filter { $0 != .other }) { type in
                        filterChip(title: type.label, isSelected: sourceFilter == type) {
                            sourceFilter = type
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var wordsSection: some View {
        Section {
            ForEach(filteredWords) { word in
                NavigationLink {
                    SavedStudyWordDetailView(word: word)
                } label: {
                    SavedStudyWordRow(word: word)
                }
            }
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.secondary.opacity(0.14))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func startReview(with words: [SavedStudyWord]) {
        let reviewWords = words.prefix(100)
        let cards = reviewWords.map { word in
            LearningCard(
                id: word.id.uuidString,
                wordTarget: word.word,
                wordNative: word.translation ?? "",
                sentenceTarget: word.sentenceTarget ?? "",
                sentenceNative: word.sentenceNative ?? "",
                audioWordFile: word.audioWordFile,
                audioSentenceFile: word.audioSentenceFile,
                mediaFile: nil,
                type: .standard,
                order: 0,
                usage: nil,
                tags: [word.sourceType.label, word.partOfSpeech, word.level].compactMap { $0 },
                isMastered: nil
            )
        }
        guard !cards.isEmpty else { return }

        let language = Language(rawValue: cards.first.flatMap { card in
            words.first(where: { $0.id.uuidString == card.id })?.languageCode
        } ?? "") ?? .spanish
        let deck = CardDeck(
            id: "saved_study_words_\(UUID().uuidString)",
            language: language,
            level: .beginner,
            title: "Saved Study Words",
            description: "\(cards.count) saved words",
            cards: cards,
            supportedModes: [.flashcards],
            baseFolderName: nil
        )
        dataManager.registerVirtualDeck(deck)
        reviewDeck = DeckMetadata(
            id: deck.id,
            title: deck.title,
            description: deck.description,
            language: deck.language,
            level: deck.level,
            proficiencyLevel: nil,
            folderName: "Virtual",
            filename: "\(deck.id).json",
            supportedModes: [.flashcards],
            gameConfiguration: nil,
            coverImage: nil
        )
    }

    private func migrateLegacyMarkedWordsIfNeeded() {
        guard let currentUserID else { return }
        let existingKeys = Set(userSavedWords.map {
            "\($0.normalizedWord)|\($0.languageCode)|\($0.sourceTypeRaw)|\($0.sourceId)"
        })
        for legacy in legacyMarkedWords where legacy.userID == currentUserID {
            let sourceType = SavedStudyWordSourceType(rawValue: legacy.resourceType) ?? .other
            let languageCode = Language(rawValue: legacy.resourceType)?.rawValue ?? "es"
            let key = "\(SavedStudyWord.normalize(legacy.word))|\(languageCode)|\(sourceType.rawValue)|\(legacy.resourceId)"
            guard !existingKeys.contains(key) else { continue }

            let capture = SavedStudyWordCapture(
                userID: legacy.userID,
                word: legacy.word,
                translation: legacy.translation,
                lemma: legacy.lemma,
                sentenceTarget: legacy.contextSnippet,
                sentenceNative: nil,
                languageCode: languageCode,
                level: nil,
                partOfSpeech: nil,
                verbTense: nil,
                grammarNotes: nil,
                sourceType: sourceType,
                sourceId: legacy.resourceId,
                sourceTitle: legacy.resourceId,
                sourceUrl: legacy.consumptionUrl,
                blockIndex: legacy.blockIndex,
                mediaStart: legacy.mediaTime,
                mediaEnd: nil,
                audioWordFile: nil,
                audioSentenceFile: nil,
                deckFolderName: nil
            )
            modelContext.insert(SavedStudyWord(capture: capture, createdAt: legacy.createdAt))
        }
        try? modelContext.save()
    }
}

private struct SavedStudyWordRow: View {
    let word: SavedStudyWord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(word.word)
                    .font(.headline)
                Spacer()
                Label(word.sourceType.label, systemImage: word.sourceType.icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let translation = word.translation, !translation.isEmpty {
                Text(translation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let sentence = word.sentenceTarget, !sentence.isEmpty {
                Text(sentence)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SavedStudyWordDetailView: View {
    @Environment(AudioManager.self) private var audioManager
    let word: SavedStudyWord

    private var language: Language {
        Language(rawValue: word.languageCode) ?? .spanish
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(word.word)
                            .font(.system(size: 30, weight: .bold, design: .serif))

                        Button(action: playWordAudio) {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Play word audio")
                    }

                    if let translation = word.translation, !translation.isEmpty {
                        Text(translation)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Context") {
                if let sentence = word.sentenceTarget, !sentence.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Text(sentence)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button(action: { playSentenceAudio(sentence) }) {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Play sentence audio")
                    }
                }
                if let native = word.sentenceNative, !native.isEmpty {
                    Text(native)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Learning Metrics") {
                metricRow("Level", word.level)
                metricRow("Part of speech", word.partOfSpeech)
                metricRow("Lemma", word.lemma)
                metricRow("Verb tense", word.verbTense)
                metricRow("Notes", word.grammarNotes)
            }

            Section("Source") {
                Label(word.sourceTitle, systemImage: word.sourceType.icon)
                if let sourceUrl = word.sourceUrl, let url = URL(string: sourceUrl) {
                    Link("Open Source", destination: url)
                }
                if let mediaStart = word.mediaStart {
                    Text("Saved at \(formatTime(mediaStart))")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Study Word")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func playWordAudio() {
        if let audioWordFile = word.audioWordFile,
           audioManager.audioExists(named: audioWordFile, folderName: word.deckFolderName) {
            audioManager.playAudio(
                named: audioWordFile,
                folderName: word.deckFolderName,
                text: word.word,
                language: language,
                useFallback: true
            )
        } else {
            audioManager.speak(text: word.word, language: language, gender: nil, rate: 0.5)
        }
    }

    private func playSentenceAudio(_ sentence: String) {
        if let audioSentenceFile = word.audioSentenceFile,
           audioManager.audioExists(named: audioSentenceFile, folderName: word.deckFolderName) {
            audioManager.playAudio(
                named: audioSentenceFile,
                folderName: word.deckFolderName,
                text: sentence,
                language: language,
                useFallback: true
            )
        } else {
            audioManager.speak(text: sentence, language: language, gender: nil, rate: 0.5)
        }
    }

    @ViewBuilder
    private func metricRow(_ title: String, _ value: String?) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            LabeledContent(title, value: value)
        }
    }

    private func formatTime(_ time: Double) -> String {
        let total = Int(time.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

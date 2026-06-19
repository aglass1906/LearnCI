import SwiftUI
import SwiftData
import Supabase
import PostgREST

struct SavedStudyWordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(DataManager.self) private var dataManager
    @Environment(AudioManager.self) private var audioManager
    @Environment(SavedStudyWordManager.self) private var savedStudyWordManager
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
            .onDelete(perform: deleteSavedWords)
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

    private func deleteSavedWords(at offsets: IndexSet) {
        let wordsToDelete = offsets.compactMap { filteredWords[safeStudyWords: $0] }
        for word in wordsToDelete {
            deleteSavedWord(word)
        }
    }

    private func deleteSavedWord(_ word: SavedStudyWord) {
        let wordID = word.id
        savedStudyWordManager.delete(word, in: modelContext)
        Task {
            try? await authManager.supabase.from("saved_study_words")
                .delete()
                .eq("id", value: wordID)
                .execute()
        }
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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Environment(AudioManager.self) private var audioManager
    @Environment(SavedStudyWordManager.self) private var savedStudyWordManager
    @Query private var stories: [Story]
    let word: SavedStudyWord

    @State private var activeClipEnd: Double?
    @State private var youtubeClip: SavedStudyWordYouTubeClip?
    @State private var showDeleteConfirmation = false

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

                        Button(action: { playContextAudio(sentence) }) {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(sourceClipBounds == nil ? "Play sentence audio" : "Play source clip")
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
                    Text(sourceClipLabel(start: mediaStart, end: word.mediaEnd))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Study Word")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete saved word")
            }
        }
        .confirmationDialog(
            "Delete Saved Word?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSavedWord()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the word from Saved Study Words on this device and from sync.")
        }
        .sheet(item: $youtubeClip) { clip in
            SavedStudyWordYouTubeClipPlayer(clip: clip)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: audioManager.streamCurrentTime) { _, currentTime in
            guard let activeClipEnd, currentTime >= activeClipEnd else { return }
            audioManager.pauseStream()
            self.activeClipEnd = nil
        }
        .onDisappear {
            activeClipEnd = nil
        }
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

    private func playContextAudio(_ sentence: String) {
        if playSourceClipIfAvailable() {
            return
        }

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

    private func playSourceClipIfAvailable() -> Bool {
        guard let bounds = sourceClipBounds else { return false }

        switch word.sourceType {
        case .podcast:
            guard let sourceUrl = word.sourceUrl,
                  let url = URL(string: sourceUrl) else { return false }
            playStreamClip(url: url, bounds: bounds)
            return true
        case .story:
            guard let playback = storyClipPlayback(for: bounds) else { return false }
            playStreamClip(url: playback.url, bounds: playback.bounds)
            return true
        case .youtube:
            guard let videoID = youtubeVideoID() else { return false }
            youtubeClip = SavedStudyWordYouTubeClip(
                videoID: videoID,
                videoURL: nil,
                title: word.sourceTitle,
                start: bounds.start,
                end: bounds.end
            )
            return true
        case .flashcard, .other:
            return false
        }
    }

    private func playStreamClip(url: URL, bounds: (start: Double, end: Double)) {
        activeClipEnd = bounds.end
        audioManager.streamAudio(url: url, startAt: bounds.start)
        audioManager.playStream()
        audioManager.updateStreamNowPlayingInfo(title: word.sourceTitle, artist: word.sourceType.label)
    }

    private var sourceClipBounds: (start: Double, end: Double)? {
        guard let mediaStart = word.mediaStart else { return nil }
        let rawEnd: Double
        if let mediaEnd = word.mediaEnd, mediaEnd > mediaStart {
            rawEnd = mediaEnd
        } else {
            rawEnd = mediaStart + 6
        }

        let start = max(0, mediaStart - 0.35)
        let end = max(start + 1, rawEnd + 0.6)
        return (start, end)
    }

    private func storyClipPlayback(for bounds: (start: Double, end: Double)) -> (url: URL, bounds: (start: Double, end: Double))? {
        guard let storyID = UUID(uuidString: word.sourceId),
              let story = stories.first(where: { $0.id == storyID }) else {
            if let sourceUrl = word.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sourceUrl.isEmpty,
               let url = StoryReaderDataAdapter.remoteAudioURL(for: sourceUrl) {
                return (url, bounds)
            }
            return nil
        }

        let adapter = StoryReaderDataAdapter(story: story)
        if let clip = bestStoryAudioClip(adapter: adapter),
           let url = storyAudioURL(for: clip, adapter: adapter) {
            return (url, adjustedStoryBounds(bounds, for: clip))
        }

        if let audioFilename = story.audioFilename?.trimmingCharacters(in: .whitespacesAndNewlines),
           !audioFilename.isEmpty {
            let localURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(audioFilename)
            if FileManager.default.fileExists(atPath: localURL.path) {
                return (localURL, bounds)
            }
        }

        if let remoteAudioPath = story.remoteAudioPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remoteAudioPath.isEmpty {
            return StoryReaderDataAdapter.remoteAudioURL(for: remoteAudioPath).map { ($0, bounds) }
        }

        return nil
    }

    private func storyAudioURL(for clip: StorySceneAudioClip, adapter: StoryReaderDataAdapter) -> URL? {
        adapter.cachedAudioURL(for: clip) ?? StoryReaderDataAdapter.remoteAudioURL(for: clip.urlString)
    }

    private func bestStoryAudioClip(adapter: StoryReaderDataAdapter) -> StorySceneAudioClip? {
        let clips = storyAudioClipCandidates(adapter: adapter)
        guard !clips.isEmpty else { return nil }

        if let sourceUrl = word.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceUrl.isEmpty,
           let exact = clips.first(where: { $0.urlString == sourceUrl }) {
            return exact
        }

        let context = word.sentenceTarget?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !context.isEmpty,
           let textMatch = clips.first(where: { clip in
               clip.caption.localizedCaseInsensitiveContains(context) ||
               context.localizedCaseInsensitiveContains(clip.caption)
           }) {
            return textMatch
        }

        let savedWord = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
        if !savedWord.isEmpty,
           let wordMatch = clips.first(where: { $0.caption.localizedCaseInsensitiveContains(savedWord) }) {
            return wordMatch
        }

        guard let mediaStart = word.mediaStart else { return clips.first }
        return clips.first(where: { clip in
            let duration = clip.duration ?? 0
            guard duration > 0 else { return false }
            return mediaStart >= clip.startOffset && mediaStart <= clip.startOffset + duration
        }) ?? clips.first(where: { clip in
            let duration = clip.duration ?? 0
            return duration > 0 && mediaStart <= duration
        }) ?? clips.first
    }

    private func storyAudioClipCandidates(adapter: StoryReaderDataAdapter) -> [StorySceneAudioClip] {
        var clips = adapter.allAudioClips()
        for chapterIndex in adapter.story.chapters.indices {
            clips.append(contentsOf: adapter.audioClips(forChapter: chapterIndex))
        }

        var seen = Set<String>()
        return clips.filter { clip in
            let key = "\(clip.id)|\(clip.urlString)|\(clip.startOffset)"
            return seen.insert(key).inserted
        }
    }

    private func adjustedStoryBounds(
        _ bounds: (start: Double, end: Double),
        for clip: StorySceneAudioClip
    ) -> (start: Double, end: Double) {
        let duration = clip.duration ?? 0
        let paddedDuration = duration + 2

        if duration > 0,
           bounds.start >= clip.startOffset,
           bounds.start <= clip.startOffset + paddedDuration {
            let start = max(0, bounds.start - clip.startOffset)
            let end = max(start + 1, min(duration, bounds.end - clip.startOffset))
            return (start, end)
        }

        if duration > 0, bounds.start <= paddedDuration {
            let start = max(0, bounds.start)
            let end = max(start + 1, min(duration, bounds.end))
            return (start, end)
        }

        let fallbackEnd = duration > 0 ? min(duration, 6) : 6
        return (0, max(1, fallbackEnd))
    }

    private func youtubeVideoID() -> String? {
        let sourceId = word.sourceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sourceId.isEmpty {
            return sourceId
        }

        guard let sourceUrl = word.sourceUrl,
              let url = URL(string: sourceUrl) else { return nil }

        if url.host?.contains("youtu.be") == true {
            return url.pathComponents.dropFirst().first
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let id = components.queryItems?.first(where: { $0.name == "v" })?.value,
           !id.isEmpty {
            return id
        }

        return nil
    }

    private func sourceClipLabel(start: Double, end: Double?) -> String {
        if let end, end > start {
            return "Clip \(formatTime(start))-\(formatTime(end))"
        }
        return "Saved at \(formatTime(start))"
    }

    private func deleteSavedWord() {
        let wordID = word.id
        activeClipEnd = nil
        audioManager.pauseStream()
        savedStudyWordManager.delete(word, in: modelContext)
        dismiss()

        Task {
            try? await authManager.supabase.from("saved_study_words")
                .delete()
                .eq("id", value: wordID)
                .execute()
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

private extension Array {
    subscript(safeStudyWords index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct SavedStudyWordYouTubeClip: Identifiable {
    let id = UUID()
    let videoID: String
    let videoURL: String?
    let title: String
    let start: Double
    let end: Double
}

private struct SavedStudyWordYouTubeClipPlayer: View {
    let clip: SavedStudyWordYouTubeClip

    @Environment(\.dismiss) private var dismiss
    @State private var watchDuration: TimeInterval = 0
    @State private var seekAndPlayRequest: Double?
    @State private var pauseRequest: Bool?
    @State private var didStartPlayback = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                YouTubePlayerView(
                    videoID: clip.videoID,
                    videoURL: clip.videoURL,
                    watchDuration: $watchDuration,
                    pauseRequest: $pauseRequest,
                    seekAndPlayRequest: $seekAndPlayRequest,
                    initialPlaybackTime: clip.start,
                    shouldResumePlayback: true,
                    onPlaybackSnapshot: handleSnapshot
                )
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    Text(clip.title)
                        .font(.headline)
                    Text("\(formatTime(clip.start))-\(formatTime(clip.end))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
            .padding()
            .navigationTitle("Source Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        pauseRequest = true
                        dismiss()
                    }
                }
            }
            .onAppear {
                seekAndPlayRequest = clip.start
            }
            .onDisappear {
                pauseRequest = true
            }
        }
    }

    private func handleSnapshot(_ snapshot: YouTubePlayerPlaybackSnapshot) {
        if !didStartPlayback, snapshot.duration > 0 {
            didStartPlayback = true
            seekAndPlayRequest = clip.start
        }

        guard snapshot.isPlaying, snapshot.currentTime >= clip.end else { return }
        pauseRequest = true
    }

    private func formatTime(_ time: Double) -> String {
        let total = Int(time.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

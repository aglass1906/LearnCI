import SwiftUI
import SwiftData
import Combine

private enum PodcastPlaybackMode: String, CaseIterable, Identifiable {
    case watch = "Watch"
    case study = "Study"

    var id: String { rawValue }
}

struct PodcastPlayerView: View {
    let episode: PodcastEpisode

    @Environment(AudioManager.self) private var audioManager
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var playbackMode: PodcastPlaybackMode = .watch
    @State private var isPlaying = false
    @State private var sliderValue: Double = 0
    @State private var duration: Double = 0
    @State private var playbackRate: Float = 1.0
    @State private var startTime: Date?
    @State private var artworkImage: UIImage?
    @State private var toastMessage: String?
    @State private var playbackError: String?

    @State private var studyLoadState: YouTubeStudyLoadState = .idle
    @State private var studyWords: [WordTiming] = []
    @State private var studyCues: [YouTubeCaptionCue] = []
    @State private var studyCachedBlocks: [StudyBlock] = []
    @State private var studyCachedCues: [YouTubeCaptionCue] = []
    @State private var studyTranslations: [String: String] = [:]
    @State private var studyTranslationState: YouTubeStudyLoadState = .idle
    @State private var studyCoverageNote: String?
    @State private var studyTranscriptSource: PodcastTranscriptSource?
    @State private var studySessionViewModel: StudySessionViewModel?
    @State private var studyFocusWindowSize: StudyFocusWindowSize = .sentence
    @State private var studyPaneDisplayMode: StudyPaneDisplayMode = .studyBlock
    @State private var studyMediaPlayer: AVPlayerStudyMediaPlayer?
    @State private var didBootstrapStudyMode = false
    @State private var whisperOffer: PodcastTranscriptWhisperOffer?
    @State private var isGeneratingWhisper = false

    @State private var showSessionSetup = false
    @State private var showNotes = false
    @State private var lookupSelection: WordSelection?
    @State private var lookupTranslation: String?
    @State private var lookupPartOfSpeech: String?
    @State private var isLookingUpWord = false

    private let transcriptService = PodcastTranscriptService()
    private let openAIService = OpenAIService()
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        modePicker

                        if playbackMode == .study {
                            studyContent
                        } else {
                            watchContent
                        }

                        Color.clear.frame(height: 160)
                    }
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                }

                AudioPlayerBar(
                    isPlaying: $isPlaying,
                    sliderValue: $sliderValue,
                    duration: duration,
                    playbackRate: $playbackRate,
                    ambientVolume: .constant(0),
                    isAmbientPlaying: false,
                    isBuffering: audioManager.streamIsBuffering,
                    bufferingLabel: "Loading episode…",
                    onPlayPause: togglePlay,
                    onSkipForward: skipForward,
                    onSkipBackward: skipBackward,
                    onSeek: seekTo,
                    onChangeRate: setRate
                )
            }

            if let message = toastMessage {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .shadow(radius: 4)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                FavoriteButton(
                    consumptionUrl: episode.favoriteConsumptionUrl,
                    type: .podcastEpisode,
                    title: episode.title,
                    author: episode.show?.title,
                    subtitle: episode.favoriteSubtitle,
                    imageUrl: episode.show?.artworkUrl,
                    sourceResourceId: episode.id.uuidString
                )
            }
        }
        .onAppear {
            startTime = Date()
            if studyMediaPlayer == nil {
                studyMediaPlayer = AVPlayerStudyMediaPlayer(audioManager: audioManager)
            }
            setupStream()
        }
        .onDisappear {
            // Avoid tearing down playback when the app backgrounds (lock screen, etc.).
            if scenePhase != .background {
                cleanupSession()
            }
        }
        .onChange(of: playbackMode) { _, newMode in
            if newMode == .study {
                Task { await bootstrapStudyModeIfNeeded() }
            } else {
                resetStudyBootstrapState()
            }
        }
        .onReceive(timer) { _ in
            syncPlaybackSnapshot()
        }
        .sheet(isPresented: $showSessionSetup) {
            if let session = studySessionViewModel {
                StudySessionSetupSheet(
                    blocks: session.blocks,
                    currentBlockIndex: session.currentBlockIndex
                ) { definition in
                    session.startSession(definition)
                    saveSessionRecord(definition: definition)
                }
            }
        }
        .sheet(isPresented: $showNotes) {
            if let session = studySessionViewModel, let block = session.currentBlock {
                StudyNotesSheet(
                    resource: session.resource,
                    block: block,
                    currentMediaTime: session.mediaPlayer.currentTime,
                    userID: authManager.currentUser ?? "",
                    onSeek: seekTo
                )
            }
        }
        .sheet(item: $lookupSelection) { selection in
            WordLookupSheet(
                word: selection.word,
                languageLabel: episode.show?.language.displayName ?? "Spanish",
                translation: lookupTranslation,
                partOfSpeech: lookupPartOfSpeech,
                isLoading: isLookingUpWord,
                seekTime: studySessionViewModel?.currentBlock?.mediaStart,
                onSeek: seekTo,
                onMarkForStudy: {
                    markWordForStudy(word: selection.word)
                }
            )
        }
    }

    // MARK: - Mode UI

    private var modePicker: some View {
        Picker("Mode", selection: $playbackMode) {
            ForEach(PodcastPlaybackMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var watchContent: some View {
        VStack(spacing: 20) {
            artworkView

            VStack(spacing: 6) {
                Text(episode.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                if let showTitle = episode.show?.title {
                    Text(showTitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if !episode.episodeDescription.isEmpty {
                Text(episode.episodeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(6)
            }

            if let message = currentPlaybackError {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var currentPlaybackError: String? {
        playbackError ?? audioManager.streamLoadError
    }

    @ViewBuilder
    private var studyContent: some View {
        if let offer = whisperOffer {
            whisperOfferView(offer)
        } else {
            switch studyLoadState {
            case .idle, .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text(isGeneratingWhisper
                         ? "Generating transcript with AI (Whisper)…"
                         : "Loading episode transcript…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            case .failed(let message):
                ContentUnavailableView(
                    "Study Mode Unavailable",
                    systemImage: "waveform",
                    description: Text(message)
                )
            case .loaded:
                if let session = studySessionViewModel {
                    VStack(alignment: .leading, spacing: 12) {
                        if let note = studyCoverageNote {
                            Label(note, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        studyPaneModePicker

                        if studyPaneDisplayMode == .studyBlock {
                            StudySessionShell(
                                session: session,
                                userID: authManager.currentUser,
                                focusWindowSize: $studyFocusWindowSize,
                                translationState: studyTranslationState,
                                showsTranscript: false,
                                transcript: { EmptyView() },
                                onWordTap: { word in
                                    lookupWordInFocus(word)
                                },
                                onDefineSession: { showSessionSetup = true },
                                onNotes: { showNotes = true },
                                onFocusWindowSizeChange: applyFocusWindowSize
                            )
                        } else {
                            podcastTranscriptModeView(session: session)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Study Mode Unavailable",
                        systemImage: "waveform",
                        description: Text("No transcript blocks were produced for this episode.")
                    )
                }
            }
        }
    }

    private var studyPaneModePicker: some View {
        Picker("Study view", selection: $studyPaneDisplayMode) {
            ForEach(StudyPaneDisplayMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private func podcastTranscriptModeView(session: StudySessionViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Transcript", systemImage: "list.bullet.rectangle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                studyFocusWindowPicker
            }

            PodcastStudyTranscriptPanel(
                blocks: session.blocks,
                activeBlockIndex: session.currentBlockIndex,
                expanded: true,
                onSeek: { time in
                    session.goToBlock(
                        at: blockIndex(for: time, in: session.blocks) ?? session.currentBlockIndex,
                        autoPlay: false
                    )
                    seekTo(time)
                }
            )

            StudyTransportBar(
                canGoPrevious: session.canGoPrevious,
                canGoNext: session.canGoNext,
                isLooping: session.isLooping,
                isBlockPlaying: session.isBlockPlaying,
                isBlockPlaybackLocked: session.playbackController.isBlockPlaybackActive,
                onPrevious: { session.goToPreviousBlock() },
                onPlayStop: { session.togglePlayStop() },
                onToggleLoop: { session.toggleLoopCurrentBlock() },
                onNext: { session.goToNextBlock() }
            )

            HStack(spacing: 12) {
                Button(action: { showSessionSetup = true }) {
                    Label("Define session", systemImage: "clock.badge.checkmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)

                Button(action: { showNotes = true }) {
                    Label("Notes", systemImage: "note.text")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            if case .loading = studyTranslationState {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading translations…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var studyFocusWindowPicker: some View {
        HStack(spacing: 6) {
            ForEach(StudyFocusWindowSize.allCases) { size in
                Button {
                    applyFocusWindowSize(size)
                } label: {
                    Text(size.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(studyFocusWindowSize == size ? .white : .primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(studyFocusWindowSize == size ? Color.blue : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(Capsule())
    }

    private func whisperOfferView(_ offer: PodcastTranscriptWhisperOffer) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ContentUnavailableView {
                Label(offer.title, systemImage: "waveform.badge.mic")
            } description: {
                Text(offer.message)
            } actions: {
                if OpenAIAPIKeyStorage.isConfigured {
                    Button {
                        Task { await startWhisperTranscription() }
                    } label: {
                        Label("Generate Transcript", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Label("OpenAI API key required", systemImage: "key.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                Button("Not Now") {
                    playbackMode = .watch
                }
                .buttonStyle(.bordered)
            }

            if !OpenAIAPIKeyStorage.isConfigured {
                Text("Add your OpenAI API key in Profile → AI Settings before generating a transcript.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if episode.hasFeedTranscript {
                Label("A feed transcript link exists but could not be used.", systemImage: "link.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var artworkView: some View {
        ZStack {
            AsyncImage(url: URL(string: episode.show?.artworkUrl ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                        .onAppear {
                            let renderer = ImageRenderer(
                                content: image.resizable().scaledToFill().frame(width: 300, height: 300)
                            )
                            artworkImage = renderer.uiImage
                        }
                default:
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.secondary.opacity(0.2))
                        .overlay(
                            Image(systemName: "headphones")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                        )
                }
            }
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 8)

            if audioManager.streamIsBuffering {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.black.opacity(0.45))
                    .frame(width: 220, height: 220)
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading episode…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: - Study bootstrap

    private func resetStudyBootstrapState() {
        didBootstrapStudyMode = false
        whisperOffer = nil
        isGeneratingWhisper = false
        studyLoadState = .idle
        studyPaneDisplayMode = .studyBlock
    }

    @MainActor
    private func bootstrapStudyModeIfNeeded(force: Bool = false) async {
        guard force || !didBootstrapStudyMode else { return }
        didBootstrapStudyMode = true
        whisperOffer = nil
        isGeneratingWhisper = false

        if hydrateStudyModeFromCacheIfAvailable() {
            return
        }

        studyLoadState = .loading
        let language = episode.show?.language ?? .spanish

        do {
            switch try await transcriptService.loadAvailableTranscript(
                episode: episode,
                language: language,
                modelContext: modelContext
            ) {
            case .ready(let result):
                applyTranscriptResult(result)
                studyLoadState = .loaded
                syncStudySessionViewModel()
                await ensureTranslationsForNearbyBlocks()
            case .whisperOffer(let offer):
                studyLoadState = .idle
                whisperOffer = offer
            }
        } catch {
            if hydrateStudyModeFromCacheIfAvailable() {
                Logger.warning(
                    "Recovered podcast study mode from cache after failure for episode \(episode.id)",
                    category: .general
                )
            } else {
                studyLoadState = .failed(message: userFacingTranscriptError(error))
            }
        }
    }

    @MainActor
    private func startWhisperTranscription() async {
        guard OpenAIAPIKeyStorage.isConfigured else {
            studyLoadState = .idle
            whisperOffer = PodcastTranscriptWhisperOffer(
                title: "Generate transcript with AI?",
                message: "An OpenAI API key is required in Profile → AI Settings before Study mode can transcribe this episode with Whisper.",
                feedAttempted: episode.hasFeedTranscript
            )
            return
        }

        whisperOffer = nil
        isGeneratingWhisper = true
        studyLoadState = .loading

        let language = episode.show?.language ?? .spanish

        do {
            let result = try await transcriptService.generateWhisperTranscript(
                episode: episode,
                language: language,
                modelContext: modelContext
            )
            applyTranscriptResult(result)
            studyLoadState = .loaded
            syncStudySessionViewModel()
            await ensureTranslationsForNearbyBlocks()
        } catch {
            studyLoadState = .failed(message: userFacingTranscriptError(error))
        }

        isGeneratingWhisper = false
    }

    private func userFacingTranscriptError(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        if let podcastError = error as? PodcastTranscriptError, let description = podcastError.errorDescription {
            return description
        }
        if let feedError = error as? PodcastFeedTranscriptError, let description = feedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    @MainActor
    private func applyTranscriptResult(_ result: PodcastTranscriptResult) {
        if let cachedBlocks = result.cachedBlocks {
            studyCachedBlocks = cachedBlocks
            studyWords = result.cachedWords ?? []
            studyCues = result.cachedCues ?? []
            studyCachedCues = result.cachedCues ?? []
        } else {
            studyWords = result.words
            studyCues = result.cues
            studyCachedBlocks = []
            studyCachedCues = []
        }

        studyTranscriptSource = result.source
        switch result.source {
        case .feed:
            studyCoverageNote = "Using published transcript from the podcast feed."
        case .whisper:
            if let covers = result.coversDurationSeconds {
                let minutes = Int(covers / 60)
                studyCoverageNote = "Generated with AI (Whisper). Covers the first \(minutes) minutes."
            } else {
                studyCoverageNote = "Generated with AI (Whisper)."
            }
        case .cache:
            studyCoverageNote = nil
        }
    }

    @MainActor
    @discardableResult
    private func hydrateStudyModeFromCacheIfAvailable() -> Bool {
        let languageCode = (episode.show?.language ?? .spanish).rawValue
        let cacheKey = MediaTranscriptCache.makeCacheKey(
            consumptionUrl: episode.audioUrl,
            languageCode: languageCode
        )
        let descriptor = FetchDescriptor<MediaTranscriptCache>(
            predicate: #Predicate { $0.cacheKey == cacheKey }
        )
        guard let cached = try? modelContext.fetch(descriptor).first,
              !cached.blocks.isEmpty else {
            return false
        }

        studyCachedBlocks = cached.blocks
        studyWords = cached.words
        studyCues = cached.cues
        studyCachedCues = cached.cues
        studyTranscriptSource = .cache
        studyLoadState = .loaded
        syncStudySessionViewModel()
        return true
    }

    private func syncStudySessionViewModel() {
        guard let studyMediaPlayer else { return }
        let blocks = makeFocusStudyBlocks()
        guard !blocks.isEmpty else {
            studySessionViewModel = nil
            return
        }

        if !activeStudyCues.isEmpty {
            let source = PodcastStudyBlockSource(
                episode: episode,
                cues: activeStudyCues,
                languageCode: episode.show?.language.rawValue,
                focusWindowSize: studyFocusWindowSize,
                translationForCue: translationForCue,
                mediaPlayer: studyMediaPlayer
            )
            studySessionViewModel = StudySessionViewModel(source: source)
        } else if !studyWords.isEmpty {
            let source = PodcastStudyBlockSource(
                episode: episode,
                words: studyWords,
                languageCode: episode.show?.language.rawValue,
                focusWindowSize: studyFocusWindowSize,
                translationsBySentenceRange: studyTranslations,
                mediaPlayer: studyMediaPlayer
            )
            studySessionViewModel = StudySessionViewModel(source: source)
        } else if !studyCachedBlocks.isEmpty {
            let source = PodcastStudyBlockSource(
                episode: episode,
                cachedBlocks: applyTranslations(to: studyCachedBlocks),
                mediaPlayer: studyMediaPlayer
            )
            studySessionViewModel = StudySessionViewModel(source: source)
        } else {
            studySessionViewModel = nil
            return
        }

        studySessionViewModel?.syncCurrentBlockToPlaybackTime()
    }

    private func refreshStudySessionBlocks() {
        guard let session = studySessionViewModel else {
            syncStudySessionViewModel()
            return
        }
        session.rebuildBlocks(makeFocusStudyBlocks(), anchorTime: session.mediaPlayer.currentTime)
    }

    private func applyFocusWindowSize(_ size: StudyFocusWindowSize) {
        studyFocusWindowSize = size
        refreshStudySessionBlocks()
    }

    private var activeStudyCues: [YouTubeCaptionCue] {
        if !studyCues.isEmpty { return studyCues }
        return studyCachedCues
    }

    private func makeFocusStudyBlocks() -> [StudyBlock] {
        if !activeStudyCues.isEmpty {
            let blocks = CaptionTranscriptProvider(
                cues: activeStudyCues,
                translationForCue: translationForCue,
                focusWindowSize: studyFocusWindowSize
            ).makeBlocks()
            return applyTranslations(to: blocks)
        }
        if !studyWords.isEmpty {
            let blocks = WhisperTranscriptProvider(
                words: studyWords,
                translationForSentenceRange: { start, end in
                    studyTranslations["\(start)-\(end)"]
                },
                focusWindowSize: studyFocusWindowSize
            ).makeBlocks()
            return applyTranslations(to: blocks)
        }
        if !studyCachedBlocks.isEmpty {
            return applyTranslations(to: studyCachedBlocks)
        }
        return []
    }

    private func translationForCue(_ cue: YouTubeCaptionCue) -> String? {
        for (key, value) in studyTranslations {
            let parts = key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            if cue.index >= parts[0], cue.index <= parts[1] {
                return value
            }
        }
        return nil
    }

    private func applyTranslations(to blocks: [StudyBlock]) -> [StudyBlock] {
        blocks.map { block in
            guard block.nativeText == nil,
                  let cueStart = block.cueStartIndex,
                  let cueEnd = block.cueEndIndex,
                  let translation = studyTranslations["\(cueStart)-\(cueEnd)"] else {
                return block
            }
            return StudyBlock(
                id: block.id,
                index: block.index,
                targetText: block.targetText,
                nativeText: translation,
                mediaStart: block.mediaStart,
                mediaEnd: block.mediaEnd,
                cueStartIndex: block.cueStartIndex,
                cueEndIndex: block.cueEndIndex
            )
        }
    }

    @MainActor
    private func ensureTranslationsForNearbyBlocks() async {
        guard let session = studySessionViewModel else { return }
        let blocksNeedingTranslation = session.blocks.filter { ($0.nativeText ?? "").isEmpty }
        guard !blocksNeedingTranslation.isEmpty else {
            studyTranslationState = studyTranslations.isEmpty ? .idle : .loaded
            return
        }

        studyTranslationState = .loading
        let languageName = episode.show?.language.displayName ?? "Spanish"

        do {
            let batch = Array(blocksNeedingTranslation.prefix(12))
            let translated = try await openAIService.translateStudyBlockBatch(
                blocks: batch,
                sourceLanguage: languageName
            )

            for block in batch {
                if let text = translated[block.index],
                   let start = block.cueStartIndex,
                   let end = block.cueEndIndex {
                    studyTranslations["\(start)-\(end)"] = text
                }
            }

            studyTranslationState = .loaded
            refreshStudySessionBlocks()

            transcriptService.updateCache(
                consumptionUrl: episode.audioUrl,
                languageCode: (episode.show?.language ?? .spanish).rawValue,
                blocks: makeFocusStudyBlocks(),
                words: studyWords.isEmpty ? nil : studyWords,
                cues: activeStudyCues.isEmpty ? nil : activeStudyCues,
                modelContext: modelContext
            )
        } catch {
            studyTranslationState = .failed(message: userFacingTranscriptError(error))
        }
    }

    private func blockIndex(for time: Double, in blocks: [StudyBlock]) -> Int? {
        blocks.last(where: { $0.contains(time: time) })?.index
    }

    // MARK: - Word lookup

    private struct WordSelection: Identifiable {
        let word: String
        var id: String { word }
    }

    private func lookupWordInFocus(_ word: String) {
        lookupSelection = WordSelection(word: word)
        lookupTranslation = nil
        lookupPartOfSpeech = nil
        isLookingUpWord = true

        Task {
            do {
                let languageName = episode.show?.language.displayName ?? "Spanish"
                let context = studySessionViewModel?.currentBlock?.targetText
                let result = try await openAIService.translateWord(word, language: languageName, context: context)
                lookupTranslation = result.translation
                lookupPartOfSpeech = result.partOfSpeech
            } catch {
                lookupTranslation = "Could not look up word."
            }
            isLookingUpWord = false
        }
    }

    private func markWordForStudy(word: String) {
        guard let userID = authManager.currentUser,
              let session = studySessionViewModel else { return }

        let marked = MarkedStudyWord(
            userID: userID,
            resource: session.resource,
            blockIndex: session.currentBlockIndex,
            word: word,
            translation: lookupTranslation,
            contextSnippet: session.currentBlock?.targetText,
            mediaTime: session.mediaPlayer.currentTime
        )
        modelContext.insert(marked)
        try? modelContext.save()
        showToast("Marked \"\(word)\" for study")
    }

    private func saveSessionRecord(definition: StudySessionDefinition) {
        guard let userID = authManager.currentUser,
              let session = studySessionViewModel else { return }
        let record = StudySessionRecord(
            userID: userID,
            resource: session.resource,
            definition: definition
        )
        modelContext.insert(record)
        try? modelContext.save()
    }

    // MARK: - Audio

    private func setupStream() {
        guard let url = episode.playableAudioURL else {
            playbackError = "This episode does not have a valid audio URL."
            return
        }

        playbackError = nil
        audioManager.streamAudio(url: url, startAt: episode.playbackPosition)
        duration = max(episode.duration, 1)

        audioManager.updateStreamNowPlayingInfo(
            title: episode.title,
            artist: episode.show?.title ?? "Podcast"
        )

        audioManager.playStream()
        isPlaying = audioManager.isStreaming
        sliderValue = episode.playbackPosition

        if let artworkUrlStr = episode.show?.artworkUrl,
           let artworkUrl = URL(string: artworkUrlStr) {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: artworkUrl),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        artworkImage = image
                        audioManager.updateStreamNowPlayingInfo(artworkImage: image)
                    }
                }
            }
        }
    }

    private func syncPlaybackSnapshot() {
        guard audioManager.streamPlayer != nil else { return }

        sliderValue = audioManager.streamCurrentTime
        isPlaying = audioManager.isStreaming

        if duration == 0 && audioManager.streamDuration > 0 {
            duration = audioManager.streamDuration
        }

        studyMediaPlayer?.applySnapshot(
            currentTime: audioManager.streamCurrentTime,
            duration: audioManager.streamDuration,
            isPlaying: audioManager.isStreaming,
            playbackRate: playbackRate
        )

        studySessionViewModel?.handlePlaybackTime(
            audioManager.streamCurrentTime,
            isPlaying: audioManager.isStreaming
        )

        if let streamError = audioManager.streamLoadError {
            playbackError = streamError
            isPlaying = false
        }
    }

    private func cleanupSession() {
        let currentTime = audioManager.streamCurrentTime
        episode.playbackPosition = currentTime
        episode.isSynced = false

        if duration > 0 && (currentTime >= duration - 30 || currentTime / duration > 0.95) {
            episode.isPlayed = true
        }

        try? modelContext.save()
        audioManager.stopStream()

        if let start = startTime {
            let minutes = Int(Date().timeIntervalSince(start) / 60)
            if minutes > 0 {
                let activity = UserActivity(
                    date: start,
                    minutes: minutes,
                    activityType: .podcasts,
                    language: episode.show?.language ?? .spanish,
                    userID: authManager.currentUser,
                    comment: "\(episode.show?.title ?? "Podcast") — \(episode.title)"
                )
                modelContext.insert(activity)
                try? modelContext.save()
                showToast("+\(minutes) min of podcast listening logged")
            }
        }
    }

    private func togglePlay() {
        if audioManager.isStreaming {
            audioManager.pauseStream()
            isPlaying = false
            studySessionViewModel?.stopBlockPlayback()
        } else {
            if audioManager.streamPlayer == nil || audioManager.streamLoadError != nil {
                setupStream()
            } else {
                audioManager.playStream()
                isPlaying = audioManager.isStreaming
            }
        }
        audioManager.updateStreamNowPlayingInfo()
    }

    private func skipForward() {
        let newTime = min(duration, audioManager.streamCurrentTime + 10)
        seekTo(newTime)
    }

    private func skipBackward() {
        let newTime = max(0, audioManager.streamCurrentTime - 10)
        seekTo(newTime)
    }

    private func seekTo(_ value: Double) {
        audioManager.seekStream(to: value)
        sliderValue = value
        studySessionViewModel?.syncCurrentBlockToPlaybackTime()
        audioManager.updateStreamNowPlayingInfo()
    }

    private func setRate(_ rate: Float) {
        playbackRate = rate
        audioManager.setStreamRate(rate)
        audioManager.updateStreamNowPlayingInfo()
    }

    private func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.3)) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.easeInOut(duration: 0.3)) {
                toastMessage = nil
            }
        }
    }
}

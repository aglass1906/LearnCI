import SwiftUI
import AVFoundation
import AVKit
import Combine
import SwiftData
import MediaPlayer

private enum StoryBookLayout {
    static let horizontalPadding: CGFloat = 16
    static let bottomScrollSpacer: CGFloat = 160

    static func readableContentWidth(in containerWidth: CGFloat) -> CGFloat {
        max(1, containerWidth - horizontalPadding * 2)
    }
}

struct StorySessionView: View {

    let story: Story
    private let initialSpineIndex: Int
    private let initialPlaybackPosition: Double?
    private let onProgressChange: ((StoryReaderProgressUpdate) -> Void)?
    @Environment(AudioManager.self) private var audioManager
    @Environment(AmbientSoundManager.self) private var ambientSoundManager
    @Environment(AuthManager.self) private var authManager
    @Environment(SavedStudyWordManager.self) private var savedStudyWordManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    // Playback State
    @State private var isPlaying: Bool = false
    @State private var sliderValue: Double = 0
    @State private var duration: Double = 0
    @State private var playbackRate: Float = 1.0
    @State private var ambientVolume: Float = 0.15
    @State private var isDownloadingAudio = false
    @State private var currentSpineIndex: Int = 0
    @State private var currentChapterIndex: Int = 0
    @State private var currentSceneClipIndex: Int = 0

    // UI State
    @State private var showStoryInfo = false
    @State private var showSpine = false
    @State private var isPlayerMinimized = false
    @State private var selectedLanguage: DisplayLanguage = .target
    @State private var heroImage: UIImage? = nil
    @State private var readingMatterHeroImage: UIImage? = nil
    @State private var isAutoContinueEnabled = false
    @State private var autoAdvanceToken = 0
    @State private var sleepTimerMinutes = 0
    @State private var sleepTimerToken = 0
    @State private var usesStoryBookSidePane = false
    @State private var isStoryBookSidePaneHidden = false
    
    // Auto-Scroll State
    @State private var activeWordIndex: Int? = nil
    @State private var activeParagraphId: Int? = nil
    
    // Analytics
    @State private var startTime: Date?
    @State private var didPlayAudio: Bool = false

    // Chapter intro vs body within the same chapter spine step.
    @State private var isShowingChapterIntro: Bool = false

    // Shared spine supplemental playback for reading matter and chapter intros.
    @State private var supplementalPlayback = StorySupplementalAudioPlayback()

    // Comprehension Quiz
    @State private var navigateToQuiz: Bool = false
    @State private var isGeneratingQuiz: Bool = false
    @State private var quizQuestions: [ComprehensionQuestion] = []

    // Word Lookup (openAIService also used for word translation)
    private let openAIService = OpenAIService()

    // Word Lookup
    @State private var selectedWord: String? = nil
    @State private var selectedWordTime: Double? = nil
    @State private var wordTranslation: String? = nil
    @State private var wordPartOfSpeech: String? = nil
    @State private var wordLookupDetails: WordTranslationResult? = nil
    @State private var isTranslatingWord: Bool = false
    @State private var showWordLookup: Bool = false
    @State private var wordTranslationCache: [String: WordTranslationResult] = [:]
    @State private var selectedWordRequest: StoryWordLookupRequest?
    @State private var phraseSelectionStart: StoryWordLookupRequest?
    @State private var phraseSelectionMessage: String?
    @State private var savedStudyRevision = 0
    @State private var didApplyInitialPlaybackPosition = false
    @State private var lastSavedPlaybackSecond = -1

    init(
        story: Story,
        initialSpineIndex: Int = 0,
        initialPlaybackPosition: Double? = nil,
        onProgressChange: ((StoryReaderProgressUpdate) -> Void)? = nil
    ) {
        self.story = story
        self.initialSpineIndex = initialSpineIndex
        self.initialPlaybackPosition = initialPlaybackPosition
        self.onProgressChange = onProgressChange
        _currentSpineIndex = State(initialValue: max(0, initialSpineIndex))
    }
    
    enum DisplayLanguage: String, CaseIterable {
        case target = "Target Language"
        case native = "English"
    }
    
    // Timer to update scrubber
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    private var adapter: StoryReaderDataAdapter {
        StoryReaderDataAdapter(story: story)
    }

    private func languageCode(for displayLanguage: DisplayLanguage) -> String {
        switch displayLanguage {
        case .target:
            return story.targetLanguageCode
        case .native:
            return story.nativeLanguageCode
        }
    }

    private var storyBookSpineItems: [StoryReadingSpineItem] {
        adapter.items(for: .storyBook)
    }

    private var storyBookChapterItems: [StoryReadingSpineItem] {
        storyBookSpineItems.filter {
            if case .chapter = $0 { return true }
            return false
        }
    }

    private var currentSpineItem: StoryReadingSpineItem? {
        storyBookSpineItems[safeStorySession: currentSpineIndex]
    }

    private var isOnChapterSpineItem: Bool {
        if case .chapter = currentSpineItem { return true }
        return false
    }

    private var nextSpineIndex: Int? {
        let next = currentSpineIndex + 1
        return storyBookSpineItems.indices.contains(next) ? next : nil
    }

    private var previousSpineIndex: Int? {
        let previous = currentSpineIndex - 1
        return previous >= 0 ? previous : nil
    }

    private func spineStepNavigationHandler(delta: Int) -> (() -> Void)? {
        if delta > 0 {
            if isShowingChapterIntro {
                return { finishChapterIntro(andPlayBody: self.isAutoContinueEnabled) }
            }
            guard let nextSpineIndex else { return nil }
            return {
                goToSpineIndex(nextSpineIndex, showChapterCard: shouldShowChapterCard(forSpineIndex: nextSpineIndex))
            }
        }

        guard let previousSpineIndex else { return nil }
        return {
            goToSpineIndex(previousSpineIndex, showChapterCard: shouldShowChapterCard(forSpineIndex: previousSpineIndex))
        }
    }

    var body: some View {
        Group {
            if let issue = adapter.requirementIssue(for: .storyBook) {
                StoryReaderUnavailableView(title: issue.title, message: issue.message)
            } else {
                readerBody
            }
        }
        .environment(\.storyWordLookupAction) { request in
            handleWordLookupRequest(request)
        }
        .overlay(alignment: .bottom) { phraseSelectionBanner }
    }

    private var readerBody: some View {
        GeometryReader { geometry in
            Group {
                if showsStoryBookSidePane {
                    HStack(spacing: 0) {
                        storyBookReaderStack
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Divider()

                        storyBookSidePane
                            .frame(width: 360)
                    }
                } else {
                    storyBookReaderStack
                }
            }
            .onAppear {
                usesStoryBookSidePane = showsStoryBookSidePane
                minimizePlayerForLandscapeIfNeeded(geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                minimizePlayerForLandscapeIfNeeded(newSize)
            }
            .onChange(of: horizontalSizeClass) { _, _ in
                if !usesStoryReaderSidePane {
                    isStoryBookSidePaneHidden = false
                }
                usesStoryBookSidePane = showsStoryBookSidePane
            }
            .onChange(of: isStoryBookSidePaneHidden) { _, _ in
                usesStoryBookSidePane = showsStoryBookSidePane
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        // Programmatic navigation to quiz on audio completion or overflow menu tap
        .navigationDestination(isPresented: $navigateToQuiz) {
            StoryQuizView(story: story, preloadedQuestions: quizQuestions.isEmpty ? nil : quizQuestions)
        }
        .onAppear {
            startTime = Date()
            ambientVolume = story.ambientVolume
            reconcileCurrentSpinePosition()
            if isOnChapterSpineItem, !isShowingChapterIntro {
                setupInitialChapterAudioIfNeeded()
            }
            if isOnChapterSpineItem {
                loadChapterImage()
            }
            if isOnReadingMatterSpineItem {
                loadReadingMatterImage()
            }
        }
        .mediaPlaybackLifecycle(
            onUserLeave: {
                cancelScheduledAutoAdvance()
                cleanupSession()
            },
            onEnterBackground: { audioManager.updateStreamNowPlayingInfo() }
        )
        .onChange(of: currentChapterIndex) { _, _ in
            loadChapterImage()
        }
        .onChange(of: currentSpineIndex) { _, _ in
            saveReadingProgress()
        }
        .onChange(of: ambientVolume) { _, newValue in
            audioManager.setAmbientVolume(newValue)
            story.ambientVolume = newValue
            try? modelContext.save()
        }
        .sheet(isPresented: $showStoryInfo) {
            StoryInfoSheet(story: story)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: Binding(
            get: { showSpine && !usesStoryReaderSidePane },
            set: { if !$0 { showSpine = false } }
        )) {
            storyBookSidePane
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showWordLookup) {
            WordLookupSheet(
                word: selectedWord ?? "",
                languageLabel: story.language.displayName,
                translation: wordTranslation,
                partOfSpeech: wordPartOfSpeech,
                details: wordLookupDetails,
                isLoading: isTranslatingWord,
                seekTime: selectedWordTime,
                onSeek: { time in
                    seekTo(time)
                },
                onSelectPhrase: canSelectPhrase ? { beginPhraseSelection() } : nil,
                onMarkForStudy: {
                    markSelectedWordForStudy()
                },
                isMarkedForStudy: isSelectedWordSaved
            )
            .presentationDetents([.fraction(0.4)])
            .presentationDragIndicator(.visible)
        }
        .onReceive(timer) { _ in
            if isOnSupplementalSpineItem {
                supplementalPlayback.syncStreamState()
                sliderValue = supplementalPlayback.currentTime
                if supplementalPlayback.duration > 0 {
                    duration = supplementalPlayback.duration
                }
                isPlaying = supplementalPlayback.isPlaying
                saveTimedReadingProgressIfNeeded(position: sliderValue)
                if isOnReadingMatterSpineItem {
                    activeWordIndex = supplementalPlayback.activeWordIndex
                }
                if let streamPlayer = audioManager.streamPlayer,
                   abs(streamPlayer.rate - playbackRate) > 0.1,
                   streamPlayer.rate != 0 {
                    playbackRate = streamPlayer.rate
                }
                return
            }

            guard isOnChapterSpineItem, !isShowingChapterIntro else { return }

            if audioManager.streamFinished {
                advanceAfterSceneClipFinished()
                return
            }

            if audioManager.streamPlayer != nil {
                let streamCurrent = audioManager.streamCurrentTime
                let streamDur = audioManager.streamDuration
                let localChapterTime = currentClipStartOffset + streamCurrent

                sliderValue = localChapterTime
                
                // Keep duration updated as AVPlayer loads the exact size asynchronously.
                // The published scene duration can be short when audio is regenerated with
                // new voices, so the actual current media duration must be allowed to expand
                // the chapter timeline.
                let resolvedDuration = adapter.duration(
                    forChapter: currentChapterIndex,
                    currentClipIndex: currentSceneClipIndex,
                    currentStreamDuration: streamDur,
                    fallback: streamDur
                )
                if resolvedDuration > 0 && abs(duration - resolvedDuration) > 0.5 {
                    duration = resolvedDuration
                }
                
                isPlaying = audioManager.isStreaming
                saveTimedReadingProgressIfNeeded(position: sliderValue)
                
                // Update active word and paragraph
                updateScrollState(time: sliderValue)
                
                // Sync rate if changed externally (e.g. lock screen)
                if let streamPlayer = audioManager.streamPlayer {
                    if abs(streamPlayer.rate - playbackRate) > 0.1 && streamPlayer.rate != 0 {
                        playbackRate = streamPlayer.rate
                    }
                }
            }
        }
        .onChange(of: heroImage) { _, newImage in
            if let img = newImage {
                audioManager.updateNowPlayingInfo(title: story.title, artist: "LearnCI Story", artworkImage: img)
            }
        }
        .onChange(of: isAutoContinueEnabled) { _, enabled in
            if enabled {
                startAutoContinueForCurrentSpineItem()
            } else {
                cancelScheduledAutoAdvance()
            }
        }
        .onChange(of: sleepTimerMinutes) { _, minutes in
            scheduleSleepTimer(minutes: minutes)
        }
    }

    private var storyBookReaderStack: some View {
        VStack(spacing: 0) {
            storyBookSpineHeader
                .zIndex(1)

            ZStack(alignment: .bottom) {
                Group {
                    switch currentSpineItem {
                    case .cover:
                        coverPageView
                    case .readingMatterPage:
                        currentReadingMatterPageView
                    case .chapter:
                        chapterReaderContent
                    case .chapterQuiz:
                        currentChapterQuizView
                    case .chapterVocabulary:
                        currentChapterVocabularyView
                    case .scene, .none:
                        StoryReaderUnavailableView(
                            title: "Reader Data Missing",
                            message: "This story spine item could not be displayed."
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                stickyPlayerView
            }
        }
    }

    private var storyBookSidePane: some View {
        StoryBookPlayerSheet(
            spineItems: storyBookSpineItems,
            currentSpineIndex: currentSpineIndex,
            adapter: adapter,
            isAutoContinueEnabled: $isAutoContinueEnabled,
            sleepTimerMinutes: $sleepTimerMinutes,
            playbackRate: $playbackRate,
            onChangeRate: setRate
        ) { spineIndex in
            showSpine = false
            isPlayerMinimized = false
            goToSpineIndex(spineIndex, showChapterCard: shouldShowChapterCard(forSpineIndex: spineIndex))
        }
    }

    private var usesStoryReaderSidePane: Bool {
        AdaptiveLayoutPolicy.usesStoryReaderSidePane(horizontalSizeClass: horizontalSizeClass)
    }

    private var showsStoryBookSidePane: Bool {
        usesStoryReaderSidePane && !isStoryBookSidePaneHidden
    }
    
    // MARK: - Audio Logic
    
    private func setupAudio(autoplay: Bool = false, sceneClipIndex: Int? = nil, startAt: Double = 0) {
        guard adapter.requirementIssue == nil else { return }
        let clips = currentChapterClips
        guard !clips.isEmpty else {
            print("[StorySession] No scene audio available for chapter \(currentChapterIndex)")
            return
        }

        currentSceneClipIndex = min(max(sceneClipIndex ?? currentSceneClipIndex, 0), clips.count - 1)
        let clip = clips[currentSceneClipIndex]
        let localURL = adapter.localAudioURL(for: clip)

        if let cachedURL = adapter.cachedAudioURL(for: clip) {
            print("[StorySession] Playing cached scene audio: \(cachedURL.lastPathComponent)")
            playLocalAudio(url: cachedURL, clip: clip, startAt: startAt, autoplay: autoplay)
            return
        }

        print("[StorySession] Downloading scene audio from remote: \(clip.urlString)")
        isDownloadingAudio = true
        Task { await downloadAndPlayAudio(clip: clip, localURL: localURL, startAt: startAt, autoplay: autoplay) }
    }

    /// Plays an already-local audio file using the AVPlayer stream interface.
    private func playLocalAudio(url: URL, clip: StorySceneAudioClip, startAt: Double = 0, autoplay: Bool = false) {
        audioManager.streamAudio(url: url, startAt: startAt)
        audioManager.setStreamRate(playbackRate)
        audioManager.onStreamFinished = {
            advanceAfterSceneClipFinished()
        }
        duration = adapter.duration(
            forChapter: currentChapterIndex,
            currentClipIndex: currentSceneClipIndex,
            currentStreamDuration: audioManager.streamDuration,
            fallback: audioManager.streamDuration
        )
        sliderValue = clip.startOffset + startAt
        audioManager.updateStreamNowPlayingInfo(
            title: clip.title,
            artist: story.title,
            artworkImage: heroImage
        )
        if autoplay {
            startAmbient()
            audioManager.playStream()
            isPlaying = true
        }
    }

    /// Downloads audio from Supabase Storage, saves it locally with the correct extension, then plays it.
    /// - Parameters:
    ///   - remotePath: Path in Supabase Storage (or full https URL).
    ///   - localURL: Base destination URL (extension may be corrected after inspecting magic bytes).
    ///   - derivedFilename: If non-nil and `story.audioFilename` is nil, saves detected filename back
    ///     to `story.audioFilename` so future opens use the cached local file without re-downloading.
    private func downloadAndPlayAudio(clip: StorySceneAudioClip, localURL: URL, startAt: Double = 0, autoplay: Bool = false) async {
        guard let url = StoryReaderDataAdapter.remoteAudioURL(for: clip.urlString) else {
            await MainActor.run { isDownloadingAudio = false }
            return
        }

        do {
            print("[StorySession] Downloading audio from \(url.absoluteString.prefix(80))…")
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 1000 else {
                print("[StorySession] Audio download failed — HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0), \(data.count) bytes")
                await MainActor.run { isDownloadingAudio = false }
                return
            }

            // Detect actual format by magic bytes — legacy uploads stored WAV content with .mp3 path.
            // AVAudioPlayer uses the file extension to choose its parser, so the extension MUST match.
            let isWAV = data.prefix(4) == Data([0x52, 0x49, 0x46, 0x46]) // "RIFF"
            let correctExt = isWAV ? "wav" : "mp3"
            let correctURL = localURL.deletingPathExtension().appendingPathExtension(correctExt)

            try data.write(to: correctURL)
            print("[StorySession] Audio downloaded (\(data.count / 1024)KB, format=\(correctExt)) — playing")

            await MainActor.run {
                isDownloadingAudio = false
                playLocalAudio(url: correctURL, clip: clip, startAt: startAt, autoplay: autoplay)
            }
        } catch {
            print("[StorySession] Audio download error: \(error)")
            await MainActor.run { isDownloadingAudio = false }
        }
    }

    private func startAmbient() {
        guard let soundId = story.ambientSoundId,
              soundId != "none",
              let sound = AmbientSound.catalog.first(where: { $0.id == soundId }) else { return }

        Task {
            do {
                let url = try await ambientSoundManager.ensureDownloaded(sound)
                await MainActor.run {
                    audioManager.playAmbient(url: url, volume: story.ambientVolume)
                }
            } catch {
                print("[StorySession] Ambient sound unavailable: \(error)")
            }
        }
    }
    
    private func cleanupSession() {
        audioManager.onStreamFinished = nil
        stopSupplementalPlayback()
        audioManager.stopAmbient()
        audioManager.stopAudio()
        
        // Analytics
        if let start = startTime {
            let end = Date()
            let interval = end.timeIntervalSince(start)
            let minutes = Int(interval / 60)
            
            if minutes > 0 {
                let type: ActivityType = didPlayAudio ? .listening : .reading
                let activity = UserActivity(
                    date: start,
                    minutes: minutes,
                    activityType: type,
                    language: story.language,
                    userID: story.userID.isEmpty ? nil : story.userID
                )
                modelContext.insert(activity)
                try? modelContext.save()
            }
        }
    }
    
    private func togglePlay() {
        if isOnSupplementalSpineItem {
            if isShowingChapterIntro, !hasChapterIntroContent {
                finishChapterIntro(andPlayBody: true)
                return
            }
            toggleSupplementalPlayback()
            return
        }

        guard isOnChapterSpineItem else { return }
        didPlayAudio = true

        if audioManager.streamPlayer == nil {
            setupAudio(autoplay: true)
            return
        }

        if audioManager.isStreaming {
            audioManager.pauseStream()
            isPlaying = false
            audioManager.pauseAmbient()
        } else {
            audioManager.playStream()
            isPlaying = true
            audioManager.resumeAmbient()
        }
        audioManager.updateStreamNowPlayingInfo()
    }
    
    private func skipForward() {
        if isOnSupplementalSpineItem, supplementalPlayback.canSeek {
            seekSupplementalPlayback(to: min(max(duration, 1), sliderValue + 10))
            return
        }
        guard isOnChapterSpineItem, !isShowingChapterIntro else { return }
        let newTime = sliderValue + 10
        let maxDur = max(duration, 10.0)
        let safeTime = min(maxDur, newTime)
        seekTo(safeTime)
        audioManager.updateStreamNowPlayingInfo()
    }
    
    private func skipBackward() {
        if isOnSupplementalSpineItem, supplementalPlayback.canSeek {
            seekSupplementalPlayback(to: max(0, sliderValue - 10))
            return
        }
        guard isOnChapterSpineItem, !isShowingChapterIntro else { return }
        let newTime = sliderValue - 10
        let safeTime = max(0, newTime)
        seekTo(safeTime)
        audioManager.updateStreamNowPlayingInfo()
    }
    
    private func seekTo(_ value: Double) {
        if isOnSupplementalSpineItem, supplementalPlayback.canSeek {
            seekSupplementalPlayback(to: value)
            return
        }
        guard isOnChapterSpineItem, !isShowingChapterIntro else { return }
        guard let target = adapter.clipIndex(forChapter: currentChapterIndex, localTime: value) else { return }
        if target.index == currentSceneClipIndex {
            audioManager.seekStream(to: target.offset)
            sliderValue = value
            updateScrollState(time: value)
        } else {
            let shouldResume = isPlaying
            setupAudio(autoplay: shouldResume, sceneClipIndex: target.index, startAt: target.offset)
        }
        audioManager.updateStreamNowPlayingInfo()
    }
    
    private func setRate(_ rate: Float) {
        playbackRate = rate
        if isOnSupplementalSpineItem {
            supplementalPlayback.setRate(rate)
        } else {
            audioManager.setStreamRate(rate)
        }
        if isPlaying {
            audioManager.updateStreamNowPlayingInfo()
        }
    }
    
    // MARK: - Word Lookup

    private var canSelectPhrase: Bool {
        selectedWordRequest?.wordIndex != nil && selectedWordRequest?.sourceText?.isEmpty == false
    }

    @ViewBuilder
    private var phraseSelectionBanner: some View {
        if let phraseSelectionStart {
            HStack(spacing: 10) {
                Image(systemName: "text.cursor")
                Text(phraseSelectionMessage ?? "Tap the last word in the phrase.")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Cancel") {
                    self.phraseSelectionStart = nil
                    phraseSelectionMessage = nil
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 8, y: 4)
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityLabel("Selecting phrase starting with \(phraseSelectionStart.word)")
        }
    }

    private func handleWordLookupRequest(_ request: StoryWordLookupRequest) {
        if phraseSelectionStart != nil {
            finishPhraseSelection(with: request)
        } else {
            lookupWord(request.word, time: request.time, context: request.context, request: request)
        }
    }

    private func lookupWord(_ word: String, time: Double?, context providedContext: String? = nil) {
        lookupWord(word, time: time, context: providedContext, request: nil)
    }

    private func lookupWord(_ word: String, time: Double?, context providedContext: String? = nil, request: StoryWordLookupRequest?) {
        selectedWordRequest = request
        selectedWord = word
        selectedWordTime = time
        wordTranslation = nil
        wordPartOfSpeech = nil
        wordLookupDetails = nil
        showWordLookup = true

        let context = providedContext ?? sentenceContaining(word: word)
        let cacheKey = "\(word.lowercased())_\(story.language.rawValue)_\(context ?? "")"
        if let cached = wordTranslationCache[cacheKey] {
            wordTranslation = cached.translation
            wordPartOfSpeech = cached.partOfSpeech
            wordLookupDetails = cached
            return
        }

        isTranslatingWord = true
        Task {
            do {
                let result = try await OpenAIService().translateWord(word, language: story.language.displayName, context: context)
                await MainActor.run {
                    wordTranslation = result.translation
                    wordPartOfSpeech = result.partOfSpeech
                    wordLookupDetails = result
                    wordTranslationCache[cacheKey] = result
                    isTranslatingWord = false
                }
            } catch {
                await MainActor.run {
                    wordTranslation = error.localizedDescription
                    wordPartOfSpeech = ""
                    wordLookupDetails = nil
                    isTranslatingWord = false
                    Logger.error("Story word lookup failed for '\(word)': \(error.localizedDescription)", category: .general)
                }
            }
        }
    }

    private var isSelectedWordSaved: Bool {
        _ = savedStudyRevision
        guard let userID = authManager.currentUser,
              let selectedWord else { return false }
        return savedStudyWordManager.isSaved(
            word: selectedWord,
            userID: userID,
            languageCode: story.language.code,
            sourceType: .story,
            sourceId: story.id.uuidString,
            in: modelContext
        )
    }

    private func markSelectedWordForStudy() {
        guard let userID = authManager.currentUser,
              let selectedWord else { return }

        let sentenceTarget = selectedWordRequest?.context ?? sentenceContaining(word: selectedWord)
        let audioResolution = StoryStudyWordAudioResolver.resolve(
            story: story,
            request: selectedWordRequest,
            fallbackWord: selectedWord,
            fallbackContext: sentenceTarget
        )
        let audioCapture = selectedStoryAudioCapture(fallback: audioResolution)
        let capture = SavedStudyWordCapture(
            userID: userID,
            word: selectedWord,
            translation: wordTranslation,
            lemma: wordLookupDetails?.lemma,
            sentenceTarget: sentenceTarget,
            sentenceNative: nil,
            languageCode: story.language.code,
            level: wordLookupDetails?.level ?? String(story.level),
            partOfSpeech: wordPartOfSpeech,
            verbTense: wordLookupDetails?.verbTense,
            grammarNotes: wordLookupDetails?.grammarNotes,
            sourceType: .story,
            sourceId: story.id.uuidString,
            sourceTitle: story.title,
            sourceUrl: audioCapture.sourceUrl,
            blockIndex: selectedWordRequest?.wordIndex,
            mediaStart: audioCapture.mediaStart,
            mediaEnd: audioCapture.mediaEnd,
            audioWordFile: nil,
            audioSentenceFile: nil,
            deckFolderName: nil
        )
        savedStudyWordManager.toggleSave(capture: capture, in: modelContext)
        savedStudyRevision += 1
    }

    private func selectedStoryAudioCapture(
        fallback: StoryStudyWordAudioResolution?
    ) -> StoryStudyWordAudioResolution {
        if let selectedWordTime,
           let match = adapter.clipIndex(forChapter: currentChapterIndex, localTime: selectedWordTime),
           let clip = currentChapterClips[safeStorySession: match.index] {
            let start = match.offset
            let end = selectedWordRequest?.endTime
                .map { max(0, $0 - clip.startOffset) }
                .flatMap { $0 > start ? $0 : nil }

            return StoryStudyWordAudioResolution(
                sourceUrl: clip.urlString,
                mediaStart: start,
                mediaEnd: end
            )
        }

        if let fallback {
            return fallback
        }

        return StoryStudyWordAudioResolution(
            sourceUrl: selectedStoryAudioClip()?.urlString,
            mediaStart: selectedWordTime,
            mediaEnd: selectedWordRequest?.endTime
        )
    }

    private func selectedStoryAudioClip() -> StorySceneAudioClip? {
        guard let selectedWordTime else {
            return currentChapterClips[safeStorySession: currentSceneClipIndex]
        }
        if let match = adapter.clipIndex(forChapter: currentChapterIndex, localTime: selectedWordTime),
           currentChapterClips.indices.contains(match.index) {
            return currentChapterClips[match.index]
        }
        return currentChapterClips[safeStorySession: currentSceneClipIndex]
    }

    private func beginPhraseSelection() {
        guard let selectedWordRequest, canSelectPhrase else { return }
        phraseSelectionStart = selectedWordRequest
        phraseSelectionMessage = "Tap the last word in the phrase."
        showWordLookup = false
        selectedWord = nil
        selectedWordTime = nil
        wordTranslation = nil
        wordPartOfSpeech = nil
        wordLookupDetails = nil
        isTranslatingWord = false
    }

    private func finishPhraseSelection(with request: StoryWordLookupRequest) {
        guard let start = phraseSelectionStart,
              let sourceText = start.sourceText,
              sourceText == request.sourceText,
              let startIndex = start.wordIndex,
              let endIndex = request.wordIndex,
              let phrase = phraseText(in: sourceText, from: startIndex, to: endIndex) else {
            phraseSelectionStart = request.wordIndex == nil ? nil : request
            phraseSelectionMessage = "Phrase selection restarted. Tap the last word in this text block."
            return
        }

        phraseSelectionStart = nil
        phraseSelectionMessage = nil
        lookupWord(
            phrase,
            time: min(start.time ?? request.time ?? 0, request.time ?? start.time ?? 0),
            context: sentenceContaining(phrase: phrase, in: sourceText),
            request: StoryWordLookupRequest(
                word: phrase,
                time: min(start.time ?? request.time ?? 0, request.time ?? start.time ?? 0),
                endTime: max(start.endTime ?? start.time ?? 0, request.endTime ?? request.time ?? 0),
                context: sentenceContaining(phrase: phrase, in: sourceText),
                sourceText: sourceText
            )
        )
    }

    private func phraseText(in text: String, from firstIndex: Int, to secondIndex: Int) -> String? {
        let matches = wordRanges(in: text)
        guard matches.indices.contains(firstIndex), matches.indices.contains(secondIndex) else { return nil }

        let lowerIndex = min(firstIndex, secondIndex)
        let upperIndex = max(firstIndex, secondIndex)
        let phrase = text[matches[lowerIndex].lowerBound..<matches[upperIndex].upperBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return phrase.isEmpty ? nil : phrase
    }

    private func wordRanges(in text: String) -> [Range<String.Index>] {
        let nsText = text as NSString
        let regex = try? NSRegularExpression(pattern: "\\p{L}+", options: [])
        return regex?.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            .compactMap { Range($0.range, in: text) } ?? []
    }

    private func sentenceContaining(word: String) -> String? {
        let text = currentChapter?.bodyTextForLanguage(story.targetLanguageCode) ?? ""
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?。！？\n"))
        return sentences.first(where: { $0.localizedCaseInsensitiveContains(word) })?.trimmingCharacters(in: .whitespaces)
    }

    private func sentenceContaining(phrase: String, in text: String) -> String? {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?。！？\n"))
        return sentences.first(where: { $0.localizedCaseInsensitiveContains(phrase) })?.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Comprehension Quiz

    private func preGenerateQuizIfNeeded() {
        guard story.comprehensionQuestionsJSON == nil && !isGeneratingQuiz else { return }
        isGeneratingQuiz = true
        Task {
            let level = LevelManager.shared.description(for: story.level)
            let questions = try? await OpenAIService().generateComprehensionQuestions(
                storyText: storyBookChapterItems.compactMap { adapter.chapter(for: $0)?.bodyTextForLanguage(story.targetLanguageCode) }.joined(separator: "\n\n"),
                language: story.language.displayName,
                level: level
            )
            await MainActor.run {
                if let qs = questions, let data = try? JSONEncoder().encode(qs) {
                    story.comprehensionQuestionsJSON = String(data: data, encoding: .utf8)
                    try? modelContext.save()
                    quizQuestions = qs
                }
                isGeneratingQuiz = false
            }
        }
    }

    private func openQuiz() {
        // Load any pre-cached questions then navigate to the full-screen quiz
        if !story.comprehensionQuestions.isEmpty {
            quizQuestions = story.comprehensionQuestions
        }
        navigateToQuiz = true
    }

    private func regenerateQuiz() {
        story.comprehensionQuestionsJSON = nil
        quizQuestions = []
        try? modelContext.save()
        openQuiz()
    }

    // MARK: - Text Chunking & Auto-Scroll

    private var storyBookCoverSection: some View {
        Group {
            if let heroImage {
                Image(uiImage: heroImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            } else if let url = storyCoverURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                    case .failure, .empty:
                        coverImagePlaceholder
                    @unknown default:
                        coverImagePlaceholder
                    }
                }
            } else {
                coverImagePlaceholder
            }
        }
    }

    private var coverImagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .overlay {
                Image(systemName: "book.closed")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .frame(maxWidth: .infinity)
    }

    private var storyCoverURL: URL? {
        if let remotePath = story.remoteCoverPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remotePath.isEmpty,
           let url = AppConfig.chapterCoverURL(remotePath) {
            return url
        }
        if let coverArt = story.coverArt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !coverArt.isEmpty,
           let url = AppConfig.chapterCoverURL(coverArt) {
            return url
        }
        return nil
    }

    private var isOnChapterSupplementSpineItem: Bool {
        if case .chapterQuiz = currentSpineItem { return true }
        if case .chapterVocabulary = currentSpineItem { return true }
        return false
    }

    private var isOnSupplementalSpineItem: Bool {
        if isOnReadingMatterSpineItem { return true }
        if isOnChapterSpineItem, isShowingChapterIntro { return true }
        return false
    }

    private var isOnReadingMatterSpineItem: Bool {
        if case .readingMatterPage = currentSpineItem { return true }
        return false
    }

    private var isOnPlayableReadingMatter: Bool {
        guard isOnReadingMatterSpineItem,
              let item = currentSpineItem,
              let page = adapter.readingMatterPage(for: item) else { return false }
        return page.audioUrlFor(languageCode(for: selectedLanguage)) != nil
            || readingMatterSpeakableText(for: page) != nil
    }

    private var currentReadingMatterPageHasGeneratedAudio: Bool {
        guard let item = currentSpineItem,
              let page = adapter.readingMatterPage(for: item) else { return false }
        return page.audioUrlFor(languageCode(for: selectedLanguage)) != nil
    }

    private var canSeekCurrentSpinePlayback: Bool {
        if isOnSupplementalSpineItem { return supplementalPlayback.canSeek }
        if isOnChapterSpineItem { return true }
        return false
    }

    private var canControlCurrentSpinePlayback: Bool {
        if isOnChapterSupplementSpineItem { return false }
        if isOnSupplementalSpineItem {
            if isShowingChapterIntro { return hasChapterIntroContent }
            return isOnPlayableReadingMatter
        }
        return isOnChapterSpineItem
    }

    private var playerContextLabel: String? {
        if isShowingChapterIntro {
            return isPlaying ? "Chapter Intro · Now Playing" : "Chapter Intro"
        }
        if isOnPlayableReadingMatter {
            return isPlaying ? "Reading Matter · Now Playing" : "Reading Matter"
        }
        return nil
    }

    private var storyBookSpineHeader: some View {
        HStack(spacing: 10) {
            readerHeaderBackButton

            spineHeaderTitleStack
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsHeaderLanguageToggle {
                chapterLanguageToggle
            }

            if !storyBookSpineItems.isEmpty {
                spineHeaderPageCounter
            }

            readerHeaderOverflowMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
    }

    private var readerHeaderBackButton: some View {
        Button {
            cancelScheduledAutoAdvance()
            cleanupSession()
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.headline.weight(.semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(.primary)
                .background(.thinMaterial)
                .clipShape(Circle())
        }
    }

    private var readerHeaderOverflowMenu: some View {
        Menu {
            Button(action: { showStoryInfo = true }) {
                Label("Story Info", systemImage: "info.circle")
            }

            Button(action: openQuiz) {
                Label("Comprehension Quiz", systemImage: "checkmark.circle")
            }

            Divider()

            Button(action: {
                if selectedLanguage == .target {
                    UIPasteboard.general.string = storyBookChapterItems.compactMap { adapter.chapter(for: $0)?.bodyTextForLanguage(story.targetLanguageCode) }.joined(separator: "\n\n")
                } else {
                    UIPasteboard.general.string = storyBookChapterItems.compactMap { adapter.chapter(for: $0)?.bodyTextForLanguage(story.nativeLanguageCode) }.joined(separator: "\n\n")
                }
            }) {
                Label(
                    selectedLanguage == .target ? "Copy Story (\(story.language.displayName))" : "Copy Story (English)",
                    systemImage: "doc.on.doc"
                )
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
        }
    }

    private var showsHeaderLanguageToggle: Bool {
        if isOnChapterSpineItem { return currentChapterHasEnglishContent }
        if isOnReadingMatterSpineItem { return currentReadingMatterHasEnglishContent }
        return false
    }

    private var spineHeaderPageCounter: some View {
        Text("\(currentSpineIndex + 1)/\(storyBookSpineItems.count)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    @ViewBuilder
    private var spineHeaderTitleStack: some View {
        if isOnChapterSpineItem {
            HStack(spacing: 8) {
                if isShowingChapterIntro {
                    chapterHeaderThumbnail
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let subtitle = currentSpineSubtitle {
                        Text(subtitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }

                    if isShowingChapterIntro {
                        Text(story.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        } else if isOnReadingMatterSpineItem {
            HStack(spacing: 8) {
                readingMatterHeaderThumbnail

                VStack(alignment: .leading, spacing: 2) {
                    Text(story.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if let subtitle = currentSpineSubtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(story.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                if let subtitle = currentSpineSubtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var chapterHeaderThumbnail: some View {
        Group {
            if let heroImage {
                Image(uiImage: heroImage)
                    .resizable()
                    .scaledToFill()
            } else if let coverPath = currentChapter?.coverUrl,
                      let url = AppConfig.chapterCoverURL(coverPath) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure, .empty:
                        chapterHeaderThumbnailPlaceholder
                    @unknown default:
                        chapterHeaderThumbnailPlaceholder
                    }
                }
            } else {
                chapterHeaderThumbnailPlaceholder
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var chapterHeaderThumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor.opacity(0.18))
            .overlay {
                Image(systemName: "text.book.closed")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
    }

    private var currentChapterHasEnglishContent: Bool {
        guard let chapter = currentChapter else { return false }
        if chapter.titleFor(story.nativeLanguageCode) != "Chapter" { return true }
        if !chapter.chapterIntroTextForLanguage(story.nativeLanguageCode).isEmpty { return true }
        if !chapter.bodyScriptForLanguage(story.nativeLanguageCode).isEmpty { return true }
        return !chapter.bodyTextForLanguage(story.nativeLanguageCode).isEmpty
    }

    private var currentReadingMatterHasEnglishContent: Bool {
        guard let item = currentSpineItem,
              let page = adapter.readingMatterPage(for: item) else { return false }
        if !page.titleFor(story.nativeLanguageCode).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !page.bodyFor(story.nativeLanguageCode).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }

    private var currentSpineSubtitle: String? {
        guard let item = currentSpineItem else { return nil }
        switch item {
        case .cover:
            return "Cover"
        case .readingMatterPage:
            if let page = adapter.readingMatterPage(for: item) {
                let title = selectedLanguage == .native
                    ? readerMatterText(page.titleFor(story.nativeLanguageCode))
                    : readerMatterText(page.titleFor(story.targetLanguageCode))
                let base = title ?? "Reading Matter"
                return base
            }
            return "Reading Matter"
        case .chapter(let index):
            if let chapter = story.chapters[safeStorySession: index] {
                let title = selectedLanguage == .native
                    ? chapter.titleFor(story.nativeLanguageCode)
                    : chapter.titleFor(story.targetLanguageCode)
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let chapterLabel = trimmed.isEmpty ? "Chapter \(index + 1)" : "Chapter \(index + 1) · \(trimmed)"
                if isShowingChapterIntro {
                    return "Chapter Intro · \(chapterLabel)"
                }
                return chapterLabel
            }
            if isShowingChapterIntro {
                return "Chapter Intro · Chapter \(index + 1)"
            }
            return "Chapter \(index + 1)"
        case .scene:
            return nil
        case .chapterQuiz:
            return "Chapter Quiz"
        case .chapterVocabulary:
            return "Word Focus"
        }
    }

    @ViewBuilder
    private var currentChapterQuizView: some View {
        if let item = currentSpineItem,
           let chapter = adapter.chapter(for: item) {
            let resolved = ChapterComprehensionQuizResolver.questions(for: chapter, in: story)
            let title = resolved.isStoryWideFallback ? "Story Comprehension Quiz" : "Chapter Comprehension"
            InlineChapterQuizView(questions: resolved.questions, title: title)
        } else {
            InlineChapterQuizView(questions: [], title: "Chapter Comprehension")
        }
    }

    @ViewBuilder
    private var currentChapterVocabularyView: some View {
        if let item = currentSpineItem,
           let chapter = adapter.chapter(for: item) {
            InlineChapterVocabularyView(
                vocabularyNote: chapter.vocabularyNoteForLanguage(story.targetLanguageCode) ?? "",
                title: "Chapter Word Focus"
            )
        } else {
            InlineChapterVocabularyView(vocabularyNote: "", title: "Chapter Word Focus")
        }
    }

    private var coverPageView: some View {
        StoryBookInsetScrollView(bottomSpacer: StoryBookLayout.bottomScrollSpacer) {
            storyBookCoverSection

            Text(story.title)
                .font(.system(size: 32, weight: .bold, design: .serif))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(story.language.displayName) · Level \(story.level)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            loadStoryCoverImage()
        }
    }

    @ViewBuilder
    private var currentReadingMatterPageView: some View {
        if let item = currentSpineItem,
           let page = adapter.readingMatterPage(for: item) {
            StoryBookReadingMatterPageView(
                heroImage: readingMatterHeroImage,
                imageURL: adapter.readingMatterImageURL(for: item),
                title: readingMatterDisplayTitle(for: page),
                bodyText: readingMatterDisplayBody(for: page),
                isUsingGeneratedAudio: supplementalPlayback.isUsingGeneratedAudio,
                playbackTime: supplementalPlayback.currentTime,
                wordTimings: supplementalPlayback.wordTimings,
                useNativeLanguage: selectedLanguage == .native,
                bottomSpacer: StoryBookLayout.bottomScrollSpacer,
                onUserScroll: minimizePlayerForReading
            )
            .onAppear {
                prepareSupplementalPlaybackForCurrentSpineItem()
            }
            .onChange(of: selectedLanguage) { _, _ in
                prepareSupplementalPlaybackForLanguageChangeIfIdle()
            }
        } else {
            StoryReaderUnavailableView(
                title: "Reading Matter Missing",
                message: "This reading matter page could not be loaded."
            )
        }
    }

    @ViewBuilder
    private var readingMatterHeaderThumbnail: some View {
        Group {
            if let readingMatterHeroImage {
                Image(uiImage: readingMatterHeroImage)
                    .resizable()
                    .scaledToFill()
            } else if let item = currentSpineItem,
                      let url = adapter.readingMatterImageURL(for: item) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure, .empty:
                        chapterHeaderThumbnailPlaceholder
                    @unknown default:
                        chapterHeaderThumbnailPlaceholder
                    }
                }
            } else {
                chapterHeaderThumbnailPlaceholder
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var chapterScrollContent: some View {
        ScrollViewReader { scrollProxy in
            GeometryReader { geo in
                let proseWidth = StoryBookLayout.readableContentWidth(in: geo.size.width)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        storyTextView

                        Color.clear.frame(height: 180)
                            .id("BottomSpacer")
                    }
                    .frame(width: proseWidth, alignment: .leading)
                    .padding(.horizontal, StoryBookLayout.horizontalPadding)
                    .padding(.top, 8)
                }
                .simultaneousGesture(readingScrollGesture)
                .onChange(of: activeParagraphId) { _, newId in
                    if let id = newId {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            scrollProxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.35))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func readerMatterText(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func readingMatterDisplayTitle(for page: ReadingMatterPage) -> String? {
        switch selectedLanguage {
        case .target:
            return readerMatterText(page.titleFor(story.targetLanguageCode))
        case .native:
            return readerMatterText(page.titleFor(story.nativeLanguageCode))
        }
    }

    private func readingMatterDisplayBody(for page: ReadingMatterPage) -> String? {
        switch selectedLanguage {
        case .target:
            return readerMatterText(page.bodyFor(story.targetLanguageCode))
        case .native:
            return readerMatterText(page.bodyFor(story.nativeLanguageCode))
        }
    }

    private func readingMatterSpeakableText(for page: ReadingMatterPage) -> String? {
        var parts: [String] = []
        if let title = readingMatterDisplayTitle(for: page) {
            parts.append(title)
        }
        if let body = readingMatterDisplayBody(for: page) {
            parts.append(body)
        }
        let text = parts.joined(separator: ". ")
        return text.isEmpty ? nil : text
    }

    private func toggleSupplementalPlayback(forcePlay: Bool = false) {
        didPlayAudio = true
        let shouldPlay = forcePlay || !isPlaying
        supplementalPlayback.syncPlayback(
            shouldPlay: shouldPlay,
            speakableText: currentSupplementalSpeakableText
        )
        isPlaying = supplementalPlayback.isPlaying

        if shouldPlay, isOnReadingMatterSpineItem, supplementalPlayback.isUsingGeneratedAudio {
            startAmbient()
        }
        if !shouldPlay {
            audioManager.pauseAmbient()
        }
    }

    private func seekSupplementalPlayback(to value: Double) {
        supplementalPlayback.seek(to: value)
        sliderValue = value
    }

    private func stopSupplementalPlayback() {
        supplementalPlayback.stop()
        activeWordIndex = nil
        if isOnSupplementalSpineItem {
            isPlaying = false
            sliderValue = 0
            duration = 0
        }
    }

    private var currentSupplementalSpeakableText: String? {
        if isOnReadingMatterSpineItem,
           let item = currentSpineItem,
           let page = adapter.readingMatterPage(for: item) {
            return readingMatterSpeakableText(for: page)
        }

        if isShowingChapterIntro, let chapter = currentChapter {
            return StorySupplementalAudioPlayback.chapterIntroSpeakableText(
                chapter: chapter,
                preferNative: selectedLanguage == .native,
                targetCode: story.targetLanguageCode,
                nativeCode: story.nativeLanguageCode
            )
        }

        return nil
    }

    private func prepareSupplementalPlaybackForCurrentSpineItem() {
        supplementalPlayback.bind(story: story, audioManager: audioManager)
        supplementalPlayback.setRate(playbackRate)
        supplementalPlayback.onFinished = nil

        if let item = currentSpineItem,
           case .readingMatterPage(let pageIndex, _) = item,
           let page = adapter.readingMatterPage(for: item) {
            supplementalPlayback.prepareReadingMatter(
                pageIndex: pageIndex,
                page: page,
                preferNative: selectedLanguage == .native
            )
            supplementalPlayback.onFinished = {
                advanceAfterSupplementalFinished()
            }
            return
        }

        if isShowingChapterIntro,
           let chapter = currentChapter {
            supplementalPlayback.prepareChapterIntro(
                chapterIndex: currentChapterIndex,
                chapter: chapter,
                preferNative: selectedLanguage == .native
            )
            supplementalPlayback.onFinished = {
                finishChapterIntro(andPlayBody: isAutoContinueEnabled)
            }
        }
    }

    private func prepareSupplementalPlaybackForLanguageChangeIfIdle() {
        guard !isPlaying else { return }
        prepareSupplementalPlaybackForCurrentSpineItem()
    }

    private var chapterLanguageToggle: some View {
        Button {
            selectedLanguage = selectedLanguage == .native ? .target : .native
        } label: {
            Text(selectedLanguage == .native ? story.nativeLanguageCode.uppercased() : story.languageBadgeAbbrev)
                .font(.caption.bold())
                .frame(minWidth: 36, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    private var storyTextView: some View {
        if selectedLanguage == .target {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(storyParagraphs) { chunk in
                    ParagraphView(
                        chunk: chunk,
                        activeWordIndex: activeWordIndex,
                        timings: currentChapter?.bodyWordTimingsForLanguage(story.targetLanguageCode) ?? [],
                        wordMatches: wordMatches,
                        onSeek: seekTo,
                        onWordTap: handleWordLookupRequest
                    )
                    .id(chunk.id)
                }
            }
        } else if let currentChapter {
            let nativeText = currentChapter.bodyTextForLanguage(story.nativeLanguageCode)
            VStack(alignment: .leading, spacing: 20) {
                Text(nativeText)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .lineSpacing(10)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var chapterReaderContent: some View {
        Group {
            if isShowingChapterIntro, let chapter = currentChapter {
                ChapterInfoCardView(
                    chapter: chapter,
                    heroImage: heroImage,
                    targetCode: story.targetLanguageCode,
                    nativeCode: story.nativeLanguageCode,
                    selectedLanguage: $selectedLanguage,
                    playbackTime: supplementalPlayback.currentTime,
                    onUserScroll: minimizePlayerForReading
                )
                .id("chapter-intro-\(currentChapterIndex)")
                .onAppear {
                    prepareSupplementalPlaybackForCurrentSpineItem()
                }
                .onChange(of: selectedLanguage) { _, _ in
                    prepareSupplementalPlaybackForLanguageChangeIfIdle()
                }
            } else {
                chapterScrollContent
                    .id("chapter-body-\(currentChapterIndex)")
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    @ViewBuilder
    private var stickyPlayerView: some View {
        if !storyBookSpineItems.isEmpty {
            AudioPlayerBar(
                isPlaying: $isPlaying,
                sliderValue: $sliderValue,
                duration: max(duration, 1),
                playbackRate: $playbackRate,
                ambientVolume: $ambientVolume,
                isAmbientPlaying: audioManager.isAmbientPlaying,
                canSeek: canSeekCurrentSpinePlayback,
                canControlPlayback: canControlCurrentSpinePlayback,
                playbackContextLabel: playerContextLabel,
                isBuffering: isOnSupplementalSpineItem ? supplementalPlayback.isLoading : isDownloadingAudio,
                bufferingLabel: "Downloading audio…",
                isMinimized: isPlayerMinimized,
                showsRateControl: false,
                onPlayPause: togglePlay,
                onSkipForward: skipForward,
                onSkipBackward: skipBackward,
                onSeek: seekTo,
                onChangeRate: setRate,
                onNextChapter: spineStepNavigationHandler(delta: 1),
                onPreviousChapter: spineStepNavigationHandler(delta: -1),
                onShowSpine: toggleSpineController,
                onExpand: expandPlayerController,
                onMinimize: minimizePlayerController
            )
            .disabled((isOnSupplementalSpineItem && supplementalPlayback.isLoading) || (isOnChapterSpineItem && isDownloadingAudio))
            .id("story-book-footer")
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var currentChapter: StoryChapter? {
        if let item = currentSpineItem, let chapter = adapter.chapter(for: item) {
            return chapter
        }
        if let item = storyBookChapterItems.first(where: { chapterIndex(for: $0) == currentChapterIndex }) {
            return adapter.chapter(for: item)
        }
        return story.chapters[safeStorySession: currentChapterIndex]
    }

    private func chapterIndex(for item: StoryReadingSpineItem) -> Int? {
        adapter.chapterIndex(for: item)
    }

    private var hasChapterIntroContent: Bool {
        guard let chapter = currentChapter else { return false }
        return chapter.hasChapterIntroContentForLanguage(story.targetLanguageCode)
    }

    private func finishChapterIntro(andPlayBody: Bool) {
        supplementalPlayback.onFinished = nil
        supplementalPlayback.stop(resetContent: false)
        isShowingChapterIntro = false
        isPlaying = false
        audioManager.streamFinished = false

        Task { @MainActor in
            if andPlayBody {
                didPlayAudio = true
                setupAudio(autoplay: true)
                isPlaying = true
                startAmbient()
            } else {
                setupAudio()
            }
        }
    }

    private func goToSpineIndex(_ index: Int?, showChapterCard: Bool) {
        guard let index, storyBookSpineItems.indices.contains(index) else { return }

        cancelScheduledAutoAdvance()
        stopSupplementalPlayback()

        if isPlaying {
            audioManager.pauseStream()
            audioManager.pauseAmbient()
            isPlaying = false
        }

        currentSpineIndex = index
        activeWordIndex = nil
        activeParagraphId = nil
        sliderValue = 0
        currentSceneClipIndex = 0
        audioManager.streamFinished = false
        isDownloadingAudio = false

        switch storyBookSpineItems[index] {
        case .chapter(let chapterIndex):
            readingMatterHeroImage = nil
            currentChapterIndex = chapterIndex
            loadChapterImage()
            audioManager.stopAudio()
            if showChapterCard, chapterHasIntroContent(at: chapterIndex) {
                isShowingChapterIntro = true
                prepareSupplementalPlaybackForCurrentSpineItem()
                if isAutoContinueEnabled {
                    startAutoContinueForCurrentSpineItem()
                }
            } else {
                isShowingChapterIntro = false
                if isAutoContinueEnabled {
                    setupAudio(autoplay: true)
                } else {
                    setupAudio()
                }
            }
        case .readingMatterPage:
            audioManager.stopAudio()
            isShowingChapterIntro = false
            sliderValue = 0
            duration = 0
            loadReadingMatterImage()
            prepareSupplementalPlaybackForCurrentSpineItem()
            if isAutoContinueEnabled {
                startAutoContinueForCurrentSpineItem()
            }
        case .cover:
            readingMatterHeroImage = nil
            audioManager.stopAudio()
            isShowingChapterIntro = false
            sliderValue = 0
            duration = 0
            loadStoryCoverImage()
            if isAutoContinueEnabled {
                scheduleAutoAdvanceToNextSpineItem()
            }
        case .chapterQuiz(let chapterIndex), .chapterVocabulary(let chapterIndex):
            readingMatterHeroImage = nil
            audioManager.stopAudio()
            isShowingChapterIntro = false
            currentChapterIndex = chapterIndex
            sliderValue = 0
            duration = 0
            loadChapterImage()
            isPlaying = false
        case .scene:
            audioManager.stopAudio()
            isShowingChapterIntro = false
        }

        saveReadingProgress()
    }

    private func reconcileCurrentSpinePosition() {
        guard storyBookSpineItems.indices.contains(currentSpineIndex) else {
            currentSpineIndex = 0
            return
        }

        switch storyBookSpineItems[currentSpineIndex] {
        case .chapter(let chapterIndex):
            currentChapterIndex = chapterIndex
            if chapterHasIntroContent(at: chapterIndex) {
                isShowingChapterIntro = true
                prepareSupplementalPlaybackForCurrentSpineItem()
            }
        case .readingMatterPage:
            isShowingChapterIntro = false
            prepareSupplementalPlaybackForCurrentSpineItem()
        case .chapterQuiz(let chapterIndex), .chapterVocabulary(let chapterIndex):
            currentChapterIndex = chapterIndex
            isShowingChapterIntro = false
        case .cover, .scene:
            isShowingChapterIntro = false
        }

        saveReadingProgress()
    }

    private func saveReadingProgress(position: Double? = nil) {
        guard storyBookSpineItems.indices.contains(currentSpineIndex) else { return }
        onProgressChange?(StoryReaderProgressUpdate(
            index: currentSpineIndex,
            total: storyBookSpineItems.count,
            chapterIndex: progressChapterIndex,
            sceneIndex: progressSceneIndex,
            position: position
        ))
    }

    private func saveTimedReadingProgressIfNeeded(position: Double) {
        let second = Int(position.rounded())
        guard second != lastSavedPlaybackSecond else { return }
        lastSavedPlaybackSecond = second
        saveReadingProgress(position: position)
    }

    private var progressChapterIndex: Int? {
        switch currentSpineItem {
        case .chapter(let index), .scene(let index, _), .chapterQuiz(let index), .chapterVocabulary(let index):
            return index
        default:
            return nil
        }
    }

    private var progressSceneIndex: Int? {
        if isOnChapterSpineItem,
           currentChapterClips.indices.contains(currentSceneClipIndex),
           !currentChapterClips[currentSceneClipIndex].isChapterIntro {
            return currentChapterClips[currentSceneClipIndex].sceneIndex
        }
        if case .scene(_, let sceneIndex) = currentSpineItem {
            return sceneIndex
        }
        return nil
    }

    private func setupInitialChapterAudioIfNeeded() {
        guard !didApplyInitialPlaybackPosition,
              let initialPlaybackPosition,
              initialPlaybackPosition > 0,
              let target = adapter.clipIndex(forChapter: currentChapterIndex, localTime: initialPlaybackPosition) else {
            setupAudio()
            return
        }

        didApplyInitialPlaybackPosition = true
        setupAudio(
            sceneClipIndex: target.index,
            startAt: target.offset
        )
    }

    private func startAutoContinueForCurrentSpineItem() {
        cancelScheduledAutoAdvance()

        if isOnChapterSupplementSpineItem {
            return
        }

        if isOnSupplementalSpineItem {
            if canControlCurrentSpinePlayback {
                toggleSupplementalPlayback(forcePlay: true)
            } else {
                scheduleAutoAdvanceToNextSpineItem()
            }
            return
        }

        if isOnChapterSpineItem {
            if audioManager.streamPlayer == nil {
                setupAudio(autoplay: true)
            } else if !audioManager.isStreaming {
                audioManager.playStream()
                isPlaying = true
                startAmbient()
            }
            return
        }

        scheduleAutoAdvanceToNextSpineItem()
    }

    private func advanceAfterSupplementalFinished() {
        guard isAutoContinueEnabled else {
            isPlaying = false
            return
        }

        if isShowingChapterIntro {
            finishChapterIntro(andPlayBody: true)
            return
        }

        guard let nextSpineIndex else {
            isPlaying = false
            return
        }

        goToSpineIndex(nextSpineIndex, showChapterCard: shouldShowChapterCard(forSpineIndex: nextSpineIndex))
    }

    private func scheduleAutoAdvanceToNextSpineItem(delay: TimeInterval = 2.0) {
        guard isAutoContinueEnabled, let nextSpineIndex else { return }
        autoAdvanceToken += 1
        let token = autoAdvanceToken

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard isAutoContinueEnabled, token == autoAdvanceToken else { return }
            goToSpineIndex(nextSpineIndex, showChapterCard: shouldShowChapterCard(forSpineIndex: nextSpineIndex))
        }
    }

    private func cancelScheduledAutoAdvance() {
        autoAdvanceToken += 1
    }

    private func scheduleSleepTimer(minutes: Int) {
        sleepTimerToken += 1
        let token = sleepTimerToken
        guard minutes > 0 else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(minutes * 60)) {
            guard token == sleepTimerToken, sleepTimerMinutes == minutes else { return }
            pauseForSleepTimer()
        }
    }

    private func pauseForSleepTimer() {
        cancelScheduledAutoAdvance()
        isAutoContinueEnabled = false
        sleepTimerMinutes = 0

        if isOnSupplementalSpineItem {
            supplementalPlayback.pause()
        } else {
            audioManager.pauseStream()
        }

        audioManager.pauseAmbient()
        isPlaying = false
    }

    private func chapterHasIntroContent(at chapterIndex: Int) -> Bool {
        guard story.chapters.indices.contains(chapterIndex) else { return false }
        let chapter = story.chapters[chapterIndex]
        return chapter.hasChapterIntroContentForLanguage(story.targetLanguageCode)
    }

    private func shouldShowChapterCard(forSpineIndex index: Int) -> Bool {
        guard storyBookSpineItems.indices.contains(index) else { return false }
        if case .chapter = storyBookSpineItems[index] { return true }
        return false
    }

    private var currentChapterClips: [StorySceneAudioClip] {
        adapter.audioClips(forChapter: currentChapterIndex)
    }

    private var currentClipStartOffset: Double {
        let clips = currentChapterClips
        guard clips.indices.contains(currentSceneClipIndex) else { return 0 }
        return clips[currentSceneClipIndex].startOffset
    }

    private func advanceAfterSceneClipFinished() {
        guard audioManager.streamFinished else { return }
        audioManager.streamFinished = false

        let clips = currentChapterClips
        if currentSceneClipIndex < clips.count - 1 {
            currentSceneClipIndex += 1
            setupAudio(autoplay: true)
            return
        }

        if let nextSpineIndex {
            goToSpineIndex(nextSpineIndex, showChapterCard: shouldShowChapterCard(forSpineIndex: nextSpineIndex))
            return
        }

        isPlaying = false
    }

    private func loadStoryCoverImage() {
        if let url = storyCoverURL {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data, let uiImage = UIImage(data: data) {
                    DispatchQueue.main.async { heroImage = uiImage }
                }
            }.resume()
            return
        }

        if let filename = story.coverArt {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(filename)
            if let data = try? Data(contentsOf: url), let uiImage = UIImage(data: data) {
                heroImage = uiImage
            }
        }
    }

    private func loadChapterImage() {
        guard let urlString = currentChapter?.coverUrl,
              let url = AppConfig.chapterCoverURL(urlString) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let uiImage = UIImage(data: data) {
                DispatchQueue.main.async { heroImage = uiImage }
            }
        }.resume()
    }

    private func loadReadingMatterImage() {
        guard let item = currentSpineItem,
              let url = adapter.readingMatterImageURL(for: item) else {
            readingMatterHeroImage = nil
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let uiImage = UIImage(data: data) {
                DispatchQueue.main.async { readingMatterHeroImage = uiImage }
            }
        }.resume()
    }

    struct ParagraphChunk: Identifiable, Equatable {
        let id: Int
        let text: String
        let range: NSRange
    }
    
    private var storyParagraphs: [ParagraphChunk] {
        let text = currentChapter?.bodyTextForLanguage(story.targetLanguageCode) ?? ""
        var chunks: [ParagraphChunk] = []
        var currentOffset = 0
        
        let components = text.components(separatedBy: "\n")
        var id = 0
        for comp in components {
            let pLength = (comp as NSString).length
            let range = NSRange(location: currentOffset, length: pLength)
            if !comp.trimmingCharacters(in: .whitespaces).isEmpty {
                chunks.append(ParagraphChunk(id: id, text: comp, range: range))
                id += 1
            }
            currentOffset += pLength + 1 // +1 for the \n
        }
        return chunks
    }
    
    private var wordMatches: [NSTextCheckingResult] {
        let regex = try? NSRegularExpression(pattern: "\\p{L}+", options: [])
        let text = currentChapter?.bodyTextForLanguage(story.targetLanguageCode) ?? ""
        let nsString = text as NSString
        return regex?.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
    }
    
    private func updateScrollState(time: Double) {
        let timings = currentChapter?.bodyWordTimingsForLanguage(story.targetLanguageCode) ?? []
        
        if let idx = timings.firstIndex(where: { time >= $0.start && time <= $0.end }) {
            if activeWordIndex != idx {
                activeWordIndex = idx
                
                // Determine which paragraph contains this word
                let matches = wordMatches
                if idx < matches.count {
                    let activeMatch = matches[idx]
                    // Find paragraph containing this match's range
                    if let pId = storyParagraphs.first(where: { NSLocationInRange(activeMatch.range.location, $0.range) })?.id {
                        if pId != activeParagraphId {
                            activeParagraphId = pId
                        }
                    }
                }
            }
        }
    }

    private var readingScrollGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width),
                      abs(value.translation.height) > 12 else { return }
                minimizePlayerForReading()
            }
    }

    private func minimizePlayerForReading() {
        guard !isPlayerMinimized, !showSpine else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isPlayerMinimized = true
        }
    }

    private func minimizePlayerController() {
        guard !isPlayerMinimized else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isPlayerMinimized = true
        }
    }

    private func minimizePlayerForLandscapeIfNeeded(_ size: CGSize) {
        guard size.width > size.height else { return }
        minimizePlayerController()
    }

    private func toggleSpineController() {
        if usesStoryReaderSidePane {
            showSpine = false
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isStoryBookSidePaneHidden.toggle()
            }
            return
        }

        isPlayerMinimized = false
        showSpine = true
    }

    private func expandPlayerController() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isPlayerMinimized = false
        }
    }
}

private extension Collection {
    subscript(safeStorySession index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Paragraph Subview

private struct StoryBookInsetScrollView<Content: View>: View {
    var spacing: CGFloat = 16
    let bottomSpacer: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let proseWidth = StoryBookLayout.readableContentWidth(in: geo.size.width)

            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    content()
                    Color.clear.frame(height: bottomSpacer)
                }
                .frame(width: proseWidth, alignment: .leading)
                .padding(.horizontal, StoryBookLayout.horizontalPadding)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct StoryBookReadingMatterPageView: View {
    let heroImage: UIImage?
    let imageURL: URL?
    let title: String?
    let bodyText: String?
    let isUsingGeneratedAudio: Bool
    let playbackTime: Double
    let wordTimings: [WordTiming]
    let useNativeLanguage: Bool
    let bottomSpacer: CGFloat
    var onUserScroll: () -> Void = {}

    var body: some View {
        GeometryReader { geo in
            let proseWidth = StoryBookLayout.readableContentWidth(in: geo.size.width)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroSection(proseWidth: proseWidth)

                    if let title {
                        Text(title)
                            .font(.title2.weight(.bold))
                            .frame(width: proseWidth, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    bodySection(proseWidth: proseWidth)

                    Color.clear.frame(height: bottomSpacer)
                }
                .frame(width: proseWidth, alignment: .leading)
                .padding(.horizontal, StoryBookLayout.horizontalPadding)
                .padding(.top, 8)
            }
            .simultaneousGesture(readingScrollGesture)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var readingScrollGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width),
                      abs(value.translation.height) > 12 else { return }
                onUserScroll()
            }
    }

    @ViewBuilder
    private func heroSection(proseWidth: CGFloat) -> some View {
        Group {
            if let heroImage {
                Image(uiImage: heroImage)
                    .resizable()
                    .scaledToFill()
            } else if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure, .empty:
                        heroPlaceholder
                    @unknown default:
                        heroPlaceholder
                    }
                }
            } else {
                heroPlaceholder
            }
        }
        .frame(width: proseWidth, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var heroPlaceholder: some View {
        LinearGradient(
            colors: [.accentColor, .accentColor.opacity(0.6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private func bodySection(proseWidth: CGFloat) -> some View {
        if let bodyText {
            if !useNativeLanguage, isUsingGeneratedAudio, !wordTimings.isEmpty {
                TimedTextView(
                    segment: StorySegmentTiming(
                        speaker: "",
                        text: bodyText,
                        startTime: 0,
                        endTime: .greatestFiniteMagnitude,
                        timings: WordTiming.bodyTimings(
                            fullTimings: wordTimings,
                            skippingLeadingSpokenText: title
                        )
                    ),
                    currentTime: playbackTime,
                    includesPadding: false
                )
                .frame(width: proseWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                if useNativeLanguage {
                    Text(bodyText)
                        .font(.body)
                        .lineSpacing(8)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(width: proseWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    TappableStoryText(
                        text: bodyText,
                        font: .body,
                        lineSpacing: 8,
                        foregroundColor: .primary
                    )
                    .frame(width: proseWidth, alignment: .leading)
                }
            }
        }
    }
}

struct ParagraphView: View {
    let chunk: StorySessionView.ParagraphChunk
    let activeWordIndex: Int?
    let timings: [WordTiming]
    let wordMatches: [NSTextCheckingResult]
    let onSeek: (Double) -> Void
    let onWordTap: (StoryWordLookupRequest) -> Void

    var body: some View {
        Text(attributedParagraph)
            .font(.system(size: 18, weight: .regular, design: .serif))
            .lineSpacing(10)
            .tint(.primary)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "x-learnci-word",
                   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let word = components.queryItems?.first(where: { $0.name == "word" })?.value {
                    let queryItems = components.queryItems ?? []
                    let targetTime = queryItems.first(where: { $0.name == "t" })?.value.flatMap(Double.init)
                    let endTime = queryItems.first(where: { $0.name == "e" })?.value.flatMap(Double.init)
                    let wordIndex = queryItems.first(where: { $0.name == "i" })?.value.flatMap(Int.init)
                    onWordTap(
                        StoryWordLookupRequest(
                            word: word,
                            time: targetTime,
                            endTime: endTime,
                            context: sentenceContaining(word: word, in: chunk.text),
                            wordIndex: wordIndex,
                            sourceText: chunk.text
                        )
                    )
                    return .handled
                }
                if url.scheme == "x-learnci-seek",
                   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let tStr = components.queryItems?.first(where: { $0.name == "t" })?.value,
                   let targetTime = Double(tStr) {
                    onSeek(targetTime)
                    return .handled
                }
                return .systemAction
            })
    }

    private var attributedParagraph: AttributedString {
        var attrString = AttributedString(chunk.text)

        if chunk.text.isEmpty {
            return attrString
        }

        for (i, match) in wordMatches.enumerated() {
            // Focus only on matches inside this chunk
            if NSLocationInRange(match.range.location, chunk.range) {
                let localRange = NSRange(location: match.range.location - chunk.range.location, length: match.range.length)

                if let swiftRange = Range(localRange, in: chunk.text),
                   let lowerBound = AttributedString.Index(swiftRange.lowerBound, within: attrString),
                   let upperBound = AttributedString.Index(swiftRange.upperBound, within: attrString) {

                    let attrRange = lowerBound..<upperBound

                    let matchedWord = String(chunk.text[swiftRange])
                    let encoded = matchedWord.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? matchedWord
                    if i < timings.count {
                        let timing = timings[i]
                        attrString[attrRange].link = URL(string: "x-learnci-word://?word=\(encoded)&i=\(i)&t=\(timing.start)&e=\(timing.end)")
                    } else {
                        attrString[attrRange].link = URL(string: "x-learnci-word://?word=\(encoded)&i=\(i)")
                    }

                    // Highlight active
                    if i == activeWordIndex {
                        attrString[attrRange].foregroundColor = .blue
                        attrString[attrRange].font = .system(size: 19, weight: .bold, design: .serif)
                    }
                }
            }
        }
        return attrString
    }

    private func sentenceContaining(word: String, in text: String) -> String? {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?。！？\n"))
        return sentences
            .first(where: { $0.localizedCaseInsensitiveContains(word) })?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Subviews

// MARK: - HeroMediaView
// Shows looping video if available, static cover image otherwise.
// Overlays a "Generate Video" button when neither exists yet.

struct HeroMediaView: View {
    let story: Story
    @Binding var image: UIImage?
    let isGeneratingVideo: Bool
    let videoStatus: String?
    let videoError: String?
    var onGenerateVideo: () -> Void
    /// Set to false to hide the "Generate Video" overlay badge (e.g. when the action
    /// is surfaced via a menu instead). The generating progress overlay still shows.
    var showGenerateButton: Bool = true
    var coverContentMode: ContentMode = .fill
    var usesScrollRevealEffect: Bool = true
    var showsVideo: Bool = true
    var showsGradientOverlay: Bool = true

    @State private var localVideoURL: URL? = nil

    private let supabaseBase = "https://vuygqrbludhuywupcbma.supabase.co/storage/v1/object/public/audio-stories"
    private let supabaseVideoBase = "https://vuygqrbludhuywupcbma.supabase.co/storage/v1/object/public/audio-stories"

    var body: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .global).minY
            let mediaHeight = geo.size.height + (usesScrollRevealEffect && minY > 0 ? minY : 0)
            let mediaOffset = usesScrollRevealEffect && minY > 0 ? -minY : 0

            ZStack(alignment: .bottomTrailing) {
                // 1. Video layer (priority)
                if showsVideo, let videoURL = localVideoURL {
                    LoopingVideoPlayerView(url: videoURL)
                        .frame(width: geo.size.width, height: mediaHeight)
                        .clipped()
                        .offset(y: mediaOffset)

                // 2. Static cover image fallback
                } else if let validImage = image {
                    Image(uiImage: validImage)
                        .resizable()
                        .aspectRatio(contentMode: coverContentMode)
                        .frame(width: geo.size.width, height: mediaHeight)
                        .clipped()
                        .offset(y: mediaOffset)

                // 3. Placeholder while loading
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(ProgressView())
                }

                // Gradient for text readability
                if showsGradientOverlay {
                    LinearGradient(
                        colors: [.black.opacity(0.55), .clear, .black.opacity(0.15)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                }

                // Video generation overlay
                if isGeneratingVideo {
                    generatingOverlay
                        .padding(12)
                } else if let err = videoError {
                    errorBadge(err)
                        .padding(12)
                } else if (localVideoURL == nil || !showsVideo) && showGenerateButton {
                    generateButton
                        .padding(12)
                }
            }
            .onAppear { loadMedia() }
            .onChange(of: isGeneratingVideo) { _, generating in
                // When generation finishes, the file now exists on disk — reload.
                if !generating { loadMedia() }
            }
        }
    }

    // MARK: Overlay badges

    private var generateButton: some View {
        Button(action: onGenerateVideo) {
            Label("Generate Video", systemImage: "video.badge.plus")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
        .foregroundStyle(.white)
    }

    private var generatingOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().tint(.white).scaleEffect(0.8)
                Text(videoStatus ?? "Starting…")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
            Text("Keep the app open · up to 6 min")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func errorBadge(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Video failed")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .foregroundStyle(.white)
    }

    // MARK: Media loading

    private func loadMedia() {
        guard showsVideo else {
            localVideoURL = nil
            loadCoverImage()
            return
        }

        let storyLabel = "\(story.title) (\(story.id.uuidString.prefix(8))…)"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // Generated video: written by VeoService, uploaded by SyncManager
        let generatedURL = docs.appendingPathComponent("video_\(story.id.uuidString).mp4")
        // Remote cache: downloaded copy of the current remote version (always refreshed when remoteVideoPath changes)
        let remoteCacheURL = docs.appendingPathComponent("video_\(story.id.uuidString)_remote.mp4")

        let hasLocalGenerated = FileManager.default.fileExists(atPath: generatedURL.path)
        let remoteCacheSize   = (try? FileManager.default.attributesOfItem(atPath: remoteCacheURL.path)[.size] as? Int) ?? 0
        let hasValidRemoteCache = remoteCacheSize > 10_000  // treat < 10KB as a corrupt/empty download

        print("[HeroMedia] \(storyLabel)")
        print("[HeroMedia]   remoteVideoPath : \(story.remoteVideoPath ?? "nil")")
        print("[HeroMedia]   local generated : \(hasLocalGenerated ? "✅ exists" : "❌ none")")
        print("[HeroMedia]   remote cache    : \(remoteCacheSize > 0 ? "✅ \(remoteCacheSize / 1024)KB" : "❌ none") \(hasValidRemoteCache ? "" : remoteCacheSize > 0 ? "(⚠️ too small — discarding)" : "")")

        // Discard corrupt/empty remote cache so we re-download
        if remoteCacheSize > 0 && !hasValidRemoteCache {
            print("[HeroMedia]   ⚠️ Deleting corrupt remote cache and re-downloading…")
            try? FileManager.default.removeItem(at: remoteCacheURL)
        }

        // 1. Remote path is set → remote (DB) is the source of truth.
        //    Use the cached download if it exists; otherwise download fresh.
        if let remotePath = story.remoteVideoPath {
            if hasValidRemoteCache {
                print("[HeroMedia]   → showing remote cache (DB is source of truth)")
                self.localVideoURL = remoteCacheURL
                return
            }
            // Build the remote URL (handle legacy full URL or new relative path)
            let remoteURL: URL?
            if remotePath.hasPrefix("https://") {
                remoteURL = URL(string: remotePath)
            } else {
                remoteURL = URL(string: "\(supabaseVideoBase)/\(remotePath)")
            }
            if let url = remoteURL {
                // Show local generated file immediately as fallback while download is in flight
                if hasLocalGenerated {
                    print("[HeroMedia]   → showing local fallback while remote downloads…")
                    self.localVideoURL = generatedURL
                } else {
                    print("[HeroMedia]   → no local fallback, waiting for remote download…")
                }
                print("[HeroMedia]   → downloading: \(url.absoluteString.prefix(80))…")
                Task {
                    do {
                        let (data, response) = try await URLSession.shared.data(from: url)
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                        guard statusCode == 200 else {
                            print("[HeroMedia]   ❌ HTTP \(statusCode) — not a valid video response")
                            if !hasLocalGenerated { await MainActor.run { self.loadCoverImage() } }
                            return
                        }
                        guard data.count > 10_000 else {
                            print("[HeroMedia]   ❌ downloaded only \(data.count) bytes — not a valid video")
                            if !hasLocalGenerated { await MainActor.run { self.loadCoverImage() } }
                            return
                        }
                        try data.write(to: remoteCacheURL)
                        print("[HeroMedia]   ✅ remote download succeeded (\(data.count / 1024)KB) — switching to remote cache")
                        await MainActor.run { self.localVideoURL = remoteCacheURL }
                    } catch {
                        print("[HeroMedia]   ❌ download error: \(error.localizedDescription)")
                        if !hasLocalGenerated { await MainActor.run { self.loadCoverImage() } }
                    }
                }

                return
            }
        }

        // 2. No remote path yet — show the locally generated file while sync is pending
        if hasLocalGenerated {
            print("[HeroMedia]   → no remote path, showing local generated (pending sync)")
            self.localVideoURL = generatedURL
            return
        }

        // 3. No video at all — fall back to cover image
        print("[HeroMedia]   → no video, loading cover image")
        loadCoverImage()
    }

    /// Call this to force a fresh download of the remote video (e.g. after user uploads a new one).
    func invalidateRemoteVideoCache() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let remoteCacheURL = docs.appendingPathComponent("video_\(story.id.uuidString)_remote.mp4")
        try? FileManager.default.removeItem(at: remoteCacheURL)
        localVideoURL = nil
        loadMedia()
    }

    private func loadCoverImage() {
        if let remotePath = story.remoteCoverPath,
           let url = URL(string: "\(supabaseBase)/\(remotePath)") {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data, let uiImage = UIImage(data: data) {
                    DispatchQueue.main.async { self.image = uiImage }
                } else {
                    loadLocalCoverFallback()
                }
            }.resume()
        } else {
            loadLocalCoverFallback()
        }
    }

    private func loadLocalCoverFallback() {
        if let filename = story.coverArt {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
            if let data = try? Data(contentsOf: url), let uiImage = UIImage(data: data) {
                self.image = uiImage
            }
        }
    }
}

private struct StoryBookPlayerSheet: View {
    let spineItems: [StoryReadingSpineItem]
    let currentSpineIndex: Int
    let adapter: StoryReaderDataAdapter
    @Binding var isAutoContinueEnabled: Bool
    @Binding var sleepTimerMinutes: Int
    @Binding var playbackRate: Float
    let onChangeRate: (Float) -> Void
    let onSelect: (Int) -> Void

    private let playbackRates: [Float] = [0.75, 1.0, 1.25, 1.5]
    private let timerOptions = [0, 5, 10, 15, 30]

    var body: some View {
        NavigationStack {
            List {
                Section("Playback") {
                    Toggle(isOn: $isAutoContinueEnabled) {
                        Label("Auto Play", systemImage: "play.circle")
                    }

                    Picker(selection: $sleepTimerMinutes) {
                        ForEach(timerOptions, id: \.self) { minutes in
                            Text(timerLabel(for: minutes)).tag(minutes)
                        }
                    } label: {
                        Label("Timer", systemImage: "timer")
                    }

                    HStack(spacing: 12) {
                        Label("Speed", systemImage: "speedometer")
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Picker("Speed", selection: speedBinding) {
                            ForEach(playbackRates, id: \.self) { rate in
                                Text("\(String(format: "%.2g", rate))x").tag(rate)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 210)
                    }
                }

                Section("Chapter Navigation") {
                    ForEach(Array(spineItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            onSelect(index)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: icon(for: item))
                                    .frame(width: 24)
                                    .foregroundStyle(index == currentSpineIndex ? Color.accentColor : .secondary)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(StoryReadingSpineTitles.spinePrimaryTitle(
                                        for: item,
                                        story: adapter.story,
                                        adapter: adapter
                                    ))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                    Text(StoryReadingSpineTitles.spinePositionLabel(
                                        index: index,
                                        total: spineItems.count,
                                        context: StoryReadingSpineTitles.spineContextLabel(
                                            for: item,
                                            story: adapter.story,
                                            adapter: adapter
                                        )
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if index == currentSpineIndex {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Player")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var speedBinding: Binding<Float> {
        Binding(
            get: { playbackRate },
            set: { rate in
                playbackRate = rate
                onChangeRate(rate)
            }
        )
    }

    private func timerLabel(for minutes: Int) -> String {
        minutes == 0 ? "Off" : "\(minutes)m"
    }

    private func icon(for item: StoryReadingSpineItem) -> String {
        switch item {
        case .cover:
            return "book.closed"
        case .readingMatterPage:
            return "doc.text"
        case .chapter:
            return "text.book.closed"
        case .chapterQuiz:
            return "checkmark.circle"
        case .chapterVocabulary:
            return "text.book.closed.fill"
        case .scene:
            return "photo"
        }
    }
}

struct AudioPlayerBar: View {
    @Binding var isPlaying: Bool
    @Binding var sliderValue: Double
    let duration: Double
    @Binding var playbackRate: Float
    @Binding var ambientVolume: Float
    let isAmbientPlaying: Bool
    var canSeek: Bool = true
    var canControlPlayback: Bool = true
    var playbackContextLabel: String? = nil
    var isBuffering: Bool = false
    var bufferingLabel: String = "Buffering…"
    var isMinimized: Bool = false
    var showsRateControl: Bool = true

    var onPlayPause: () -> Void
    var onSkipForward: () -> Void
    var onSkipBackward: () -> Void
    var onSeek: (Double) -> Void
    var onChangeRate: (Float) -> Void
    
    var onNextChapter: (() -> Void)? = nil
    var onPreviousChapter: (() -> Void)? = nil
    var onSkipPreviousChapter: (() -> Void)? = nil
    var onSkipNextChapter: (() -> Void)? = nil
    var onShowSpine: (() -> Void)? = nil
    var onExpand: (() -> Void)? = nil
    var onMinimize: (() -> Void)? = nil

    @State private var isScrubbing = false
    @State private var scrubberPreviewValue: Double = 0

    private var displayedSliderValue: Double {
        isScrubbing ? scrubberPreviewValue : sliderValue
    }

    var body: some View {
        Group {
            if isMinimized {
                minimizedBody
            } else {
                expandedBody
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var minimizedBody: some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 44, height: 5)
                .accessibilityHidden(true)

            Text(formatTime(displayedSliderValue))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(canControlPlayback ? .white : .secondary)
                    .frame(width: 38, height: 38)
                    .background(canControlPlayback ? Color.accentColor : Color(.systemGray5))
                    .clipShape(Circle())
            }
            .disabled(!canControlPlayback)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(
            Rectangle()
                .fill(.thinMaterial)
                .cornerRadius(24, corners: [.topLeft, .topRight])
                .ignoresSafeArea(edges: .bottom)
        )
        .shadow(radius: 8, y: -4)
        .contentShape(Rectangle())
        .onTapGesture { onExpand?() }
        .gesture(
            DragGesture(minimumDistance: 8)
                .onEnded { value in
                    if value.translation.height < -12 {
                        onExpand?()
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Minimized audio player")
        .accessibilityHint("Swipe up or tap to show playback controls")
    }

    private var expandedBody: some View {
        VStack(spacing: 12) {
            if let onMinimize {
                HStack {
                    Spacer()
                    Button(action: onMinimize) {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 28)
                            .background(Color(.secondarySystemBackground).opacity(0.85))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Minimize player")
                }
                .padding(.horizontal, 20)
            }

            if isBuffering {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(bufferingLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .padding(.top, 4)
            }

            if let playbackContextLabel {
                Text(playbackContextLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)
            }

            // Ambient volume row — only visible while ambient audio is active
            if isAmbientPlaying {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Slider(value: $ambientVolume, in: 0...1)
                        .tint(.secondary)
                    Image(systemName: "music.note.list")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }

            HStack(spacing: 8) {
                Text(formatTime(displayedSliderValue))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)

                Slider(value: Binding(
                    get: { displayedSliderValue },
                    set: { newValue in
                        guard canSeek else { return }
                        scrubberPreviewValue = min(max(0, newValue), duration)
                    }
                ), in: 0...duration) { editing in
                    guard canSeek else { return }
                    if editing {
                        scrubberPreviewValue = sliderValue
                        isScrubbing = true
                    } else {
                        let seekValue = min(max(0, scrubberPreviewValue), duration)
                        sliderValue = seekValue
                        isScrubbing = false
                        onSeek(seekValue)
                    }
                }
                .disabled(!canSeek)

                Text(formatTime(duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .opacity(canSeek ? 1 : 0.55)

            if onSkipPreviousChapter != nil || onSkipNextChapter != nil {
                HStack(spacing: 12) {
                    Button {
                        onSkipPreviousChapter?()
                    } label: {
                        Image(systemName: "chevron.left.2")
                            .font(.caption.weight(.semibold))
                    }
                    .disabled(onSkipPreviousChapter == nil)
                    .opacity(onSkipPreviousChapter == nil ? 0.35 : 1)

                    Spacer()

                    Text("Chapter")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        onSkipNextChapter?()
                    } label: {
                        Image(systemName: "chevron.right.2")
                            .font(.caption.weight(.semibold))
                    }
                    .disabled(onSkipNextChapter == nil)
                    .opacity(onSkipNextChapter == nil ? 0.35 : 1)
                }
                .padding(.horizontal, 28)
            }
            
            StoryPlaybackControls(
                isPlaying: isPlaying,
                playbackRate: playbackRate,
                canGoPrevious: onPreviousChapter != nil,
                canGoNext: onNextChapter != nil,
                canPlayPause: canControlPlayback,
                onPlayPause: onPlayPause,
                onPrevious: { onPreviousChapter?() },
                onNext: { onNextChapter?() },
                onChangeRate: onChangeRate,
                showsRateControl: showsRateControl,
                onShowSpine: onShowSpine
            )
            .padding(.horizontal)
        }
        .padding(.top, onMinimize == nil ? 20 : 10)
        .padding(.bottom, 20)
        .background(
            Rectangle()
                .fill(.thinMaterial)
                .cornerRadius(24, corners: [.topLeft, .topRight])
                .ignoresSafeArea(edges: .bottom)
        )
        .shadow(radius: 10, y: -5)
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct StoryPlaybackControls: View {
    let isPlaying: Bool
    let playbackRate: Float
    let canGoPrevious: Bool
    let canGoNext: Bool
    var canPlayPause: Bool = true
    let onPlayPause: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onChangeRate: (Float) -> Void
    var showsRateControl: Bool = true
    var onShowSpine: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            circleButton(
                systemName: "backward.end.fill",
                isEnabled: canGoPrevious,
                action: onPrevious
            )
            .disabled(!canGoPrevious)

            circleButton(
                systemName: isPlaying ? "pause.fill" : "play.fill",
                diameter: 52,
                isEnabled: canPlayPause,
                action: onPlayPause
            )
            .disabled(!canPlayPause)

            circleButton(
                systemName: "forward.end.fill",
                isEnabled: canGoNext,
                action: onNext
            )
            .disabled(!canGoNext)

            if showsRateControl {
                if canPlayPause {
                    Menu {
                        Button("0.75x") { onChangeRate(0.75) }
                        Button("1.0x") { onChangeRate(1.0) }
                        Button("1.25x") { onChangeRate(1.25) }
                        Button("1.5x") { onChangeRate(1.5) }
                    } label: {
                        playbackRateLabel
                    }
                } else {
                    playbackRateLabel
                        .opacity(0.45)
                        .allowsHitTesting(false)
                }
            }

            AirPlayRoutePicker()
                .frame(width: 44, height: 44)

            if let onShowSpine {
                circleButton(
                    systemName: "list.bullet",
                    isEnabled: true,
                    action: onShowSpine
                )
            }
        }
    }

    private var playbackRateLabel: some View {
        Text("\(String(format: "%.1f", playbackRate))x")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: 52, height: 44)
            .background(Color.accentColor)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
    }

    private func circleButton(
        systemName: String,
        diameter: CGFloat = 44,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: diameter == 52 ? 18 : 15, weight: .bold))
                .foregroundStyle(isEnabled ? .white : .secondary)
                .frame(width: diameter, height: diameter)
                .background(isEnabled ? Color.accentColor : Color(.systemGray5))
                .clipShape(Circle())
                .shadow(color: isEnabled ? .black.opacity(0.16) : .clear, radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }
}

private struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.activeTintColor = UIColor(Color.accentColor)
        picker.tintColor = UIColor.label
        picker.prioritizesVideoDevices = false
        picker.backgroundColor = .clear
        picker.accessibilityLabel = "AirPlay Audio"
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.activeTintColor = UIColor(Color.accentColor)
        uiView.tintColor = UIColor.label
    }
}

// Helper for rounded corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// MARK: - Story Info Sheet

struct StoryInfoSheet: View {
    let story: Story
    @Environment(\.dismiss) private var dismiss

    private var preferences: StoryPreferences {
        guard let json = story.preferencesJSON, let data = json.data(using: .utf8) else {
            return StoryPreferences()
        }
        return (try? JSONDecoder().decode(StoryPreferences.self, from: data)) ?? StoryPreferences()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    infoRow(label: "Title", value: story.title)

                    // Language & Level
                    infoRow(label: "Language", value: story.language.displayName)
                    infoRow(label: "Level", value: "\(story.level) - \(LevelManager.shared.description(for: story.level))")

                    // Topic
                    if let prompt = story.prompt, !prompt.isEmpty {
                        infoRow(label: "Topic", value: prompt)
                    }

                    Divider()

                    // Preferences
                    Text("Story Settings")
                        .font(.headline)

                    let prefs = preferences
                    infoRow(label: "Genre", value: prefs.genre.rawValue)
                    infoRow(label: "Length", value: prefs.storyLength.rawValue)
                    infoRow(label: "Ending", value: prefs.endingType.rawValue)
                    infoRow(label: "Dialogue", value: prefs.dialogueAmount.rawValue)
                    infoRow(label: "Voice", value: prefs.voice.displayName)
                    infoRow(label: "Cover Style", value: prefs.coverArtStyle.rawValue)

                    if !prefs.protagonistName.isEmpty {
                        infoRow(label: "Protagonist", value: "\(prefs.protagonistName) (\(prefs.protagonistGender.rawValue))")
                    }

                    // Keywords / Vocabulary
                    if !prefs.targetVocabulary.isEmpty {
                        infoRow(label: "Target Vocabulary", value: prefs.targetVocabulary)
                    }

                    if !prefs.grammarFocus.isEmpty {
                        infoRow(label: "Grammar Focus", value: prefs.grammarFocus)
                    }

                    Divider()

                    // Date
                    infoRow(label: "Created", value: story.createdAt.formatted(date: .long, time: .shortened))
                }
                .padding()
            }
            .navigationTitle("Story Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Quiz Banner

struct QuizBannerView: View {
    let onTakeQuiz: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Story complete!")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Test your comprehension")
                    .font(.subheadline.bold())
            }
            Spacer()
            Button(action: onTakeQuiz) {
                Text("Take Quiz →")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial)
        .cornerRadius(16, corners: [.topLeft, .topRight])
        .shadow(radius: 4, y: -2)
    }
}

// MARK: - Comprehension Quiz Sheet

struct ComprehensionQuizSheet: View {
    let questions: [ComprehensionQuestion]
    let isLoading: Bool
    let language: Language
    var onRetry: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex: Int = 0
    @State private var selectedAnswer: Int? = nil
    @State private var score: Int = 0
    @State private var isComplete: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && questions.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.3)
                        Text("Generating questions…")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isComplete {
                    quizResultsView
                } else if !questions.isEmpty {
                    questionView
                } else {
                    // Generation failed or returned empty
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("Couldn't load questions")
                            .font(.headline)
                        Text("Check your connection and try again.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { onRetry?() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Comprehension Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var questionView: some View {
        let question = questions[currentIndex]
        return VStack(alignment: .leading, spacing: 0) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: geo.size.width * CGFloat(currentIndex + 1) / CGFloat(questions.count))
                        .animation(.easeInOut, value: currentIndex)
                }
            }
            .frame(height: 4)
            .padding(.horizontal)
            .padding(.bottom, 12)

            Text("Question \(currentIndex + 1) of \(questions.count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(question.question)
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .lineSpacing(6)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    VStack(spacing: 10) {
                        ForEach(question.choices.indices, id: \.self) { idx in
                            Button {
                                guard selectedAnswer == nil else { return }
                                selectedAnswer = idx
                                if idx == question.correctIndex { score += 1 }
                            } label: {
                                HStack {
                                    Text(["A", "B", "C", "D"][idx])
                                        .font(.caption.bold())
                                        .frame(width: 24, height: 24)
                                        .background(choiceBadgeColor(idx: idx, correctIndex: question.correctIndex))
                                        .clipShape(Circle())
                                        .foregroundColor(.white)
                                    Text(question.choices[idx])
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                }
                                .padding()
                                .background(choiceBackground(idx: idx, correctIndex: question.correctIndex))
                                .cornerRadius(12)
                            }
                            .disabled(selectedAnswer != nil)
                        }
                    }
                    .padding(.horizontal)

                    if selectedAnswer != nil {
                        Button {
                            if currentIndex + 1 < questions.count {
                                currentIndex += 1
                                selectedAnswer = nil
                            } else {
                                isComplete = true
                            }
                        } label: {
                            Text(currentIndex + 1 < questions.count ? "Next →" : "See Results")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedAnswer)
                .padding(.bottom, 30)
            }
        }
        .padding(.top, 8)
    }

    private var quizResultsView: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 12)
                    .frame(width: 120, height: 120)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / CGFloat(questions.count))
                    .stroke(score >= (questions.count * 3 / 4) ? Color.green : Color.orange, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 120, height: 120)
                    .animation(.easeOut(duration: 0.8), value: score)
                VStack(spacing: 2) {
                    Text("\(score)")
                        .font(.system(size: 40, weight: .bold))
                    Text("of \(questions.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            VStack(spacing: 8) {
                Text(score >= (questions.count * 3 / 4) ? "Great job!" : "Keep practicing!")
                    .font(.title2.bold())
                Text(score >= (questions.count * 3 / 4)
                    ? "You understood the story well."
                    : "Try re-reading the story and take the quiz again.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            Button("Done") { dismiss() }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.bottom, 20)
        }
    }

    private func choiceBackground(idx: Int, correctIndex: Int) -> Color {
        guard let selected = selectedAnswer else { return Color(.secondarySystemBackground) }
        if idx == correctIndex { return Color.green.opacity(0.15) }
        if idx == selected { return Color.red.opacity(0.15) }
        return Color(.secondarySystemBackground)
    }

    private func choiceBadgeColor(idx: Int, correctIndex: Int) -> Color {
        guard let selected = selectedAnswer else { return Color.secondary.opacity(0.4) }
        if idx == correctIndex { return Color.green }
        if idx == selected { return Color.red }
        return Color.secondary.opacity(0.3)
    }
}

// MARK: - Word Lookup Sheet

struct WordLookupSheet: View {
    let word: String
    let languageLabel: String
    let translation: String?
    let partOfSpeech: String?
    var details: WordTranslationResult? = nil
    let isLoading: Bool
    let seekTime: Double?
    let onSeek: (Double) -> Void
    var onSelectPhrase: (() -> Void)? = nil
    var onMarkForStudy: (() -> Void)? = nil
    var isMarkedForStudy: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Word or phrase + language badge
                        Text(word)
                            .font(.system(size: 20, weight: .semibold, design: .serif))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)

                        Text(languageLabel)
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())

                        // Part of speech
                        if let pos = partOfSpeech, !pos.isEmpty {
                            Text(pos)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .italic()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Divider()
                        .padding(.vertical, 16)

                    // Translation
                    Group {
                        if isLoading {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Translating...")
                                    .foregroundColor(.secondary)
                            }
                        } else if let t = translation, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(t)
                                    .font(.system(size: 22, weight: .regular))
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)

                                lookupDetailsView
                            }
                        } else {
                            Text("Translation unavailable.")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }

                Spacer()

                if let onMarkForStudy {
                    SaveForStudyControl(
                        isSaved: isMarkedForStudy,
                        style: .prominentButton,
                        action: onMarkForStudy
                    )
                    .disabled(isLoading)
                    .padding(.horizontal)
                    .padding(.bottom, onSelectPhrase == nil && seekTime == nil ? 20 : 8)
                }

                if let onSelectPhrase {
                    Button {
                        onSelectPhrase()
                        dismiss()
                    } label: {
                        Label("Select phrase", systemImage: "text.cursor")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.secondary.opacity(0.12))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, seekTime == nil ? 20 : 8)
                    .disabled(isLoading)
                }

                // Seek button
                if let time = seekTime {
                    Button {
                        onSeek(time)
                        dismiss()
                    } label: {
                        Label("Jump to this word in audio", systemImage: "arrow.right.circle")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Word Lookup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var lookupDetailsView: some View {
        if let details {
            let rows = lookupDetailRows(details)
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows, id: \.label) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(row.value)
                                .font(.subheadline)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func lookupDetailRows(_ details: WordTranslationResult) -> [(label: String, value: String)] {
        [
            ("Lemma", details.lemma),
            ("Level", details.level),
            ("Verb tense", details.verbTense),
            ("Grammar", details.grammarNotes),
            ("Usage", details.usageNote),
            ("Example", details.exampleTarget),
            ("Example translation", details.exampleEnglish)
        ].compactMap { label, value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : (label, trimmed)
        }
    }
}

// MARK: - Story Prompts Sheet

struct StoryPromptsSheet: View {
    let story: Story
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var localTextPrompt: String?
    @State private var localImagePrompt: String?
    @State private var isRecreating: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    promptSection(title: "User Topic", content: story.prompt ?? "N/A")

                    Divider()

                    promptSection(
                        title: "Text Generation Prompt",
                        content: localTextPrompt ?? story.textGenPrompt ?? "Not saved."
                    )

                    promptSection(
                        title: "Image Generation Prompt",
                        content: localImagePrompt ?? story.imageGenPrompt ?? "Not saved."
                    )

                    Button(action: recreatePrompts) {
                        HStack {
                            if isRecreating {
                                ProgressView()
                                    .padding(.trailing, 5)
                            }
                            Text("Recreate Prompts from Preferences")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                    }
                    .disabled(isRecreating)
                }
                .padding()
            }
            .navigationTitle("AI Prompts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func promptSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(action: {
                    UIPasteboard.general.string = content
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
            Text(content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                .textSelection(.enabled)
        }
    }

    private func recreatePrompts() {
        isRecreating = true
        Task {
            let decoder = JSONDecoder()
            let prefs: StoryPreferences
            if let json = story.preferencesJSON, let data = json.data(using: .utf8) {
                prefs = (try? decoder.decode(StoryPreferences.self, from: data)) ?? StoryPreferences()
            } else {
                prefs = StoryPreferences()
            }

            let service = OpenAIService()

            let textPrompt = await service.constructStoryPrompt(
                topic: story.prompt ?? "",
                language: story.language.displayName,
                level: LevelManager.shared.description(for: story.level),
                preferences: prefs
            )

            let imagePrompt = service.constructCoverArtPrompt(
                title: story.title,
                topic: story.prompt ?? "",
                style: prefs.coverArtStyle
            )

            await MainActor.run {
                self.localTextPrompt = textPrompt
                self.localImagePrompt = imagePrompt

                if story.textGenPrompt == nil { story.textGenPrompt = textPrompt }
                if story.imageGenPrompt == nil { story.imageGenPrompt = imagePrompt }
                try? modelContext.save()

                isRecreating = false
            }
        }
    }
}

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
    @Environment(AudioManager.self) private var audioManager
    @Environment(AmbientSoundManager.self) private var ambientSoundManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
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
    @State private var selectedLanguage: DisplayLanguage = .target
    @State private var heroImage: UIImage? = nil
    @State private var readingMatterHeroImage: UIImage? = nil
    
    // Auto-Scroll State
    @State private var activeWordIndex: Int? = nil
    @State private var activeParagraphId: Int? = nil
    
    // Analytics
    @State private var startTime: Date?
    @State private var didPlayAudio: Bool = false

    // Chapter intro vs body within the same chapter spine step.
    @State private var isShowingChapterIntro: Bool = false

    // Reading matter playback: generated audio when present, otherwise TTS.
    @State private var readingMatterSynthesizer = AVSpeechSynthesizer()
    @State private var readingMatterSpeechFinishTask: DispatchWorkItem?
    @State private var isReadingMatterUsingGeneratedAudio = false

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
    @State private var isTranslatingWord: Bool = false
    @State private var showWordLookup: Bool = false
    @State private var wordTranslationCache: [String: (translation: String, pos: String)] = [:]
    
    enum DisplayLanguage: String, CaseIterable {
        case target = "Target Language"
        case native = "English"
    }
    
    // Timer to update scrubber
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    private var adapter: StoryReaderDataAdapter {
        StoryReaderDataAdapter(story: story)
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
                return { finishChapterIntro(andPlayBody: false) }
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
    }

    private var readerBody: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                storyBookSpineHeader

                Group {
                    switch currentSpineItem {
                    case .cover:
                        coverPageView
                    case .readingMatterPage:
                        currentReadingMatterPageView
                    case .chapter:
                        chapterReaderContent
                    case .scene, .none:
                        StoryReaderUnavailableView(
                            title: "Reader Data Missing",
                            message: "This story spine item could not be displayed."
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            stickyPlayerView
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        // Programmatic navigation to quiz on audio completion or overflow menu tap
        .navigationDestination(isPresented: $navigateToQuiz) {
            StoryQuizView(story: story, preloadedQuestions: quizQuestions.isEmpty ? nil : quizQuestions)
        }
        .onAppear {
            startTime = Date()
            ambientVolume = story.ambientVolume
            if isOnChapterSpineItem, !isShowingChapterIntro {
                setupAudio()
            }
            if isOnChapterSpineItem {
                loadChapterImage()
            }
            if isOnReadingMatterSpineItem {
                loadReadingMatterImage()
            }
        }
        .mediaPlaybackLifecycle(
            onUserLeave: cleanupSession,
            onEnterBackground: { audioManager.updateStreamNowPlayingInfo() }
        )
        .onChange(of: currentChapterIndex) { _, _ in
            loadChapterImage()
        }
        .onChange(of: ambientVolume) { _, newValue in
            audioManager.setAmbientVolume(newValue)
            story.ambientVolume = newValue
            try? modelContext.save()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { showStoryInfo = true }) {
                        Label("Story Info", systemImage: "info.circle")
                    }

                    Divider()

                    Button(action: openQuiz) {
                        Label("Comprehension Quiz", systemImage: "checkmark.circle")
                    }

                    Divider()

                    Button(action: {
                        if selectedLanguage == .target {
                            UIPasteboard.general.string = storyBookChapterItems.compactMap { adapter.chapter(for: $0)?.bodyTextTargetForReading }.joined(separator: "\n\n")
                        } else {
                            UIPasteboard.general.string = storyBookChapterItems.compactMap { adapter.chapter(for: $0)?.bodyTextEnglishForReading }.joined(separator: "\n\n")
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
                        .foregroundColor(.primary)
                }
            }
        }
        .sheet(isPresented: $showStoryInfo) {
            StoryInfoSheet(story: story)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSpine) {
            StoryBookSpineSheet(
                spineItems: storyBookSpineItems,
                currentSpineIndex: currentSpineIndex,
                adapter: adapter
            ) { spineIndex in
                showSpine = false
                goToSpineIndex(spineIndex, showChapterCard: shouldShowChapterCard(forSpineIndex: spineIndex))
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showWordLookup) {
            WordLookupSheet(
                word: selectedWord ?? "",
                languageLabel: story.language.displayName,
                translation: wordTranslation,
                partOfSpeech: wordPartOfSpeech,
                isLoading: isTranslatingWord,
                seekTime: selectedWordTime,
                onSeek: { time in
                    seekTo(time)
                }
            )
            .presentationDetents([.fraction(0.4)])
            .presentationDragIndicator(.visible)
        }
        .onReceive(timer) { _ in
            if isOnReadingMatterSpineItem, isReadingMatterUsingGeneratedAudio {
                updateReadingMatterStreamState()
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
        stopReadingMatterPlayback()
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
        if isOnReadingMatterSpineItem {
            toggleReadingMatterPlayback()
            return
        }

        guard isOnChapterSpineItem else { return }
        didPlayAudio = true

        if isShowingChapterIntro {
            if isPlaying {
                isPlaying = false
            } else if hasChapterIntroContent {
                isPlaying = true
            } else {
                finishChapterIntro(andPlayBody: true)
            }
            return
        }

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
        if isOnReadingMatterSpineItem, isReadingMatterUsingGeneratedAudio {
            seekReadingMatter(to: min(max(duration, 1), sliderValue + 10))
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
        if isOnReadingMatterSpineItem, isReadingMatterUsingGeneratedAudio {
            seekReadingMatter(to: max(0, sliderValue - 10))
            return
        }
        guard isOnChapterSpineItem, !isShowingChapterIntro else { return }
        let newTime = sliderValue - 10
        let safeTime = max(0, newTime)
        seekTo(safeTime)
        audioManager.updateStreamNowPlayingInfo()
    }
    
    private func seekTo(_ value: Double) {
        if isOnReadingMatterSpineItem, isReadingMatterUsingGeneratedAudio {
            seekReadingMatter(to: value)
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
        audioManager.setStreamRate(rate)
        if isPlaying {
            audioManager.updateStreamNowPlayingInfo()
        }
    }
    
    // MARK: - Word Lookup

    private func lookupWord(_ word: String, time: Double) {
        selectedWord = word
        selectedWordTime = time
        wordTranslation = nil
        wordPartOfSpeech = nil
        showWordLookup = true

        let cacheKey = "\(word.lowercased())_\(story.language.rawValue)"
        if let cached = wordTranslationCache[cacheKey] {
            wordTranslation = cached.translation
            wordPartOfSpeech = cached.pos
            return
        }

        isTranslatingWord = true
        let context = sentenceContaining(word: word)
        Task {
            do {
                let result = try await OpenAIService().translateWord(word, language: story.language.displayName, context: context)
                await MainActor.run {
                    wordTranslation = result.translation
                    wordPartOfSpeech = result.partOfSpeech
                    wordTranslationCache[cacheKey] = (result.translation, result.partOfSpeech)
                    isTranslatingWord = false
                }
            } catch {
                await MainActor.run {
                    wordTranslation = "Translation unavailable"
                    wordPartOfSpeech = ""
                    isTranslatingWord = false
                }
            }
        }
    }

    private func sentenceContaining(word: String) -> String? {
        let text = currentChapter?.bodyTextTargetForReading ?? ""
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?。！？\n"))
        return sentences.first(where: { $0.localizedCaseInsensitiveContains(word) })?.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Comprehension Quiz

    private func preGenerateQuizIfNeeded() {
        guard story.comprehensionQuestionsJSON == nil && !isGeneratingQuiz else { return }
        isGeneratingQuiz = true
        Task {
            let level = LevelManager.shared.description(for: story.level)
            let questions = try? await OpenAIService().generateComprehensionQuestions(
                storyText: storyBookChapterItems.compactMap { adapter.chapter(for: $0)?.bodyTextTargetForReading }.joined(separator: "\n\n"),
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

    private var isOnReadingMatterSpineItem: Bool {
        if case .readingMatterPage = currentSpineItem { return true }
        return false
    }

    private var isOnPlayableReadingMatter: Bool {
        guard isOnReadingMatterSpineItem,
              let item = currentSpineItem,
              let page = adapter.readingMatterPage(for: item) else { return false }
        return page.hasGeneratedAudio(preferNative: selectedLanguage == .native)
            || readingMatterSpeakableText(for: page) != nil
    }

    private var currentReadingMatterPageHasGeneratedAudio: Bool {
        guard let item = currentSpineItem,
              let page = adapter.readingMatterPage(for: item) else { return false }
        return page.hasGeneratedAudio(preferNative: selectedLanguage == .native)
    }

    private var canSeekCurrentSpinePlayback: Bool {
        if isShowingChapterIntro { return false }
        if isOnChapterSpineItem { return true }
        if isOnReadingMatterSpineItem, currentReadingMatterPageHasGeneratedAudio { return true }
        return false
    }

    private var canControlCurrentSpinePlayback: Bool {
        isOnChapterSpineItem || isOnPlayableReadingMatter
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
        Group {
            if isOnChapterSpineItem {
                chapterSpineHeader
            } else if isOnReadingMatterSpineItem {
                readingMatterSpineHeader
            } else {
                defaultSpineHeader
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var defaultSpineHeader: some View {
        HStack(spacing: 10) {
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
            .frame(maxWidth: .infinity, alignment: .leading)

            if !storyBookSpineItems.isEmpty {
                Text("\(currentSpineIndex + 1)/\(storyBookSpineItems.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var chapterSpineHeader: some View {
        HStack(spacing: 10) {
            chapterHeaderThumbnail

            VStack(alignment: .leading, spacing: 2) {
                if let subtitle = currentSpineSubtitle {
                    Text(subtitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }

                Text(story.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if currentChapterHasEnglishContent {
                chapterLanguageToggle
            }

            if !storyBookSpineItems.isEmpty {
                Text("\(currentSpineIndex + 1)/\(storyBookSpineItems.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var chapterHeaderThumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.accentColor.opacity(0.18))
            .overlay {
                Image(systemName: "text.book.closed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
    }

    private var readingMatterSpineHeader: some View {
        HStack(spacing: 10) {
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
            .frame(maxWidth: .infinity, alignment: .leading)

            if currentReadingMatterHasEnglishContent {
                chapterLanguageToggle
            }

            if !storyBookSpineItems.isEmpty {
                Text("\(currentSpineIndex + 1)/\(storyBookSpineItems.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var currentChapterHasEnglishContent: Bool {
        guard let chapter = currentChapter else { return false }
        if !chapter.titleEnglish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let intro = chapter.chapterIntroTextEnglish,
           !intro.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return !chapter.bodyTextEnglishForReading.isEmpty
    }

    private var currentReadingMatterHasEnglishContent: Bool {
        guard let item = currentSpineItem,
              let page = adapter.readingMatterPage(for: item) else { return false }
        if let title = page.titleNative, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let body = page.bodyNative, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
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
                    ? (readerMatterText(page.titleNative) ?? readerMatterText(page.titleTarget))
                    : readerMatterText(page.titleTarget)
                let base = title ?? "Reading Matter"
                if isPlaying, isOnReadingMatterSpineItem {
                    return "\(base) · Now Playing"
                }
                return base
            }
            return "Reading Matter"
        case .chapter(let index):
            if let chapter = story.chapters[safeStorySession: index] {
                let title = selectedLanguage == .native
                    ? (chapter.titleEnglish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? chapter.titleTargetLanguage
                        : chapter.titleEnglish)
                    : chapter.titleTargetLanguage
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let chapterLabel = trimmed.isEmpty ? "Chapter \(index + 1)" : "Chapter \(index + 1) · \(trimmed)"
                if isShowingChapterIntro {
                    let introPrefix = isPlaying ? "Chapter Intro · Now Playing" : "Chapter Intro"
                    return "\(introPrefix) · \(chapterLabel)"
                }
                return chapterLabel
            }
            if isShowingChapterIntro {
                let introPrefix = isPlaying ? "Chapter Intro · Now Playing" : "Chapter Intro"
                return "\(introPrefix) · Chapter \(index + 1)"
            }
            return "Chapter \(index + 1)"
        case .scene:
            return nil
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
                isUsingGeneratedAudio: isReadingMatterUsingGeneratedAudio,
                playbackTime: sliderValue,
                wordTimings: page.wordTimingsForPlayback(preferNative: selectedLanguage == .native),
                useNativeLanguage: selectedLanguage == .native,
                bottomSpacer: StoryBookLayout.bottomScrollSpacer
            )
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
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
            return readerMatterText(page.titleTarget)
        case .native:
            return readerMatterText(page.titleNative) ?? readerMatterText(page.titleTarget)
        }
    }

    private func readingMatterDisplayBody(for page: ReadingMatterPage) -> String? {
        switch selectedLanguage {
        case .target:
            return readerMatterText(page.bodyTarget)
        case .native:
            return readerMatterText(page.bodyNative) ?? readerMatterText(page.bodyTarget)
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

    private func toggleReadingMatterPlayback() {
        guard let item = currentSpineItem,
              let page = adapter.readingMatterPage(for: item) else { return }

        didPlayAudio = true

        if page.hasGeneratedAudio(preferNative: selectedLanguage == .native) {
            toggleReadingMatterGeneratedAudio(for: item, page: page)
            return
        }

        guard let text = readingMatterSpeakableText(for: page) else { return }

        if isPlaying {
            isPlaying = false
            if readingMatterSynthesizer.isSpeaking {
                readingMatterSynthesizer.pauseSpeaking(at: .word)
            }
            return
        }

        if readingMatterSynthesizer.isPaused {
            readingMatterSynthesizer.continueSpeaking()
            isPlaying = true
            return
        }

        startReadingMatterSpeech(text: text)
    }

    private func toggleReadingMatterGeneratedAudio(for item: StoryReadingSpineItem, page: ReadingMatterPage) {
        guard case .readingMatterPage(let pageIndex, _) = item else { return }

        if isReadingMatterUsingGeneratedAudio, audioManager.streamPlayer != nil {
            if audioManager.isStreaming {
                audioManager.pauseStream()
                audioManager.pauseAmbient()
                isPlaying = false
            } else {
                audioManager.playStream()
                audioManager.resumeAmbient()
                isPlaying = true
            }
            audioManager.updateStreamNowPlayingInfo()
            return
        }

        setupReadingMatterAudio(pageIndex: pageIndex, page: page, autoplay: true)
    }

    private func setupReadingMatterAudio(
        pageIndex: Int,
        page: ReadingMatterPage,
        autoplay: Bool = false,
        startAt: Double = 0
    ) {
        guard let clip = adapter.readingMatterAudioClip(
            pageIndex: pageIndex,
            page: page,
            preferNative: selectedLanguage == .native
        ) else { return }

        stopReadingMatterSpeech()
        isReadingMatterUsingGeneratedAudio = true
        activeWordIndex = nil

        let localURL = adapter.localAudioURL(for: clip)
        if let cachedURL = adapter.cachedAudioURL(for: clip) {
            playReadingMatterAudio(url: cachedURL, clip: clip, page: page, startAt: startAt, autoplay: autoplay)
            return
        }

        isDownloadingAudio = true
        Task {
            await downloadAndPlayReadingMatterAudio(
                clip: clip,
                page: page,
                localURL: localURL,
                startAt: startAt,
                autoplay: autoplay
            )
        }
    }

    private func playReadingMatterAudio(
        url: URL,
        clip: StorySceneAudioClip,
        page: ReadingMatterPage,
        startAt: Double = 0,
        autoplay: Bool = false
    ) {
        audioManager.streamAudio(url: url, startAt: startAt)
        audioManager.setStreamRate(playbackRate)
        let timedDuration = page.wordTimingsForPlayback(preferNative: selectedLanguage == .native).last?.end
        duration = max(timedDuration ?? 0, audioManager.streamDuration, 1)
        sliderValue = startAt
        updateReadingMatterWordHighlight(time: startAt)
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

    private func downloadAndPlayReadingMatterAudio(
        clip: StorySceneAudioClip,
        page: ReadingMatterPage,
        localURL: URL,
        startAt: Double = 0,
        autoplay: Bool = false
    ) async {
        guard let url = StoryReaderDataAdapter.remoteAudioURL(for: clip.urlString) else {
            await MainActor.run { isDownloadingAudio = false }
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 1000 else {
                await MainActor.run { isDownloadingAudio = false }
                return
            }

            let isWAV = data.prefix(4) == Data([0x52, 0x49, 0x46, 0x46])
            let correctExt = isWAV ? "wav" : "mp3"
            let correctURL = localURL.deletingPathExtension().appendingPathExtension(correctExt)
            try data.write(to: correctURL)

            await MainActor.run {
                isDownloadingAudio = false
                playReadingMatterAudio(url: correctURL, clip: clip, page: page, startAt: startAt, autoplay: autoplay)
            }
        } catch {
            await MainActor.run { isDownloadingAudio = false }
        }
    }

    private func updateReadingMatterStreamState() {
        if audioManager.streamFinished {
            audioManager.streamFinished = false
            isPlaying = false
            return
        }

        guard audioManager.streamPlayer != nil else { return }

        sliderValue = audioManager.streamCurrentTime
        let streamDur = audioManager.streamDuration
        if streamDur > 0 {
            duration = max(duration, streamDur)
        }
        isPlaying = audioManager.isStreaming
        updateReadingMatterWordHighlight(time: sliderValue)

        if let streamPlayer = audioManager.streamPlayer,
           abs(streamPlayer.rate - playbackRate) > 0.1,
           streamPlayer.rate != 0 {
            playbackRate = streamPlayer.rate
        }
    }

    private func updateReadingMatterWordHighlight(time: Double) {
        guard let item = currentSpineItem,
              let page = adapter.readingMatterPage(for: item) else { return }
        let timings = page.wordTimingsForPlayback(preferNative: selectedLanguage == .native)
        activeWordIndex = timings.firstIndex(where: { time >= $0.start && time <= $0.end })
    }

    private func seekReadingMatter(to value: Double) {
        audioManager.seekStream(to: value)
        sliderValue = value
        updateReadingMatterWordHighlight(time: value)
        audioManager.updateStreamNowPlayingInfo()
    }

    private func startReadingMatterSpeech(text: String) {
        stopReadingMatterSpeech()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(
            language: speechLanguageCode(for: selectedLanguage == .native ? "en" : story.languageRaw)
        )
        utterance.rate = 0.5

        readingMatterSynthesizer.speak(utterance)
        isPlaying = true

        let finishTask = DispatchWorkItem {
            guard isPlaying else { return }
            isPlaying = false
        }
        readingMatterSpeechFinishTask = finishTask
        DispatchQueue.main.asyncAfter(
            deadline: .now() + estimatedSpeechDuration(for: text),
            execute: finishTask
        )
    }

    private func stopReadingMatterPlayback() {
        stopReadingMatterSpeech()
        if isReadingMatterUsingGeneratedAudio {
            audioManager.stopAudio()
            isReadingMatterUsingGeneratedAudio = false
        }
        activeWordIndex = nil
        if isOnReadingMatterSpineItem {
            isPlaying = false
            sliderValue = 0
            duration = 0
        }
    }

    private func stopReadingMatterSpeech() {
        readingMatterSpeechFinishTask?.cancel()
        readingMatterSpeechFinishTask = nil
        if readingMatterSynthesizer.isSpeaking || readingMatterSynthesizer.isPaused {
            readingMatterSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func speechLanguageCode(for code: String) -> String {
        switch code {
        case "es": return "es-MX"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "fr": return "fr-FR"
        case "vi": return "vi-VN"
        case "en": return "en-US"
        default: return code
        }
    }

    private func estimatedSpeechDuration(for text: String) -> TimeInterval {
        max(2.0, Double(text.count) * 0.06)
    }

    private var chapterLanguageToggle: some View {
        Picker("Language", selection: $selectedLanguage) {
            Text(story.language.rawValue.uppercased()).tag(DisplayLanguage.target)
            Text("EN").tag(DisplayLanguage.native)
        }
        .pickerStyle(.segmented)
        .frame(width: 88)
    }

    @ViewBuilder
    private var storyTextView: some View {
        if selectedLanguage == .target {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(storyParagraphs) { chunk in
                    ParagraphView(
                        chunk: chunk,
                        activeWordIndex: activeWordIndex,
                        timings: currentChapter?.bodyWordTimingsForPlayback ?? [],
                        wordMatches: wordMatches,
                        onSeek: seekTo,
                        onWordTap: lookupWord
                    )
                    .id(chunk.id)
                }
            }
        } else if let currentChapter {
            let nativeText = currentChapter.bodyTextEnglishForReading
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
                    languageCode: story.languageRaw,
                    selectedLanguage: $selectedLanguage,
                    isPlaying: $isPlaying,
                    onIntroFinished: { finishChapterIntro(andPlayBody: false) }
                )
                .id("chapter-intro-\(currentChapterIndex)")
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
                isBuffering: isDownloadingAudio,
                bufferingLabel: "Downloading audio…",
                onPlayPause: togglePlay,
                onSkipForward: skipForward,
                onSkipBackward: skipBackward,
                onSeek: seekTo,
                onChangeRate: setRate,
                onNextChapter: spineStepNavigationHandler(delta: 1),
                onPreviousChapter: spineStepNavigationHandler(delta: -1),
                onShowSpine: { showSpine = true }
            )
            .disabled(isOnChapterSpineItem && isDownloadingAudio)
            .id("story-book-footer")
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var currentChapter: StoryChapter? {
        guard let item = storyBookChapterItems.first(where: { chapterIndex(for: $0) == currentChapterIndex }) else { return nil }
        return adapter.chapter(for: item)
    }

    private func chapterIndex(for item: StoryReadingSpineItem) -> Int? {
        guard case .chapter(let index) = item else { return nil }
        return index
    }

    private var hasChapterIntroContent: Bool {
        guard let chapter = currentChapter else { return false }
        let hasAudio = !(chapter.chapterIntroAudioUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasText = !(chapter.chapterIntroText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasAudio || hasText
    }

    private func finishChapterIntro(andPlayBody: Bool) {
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

        stopReadingMatterPlayback()

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
            } else {
                isShowingChapterIntro = false
                setupAudio()
            }
        case .readingMatterPage:
            isReadingMatterUsingGeneratedAudio = false
            audioManager.stopAudio()
            isShowingChapterIntro = false
            sliderValue = 0
            duration = 0
            loadReadingMatterImage()
        case .cover:
            readingMatterHeroImage = nil
            isReadingMatterUsingGeneratedAudio = false
            audioManager.stopAudio()
            isShowingChapterIntro = false
            sliderValue = 0
            duration = 0
            loadStoryCoverImage()
        case .scene:
            audioManager.stopAudio()
            isShowingChapterIntro = false
        }
    }

    private func chapterHasIntroContent(at chapterIndex: Int) -> Bool {
        guard story.chapters.indices.contains(chapterIndex) else { return false }
        let chapter = story.chapters[chapterIndex]
        let hasAudio = !(chapter.chapterIntroAudioUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasText = !(chapter.chapterIntroText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasAudio || hasText
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
        if !navigateToQuiz {
            navigateToQuiz = true
        }
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
        let text = currentChapter?.bodyTextTargetForReading ?? ""
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
        let text = currentChapter?.bodyTextTargetForReading ?? ""
        let nsString = text as NSString
        return regex?.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
    }
    
    private func updateScrollState(time: Double) {
        let timings = currentChapter?.bodyWordTimingsForPlayback ?? []
        
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                        timings: wordTimings
                    ),
                    currentTime: playbackTime,
                    includesPadding: false
                )
                .frame(width: proseWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(bodyText)
                    .font(.body)
                    .lineSpacing(8)
                    .foregroundStyle(useNativeLanguage ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(width: proseWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
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
    let onWordTap: (String, Double) -> Void

    var body: some View {
        Text(attributedParagraph)
            .font(.system(size: 18, weight: .regular, design: .serif))
            .lineSpacing(10)
            .tint(.primary)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "x-learnci-word",
                   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let word = components.queryItems?.first(where: { $0.name == "word" })?.value,
                   let tStr = components.queryItems?.first(where: { $0.name == "t" })?.value,
                   let targetTime = Double(tStr) {
                    onWordTap(word, targetTime)
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

        if timings.isEmpty || chunk.text.isEmpty {
            return attrString
        }

        for (i, match) in wordMatches.enumerated() {
            guard i < timings.count else { break }
            let timing = timings[i]

            // Focus only on matches inside this chunk
            if NSLocationInRange(match.range.location, chunk.range) {
                let localRange = NSRange(location: match.range.location - chunk.range.location, length: match.range.length)

                if let swiftRange = Range(localRange, in: chunk.text),
                   let lowerBound = AttributedString.Index(swiftRange.lowerBound, within: attrString),
                   let upperBound = AttributedString.Index(swiftRange.upperBound, within: attrString) {

                    let attrRange = lowerBound..<upperBound

                    // Word lookup link (includes word text + timestamp)
                    let encoded = timing.word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? timing.word
                    attrString[attrRange].link = URL(string: "x-learnci-word://?word=\(encoded)&t=\(timing.start)")

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

    @State private var localVideoURL: URL? = nil

    private let supabaseBase = "https://vuygqrbludhuywupcbma.supabase.co/storage/v1/object/public/audio-stories"
    private let supabaseVideoBase = "https://vuygqrbludhuywupcbma.supabase.co/storage/v1/object/public/audio-stories"

    var body: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .global).minY

            ZStack(alignment: .bottomTrailing) {
                // 1. Video layer (priority)
                if let videoURL = localVideoURL {
                    LoopingVideoPlayerView(url: videoURL)
                        .frame(width: geo.size.width, height: geo.size.height + (minY > 0 ? minY : 0))
                        .clipped()
                        .offset(y: minY > 0 ? -minY : 0)

                // 2. Static cover image fallback
                } else if let validImage = image {
                    Image(uiImage: validImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height + (minY > 0 ? minY : 0))
                        .clipped()
                        .offset(y: minY > 0 ? -minY : 0)

                // 3. Placeholder while loading
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(ProgressView())
                }

                // Gradient for text readability
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear, .black.opacity(0.15)],
                    startPoint: .bottom,
                    endPoint: .top
                )

                // Video generation overlay
                if isGeneratingVideo {
                    generatingOverlay
                        .padding(12)
                } else if let err = videoError {
                    errorBadge(err)
                        .padding(12)
                } else if localVideoURL == nil && showGenerateButton {
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

private struct StoryBookSpineSheet: View {
    let spineItems: [StoryReadingSpineItem]
    let currentSpineIndex: Int
    let adapter: StoryReaderDataAdapter
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            List(Array(spineItems.enumerated()), id: \.element.id) { index, item in
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
            .navigationTitle("Story Spine")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func icon(for item: StoryReadingSpineItem) -> String {
        switch item {
        case .cover:
            return "book.closed"
        case .readingMatterPage:
            return "doc.text"
        case .chapter:
            return "text.book.closed"
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

    var body: some View {
        VStack(spacing: 12) {
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
                Text(formatTime(sliderValue))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)

                Slider(value: Binding(
                    get: { sliderValue },
                    set: { newValue in
                        guard canSeek else { return }
                        sliderValue = newValue
                        onSeek(newValue)
                    }
                ), in: 0...duration)
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
                onShowSpine: onShowSpine
            )
            .padding(.horizontal)
        }
        .padding(.top, 20)
        .padding(.bottom, 20)
        .background(
            Rectangle()
                .fill(.thinMaterial)
                .cornerRadius(24, corners: [.topLeft, .topRight])
                .ignoresSafeArea(edges: .bottom)
        )
        .shadow(radius: 10, y: -5)
        .fixedSize(horizontal: false, vertical: true)
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

            Group {
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
    let isLoading: Bool
    let seekTime: Double?
    let onSeek: (Double) -> Void
    var onMarkForStudy: (() -> Void)? = nil
    var isMarkedForStudy: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    // Word + language badge
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(word)
                            .font(.system(size: 32, weight: .bold, design: .serif))
                        Text(languageLabel)
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    // Part of speech
                    if let pos = partOfSpeech, !pos.isEmpty {
                        Text(pos)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
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
                            Text("Translating…")
                                .foregroundColor(.secondary)
                        }
                    } else if let t = translation, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(t)
                            .font(.system(size: 22, weight: .regular))
                    } else {
                        Text("Translation unavailable.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                Spacer()

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
                ToolbarItem(placement: .topBarLeading) {
                    if let onMarkForStudy {
                        Button {
                            onMarkForStudy()
                        } label: {
                            Label(
                                isMarkedForStudy ? "Saved" : "Mark for study",
                                systemImage: isMarkedForStudy ? "star.fill" : "star"
                            )
                        }
                        .disabled(isMarkedForStudy || isLoading)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
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

import SwiftUI
import Combine
import SwiftData

struct PictureBookReaderView: View {
    let story: Story
    private let initialSpreadIndex: Int
    private let initialPlaybackPosition: Double?
    private let onProgressChange: ((StoryReaderProgressUpdate) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var currentSpreadIndex = 0
    @State private var currentClipIndex = 0
    @State private var isPlaying = false
    @State private var isDownloadingAudio = false
    @State private var sliderValue = 0.0
    @State private var duration = 0.0
    @State private var playbackRate: Float = 1.0
    @State private var showSpine = false
    @State private var isPlayerMinimized = false
    @State private var isLoadingBook = true
    @State private var loadingIssue: StoryReaderRequirementIssue?
    @State private var spreads: [PictureBookSpreadModel]
    @State private var clips: [StorySceneAudioClip]
    @State private var spreadIndexToClipIndex: [Int: Int]
    @State private var clipIndexToSpreadIndex: [Int: Int]
    @State private var selectedLanguage: StorySessionView.DisplayLanguage = .target
    @State private var supplementalPlayback = StorySupplementalAudioPlayback()
    @State private var isAutoContinueEnabled = true
    @State private var autoAdvanceToken = 0
    @State private var sleepTimerMinutes = 0
    @State private var sleepTimerToken = 0
    @State private var lastSavedPlaybackSecond = -1
    @State private var startTime: Date?
    @State private var didPlayAudio = false
    @State private var didLogActivity = false

    @Environment(\.modelContext) private var modelContext
    private var audioManager = AudioManager.shared
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    init(
        story: Story,
        initialSpreadIndex: Int = 0,
        initialPlaybackPosition: Double? = nil,
        onProgressChange: ((StoryReaderProgressUpdate) -> Void)? = nil
    ) {
        self.story = story
        self.initialSpreadIndex = initialSpreadIndex
        self.initialPlaybackPosition = initialPlaybackPosition
        self.onProgressChange = onProgressChange
        _spreads = State(initialValue: [])
        _clips = State(initialValue: [])
        _spreadIndexToClipIndex = State(initialValue: [:])
        _clipIndexToSpreadIndex = State(initialValue: [:])
    }

    private var adapter: StoryReaderDataAdapter {
        StoryReaderDataAdapter(story: story)
    }

    private static func makeClipMaps(
        spreads: [PictureBookSpreadModel],
        clips: [StorySceneAudioClip]
    ) -> (spreadToClip: [Int: Int], clipToSpread: [Int: Int]) {
        let spreadClipPairs: [(Int, Int)] = spreads.enumerated().compactMap { spreadIndex, spread in
            guard let clip = spread.audioClip,
                  let clipIndex = clips.firstIndex(where: { $0.id == clip.id }) else { return nil }
            return (spreadIndex, clipIndex)
        }
        let spreadToClip = Dictionary<Int, Int>(uniqueKeysWithValues: spreadClipPairs)
        let clipSpreadPairs: [(Int, Int)] = spreadToClip.map { ($0.value, $0.key) }
        return (
            spreadToClip,
            Dictionary<Int, Int>(uniqueKeysWithValues: clipSpreadPairs)
        )
    }

    var body: some View {
        Group {
            if isLoadingBook {
                PictureBookLoadingView(title: story.title)
            } else if let issue = loadingIssue {
                StoryReaderUnavailableView(title: issue.title, message: issue.message)
            } else if spreads.isEmpty {
                StoryReaderUnavailableView(title: "Reader Data Missing", message: "This picture book has no visible spine items.")
            } else {
                pictureBookBody
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if startTime == nil {
                startTime = Date()
            }
            loadBookIfNeeded()
        }
        .onChange(of: isAutoContinueEnabled) { _, enabled in
            if enabled {
                startAutoContinueForCurrentSpread()
            } else {
                cancelScheduledAutoAdvance()
            }
        }
        .onChange(of: sleepTimerMinutes) { _, minutes in
            scheduleSleepTimer(minutes: minutes)
        }
        .sheet(isPresented: $showSpine) {
            PictureBookPlayerSheet(
                spreads: spreads,
                currentSpreadIndex: currentSpreadIndex,
                isAutoContinueEnabled: $isAutoContinueEnabled,
                sleepTimerMinutes: $sleepTimerMinutes,
                playbackRate: $playbackRate,
                onChangeRate: setRate
            ) { index in
                showSpine = false
                goToSpread(index)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .mediaPlaybackLifecycle(
            onUserLeave: {
                cancelScheduledAutoAdvance()
                cleanupSession()
            },
            onEnterBackground: { audioManager.updateStreamNowPlayingInfo() }
        )
        .onChange(of: currentSpreadIndex) { _, _ in
            prepareSupplementalForCurrentSpread()
            saveReadingProgress()
        }
        .onChange(of: selectedLanguage) { _, _ in
            guard isOnSupplementalSpread else { return }
            let wasPlaying = supplementalPlayback.isPlaying
            prepareSupplementalForCurrentSpread()
            if wasPlaying {
                supplementalPlayback.syncPlayback(
                    shouldPlay: true,
                    speakableText: currentSupplementalSpeakableText
                )
            }
        }
        .onReceive(timer) { _ in
            if isOnSupplementalSpread {
                supplementalPlayback.syncStreamState()
                sliderValue = supplementalPlayback.currentTime
                if supplementalPlayback.duration > 0 {
                    duration = supplementalPlayback.duration
                }
                isPlaying = supplementalPlayback.isPlaying
                saveTimedReadingProgressIfNeeded(position: sliderValue)
                return
            }

            guard !clips.isEmpty else { return }

            if audioManager.streamFinished {
                advanceAfterClipFinished()
                return
            }

            if audioManager.streamPlayer != nil {
                sliderValue = audioManager.streamCurrentTime
                if audioManager.streamDuration > 0 {
                    duration = audioManager.streamDuration
                }
                isPlaying = audioManager.isStreaming
                saveTimedReadingProgressIfNeeded(position: sliderValue)
            }
        }
    }

    private func loadBookIfNeeded() {
        guard isLoadingBook, spreads.isEmpty else { return }

        DispatchQueue.main.async {
            let adapter = StoryReaderDataAdapter(story: story)
            let issue = adapter.requirementIssue(for: .pictureBook)
            let loadedSpreads = issue == nil ? PictureBookRenderer.makeSpreads(story: story, adapter: adapter) : []
            let loadedClips = issue == nil ? adapter.audioClips(for: .pictureBook) : []
            let maps = Self.makeClipMaps(spreads: loadedSpreads, clips: loadedClips)

            loadingIssue = issue
            spreads = loadedSpreads
            clips = loadedClips
            spreadIndexToClipIndex = maps.spreadToClip
            clipIndexToSpreadIndex = maps.clipToSpread
            currentSpreadIndex = loadedSpreads.indices.contains(initialSpreadIndex) ? initialSpreadIndex : 0
            currentClipIndex = 0
            isLoadingBook = false
            prepareSupplementalForCurrentSpread()
            prepareInitialPlaybackPositionIfNeeded()
            saveReadingProgress()
        }
    }

    private var pictureBookBody: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                compactReaderHeader

                if spreads.indices.contains(currentSpreadIndex) {
                    PictureBookSpreadView(
                        spread: spreads[currentSpreadIndex],
                        story: story,
                        selectedLanguage: selectedLanguage,
                        supplementalPlayback: isOnSupplementalSpread ? supplementalPlayback : nil,
                        onUserScroll: minimizePlayerForReading
                    )
                    .id("\(spreads[currentSpreadIndex].id)-\(selectedLanguage.rawValue)")
                    .transition(.opacity)
                }
            }

            playbackControls
        }
    }

    @ViewBuilder
    private var compactReaderHeader: some View {
        let spread = spreads[safeForPictureBook: currentSpreadIndex]

        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.primary)
                    .background(.thinMaterial)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(story.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                if let subtitle = spread?.headerSubtitle(
                    story: story,
                    language: selectedLanguage
                ) {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            pictureBookLanguageToggle

            Text("\(currentSpreadIndex + 1)/\(spreads.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
    }

    private var pictureBookLanguageToggle: some View {
        Picker("Language", selection: $selectedLanguage) {
            Text(story.language.rawValue.uppercased()).tag(StorySessionView.DisplayLanguage.target)
            Text("EN").tag(StorySessionView.DisplayLanguage.native)
        }
        .pickerStyle(.segmented)
        .frame(width: 88)
    }

    @ViewBuilder
    private var playbackControls: some View {
        VStack(spacing: 10) {
            if isDownloadingAudio || supplementalPlayback.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(supplementalPlayback.isLoading ? "Loading audio…" : "Loading scene audio...")
                        .font(.caption.weight(.semibold))
                    Spacer()
                }
            }

            AudioPlayerBar(
                isPlaying: $isPlaying,
                sliderValue: $sliderValue,
                duration: max(isOnSupplementalSpread ? supplementalPlayback.duration : duration, 1),
                playbackRate: $playbackRate,
                ambientVolume: .constant(0),
                isAmbientPlaying: false,
                canSeek: isOnSupplementalSpread ? supplementalPlayback.canSeek : audioManager.streamPlayer != nil,
                canControlPlayback: canControlSpreadPlayback,
                playbackContextLabel: spreadPlaybackContextLabel,
                isBuffering: supplementalPlayback.isLoading,
                bufferingLabel: "Loading audio…",
                isMinimized: isPlayerMinimized,
                showsRateControl: false,
                onPlayPause: togglePlay,
                onSkipForward: skipForward,
                onSkipBackward: skipBackward,
                onSeek: seekTo,
                onChangeRate: setRate,
                onNextChapter: currentSpreadIndex < spreads.count - 1 ? {
                    goToSpread(currentSpreadIndex + 1, autoplay: isAutoContinueEnabled)
                } : nil,
                onPreviousChapter: currentSpreadIndex > 0 ? {
                    goToSpread(currentSpreadIndex - 1)
                } : nil,
                onShowSpine: {
                    isPlayerMinimized = false
                    showSpine = true
                },
                onExpand: expandPlayerController
            )
            .disabled(isDownloadingAudio || supplementalPlayback.isLoading)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var currentSpread: PictureBookSpreadModel? {
        spreads[safeForPictureBook: currentSpreadIndex]
    }

    private var isOnReadingMatterSpread: Bool {
        if case .readingMatterPage = currentSpread?.spineItem { return true }
        return false
    }

    private var isOnChapterIntroSpread: Bool {
        currentSpread?.isChapterIntro == true
    }

    private var isOnSupplementalSpread: Bool {
        isOnReadingMatterSpread || isOnChapterIntroSpread
    }

    private var isOnChapterSupplementSpread: Bool {
        guard let spread = currentSpread else { return false }
        switch spread.spineItem {
        case .chapterQuiz, .chapterVocabulary:
            return true
        default:
            return false
        }
    }

    private var preferNativeLanguage: Bool {
        selectedLanguage == .native
    }

    private var canControlSpreadPlayback: Bool {
        if isOnSupplementalSpread {
            return currentSupplementalCanPlay
        }
        if case .cover = currentSpread?.spineItem {
            return currentSpreadIndex < spreads.count - 1
        }
        return currentSpread?.isScene == true
    }

    private var spreadPlaybackContextLabel: String? {
        guard isOnSupplementalSpread, currentSupplementalCanPlay else { return nil }
        if isOnChapterIntroSpread {
            return supplementalPlayback.isPlaying ? "Chapter Intro · Now Playing" : "Chapter Intro"
        }
        return supplementalPlayback.isPlaying ? "Reading Matter · Now Playing" : "Reading Matter"
    }

    private var currentSupplementalCanPlay: Bool {
        if isOnReadingMatterSpread {
            return currentReadingMatterCanPlay
        }
        if isOnChapterIntroSpread {
            return currentChapterIntroCanPlay
        }
        return false
    }

    private var currentReadingMatterCanPlay: Bool {
        guard let page = currentSpread?.readingMatterPage else { return false }
        let code = preferNativeLanguage ? story.nativeLanguageCode : story.targetLanguageCode
        return page.audioUrlFor(code) != nil || currentReadingMatterSpeakableText != nil
    }

    private var currentReadingMatterSpeakableText: String? {
        guard let spread = currentSpread, spread.readingMatterPage != nil else { return nil }
        return spread.displayBody(language: selectedLanguage)
    }

    private var currentChapterIntroCanPlay: Bool {
        guard let chapter = currentSpread?.chapter else { return false }
        let code = preferNativeLanguage ? story.nativeLanguageCode : story.targetLanguageCode
        let hasAudio = chapter.chapterIntroAudioUrlForLanguage(code) != nil
        return hasAudio || currentChapterIntroSpeakableText != nil
    }

    private var currentChapterIntroSpeakableText: String? {
        guard let chapter = currentSpread?.chapter else { return nil }
        return StorySupplementalAudioPlayback.chapterIntroSpeakableText(
            chapter: chapter,
            preferNative: preferNativeLanguage,
            targetCode: story.targetLanguageCode,
            nativeCode: story.nativeLanguageCode
        )
    }

    private var currentSupplementalSpeakableText: String? {
        if isOnReadingMatterSpread {
            return currentReadingMatterSpeakableText
        }
        if isOnChapterIntroSpread {
            return currentChapterIntroSpeakableText
        }
        return nil
    }

    private func prepareSupplementalForCurrentSpread() {
        supplementalPlayback.onFinished = nil

        if isOnChapterIntroSpread,
           let spread = currentSpread,
           let chapter = spread.chapter,
           case .chapter(let chapterIndex) = spread.spineItem {
            supplementalPlayback.bind(story: story, audioManager: audioManager)
            supplementalPlayback.setRate(playbackRate)
            supplementalPlayback.prepareChapterIntro(
                chapterIndex: chapterIndex,
                chapter: chapter,
                preferNative: preferNativeLanguage
            )
            supplementalPlayback.onFinished = {
                advanceAfterSupplementalFinished()
            }
            return
        }

        guard isOnReadingMatterSpread,
              let spread = currentSpread,
              let page = spread.readingMatterPage,
              case .readingMatterPage(let pageIndex, _) = spread.spineItem else {
            supplementalPlayback.stop()
            return
        }

        supplementalPlayback.bind(story: story, audioManager: audioManager)
        supplementalPlayback.setRate(playbackRate)
        supplementalPlayback.prepareReadingMatter(
            pageIndex: pageIndex,
            page: page,
            preferNative: preferNativeLanguage
        )
        supplementalPlayback.onFinished = {
            advanceAfterSupplementalFinished()
        }
    }

    private func stopSupplementalPlayback() {
        supplementalPlayback.stop()
        if isOnSupplementalSpread {
            isPlaying = false
            sliderValue = 0
            duration = 0
        }
    }

    private var currentSpreadLabel: String {
        guard spreads.indices.contains(currentSpreadIndex) else { return "" }
        switch spreads[currentSpreadIndex].spineItem {
        case .cover:
            return "Cover"
        case .readingMatterPage:
            return "Reading Matter"
        case .chapter:
            return "Chapter"
        case .chapterQuiz:
            return "Quiz"
        case .chapterVocabulary:
            return "Word Focus"
        case .scene:
            return "Scene"
        }
    }

    private func goToSpread(_ index: Int, autoplay: Bool? = nil) {
        guard spreads.indices.contains(index) else { return }

        cancelScheduledAutoAdvance()
        let shouldAutoplay = autoplay ?? isPlaying
        stopSupplementalPlayback()
        if !spreads[index].isScene {
            audioManager.stopAudio()
        }

        withAnimation(.easeOut(duration: 0.18)) {
            currentSpreadIndex = index
        }

        prepareSupplementalForCurrentSpread()

        guard shouldAutoplay else { return }

        if isOnSupplementalSpread {
            supplementalPlayback.syncPlayback(
                shouldPlay: true,
                speakableText: currentSupplementalSpeakableText
            )
            isPlaying = supplementalPlayback.isPlaying
            if isPlaying {
                didPlayAudio = true
            }
            return
        }

        guard let targetClipIndex = spreadIndexToClipIndex[index] else {
            isPlaying = false
            return
        }
        playClip(at: targetClipIndex, autoplay: true)
    }

    private func togglePlay() {
        if isOnSupplementalSpread {
            let shouldPlay = !supplementalPlayback.isPlaying
            supplementalPlayback.syncPlayback(
                shouldPlay: shouldPlay,
                speakableText: currentSupplementalSpeakableText
            )
            isPlaying = supplementalPlayback.isPlaying
            if isPlaying {
                didPlayAudio = true
            }
            return
        }

        if audioManager.streamPlayer == nil {
            if let clipIndex = spreadIndexToClipIndex[currentSpreadIndex] {
                playClip(at: clipIndex, autoplay: true)
            } else {
                beginPlaybackFromCurrentSpread()
            }
            return
        }

        if audioManager.isStreaming {
            audioManager.pauseStream()
            isPlaying = false
        } else {
            audioManager.playStream()
            isPlaying = true
            didPlayAudio = true
        }
        audioManager.updateStreamNowPlayingInfo()
    }

    private func skipForward() {
        guard isOnSupplementalSpread, supplementalPlayback.canSeek else { return }
        seekTo(min(sliderValue + 10, max(supplementalPlayback.duration, 1)))
    }

    private func skipBackward() {
        guard isOnSupplementalSpread, supplementalPlayback.canSeek else { return }
        seekTo(max(0, sliderValue - 10))
    }

    private func seekTo(_ value: Double) {
        if isOnSupplementalSpread, supplementalPlayback.canSeek {
            supplementalPlayback.seek(to: value)
            sliderValue = value
            return
        }
        sliderValue = value
        audioManager.seekStream(to: value)
        audioManager.updateStreamNowPlayingInfo()
    }

    private func setRate(_ rate: Float) {
        playbackRate = rate
        if isOnSupplementalSpread {
            supplementalPlayback.setRate(rate)
        } else {
            audioManager.setStreamRate(rate)
        }
    }

    private func beginPlaybackFromCurrentSpread() {
        guard currentSpreadIndex < spreads.count - 1 else { return }
        goToSpread(currentSpreadIndex + 1, autoplay: true)
    }

    private func playClip(at index: Int, autoplay: Bool, startAt: Double = 0) {
        guard clips.indices.contains(index) else { return }
        cancelScheduledAutoAdvance()
        stopSupplementalPlayback()
        currentClipIndex = index
        if let spreadIndex = clipIndexToSpreadIndex[index],
           spreadIndex != currentSpreadIndex {
            withAnimation(.easeOut(duration: 0.18)) {
                currentSpreadIndex = spreadIndex
            }
        }

        let clip = clips[index]
        let localURL = adapter.localAudioURL(for: clip)

        if let cachedURL = adapter.cachedAudioURL(for: clip) {
            playLocal(url: cachedURL, clip: clip, autoplay: autoplay, startAt: startAt)
            return
        }

        isDownloadingAudio = true
        Task { await downloadAndPlay(clip: clip, localURL: localURL, autoplay: autoplay, startAt: startAt) }
    }

    private func playLocal(url: URL, clip: StorySceneAudioClip, autoplay: Bool, startAt: Double = 0) {
        audioManager.streamAudio(url: url, startAt: startAt)
        audioManager.setStreamRate(playbackRate)
        audioManager.onStreamFinished = {
            advanceAfterClipFinished()
        }
        duration = clip.duration ?? audioManager.streamDuration
        sliderValue = startAt
        audioManager.updateStreamNowPlayingInfo(title: clip.title, artist: story.title, artworkImage: nil)
        if autoplay {
            didPlayAudio = true
            audioManager.playStream()
            isPlaying = true
        }
    }

    private func downloadAndPlay(clip: StorySceneAudioClip, localURL: URL, autoplay: Bool, startAt: Double = 0) async {
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
            let isM4A = data.prefix(4).count == 4 && data.dropFirst(4).prefix(4) == Data([0x66, 0x74, 0x79, 0x70])
            let ext = isWAV ? "wav" : (isM4A ? "m4a" : "mp3")
            let correctURL = localURL.deletingPathExtension().appendingPathExtension(ext)
            try data.write(to: correctURL)

            await MainActor.run {
                isDownloadingAudio = false
                playLocal(url: correctURL, clip: clip, autoplay: autoplay, startAt: startAt)
            }
        } catch {
            await MainActor.run { isDownloadingAudio = false }
        }
    }

    private func advanceAfterClipFinished() {
        audioManager.streamFinished = false

        if clips.indices.contains(currentClipIndex),
           isLastSceneClipInChapter(clips[currentClipIndex]),
           let supplementSpread = immediateChapterSupplementSpread(after: currentSpreadIndex) {
            goToSpread(supplementSpread, autoplay: false)
            return
        }

        guard currentClipIndex < clips.count - 1 else {
            isPlaying = false
            if let backMatterIndex = spreads.indices.dropFirst(currentSpreadIndex + 1).first(where: {
                if case .readingMatterPage = spreads[$0].spineItem { return true }
                return false
            }) {
                goToSpread(backMatterIndex, autoplay: isAutoContinueEnabled)
            }
            return
        }
        playClip(at: currentClipIndex + 1, autoplay: true)
    }

    private func isLastSceneClipInChapter(_ clip: StorySceneAudioClip) -> Bool {
        adapter.audioClips(forChapter: clip.chapterIndex).last?.id == clip.id
    }

    private func immediateChapterSupplementSpread(after spreadIndex: Int) -> Int? {
        let next = spreadIndex + 1
        guard spreads.indices.contains(next) else { return nil }
        switch spreads[next].spineItem {
        case .chapterQuiz, .chapterVocabulary:
            return next
        default:
            return nil
        }
    }

    private func startAutoContinueForCurrentSpread() {
        cancelScheduledAutoAdvance()

        if isOnChapterSupplementSpread {
            return
        }

        if isOnSupplementalSpread {
            if currentSupplementalCanPlay {
                supplementalPlayback.syncPlayback(
                    shouldPlay: true,
                    speakableText: currentSupplementalSpeakableText
                )
                isPlaying = supplementalPlayback.isPlaying
                if isPlaying {
                    didPlayAudio = true
                }
            } else {
                scheduleAutoAdvanceToNextSpread()
            }
            return
        }

        if currentSpread?.isScene == true {
            if let clipIndex = spreadIndexToClipIndex[currentSpreadIndex] {
                if currentClipIndex == clipIndex, audioManager.streamPlayer != nil {
                    if !audioManager.isStreaming {
                        audioManager.playStream()
                        isPlaying = true
                        didPlayAudio = true
                    }
                } else {
                    playClip(at: clipIndex, autoplay: true)
                }
            } else {
                scheduleAutoAdvanceToNextSpread()
            }
            return
        }

        scheduleAutoAdvanceToNextSpread()
    }

    private func advanceAfterSupplementalFinished() {
        guard isAutoContinueEnabled else {
            isPlaying = false
            return
        }
        guard currentSpreadIndex < spreads.count - 1 else {
            isPlaying = false
            return
        }
        goToSpread(currentSpreadIndex + 1, autoplay: true)
    }

    private func scheduleAutoAdvanceToNextSpread(delay: TimeInterval = 2.0) {
        guard isAutoContinueEnabled, currentSpreadIndex < spreads.count - 1 else { return }
        autoAdvanceToken += 1
        let token = autoAdvanceToken
        let nextIndex = currentSpreadIndex + 1

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard isAutoContinueEnabled, token == autoAdvanceToken else { return }
            goToSpread(nextIndex, autoplay: true)
        }
    }

    private func cancelScheduledAutoAdvance() {
        autoAdvanceToken += 1
    }

    private func minimizePlayerForReading() {
        guard !isPlayerMinimized, !showSpine else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isPlayerMinimized = true
        }
    }

    private func expandPlayerController() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isPlayerMinimized = false
        }
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

        if isOnSupplementalSpread {
            supplementalPlayback.pause()
        } else {
            audioManager.pauseStream()
        }

        isPlaying = false
    }

    private func saveReadingProgress() {
        guard spreads.indices.contains(currentSpreadIndex) else { return }
        onProgressChange?(StoryReaderProgressUpdate(
            index: currentSpreadIndex,
            total: spreads.count,
            chapterIndex: currentSpread?.chapterIndex,
            sceneIndex: sceneIndex(for: currentSpread),
            position: sliderValue > 0 ? sliderValue : nil
        ))
    }

    private func saveTimedReadingProgressIfNeeded(position: Double) {
        let second = Int(position.rounded())
        guard second != lastSavedPlaybackSecond else { return }
        lastSavedPlaybackSecond = second
        saveReadingProgress()
    }

    private func cleanupSession() {
        audioManager.onStreamFinished = nil
        supplementalPlayback.stop()
        audioManager.stopAudio()
        logActivityIfNeeded()
    }

    private func logActivityIfNeeded() {
        guard !didLogActivity else { return }
        guard let startTime else { return }
        let minutes = Int(Date().timeIntervalSince(startTime) / 60)
        guard minutes > 0 else { return }

        let activity = UserActivity(
            date: startTime,
            minutes: minutes,
            activityType: didPlayAudio ? .listening : .reading,
            language: story.language,
            userID: story.userID.isEmpty ? nil : story.userID,
            comment: story.title
        )
        modelContext.insert(activity)
        try? modelContext.save()
        didLogActivity = true
    }

    private func prepareInitialPlaybackPositionIfNeeded() {
        guard let initialPlaybackPosition,
              initialPlaybackPosition > 0,
              currentSpread?.isScene == true,
              let clipIndex = spreadIndexToClipIndex[currentSpreadIndex] else { return }
        playClip(at: clipIndex, autoplay: false, startAt: initialPlaybackPosition)
    }

    private func sceneIndex(for spread: PictureBookSpreadModel?) -> Int? {
        guard let spread else { return nil }
        if case .scene(_, let sceneIndex) = spread.spineItem {
            return sceneIndex
        }
        return nil
    }
}

struct PictureBookRenderer {
    static func makeSpreads(story: Story, adapter: StoryReaderDataAdapter) -> [PictureBookSpreadModel] {
        let clipsBySceneID = Dictionary(uniqueKeysWithValues: adapter.audioClips(for: .pictureBook).map {
            (StoryReadingSpineItem.scene(chapterIndex: $0.chapterIndex, sceneIndex: $0.sceneIndex).id, $0)
        })

        return adapter.items(for: .pictureBook).enumerated().compactMap { spreadIndex, item in
            switch item {
            case .cover:
                return PictureBookSpreadModel(
                    id: item.id,
                    spineItem: item,
                    spreadIndex: spreadIndex,
                    storyTitle: story.title,
                    targetCode: story.targetLanguageCode,
                    nativeCode: story.nativeLanguageCode,
                    chapterIndex: nil,
                    chapterTitle: nil,
                    sceneTitle: nil,
                    spinePrimaryTitle: story.title,
                    spineContextLabel: "Cover",
                    title: story.title,
                    subtitle: "\(story.language.displayName) · Level \(story.level)",
                    body: nil,
                    readingMatterPage: nil,
                    chapter: nil,
                    scene: nil,
                    panel: nil,
                    layoutPanels: [],
                    audioClip: nil,
                    imageURL: coverURL(for: story)
                )
            case .readingMatterPage:
                guard let page = adapter.readingMatterPage(for: item) else { return nil }
                let title = page.titleFor(story.targetLanguageCode).nilIfEmptyForPictureBook
                    ?? page.titleFor(story.nativeLanguageCode).nilIfEmptyForPictureBook
                    ?? page.id.nilIfEmptyForPictureBook
                return PictureBookSpreadModel(
                    id: item.id,
                    spineItem: item,
                    spreadIndex: spreadIndex,
                    storyTitle: story.title,
                    targetCode: story.targetLanguageCode,
                    nativeCode: story.nativeLanguageCode,
                    chapterIndex: nil,
                    chapterTitle: nil,
                    sceneTitle: nil,
                    spinePrimaryTitle: StoryReadingSpineTitles.readingMatterTitle(for: page, targetCode: story.targetLanguageCode, nativeCode: story.nativeLanguageCode),
                    spineContextLabel: "Reading Matter",
                    title: title,
                    subtitle: nil,
                    body: page.bodyFor(story.targetLanguageCode).nilIfEmptyForPictureBook,
                    readingMatterPage: page,
                    chapter: nil,
                    scene: nil,
                    panel: nil,
                    layoutPanels: [],
                    audioClip: nil,
                    imageURL: coverURL(for: story)
                )
            case .chapter(let chapterIndex):
                guard let chapter = story.chapters[safeForPictureBook: chapterIndex],
                      chapter.hasChapterIntroContentForLanguage(story.targetLanguageCode) else { return nil }
                let chapterTitle = chapter.titleFor(story.targetLanguageCode).nilIfEmptyForPictureBook
                let regularChapterCount = story.chapters.filter { !$0.isPrologue && !$0.isEpilogue }.count
                return PictureBookSpreadModel(
                    id: item.id,
                    spineItem: item,
                    spreadIndex: spreadIndex,
                    storyTitle: story.title,
                    targetCode: story.targetLanguageCode,
                    nativeCode: story.nativeLanguageCode,
                    chapterIndex: chapterIndex,
                    chapterTitle: chapterTitle,
                    sceneTitle: nil,
                    spinePrimaryTitle: StoryReadingSpineTitles.chapterTitle(for: chapter, index: chapterIndex, targetCode: story.targetLanguageCode),
                    spineContextLabel: StoryReadingSpineTitles.chapterKindLabel(
                        for: chapter,
                        index: chapterIndex,
                        regularChapterCount: regularChapterCount,
                        targetCode: story.targetLanguageCode
                    ),
                    title: chapterTitle,
                    subtitle: "Chapter Intro",
                    body: chapter.chapterIntroTextForLanguage(story.targetLanguageCode).nilIfEmptyForPictureBook,
                    readingMatterPage: nil,
                    chapter: chapter,
                    scene: nil,
                    panel: nil,
                    layoutPanels: [],
                    audioClip: nil,
                    imageURL: adapter.chapterImageURL(forChapterAt: chapterIndex)
                )
            case .scene(let chapterIndex, let sceneIndex):
                guard let scene = adapter.scene(for: item) else { return nil }
                let chapter = story.chapters[safeForPictureBook: chapterIndex]
                let chapterTitle = chapter?.titleFor(story.targetLanguageCode).nilIfEmptyForPictureBook
                let breakdownTitle = StoryReadingSpineTitles.sceneTitleFromBreakdown(
                    story: story,
                    chapterIndex: chapterIndex,
                    sceneIndex: sceneIndex
                )
                let sceneTitle = StoryReadingSpineTitles.sceneTitle(
                    from: scene,
                    sceneIndex: sceneIndex,
                    targetCode: story.targetLanguageCode,
                    breakdownTitle: breakdownTitle
                )
                return PictureBookSpreadModel(
                    id: item.id,
                    spineItem: item,
                    spreadIndex: spreadIndex,
                    storyTitle: story.title,
                    targetCode: story.targetLanguageCode,
                    nativeCode: story.nativeLanguageCode,
                    chapterIndex: chapterIndex,
                    chapterTitle: chapterTitle,
                    sceneTitle: sceneTitle,
                    spinePrimaryTitle: sceneTitle,
                    spineContextLabel: StoryReadingSpineTitles.sceneContextLabel(
                        chapter: chapter,
                        chapterIndex: chapterIndex,
                        sceneIndex: sceneIndex,
                        targetCode: story.targetLanguageCode
                    ),
                    title: chapterTitle,
                    subtitle: nil,
                    body: scene.captionFor(story.targetLanguageCode).nilIfEmptyForPictureBook,
                    readingMatterPage: nil,
                    chapter: nil,
                    scene: scene,
                    panel: panel(for: item, in: story.storyLayout),
                    layoutPanels: layoutPanels(for: item, story: story, adapter: adapter),
                    audioClip: clipsBySceneID[item.id],
                    imageURL: adapter.sceneImageURL(scene: scene, chapterIndex: chapterIndex)
                )
            case .chapterQuiz(let chapterIndex):
                guard let chapter = story.chapters[safeForPictureBook: chapterIndex] else { return nil }
                return PictureBookSpreadModel(
                    id: item.id,
                    spineItem: item,
                    spreadIndex: spreadIndex,
                    storyTitle: story.title,
                    targetCode: story.targetLanguageCode,
                    nativeCode: story.nativeLanguageCode,
                    chapterIndex: chapterIndex,
                    chapterTitle: chapter.titleFor(story.targetLanguageCode).nilIfEmptyForPictureBook,
                    sceneTitle: nil,
                    spinePrimaryTitle: "Chapter Quiz",
                    spineContextLabel: StoryReadingSpineTitles.spineContextLabel(for: item, story: story, adapter: adapter),
                    title: "Chapter Quiz",
                    subtitle: nil,
                    body: nil,
                    readingMatterPage: nil,
                    chapter: chapter,
                    scene: nil,
                    panel: nil,
                    layoutPanels: [],
                    audioClip: nil,
                    imageURL: adapter.chapterImageURL(forChapterAt: chapterIndex)
                )
            case .chapterVocabulary(let chapterIndex):
                guard let chapter = story.chapters[safeForPictureBook: chapterIndex] else { return nil }
                return PictureBookSpreadModel(
                    id: item.id,
                    spineItem: item,
                    spreadIndex: spreadIndex,
                    storyTitle: story.title,
                    targetCode: story.targetLanguageCode,
                    nativeCode: story.nativeLanguageCode,
                    chapterIndex: chapterIndex,
                    chapterTitle: chapter.titleFor(story.targetLanguageCode).nilIfEmptyForPictureBook,
                    sceneTitle: nil,
                    spinePrimaryTitle: "Word Focus",
                    spineContextLabel: StoryReadingSpineTitles.spineContextLabel(for: item, story: story, adapter: adapter),
                    title: "Word Focus",
                    subtitle: nil,
                    body: chapter.vocabularyNoteForLanguage(story.targetLanguageCode),
                    readingMatterPage: nil,
                    chapter: chapter,
                    scene: nil,
                    panel: nil,
                    layoutPanels: [],
                    audioClip: nil,
                    imageURL: adapter.chapterImageURL(forChapterAt: chapterIndex)
                )
            }
        }
    }

    private static func coverURL(for story: Story) -> URL? {
        if let remoteCoverPath = story.remoteCoverPath?.nilIfEmptyForPictureBook {
            return AppConfig.chapterCoverURL(remoteCoverPath)
        }
        if let coverArt = story.coverArt?.nilIfEmptyForPictureBook {
            return AppConfig.chapterCoverURL(coverArt)
        }
        return nil
    }

    private static func panel(for item: StoryReadingSpineItem, in layout: StoryLayout?) -> PanelLayout? {
        guard case .scene(let chapterIndex, let sceneIndex) = item else { return nil }
        return layout?.flatSequence.first {
            $0.chapterIndex == chapterIndex && $0.sceneIndex == sceneIndex
        }
    }

    private static func layoutPanels(
        for item: StoryReadingSpineItem,
        story: Story,
        adapter: StoryReaderDataAdapter
    ) -> [PictureBookPanelModel] {
        guard case .scene(let chapterIndex, let sceneIndex) = item,
              let layout = story.storyLayout else { return [] }

        let matchingPage = layout.pages.first { page in
            if page.chapterIndex == chapterIndex && page.sceneIndex == sceneIndex {
                return true
            }
            return page.canvases.flatMap(\.panels).contains {
                $0.chapterIndex == chapterIndex && $0.sceneIndex == sceneIndex
            }
        }

        guard let matchingPage else { return [] }

        return matchingPage.canvases
            .flatMap(\.panels)
            .compactMap { panel in
                let panelItem = StoryReadingSpineItem.scene(chapterIndex: panel.chapterIndex, sceneIndex: panel.sceneIndex)
                guard let scene = adapter.scene(for: panelItem) else { return nil }
                return PictureBookPanelModel(
                    panel: panel,
                    scene: scene,
                    imageURL: adapter.sceneImageURL(scene: scene, chapterIndex: panel.chapterIndex)
                )
            }
    }
}

struct PictureBookSpreadModel: Identifiable {
    let id: String
    let spineItem: StoryReadingSpineItem
    let spreadIndex: Int
    let storyTitle: String
    let targetCode: String
    let nativeCode: String
    let chapterIndex: Int?
    let chapterTitle: String?
    let sceneTitle: String?
    let spinePrimaryTitle: String
    let spineContextLabel: String
    let title: String?
    let subtitle: String?
    let body: String?
    let readingMatterPage: ReadingMatterPage?
    let chapter: StoryChapter?
    let scene: StoryScene?
    let panel: PanelLayout?
    let layoutPanels: [PictureBookPanelModel]
    let audioClip: StorySceneAudioClip?
    let imageURL: URL?

    func headerSubtitle(
        story: Story,
        language: StorySessionView.DisplayLanguage
    ) -> String? {
        switch spineItem {
        case .cover:
            return nil
        case .readingMatterPage:
            return displayMatterTitle(language: language) ?? spineContextLabel
        case .chapter:
            return title?.nilIfEmptyForPictureBook ?? spineContextLabel
        case .scene(let chapterIndex, _):
            let chapter = story.chapters[safeForPictureBook: chapterIndex]
            let resolvedChapterTitle: String? = {
                guard let chapter else { return chapterTitle }
                switch language {
                case .target:
                    return chapter.titleFor(targetCode).nilIfEmptyForPictureBook
                case .native:
                    return chapter.titleFor(nativeCode).nilIfEmptyForPictureBook
                }
            }()
            return [resolvedChapterTitle, sceneTitle]
                .compactMap { $0?.nilIfEmptyForPictureBook }
                .joined(separator: " / ")
                .nilIfEmptyForPictureBook
        case .chapterQuiz, .chapterVocabulary:
            return chapterTitle?.nilIfEmptyForPictureBook ?? spineContextLabel
        }
    }

    func displayBody(language: StorySessionView.DisplayLanguage) -> String? {
        switch spineItem {
        case .readingMatterPage:
            guard let page = readingMatterPage else { return body }
            switch language {
            case .target:
                return page.bodyFor(targetCode).nilIfEmptyForPictureBook
            case .native:
                return page.bodyFor(nativeCode).nilIfEmptyForPictureBook
            }
        case .chapter:
            guard let chapter else { return body }
            switch language {
            case .target:
                return chapter.chapterIntroTextForLanguage(targetCode).nilIfEmptyForPictureBook
            case .native:
                return chapter.chapterIntroTextForLanguage(nativeCode).nilIfEmptyForPictureBook
            }
        case .scene:
            guard let scene else { return body }
            return scene.pictureBookPreviewText(langCode: language == .native ? nativeCode : targetCode)
        default:
            return body
        }
    }

    func displayMatterTitle(language: StorySessionView.DisplayLanguage) -> String? {
        guard let page = readingMatterPage else { return title?.nilIfEmptyForPictureBook }
        switch language {
        case .target:
            return page.titleFor(targetCode).nilIfEmptyForPictureBook
        case .native:
            return page.titleFor(nativeCode).nilIfEmptyForPictureBook
        }
    }

    var isChapterSupplement: Bool {
        switch spineItem {
        case .chapterQuiz, .chapterVocabulary:
            return true
        default:
            return false
        }
    }

    var isChapterIntro: Bool {
        if case .chapter = spineItem { return true }
        return false
    }

    var isScene: Bool {
        if case .scene = spineItem { return true }
        return false
    }
}

struct PictureBookPanelModel: Identifiable, Equatable {
    let id: String
    let panel: PanelLayout
    let scene: StoryScene
    let imageURL: URL?

    init(panel: PanelLayout, scene: StoryScene, imageURL: URL?) {
        self.id = "\(panel.id)-\(scene.sceneIndex)"
        self.panel = panel
        self.scene = scene
        self.imageURL = imageURL
    }
}

private struct PictureBookLoadingView: View {
    let title: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Loading story...")
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .navigationTitle(title)
    }
}

private struct PictureBookPlayerSheet: View {
    let spreads: [PictureBookSpreadModel]
    let currentSpreadIndex: Int
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
                    ForEach(Array(spreads.enumerated()), id: \.element.id) { index, spread in
                        Button {
                            onSelect(index)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: icon(for: spread))
                                    .frame(width: 24)
                                    .foregroundStyle(index == currentSpreadIndex ? Color.accentColor : .secondary)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(spread.spinePrimaryTitle)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(StoryReadingSpineTitles.spinePositionLabel(
                                        index: index,
                                        total: spreads.count,
                                        context: spread.spineContextLabel
                                    ))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if index == currentSpreadIndex {
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

    private func icon(for spread: PictureBookSpreadModel) -> String {
        switch spread.spineItem {
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

private struct PictureBookSpreadView: View {
    let spread: PictureBookSpreadModel
    let story: Story
    let selectedLanguage: StorySessionView.DisplayLanguage
    var supplementalPlayback: StorySupplementalAudioPlayback? = nil
    var onUserScroll: () -> Void = {}

    var body: some View {
        GeometryReader { geometry in
            let safeFrame = geometry.frame(in: .local)
            Color(.systemBackground)
                .overlay {
                    switch spread.spineItem {
                    case .cover:
                        coverLayout(in: safeFrame)
                    case .readingMatterPage:
                        readingMatterLayout(in: safeFrame)
                    case .chapter:
                        chapterIntroLayout(in: safeFrame)
                    case .chapterQuiz:
                        chapterQuizLayout(in: safeFrame)
                    case .chapterVocabulary:
                        chapterVocabularyLayout(in: safeFrame)
                    case .scene:
                        sceneLayout(in: safeFrame)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func chapterQuizLayout(in frame: CGRect) -> some View {
        let resolved: (questions: [ComprehensionQuestion], isStoryWideFallback: Bool) = {
            guard let chapter = spread.chapter else { return ([], false) }
            return ChapterComprehensionQuizResolver.questions(for: chapter, in: story)
        }()
        let title = resolved.isStoryWideFallback ? "Story Comprehension Quiz" : "Chapter Comprehension"
        return InlineChapterQuizView(questions: resolved.questions, title: title)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }

    private func chapterVocabularyLayout(in frame: CGRect) -> some View {
        InlineChapterVocabularyView(
            vocabularyNote: spread.chapter?.vocabularyNoteForLanguage(story.targetLanguageCode) ?? "",
            title: "Chapter Word Focus"
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var supplementalWordTimings: [WordTiming] {
        if spread.isChapterIntro, let chapter = spread.chapter {
            let code = selectedLanguage == .native ? story.nativeLanguageCode : story.targetLanguageCode
            return chapter.chapterIntroBodyWordTimingsForLanguage(code)
        }
        if let page = spread.readingMatterPage {
            let code = selectedLanguage == .native ? story.nativeLanguageCode : story.targetLanguageCode
            return page.bodyWordTimingsFor(code)
        }
        return supplementalPlayback?.wordTimings ?? []
    }

    private var showsSupplementalTimedText: Bool {
        spread.isChapterIntro || spread.readingMatterPage != nil
    }

    private var readingScrollGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width),
                      abs(value.translation.height) > 12 else { return }
                onUserScroll()
            }
    }

    private func imageHeight(in frame: CGRect) -> CGFloat {
        min(270, max(190, frame.height * 0.38))
    }

    private func proseBody(in frame: CGRect, spacing: CGFloat = 14) -> some View {
        let horizontalPadding: CGFloat = 18
        let contentWidth = max(1, frame.width - horizontalPadding * 2)

        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: spacing) {
                if !spread.isScene,
                   let title = spread.displayMatterTitle(language: selectedLanguage) ?? spread.title {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: contentWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let body = spread.displayBody(language: selectedLanguage) {
                    if showsSupplementalTimedText,
                       selectedLanguage == .target,
                       let playback = supplementalPlayback,
                       playback.isUsingGeneratedAudio,
                       !supplementalWordTimings.isEmpty {
                        TimedTextView(
                            segment: StorySegmentTiming(
                                speaker: "",
                                text: body,
                                startTime: 0,
                                endTime: .greatestFiniteMagnitude,
                                timings: supplementalWordTimings
                            ),
                            currentTime: playback.currentTime,
                            includesPadding: false
                        )
                        .frame(width: contentWidth, alignment: .leading)
                    } else if selectedLanguage == .target {
                        TappableStoryText(
                            text: body,
                            font: .body.weight(.regular),
                            lineSpacing: 6,
                            foregroundColor: .primary
                        )
                        .frame(width: contentWidth, alignment: .leading)
                    } else {
                        Text(body)
                            .font(.body.weight(.regular))
                            .lineSpacing(6)
                            .foregroundStyle(.secondary)
                            .frame(width: contentWidth, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 18)
            .frame(width: contentWidth, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
        }
        .simultaneousGesture(readingScrollGesture)
        .frame(minWidth: frame.width, maxWidth: frame.width, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
        .clipped()
    }

    private func coverLayout(in frame: CGRect) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color(.systemBackground)
                .ignoresSafeArea()

            PictureBookImage(url: spread.imageURL, cropRegion: .center, fillsFrame: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )

            darkTextPanel(maxHeight: frame.height * 0.34)
                .padding(.horizontal, 18)
                .padding(.bottom, 128)
        }
    }

    private func readingMatterLayout(in frame: CGRect) -> some View {
        VStack(spacing: 0) {
            PictureBookImage(url: spread.imageURL, cropRegion: .center)
                .frame(height: imageHeight(in: frame))
                .frame(width: frame.width)
                .clipped()

            proseBody(in: frame)

            Color.clear.frame(height: audioBottomSpacer)
        }
        .frame(width: frame.width)
        .clipped()
    }

    private func chapterIntroLayout(in frame: CGRect) -> some View {
        readingMatterLayout(in: frame)
    }

    private func sceneLayout(in frame: CGRect) -> some View {
        let panelModels = spread.layoutPanels.isEmpty
            ? [PictureBookPanelModel(
                panel: spread.panel ?? PanelLayout(chapterIndex: 0, sceneIndex: spread.scene?.sceneIndex ?? 0),
                scene: spread.scene ?? StoryScene(sceneIndex: 0),
                imageURL: spread.imageURL
            )]
            : spread.layoutPanels

        return VStack(spacing: 0) {
            ZStack {
                PictureBookImage(
                    url: spread.imageURL,
                    cropRegion: spread.panel?.cropRegion ?? spread.scene?.cropRegion ?? .center
                )

                ForEach(panelModels.filter { $0.imageURL != spread.imageURL }) { panelModel in
                    let panelFrame = PictureBookLayout.panelFrame(for: panelModel.panel, in: CGRect(
                        x: 0,
                        y: 0,
                        width: frame.width,
                        height: imageHeight(in: frame)
                    ))
                    PictureBookImage(
                        url: panelModel.imageURL ?? spread.imageURL,
                        cropRegion: panelModel.panel.cropRegion
                    )
                    .frame(width: panelFrame.width, height: panelFrame.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .position(x: panelFrame.midX, y: panelFrame.midY)
                }
            }
            .frame(height: imageHeight(in: frame))
            .frame(width: frame.width)
            .clipped()

            proseBody(in: frame)

            Color.clear.frame(height: audioBottomSpacer)
        }
        .frame(width: frame.width)
        .clipped()
    }

    private var audioBottomSpacer: CGFloat {
        88
    }

    private func darkTextPanel(maxHeight: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let title = spread.title {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }

                if let subtitle = spread.subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

                if let body = spread.displayBody(language: selectedLanguage) {
                    if selectedLanguage == .target {
                        TappableStoryText(
                            text: body,
                            font: .title3.weight(.semibold),
                            lineSpacing: 4,
                            foregroundColor: .white
                        )
                    } else {
                        Text(body)
                            .font(.title3.weight(.semibold))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .simultaneousGesture(readingScrollGesture)
        .frame(maxWidth: 520, maxHeight: maxHeight, alignment: .leading)
        .background(.black.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PictureBookImage: View {
    let url: URL?
    let cropRegion: CropRegion
    var fillsFrame: Bool = true

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                if fillsFrame {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cropRegion.pictureBookAlignment)
                } else {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            case .failure:
                placeholder
            case .empty:
                placeholder.overlay { ProgressView().tint(.white) }
            @unknown default:
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.indigo.opacity(0.55), Color.teal.opacity(0.45), Color.orange.opacity(0.38)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

enum PictureBookLayout {
    static func normalized(_ value: Double) -> CGFloat {
        let unitValue = value > 1 ? value / 100.0 : value
        return CGFloat(min(max(unitValue, 0), 1))
    }

    static func panelFrame(for panel: PanelLayout?, in frame: CGRect) -> CGRect {
        let safeTop: CGFloat = 68
        let safeBottom: CGFloat = 300
        let horizontalInset: CGFloat = 18
        let drawable = frame.insetBy(dx: horizontalInset, dy: 0)
            .inset(by: UIEdgeInsets(top: safeTop, left: 0, bottom: safeBottom, right: 0))

        guard let panel else { return drawable }

        let x = normalized(panel.x)
        let y = normalized(panel.y)
        let width = max(0.24, normalized(panel.width))
        let height = max(0.24, normalized(panel.height))
        let raw = CGRect(
            x: drawable.minX + drawable.width * x,
            y: drawable.minY + drawable.height * y,
            width: drawable.width * min(width, 1 - x),
            height: drawable.height * min(height, 1 - y)
        )

        return raw.intersection(drawable).isNull ? drawable : raw.intersection(drawable)
    }
}

private extension Collection {
    subscript(safeForPictureBook index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var nilIfEmptyForPictureBook: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension StoryScene {
    func pictureBookPreviewText(langCode: String) -> String? {
        var lines: [String] = []

        if let caption = captionFor(langCode).nilIfEmptyForPictureBook {
            lines.append(caption)
        }
        for dialogue in dialoguesFor(langCode) {
            guard !dialogue.character.isEmpty,
                  let line = dialogue.text.nilIfEmptyForPictureBook else { continue }
            lines.append("\(dialogue.character): \(line)")
        }
        if lines.isEmpty, let script = scriptFor(langCode)?.nilIfEmptyForPictureBook {
            lines.append(script)
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

private extension CropRegion {
    var pictureBookAlignment: Alignment {
        switch self {
        case .topLeft:
            return .topLeading
        case .topRight:
            return .topTrailing
        case .bottomLeft:
            return .bottomLeading
        case .bottomRight:
            return .bottomTrailing
        case .topHalf:
            return .top
        case .bottomHalf:
            return .bottom
        case .center, .centre, .full:
            return .center
        }
    }
}

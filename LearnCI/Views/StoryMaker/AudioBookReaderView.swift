import SwiftUI
import Combine
import SwiftData

struct AudioBookReaderView: View {
    let story: Story
    private let initialNavIndex: Int
    private let initialPlaybackPosition: Double?
    private let onProgressChange: ((StoryReaderProgressUpdate) -> Void)?

    @State private var isPreparingReader = true
    @State private var readerIssue: StoryReaderRequirementIssue?
    @State private var clips: [StorySceneAudioClip] = []
    @State private var navItems: [AudioBookNavItem] = []
    @State private var sceneCountByChapter: [Int: Int] = [:]
    @State private var currentClipIndex = 0
    @State private var selectedNavItemID: String?
    @State private var isPlaying = false
    @State private var loadingAudioLabel: String?
    @State private var sliderValue = 0.0
    @State private var duration = 0.0
    @State private var playbackRate: Float = 1.0
    @State private var showTranscript = false
    @State private var showTracklist = false
    @State private var prefetchingClipIDs: Set<String> = []
    @State private var lockScreenArtwork: UIImage?
    @State private var sleepTimerMode: AudioBookSleepTimerMode = .inactive
    @State private var sleepTimerEndDate: Date?
    @State private var isAutoContinueEnabled = true
    @State private var supplementalPlayback = StorySupplementalAudioPlayback()
    @State private var lastSavedPlaybackSecond = -1
    @State private var startTime: Date?
    @State private var didPlayAudio = false
    @State private var didLogActivity = false
    @State private var usesAudioBookSidePane = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable private var audioManager = AudioManager.shared
    private let sleepTimerTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let supplementalTicker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    init(
        story: Story,
        initialNavIndex: Int = 0,
        initialPlaybackPosition: Double? = nil,
        onProgressChange: ((StoryReaderProgressUpdate) -> Void)? = nil
    ) {
        self.story = story
        self.initialNavIndex = initialNavIndex
        self.initialPlaybackPosition = initialPlaybackPosition
        self.onProgressChange = onProgressChange
    }

    private var isBufferingPlayback: Bool {
        audioManager.streamIsBuffering && audioManager.streamPlayer != nil
    }

    private var readerAdapter: StoryReaderDataAdapter {
        StoryReaderDataAdapter(story: story)
    }

    private var currentChapterClips: [StorySceneAudioClip] {
        guard let chapterIndex = currentChapterIndex else { return [] }
        return readerAdapter.chapterPlaybackClips(forChapter: chapterIndex)
    }

    private var currentSceneClipIndex: Int {
        guard let chapterIndex = currentChapterIndex,
              clips.indices.contains(currentClipIndex) else { return 0 }
        let clip = clips[currentClipIndex]
        let chapterClips = readerAdapter.chapterPlaybackClips(forChapter: chapterIndex)
        return chapterClips.firstIndex { $0.id == clip.id } ?? 0
    }

    private var currentClipStartOffset: Double {
        let chapterClips = currentChapterClips
        let sceneIndex = currentSceneClipIndex
        guard chapterClips.indices.contains(sceneIndex) else { return 0 }
        return chapterClips[sceneIndex].startOffset
    }

    private var selectedNavItem: AudioBookNavItem? {
        if let selectedNavItemID,
           let item = navItems.first(where: { $0.id == selectedNavItemID }) {
            return item
        }
        return navItems.first
    }

    private var firstFrontReadingMatterItem: AudioBookNavItem? {
        guard let firstChapterIndex = navItems.firstIndex(where: { $0.kind == .chapter }) else {
            return navItems.first(where: { $0.kind == .readingMatter })
        }
        return navItems[..<firstChapterIndex].first(where: { $0.kind == .readingMatter })
    }

    private var storyCoverImageURL: URL? {
        Self.storyCoverImageURL(for: story)
    }

    var body: some View {
        Group {
            if isPreparingReader {
                AudioBookLoadingView(title: story.title)
            } else if let issue = readerIssue {
                StoryReaderUnavailableView(title: issue.title, message: issue.message)
            } else {
                podcastBody
            }
        }
        .navigationTitle("Audio Book")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if startTime == nil {
                startTime = Date()
            }
            prepareReaderIfNeeded()
        }
        .mediaPlaybackLifecycle(
            onUserLeave: {
                cancelSleepTimer()
                cleanupSession()
            },
            onEnterBackground: { updateNowPlayingMetadata() }
        )
        .onReceive(supplementalTicker) { _ in
            guard isOnReadingMatterSelection else { return }
            supplementalPlayback.syncStreamState()
            sliderValue = supplementalPlayback.currentTime
            if supplementalPlayback.duration > 0 {
                duration = supplementalPlayback.duration
            }
            isPlaying = supplementalPlayback.isPlaying
            saveTimedReadingProgressIfNeeded(position: sliderValue)
        }
        .onChange(of: currentClipIndex) { _, _ in
            syncSelectionToCurrentClip()
            refreshChapterDuration()
            loadLockScreenArtwork()
            updateNowPlayingMetadata()
        }
        .onChange(of: selectedNavItemID) { _, _ in
            loadLockScreenArtwork()
            prepareSupplementalForSelectedNavItem()
            saveReadingProgress()
        }
        .onChange(of: audioManager.streamFinished) { _, finished in
            guard finished else { return }
            advanceAfterClipFinished()
        }
        .onChange(of: audioManager.streamCurrentTime) { _, time in
            guard !isOnReadingMatterSelection else { return }
            guard audioManager.streamPlayer != nil, currentChapterIndex != nil else { return }
            sliderValue = currentClipStartOffset + time
            saveTimedReadingProgressIfNeeded(position: sliderValue)
            updateNowPlayingMetadata()
        }
        .onReceive(sleepTimerTicker) { _ in
            guard let endDate = sleepTimerEndDate, Date() >= endDate else { return }
            fireSleepTimer()
        }
        .onChange(of: audioManager.streamDuration) { _, streamDuration in
            guard !isOnReadingMatterSelection else { return }
            guard streamDuration > 0, let chapterIndex = currentChapterIndex else { return }
            let resolvedDuration = readerAdapter.duration(
                forChapter: chapterIndex,
                currentClipIndex: currentSceneClipIndex,
                currentStreamDuration: streamDuration,
                fallback: streamDuration,
                includeIntro: true
            )
            if resolvedDuration > 0, abs(duration - resolvedDuration) > 0.5 {
                duration = resolvedDuration
            }
        }
        .onChange(of: audioManager.isStreaming) { _, streaming in
            if isOnReadingMatterSelection {
                if supplementalPlayback.isUsingGeneratedAudio {
                    isPlaying = streaming
                }
                return
            }
            isPlaying = streaming
        }
        .sheet(isPresented: $showTranscript) {
            if let item = selectedNavItem {
                AudioBookTranscriptSheet(
                    story: story,
                    navItem: item,
                    clips: clips,
                    currentClipIndex: currentClipIndex,
                    audioManager: audioManager,
                    adapter: StoryReaderDataAdapter(story: story)
                )
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: Binding(
            get: { showTracklist && !usesAudioBookSidePane },
            set: { if !$0 { showTracklist = false } }
        )) {
            audioBookSidePane
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var playerSheetChapterClips: [StorySceneAudioClip] {
        guard selectedNavItem?.kind == .chapter,
              let currentChapterIndex else { return [] }
        return readerAdapter.chapterPlaybackClips(forChapter: currentChapterIndex)
    }

    @ViewBuilder
    private var tracklistSheet: some View {
        if selectedNavItem?.kind == .chapter, let chapterIndex = currentChapterIndex {
            AudioBookChapterTracklistSheet(
                story: story,
                chapterIndex: chapterIndex,
                chapterClips: readerAdapter.chapterPlaybackClips(forChapter: chapterIndex),
                globalClips: clips,
                currentClipIndex: currentClipIndex,
                adapter: readerAdapter
            ) { globalIndex in
                showTracklist = false
                playClip(at: globalIndex, autoplay: true)
            }
        } else {
            AudioBookMacroTracklistSheet(
                navItems: navItems,
                selectedNavItemID: selectedNavItemID
            ) { item in
                showTracklist = false
                selectNavItem(item)
            }
        }
    }

    private func prepareReaderIfNeeded() {
        guard isPreparingReader, clips.isEmpty else { return }

        Task(priority: .userInitiated) {
            let adapter = StoryReaderDataAdapter(story: story)
            let issue = adapter.requirementIssue(for: .audioBook)
            let loadedClips = issue == nil ? adapter.audioBookPlaybackClips() : []
            let loadedNavItems = issue == nil
                ? Self.buildNavItems(story: story, adapter: adapter, clips: loadedClips)
                : []
            var sceneCounts: [Int: Int] = [:]
            for clip in loadedClips where !clip.isChapterIntro {
                sceneCounts[clip.chapterIndex, default: 0] += 1
            }

            await MainActor.run {
                readerIssue = issue
                clips = loadedClips
                navItems = loadedNavItems
                sceneCountByChapter = sceneCounts
                isPreparingReader = false
                bootstrapSelection()
                prepareSupplementalForSelectedNavItem()
                prepareInitialPlaybackPositionIfNeeded()
                saveReadingProgress()
                if isOnReadingMatterSelection {
                    startReadingMatterPlayback()
                }
                loadLockScreenArtwork()
            }

            if issue == nil, let firstClip = loadedClips.first {
                await prefetchClipToCache(firstClip)
            }
        }
    }

    private static func buildNavItems(
        story: Story,
        adapter: StoryReaderDataAdapter,
        clips: [StorySceneAudioClip]
    ) -> [AudioBookNavItem] {
        let coverURL = Self.storyCoverImageURL(for: story)
        var firstClipByChapter: [Int: Int] = [:]
        for (index, clip) in clips.enumerated() where firstClipByChapter[clip.chapterIndex] == nil {
            firstClipByChapter[clip.chapterIndex] = index
        }

        return adapter.items(for: .audioBook).compactMap { item in
            switch item {
            case .cover:
                return AudioBookNavItem(
                    id: item.id,
                    spineItem: item,
                    kind: .cover,
                    title: story.title,
                    subtitle: "\(story.language.displayName) · Level \(story.level)",
                    imageURL: coverURL,
                    chapterIndex: nil,
                    firstClipIndex: nil
                )

            case .readingMatterPage:
                guard let page = adapter.readingMatterPage(for: item) else { return nil }
                let title = page.titleTarget?.nilIfEmptyAudioBook
                    ?? page.titleNative?.nilIfEmptyAudioBook
                    ?? "Reading Matter"
                let body = page.bodyTarget?.nilIfEmptyAudioBook ?? page.bodyNative?.nilIfEmptyAudioBook
                let subtitle: String? = {
                    guard let body else { return nil }
                    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return nil }
                    return trimmed.count <= 120 ? trimmed : String(trimmed.prefix(120)) + "…"
                }()
                return AudioBookNavItem(
                    id: item.id,
                    spineItem: item,
                    kind: .readingMatter,
                    title: title,
                    subtitle: subtitle,
                    imageURL: coverURL,
                    chapterIndex: nil,
                    firstClipIndex: nil
                )

            case .chapter(let index):
                guard let chapter = adapter.chapter(for: item) else { return nil }
                let title = chapter.titleTargetLanguage.nilIfEmptyAudioBook
                    ?? "Chapter \(index + 1)"
                let subtitle = chapter.tableOfContentsOverview
                    ?? clips.first(where: { $0.chapterIndex == index })?.caption.nilIfEmptyAudioBook
                return AudioBookNavItem(
                    id: item.id,
                    spineItem: item,
                    kind: .chapter,
                    title: title,
                    subtitle: subtitle,
                    imageURL: adapter.chapterImageURL(forChapterAt: index),
                    chapterIndex: index,
                    firstClipIndex: firstClipByChapter[index]
                )

            case .scene:
                return nil
            }
        }
    }

    private static func storyCoverImageURL(for story: Story) -> URL? {
        if let path = story.remoteCoverPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty,
           let url = AppConfig.chapterCoverURL(path) {
            return url
        }
        if let path = story.coverArt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty,
           let url = AppConfig.chapterCoverURL(path) {
            return url
        }
        return nil
    }

    private var podcastBody: some View {
        GeometryReader { _ in
            Group {
                if usesStoryReaderSidePane {
                    HStack(spacing: 0) {
                        audioBookMainColumn(showsSpineNavigation: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Divider()

                        audioBookSidePane
                            .frame(width: 380)
                    }
                } else {
                    audioBookMainColumn(showsSpineNavigation: true)
                }
            }
            .onAppear {
                updateAudioBookSidePaneState()
            }
            .onChange(of: horizontalSizeClass) { _, _ in
                updateAudioBookSidePaneState()
            }
        }
        .background { podcastBackground }
    }

    private func audioBookMainColumn(showsSpineNavigation: Bool) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    if let item = selectedNavItem {
                        currentItemHero(item)
                    }

                    if isBufferingPlayback {
                        audioLoadingBanner
                    }

                    if showsSpineNavigation {
                        spineNavigationSection
                    }

                    Color.clear.frame(height: 140)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            playerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var audioBookSidePane: some View {
        AudioBookPlayerSheet(
            navItems: navItems,
            selectedNavItemID: selectedNavItemID,
            currentChapterTitle: selectedNavItem?.kind == .chapter ? selectedNavItem?.title : nil,
            chapterClips: playerSheetChapterClips,
            globalClips: clips,
            currentClipIndex: currentClipIndex,
            adapter: readerAdapter,
            story: story,
            isAutoContinueEnabled: $isAutoContinueEnabled,
            sleepTimerMode: $sleepTimerMode,
            playbackRate: $playbackRate,
            onChangeRate: setRate,
            onSelectTimer: applySleepTimer,
            onSelectNavItem: { item in
                showTracklist = false
                selectNavItem(item)
            },
            onSelectClip: { globalIndex in
                showTracklist = false
                playClip(at: globalIndex, autoplay: true)
            }
        )
    }

    private var usesStoryReaderSidePane: Bool {
        AdaptiveLayoutPolicy.usesStoryReaderSidePane(horizontalSizeClass: horizontalSizeClass)
    }

    private func updateAudioBookSidePaneState() {
        usesAudioBookSidePane = usesStoryReaderSidePane
        if usesStoryReaderSidePane {
            showTracklist = false
        }
    }

    @ViewBuilder
    private var podcastBackground: some View {
        ZStack {
            Color(.systemBackground)

            if let url = selectedNavItem?.imageURL ?? storyCoverImageURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
                .blur(radius: 36)
                .opacity(0.28)
                .allowsHitTesting(false)
            }

            LinearGradient(
                colors: [
                    Color(.systemBackground).opacity(0.35),
                    Color(.systemBackground).opacity(0.92),
                    Color(.systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var audioLoadingBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            VStack(alignment: .leading, spacing: 2) {
                Text("Loading audio")
                    .font(.subheadline.weight(.semibold))
                Text(loadingAudioLabel ?? "Preparing narration…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func currentItemHero(_ item: AudioBookNavItem) -> some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let url = item.imageURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            case .failure, .empty:
                                heroPlaceholder(for: item)
                            @unknown default:
                                heroPlaceholder(for: item)
                            }
                        }
                    } else {
                        heroPlaceholder(for: item)
                    }
                }
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)

                if isNowPlaying(item) {
                    Label("Now Playing", systemImage: "waveform")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(10)
                }
            }

            VStack(spacing: 6) {
                Text(item.kind.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(item.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .center)

                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if let clip = clips[safeAudioBook: currentClipIndex],
                   item.kind == .chapter,
                   item.chapterIndex == clip.chapterIndex {
                    if clip.isChapterIntro {
                        Text("Chapter Intro")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("Scene \(clip.sceneIndex + 1) of \(sceneCountByChapter[clip.chapterIndex] ?? 1)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if item.kind == .chapter, let chapterIndex = item.chapterIndex {
                chapterSceneChipStrip(chapterIndex: chapterIndex)
            }

            Button {
                showTranscript = true
            } label: {
                Label("Show Transcript", systemImage: "text.quote")
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
    }

    private func chapterSceneChipStrip(chapterIndex: Int) -> some View {
        let chapterClips = readerAdapter.chapterPlaybackClips(forChapter: chapterIndex)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chapterClips) { clip in
                    let isActive = clips[safeAudioBook: currentClipIndex]?.id == clip.id
                    Button {
                        guard let globalIndex = clips.firstIndex(where: { $0.id == clip.id }) else { return }
                        playClip(at: globalIndex, autoplay: isPlaying)
                    } label: {
                        Text(clip.isChapterIntro ? "Intro" : "\(clip.sceneIndex + 1)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isActive ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(isActive ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
                            )
                            .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func heroPlaceholder(for item: AudioBookNavItem) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor.opacity(0.85))
        }
    }

    private var spineNavigationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In This Story")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(navItems) { item in
                Button {
                    selectNavItem(item)
                } label: {
                    AudioBookNavRow(
                        item: item,
                        isSelected: selectedNavItem?.id == item.id,
                        isNowPlaying: isNowPlaying(item)
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var playerBar: some View {
        VStack(spacing: 10) {
            if sleepTimerMode != .inactive {
                sleepTimerBanner
            }

            AudioPlayerBar(
                isPlaying: $isPlaying,
                sliderValue: $sliderValue,
                duration: max(playerBarDuration, 1),
                playbackRate: $playbackRate,
                ambientVolume: .constant(0),
                isAmbientPlaying: false,
                canSeek: playerBarCanSeek,
                canControlPlayback: playerBarCanControl,
                playbackContextLabel: playerBarContextLabel,
                isBuffering: playerBarIsBuffering,
                bufferingLabel: loadingAudioLabel ?? "Loading audio…",
                showsRateControl: false,
                onPlayPause: togglePlay,
                onSkipForward: skipForward,
                onSkipBackward: skipBackward,
                onSeek: seekPlayback,
                onChangeRate: setRate,
                onNextChapter: nextPlaybackAction,
                onPreviousChapter: previousPlaybackAction,
                onSkipPreviousChapter: skipToPreviousChapterAction,
                onSkipNextChapter: skipToNextChapterAction,
                onShowSpine: { showTracklist = true }
            )
            .disabled(playerBarIsBuffering)
        }
    }

    private var isOnReadingMatterSelection: Bool {
        selectedNavItem?.kind == .readingMatter
    }

    private var playerBarDuration: Double {
        isOnReadingMatterSelection ? supplementalPlayback.duration : duration
    }

    private var playerBarCanSeek: Bool {
        if isOnReadingMatterSelection {
            return supplementalPlayback.canSeek
        }
        return selectedNavItem?.kind == .chapter && !isBufferingPlayback
    }

    private var playerBarCanControl: Bool {
        if isOnReadingMatterSelection {
            return currentReadingMatterCanPlay
        }
        return !isBufferingPlayback
    }

    private var playerBarIsBuffering: Bool {
        if isOnReadingMatterSelection {
            return supplementalPlayback.isLoading
        }
        return isBufferingPlayback
    }

    private var playerBarContextLabel: String? {
        guard isOnReadingMatterSelection, currentReadingMatterCanPlay else { return nil }
        return supplementalPlayback.isPlaying ? "Reading Matter · Now Playing" : "Reading Matter"
    }

    private var currentReadingMatterCanPlay: Bool {
        guard let item = selectedNavItem,
              let page = readerAdapter.readingMatterPage(for: item.spineItem) else { return false }
        return page.hasGeneratedAudio(preferNative: false) || readingMatterSpeakableText(for: page) != nil
    }

    private func readingMatterSpeakableText(for page: ReadingMatterPage) -> String? {
        var parts: [String] = []
        if let title = page.titleTarget?.nilIfEmptyAudioBook ?? page.titleNative?.nilIfEmptyAudioBook {
            parts.append(title)
        }
        if let body = page.bodyTarget?.nilIfEmptyAudioBook ?? page.bodyNative?.nilIfEmptyAudioBook {
            parts.append(body)
        }
        let text = parts.joined(separator: ". ")
        return text.isEmpty ? nil : text
    }

    private func prepareSupplementalForSelectedNavItem() {
        supplementalPlayback.onFinished = nil
        guard isOnReadingMatterSelection,
              let item = selectedNavItem,
              let page = readerAdapter.readingMatterPage(for: item.spineItem),
              case .readingMatterPage(let pageIndex, _) = item.spineItem else {
            supplementalPlayback.stop()
            return
        }

        supplementalPlayback.bind(story: story, audioManager: audioManager)
        supplementalPlayback.setRate(playbackRate)
        supplementalPlayback.prepareReadingMatter(
            pageIndex: pageIndex,
            page: page,
            preferNative: false
        )
        supplementalPlayback.onFinished = {
            advanceAfterReadingMatterFinished()
        }
    }

    private func startReadingMatterPlayback() {
        guard isOnReadingMatterSelection,
              let page = selectedNavItem.flatMap({ readerAdapter.readingMatterPage(for: $0.spineItem) }) else { return }

        audioManager.stopAudio()
        supplementalPlayback.syncPlayback(
            shouldPlay: true,
            speakableText: readingMatterSpeakableText(for: page)
        )
        isPlaying = supplementalPlayback.isPlaying
        if isPlaying {
            didPlayAudio = true
        }
    }

    private func advanceAfterReadingMatterFinished() {
        guard isAutoContinueEnabled else {
            isPlaying = false
            return
        }
        guard let currentID = selectedNavItemID,
              let index = navItems.firstIndex(where: { $0.id == currentID }),
              index < navItems.count - 1 else {
            isPlaying = false
            return
        }

        let nextItem = navItems[index + 1]
        selectNavItem(nextItem, autoplay: true)
    }

    private func stopSupplementalPlayback() {
        supplementalPlayback.stop()
        if isOnReadingMatterSelection {
            isPlaying = false
            sliderValue = 0
            duration = 0
        }
    }

    private var nextPlaybackAction: (() -> Void)? {
        if isOnReadingMatterSelection || selectedNavItem?.kind == .cover {
            return nextNavItemAction
        }
        return nextClipAction
    }

    private var previousPlaybackAction: (() -> Void)? {
        if isOnReadingMatterSelection || selectedNavItem?.kind == .cover {
            return previousNavItemAction
        }
        return previousClipAction
    }

    private var nextNavItemAction: (() -> Void)? {
        guard let currentID = selectedNavItemID,
              let index = navItems.firstIndex(where: { $0.id == currentID }),
              index < navItems.count - 1 else { return nil }
        return { selectNavItem(navItems[index + 1]) }
    }

    private var previousNavItemAction: (() -> Void)? {
        guard let currentID = selectedNavItemID,
              let index = navItems.firstIndex(where: { $0.id == currentID }),
              index > 0 else { return nil }
        return { selectNavItem(navItems[index - 1]) }
    }

    private func seekPlayback(_ value: Double) {
        if isOnReadingMatterSelection, supplementalPlayback.canSeek {
            supplementalPlayback.seek(to: value)
            sliderValue = value
            return
        }
        seekToChapterTime(value)
    }

    private var nextClipAction: (() -> Void)? {
        currentClipIndex < clips.count - 1 ? { nextClip() } : nil
    }

    private var previousClipAction: (() -> Void)? {
        currentClipIndex > 0 ? { previousClip() } : nil
    }

    private var skipToNextChapterAction: (() -> Void)? {
        guard let chapterIndex = currentChapterIndex else { return nil }
        guard let next = navItems.first(where: {
            $0.kind == .chapter && ($0.chapterIndex ?? -1) > chapterIndex
        }), let clipIndex = next.firstClipIndex else { return nil }
        return { playClip(at: clipIndex, autoplay: isPlaying) }
    }

    private var skipToPreviousChapterAction: (() -> Void)? {
        guard let chapterIndex = currentChapterIndex else { return nil }
        guard let previous = navItems.last(where: {
            $0.kind == .chapter && ($0.chapterIndex ?? Int.max) < chapterIndex
        }), let clipIndex = previous.firstClipIndex else { return nil }
        return { playClip(at: clipIndex, autoplay: isPlaying) }
    }

    private func isNowPlaying(_ item: AudioBookNavItem) -> Bool {
        if item.kind == .readingMatter {
            return isPlaying && selectedNavItem?.id == item.id
        }
        guard item.kind == .chapter, let chapterIndex = item.chapterIndex else { return false }
        guard isPlaying else { return false }
        return currentChapterIndex == chapterIndex
    }

    private func bootstrapSelection() {
        if navItems.indices.contains(initialNavIndex) {
            selectedNavItemID = navItems[initialNavIndex].id
            if let clipIndex = navItems[initialNavIndex].firstClipIndex {
                currentClipIndex = clipIndex
            }
            return
        }

        if let firstMatter = firstFrontReadingMatterItem {
            selectedNavItemID = firstMatter.id
        } else if let cover = navItems.first(where: { $0.kind == .cover }) {
            selectedNavItemID = cover.id
        } else {
            selectedNavItemID = navItems.first?.id
        }
    }

    private func syncSelectionToCurrentClip() {
        guard supplementalPlayback.activeContent == .none else { return }
        guard let chapterIndex = currentChapterIndex,
              let item = navItems.first(where: { $0.kind == .chapter && $0.chapterIndex == chapterIndex }) else { return }
        selectedNavItemID = item.id
    }

    private func selectNavItem(_ item: AudioBookNavItem, autoplay: Bool = false) {
        selectedNavItemID = item.id
        switch item.kind {
        case .chapter:
            stopSupplementalPlayback()
            if let clipIndex = item.firstClipIndex {
                playClip(at: clipIndex, autoplay: true)
            }
        case .readingMatter:
            audioManager.stopAudio()
            isPlaying = false
            sliderValue = 0
            duration = 0
            prepareSupplementalForSelectedNavItem()
            if autoplay {
                startReadingMatterPlayback()
            }
        case .cover:
            stopSupplementalPlayback()
            if audioManager.isStreaming {
                audioManager.pauseStream()
                isPlaying = false
            }
            if autoplay {
                beginPlaybackFromCover()
            }
        }
    }

    private func beginPlaybackFromCover() {
        if let firstMatter = firstFrontReadingMatterItem {
            selectNavItem(firstMatter, autoplay: true)
            return
        }
        if let firstChapter = navItems.first(where: { $0.kind == .chapter }) {
            selectNavItem(firstChapter)
        }
    }

    private func togglePlay() {
        switch selectedNavItem?.kind {
        case .readingMatter:
            let shouldPlay = !supplementalPlayback.isPlaying
            supplementalPlayback.syncPlayback(
                shouldPlay: shouldPlay,
                speakableText: selectedNavItem.flatMap { readerAdapter.readingMatterPage(for: $0.spineItem) }
                    .flatMap { readingMatterSpeakableText(for: $0) }
            )
            isPlaying = supplementalPlayback.isPlaying
            if isPlaying {
                didPlayAudio = true
            }

        case .cover:
            beginPlaybackFromCover()

        case .chapter:
            if audioManager.streamPlayer == nil {
                playClip(at: currentClipIndex, autoplay: true)
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

        case .none:
            beginPlaybackFromCover()
        }
    }

    private func skipForward() {
        if isOnReadingMatterSelection, supplementalPlayback.canSeek {
            seekPlayback(min(sliderValue + 15, max(supplementalPlayback.duration, 1)))
            return
        }
        guard selectedNavItem?.kind == .chapter else { return }
        seekToChapterTime(min(sliderValue + 15, duration))
    }

    private func skipBackward() {
        if isOnReadingMatterSelection, supplementalPlayback.canSeek {
            seekPlayback(max(0, sliderValue - 15))
            return
        }
        guard selectedNavItem?.kind == .chapter else { return }
        seekToChapterTime(max(sliderValue - 15, 0))
    }

    private func seekToChapterTime(_ chapterTime: Double) {
        guard let chapterIndex = currentChapterIndex else { return }
        guard let target = readerAdapter.clipIndex(forChapter: chapterIndex, localTime: chapterTime, includeIntro: true) else { return }

        let chapterClips = readerAdapter.chapterPlaybackClips(forChapter: chapterIndex)
        guard chapterClips.indices.contains(target.index) else { return }
        let targetClip = chapterClips[target.index]
        guard let globalIndex = clips.firstIndex(where: { $0.id == targetClip.id }) else { return }

        if globalIndex == currentClipIndex {
            audioManager.seekStream(to: target.offset)
            sliderValue = chapterTime
        } else {
            playClip(at: globalIndex, autoplay: isPlaying, startAt: target.offset)
        }
    }

    private func refreshChapterDuration() {
        guard let chapterIndex = currentChapterIndex else { return }
        let resolvedDuration = readerAdapter.duration(
            forChapter: chapterIndex,
            currentClipIndex: currentSceneClipIndex,
            currentStreamDuration: audioManager.streamDuration,
            fallback: audioManager.streamDuration,
            includeIntro: true
        )
        if resolvedDuration > 0 {
            duration = resolvedDuration
        }
    }

    private func playClip(at index: Int, autoplay: Bool, startAt: Double = 0) {
        guard clips.indices.contains(index) else { return }
        stopSupplementalPlayback()
        currentClipIndex = index
        let clip = clips[index]
        if clip.isChapterIntro {
            loadingAudioLabel = "Chapter \(clip.chapterIndex + 1) · Intro"
        } else {
            loadingAudioLabel = "Chapter \(clip.chapterIndex + 1) · Scene \(clip.sceneIndex + 1)"
        }

        let playbackURL: URL? = StoryReaderDataAdapter.cachedAudioURL(
            storyID: story.id,
            clip: clip,
            storyUpdatedAt: story.updatedAt
        ) ?? StoryReaderDataAdapter.remoteAudioURL(for: clip.urlString)

        guard let url = playbackURL else { return }

        startPlayback(url: url, clip: clip, autoplay: autoplay, startAt: startAt)
        prefetchClipToCache(at: index + 1)
        if StoryReaderDataAdapter.cachedAudioURL(storyID: story.id, clip: clip, storyUpdatedAt: story.updatedAt) == nil {
            Task { await prefetchClipToCache(clip) }
        }
    }

    private func startPlayback(url: URL, clip: StorySceneAudioClip, autoplay: Bool, startAt: Double = 0) {
        audioManager.streamAudio(url: url, startAt: startAt)
        audioManager.setStreamRate(playbackRate)
        refreshChapterDuration()
        sliderValue = currentClipStartOffset + startAt
        updateNowPlayingMetadata(clip: clip)
        if autoplay {
            didPlayAudio = true
            let announcement = startAt == 0 ? readerAdapter.playbackAnnouncement(for: clip) : nil
            audioManager.announceThenPlayStream(announcement, language: story.language)
            isPlaying = true
        }
        syncSelectionToCurrentClip()
    }

    private var sleepTimerBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(.secondary)
            Text(sleepTimerStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Cancel") {
                cancelSleepTimer()
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var sleepTimerStatusText: String {
        switch sleepTimerMode {
        case .inactive:
            return ""
        case .minutes(let minutes):
            if let endDate = sleepTimerEndDate {
                let remaining = max(0, Int(endDate.timeIntervalSinceNow.rounded()))
                let mins = remaining / 60
                let secs = remaining % 60
                return "Sleep in \(mins):\(String(format: "%02d", secs)) (\(minutes) min)"
            }
            return "Sleep timer: \(minutes) min"
        case .endOfChapter:
            return "Sleep at end of chapter"
        case .endOfStory:
            return "Sleep at end of story"
        }
    }

    private func loadLockScreenArtwork() {
        let imageURL = selectedNavItem?.imageURL ?? storyCoverImageURL
        guard let imageURL else { return }

        Task {
            if let (data, _) = try? await URLSession.shared.data(from: imageURL),
               let image = UIImage(data: data) {
                await MainActor.run {
                    lockScreenArtwork = image
                    updateNowPlayingMetadata()
                }
            }
        }
    }

    private func updateNowPlayingMetadata(clip: StorySceneAudioClip? = nil) {
        let activeClip = clip ?? clips[safeAudioBook: currentClipIndex]
        guard let activeClip else { return }
        audioManager.updateStreamNowPlayingInfo(
            title: activeClip.title,
            artist: story.title,
            artworkImage: lockScreenArtwork
        )
    }

    private func applySleepTimer(_ mode: AudioBookSleepTimerMode) {
        sleepTimerMode = mode
        switch mode {
        case .inactive:
            sleepTimerEndDate = nil
        case .minutes(let minutes):
            sleepTimerEndDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        case .endOfChapter, .endOfStory:
            sleepTimerEndDate = nil
        }
    }

    private func cancelSleepTimer() {
        sleepTimerMode = .inactive
        sleepTimerEndDate = nil
    }

    private func fireSleepTimer() {
        if isOnReadingMatterSelection {
            supplementalPlayback.pause()
        } else {
            audioManager.pauseStream()
        }
        isAutoContinueEnabled = false
        isPlaying = false
        cancelSleepTimer()
    }

    private func handleSleepTimerChapterBoundary() {
        if sleepTimerMode == .endOfChapter {
            fireSleepTimer()
        }
    }

    private func handleSleepTimerStoryEnd() {
        if sleepTimerMode == .endOfStory {
            fireSleepTimer()
        }
    }

    private func prefetchClipToCache(at index: Int) {
        guard clips.indices.contains(index) else { return }
        let clip = clips[index]
        Task { await prefetchClipToCache(clip) }
    }

    private func prefetchClipToCache(_ clip: StorySceneAudioClip) async {
        if StoryReaderDataAdapter.cachedAudioURL(
            storyID: story.id,
            clip: clip,
            storyUpdatedAt: story.updatedAt
        ) != nil {
            return
        }

        let shouldStart = await MainActor.run { () -> Bool in
            if prefetchingClipIDs.contains(clip.id) { return false }
            prefetchingClipIDs.insert(clip.id)
            return true
        }
        guard shouldStart else { return }

        defer {
            Task { @MainActor in
                prefetchingClipIDs.remove(clip.id)
            }
        }

        _ = await StoryReaderDataAdapter.downloadAndCacheAudioIfNeeded(
            storyID: story.id,
            clip: clip,
            storyUpdatedAt: story.updatedAt
        )
    }

    private func advanceAfterClipFinished() {
        audioManager.streamFinished = false

        let chapterClips = currentChapterClips
        let sceneIndex = currentSceneClipIndex
        if sceneIndex < chapterClips.count - 1,
           let nextSceneClip = chapterClips[safeAudioBook: sceneIndex + 1],
           let nextGlobalIndex = clips.firstIndex(where: { $0.id == nextSceneClip.id }) {
            guard isAutoContinueEnabled else {
                isPlaying = false
                return
            }
            Task { @MainActor in
                playClip(at: nextGlobalIndex, autoplay: true)
            }
            return
        }

        handleSleepTimerChapterBoundary()

        guard currentClipIndex < clips.count - 1 else {
            isPlaying = false
            handleSleepTimerStoryEnd()
            return
        }
        let nextIndex = currentClipIndex + 1
        guard isAutoContinueEnabled else {
            isPlaying = false
            return
        }
        Task { @MainActor in
            playClip(at: nextIndex, autoplay: true)
        }
    }

    private func nextClip() {
        guard currentClipIndex < clips.count - 1 else { return }
        playClip(at: currentClipIndex + 1, autoplay: isPlaying)
    }

    private func previousClip() {
        guard currentClipIndex > 0 else {
            audioManager.seekStream(to: 0)
            return
        }
        playClip(at: currentClipIndex - 1, autoplay: isPlaying)
    }

    private func setRate(_ rate: Float) {
        playbackRate = rate
        if isOnReadingMatterSelection {
            supplementalPlayback.setRate(rate)
        } else {
            audioManager.setStreamRate(rate)
        }
    }

    private var currentChapterIndex: Int? {
        guard clips.indices.contains(currentClipIndex) else { return nil }
        return clips[currentClipIndex].chapterIndex
    }

    private func saveReadingProgress() {
        guard let selectedNavItemID,
              let index = navItems.firstIndex(where: { $0.id == selectedNavItemID }) else { return }
        onProgressChange?(StoryReaderProgressUpdate(
            index: index,
            total: navItems.count,
            chapterIndex: currentChapterIndex,
            sceneIndex: currentSceneIndexForProgress,
            position: sliderValue > 0 ? sliderValue : nil
        ))
    }

    private var currentSceneIndexForProgress: Int? {
        guard clips.indices.contains(currentClipIndex) else { return nil }
        let clip = clips[currentClipIndex]
        return clip.isChapterIntro ? nil : clip.sceneIndex
    }

    private func saveTimedReadingProgressIfNeeded(position: Double) {
        let second = Int(position.rounded())
        guard second != lastSavedPlaybackSecond else { return }
        lastSavedPlaybackSecond = second
        saveReadingProgress()
    }

    private func cleanupSession() {
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
              let chapterIndex = currentChapterIndex,
              let target = readerAdapter.clipIndex(
                forChapter: chapterIndex,
                localTime: initialPlaybackPosition,
                includeIntro: true
              ) else { return }

        let chapterClips = readerAdapter.chapterPlaybackClips(forChapter: chapterIndex)
        guard chapterClips.indices.contains(target.index),
              let globalIndex = clips.firstIndex(where: { $0.id == chapterClips[target.index].id }) else { return }
        playClip(at: globalIndex, autoplay: false, startAt: target.offset)
    }
}

// MARK: - Loading

private struct AudioBookLoadingView: View {
    let title: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Preparing audio book…")
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - Navigation model

private enum AudioBookNavKind {
    case cover
    case readingMatter
    case chapter

    var label: String {
        switch self {
        case .cover: return "Cover"
        case .readingMatter: return "Reading Matter"
        case .chapter: return "Chapter"
        }
    }

    var systemImage: String {
        switch self {
        case .cover: return "book.closed.fill"
        case .readingMatter: return "doc.text.fill"
        case .chapter: return "headphones"
        }
    }
}

private struct AudioBookNavItem: Identifiable {
    let id: String
    let spineItem: StoryReadingSpineItem
    let kind: AudioBookNavKind
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let chapterIndex: Int?
    let firstClipIndex: Int?
}

private struct AudioBookNavRow: View {
    let item: AudioBookNavItem
    let isSelected: Bool
    let isNowPlaying: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            navThumbnail

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.kind.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)

                    if isNowPlaying {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .layoutPriority(1)

            if item.kind == .chapter {
                Image(systemName: isNowPlaying ? "speaker.wave.2.fill" : "play.circle")
                    .font(.title3)
                    .foregroundStyle(isNowPlaying ? Color.accentColor : .secondary)
                    .frame(width: 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : .clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var navThumbnail: some View {
        Group {
            if let url = item.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        thumbnailPlaceholder
                    }
                }
            } else {
                thumbnailPlaceholder
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sleep Timer

private enum AudioBookSleepTimerMode: Hashable {
    case inactive
    case minutes(Int)
    case endOfChapter
    case endOfStory
}

private struct AudioBookSleepTimerSheet: View {
    @Binding var mode: AudioBookSleepTimerMode
    let onSelect: (AudioBookSleepTimerMode) -> Void
    @Environment(\.dismiss) private var dismiss

    private let minuteOptions = [5, 10, 15, 30, 45, 60]

    var body: some View {
        NavigationStack {
            List {
                Section("Timer") {
                    ForEach(minuteOptions, id: \.self) { minutes in
                        Button("\(minutes) minutes") {
                            onSelect(.minutes(minutes))
                            dismiss()
                        }
                    }
                }

                Section("Stop Playback") {
                    Button("End of Chapter") {
                        onSelect(.endOfChapter)
                        dismiss()
                    }
                    Button("End of Story") {
                        onSelect(.endOfStory)
                        dismiss()
                    }
                }

                if mode != .inactive {
                    Section {
                        Button("Cancel Timer", role: .destructive) {
                            onSelect(.inactive)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Tracklist

private struct AudioBookPlayerSheet: View {
    let navItems: [AudioBookNavItem]
    let selectedNavItemID: String?
    let currentChapterTitle: String?
    let chapterClips: [StorySceneAudioClip]
    let globalClips: [StorySceneAudioClip]
    let currentClipIndex: Int
    let adapter: StoryReaderDataAdapter
    let story: Story
    @Binding var isAutoContinueEnabled: Bool
    @Binding var sleepTimerMode: AudioBookSleepTimerMode
    @Binding var playbackRate: Float
    let onChangeRate: (Float) -> Void
    let onSelectTimer: (AudioBookSleepTimerMode) -> Void
    let onSelectNavItem: (AudioBookNavItem) -> Void
    let onSelectClip: (Int) -> Void

    private let playbackRates: [Float] = [0.75, 1.0, 1.25, 1.5]
    private let timerOptions: [(label: String, mode: AudioBookSleepTimerMode)] = [
        ("Off", .inactive),
        ("5m", .minutes(5)),
        ("10m", .minutes(10)),
        ("15m", .minutes(15)),
        ("30m", .minutes(30)),
        ("Chapter", .endOfChapter)
    ]

    private var currentClipID: String? {
        globalClips[safeAudioBook: currentClipIndex]?.id
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Playback") {
                    Toggle(isOn: $isAutoContinueEnabled) {
                        Label("Auto Play", systemImage: "play.circle")
                    }

                    Picker(selection: timerBinding) {
                        ForEach(timerOptions, id: \.label) { option in
                            Text(option.label).tag(option.mode)
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

                if !chapterClips.isEmpty {
                    Section(currentChapterTitle ?? "Current Chapter") {
                        ForEach(chapterClips) { clip in
                            let globalIndex = globalClips.firstIndex { $0.id == clip.id }
                            let isCurrent = clip.id == currentClipID
                            Button {
                                guard let globalIndex else { return }
                                onSelectClip(globalIndex)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: clip.isChapterIntro ? "text.quote" : "waveform")
                                        .frame(width: 24)
                                        .foregroundStyle(isCurrent ? Color.accentColor : .secondary)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(trackTitle(for: clip))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        Text(trackSubtitle(for: clip))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)

                                        if let duration = clip.duration, duration > 0 {
                                            Text(formatDuration(duration))
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .monospacedDigit()
                                        }
                                    }

                                    Spacer(minLength: 0)

                                    if isCurrent {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .disabled(globalIndex == nil)
                        }
                    }
                }

                Section("Chapter Navigation") {
                    ForEach(navItems) { item in
                        Button {
                            onSelectNavItem(item)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.kind.systemImage)
                                    .frame(width: 24)
                                    .foregroundStyle(selectedNavItemID == item.id ? Color.accentColor : .secondary)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(item.kind.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)

                                if selectedNavItemID == item.id {
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

    private var timerBinding: Binding<AudioBookSleepTimerMode> {
        Binding(
            get: { sleepTimerMode },
            set: { mode in
                sleepTimerMode = mode
                onSelectTimer(mode)
            }
        )
    }

    private func trackTitle(for clip: StorySceneAudioClip) -> String {
        guard let chapter = story.chapters[safeAudioBook: clip.chapterIndex] else {
            return clip.title
        }
        return adapter.tracklistTitle(for: clip, chapter: chapter)
    }

    private func trackSubtitle(for clip: StorySceneAudioClip) -> String {
        guard let chapter = story.chapters[safeAudioBook: clip.chapterIndex] else {
            return clip.caption
        }
        return adapter.tracklistSubtitle(for: clip, chapter: chapter)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

private struct AudioBookChapterTracklistSheet: View {
    let story: Story
    let chapterIndex: Int
    let chapterClips: [StorySceneAudioClip]
    let globalClips: [StorySceneAudioClip]
    let currentClipIndex: Int
    let adapter: StoryReaderDataAdapter
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private var chapter: StoryChapter? {
        story.chapters[safeAudioBook: chapterIndex]
    }

    private var currentClipID: String? {
        globalClips[safeAudioBook: currentClipIndex]?.id
    }

    var body: some View {
        NavigationStack {
            List {
                if let chapter {
                    ForEach(chapterClips) { clip in
                        let globalIndex = globalClips.firstIndex { $0.id == clip.id }
                        let isCurrent = clip.id == currentClipID
                        Button {
                            guard let globalIndex else { return }
                            onSelect(globalIndex)
                            dismiss()
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: clip.isChapterIntro ? "text.quote" : "waveform")
                                    .frame(width: 24)
                                    .foregroundStyle(isCurrent ? Color.accentColor : .secondary)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(adapter.tracklistTitle(for: clip, chapter: chapter))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    let subtitle = adapter.tracklistSubtitle(for: clip, chapter: chapter)
                                    if !subtitle.isEmpty {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    if let duration = clip.duration, duration > 0 {
                                        Text(formatDuration(duration))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .monospacedDigit()
                                    }
                                }

                                Spacer(minLength: 0)

                                if isCurrent {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .disabled(globalIndex == nil)
                    }
                }
            }
            .navigationTitle(chapter?.titleTargetLanguage.nilIfEmptyAudioBook ?? "Chapter \(chapterIndex + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

private struct AudioBookMacroTracklistSheet: View {
    let navItems: [AudioBookNavItem]
    let selectedNavItemID: String?
    let onSelect: (AudioBookNavItem) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(navItems) { item in
                Button {
                    onSelect(item)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.kind.systemImage)
                            .frame(width: 24)
                            .foregroundStyle(selectedNavItemID == item.id ? Color.accentColor : .secondary)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(item.kind.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        if selectedNavItemID == item.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("In This Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Transcript

private struct AudioBookTranscriptSheet: View {
    let story: Story
    let navItem: AudioBookNavItem
    let clips: [StorySceneAudioClip]
    let currentClipIndex: Int
    @Bindable var audioManager: AudioManager
    let adapter: StoryReaderDataAdapter

    @Environment(\.dismiss) private var dismiss

    private var currentClip: StorySceneAudioClip? {
        clips[safeAudioBook: currentClipIndex]
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(transcriptSections) { section in
                            transcriptSectionView(section)
                                .id(section.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: currentClipIndex) { _, _ in
                    scrollToNowPlaying(with: proxy)
                }
                .onAppear {
                    scrollToNowPlaying(with: proxy)
                }
            }
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func transcriptSectionView(_ section: AudioBookTranscriptSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let heading = section.heading {
                Text(heading)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(section.isNowPlaying ? Color.accentColor : .secondary)
            }

            if section.isNowPlaying, !section.segments.isEmpty {
                ForEach(Array(section.segments.enumerated()), id: \.offset) { _, segment in
                    if section.segments.count > 1 {
                        Text(segment.speaker.replacingOccurrences(of: "_", with: " "))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    TimedTextView(segment: segment, currentTime: audioManager.streamCurrentTime)
                        .padding(.horizontal, -16)
                }
            } else {
                if section.allowsWordLookup {
                    TappableStoryText(
                        text: section.body,
                        font: .body,
                        lineSpacing: 6,
                        foregroundColor: section.isNowPlaying ? .primary : .secondary
                    )
                } else {
                    Text(section.body)
                        .font(.body)
                        .lineSpacing(6)
                        .foregroundStyle(section.isNowPlaying ? .primary : .secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(section.isNowPlaying ? 12 : 0)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(section.isNowPlaying ? Color.accentColor.opacity(0.08) : .clear)
        )
    }

    private func scrollToNowPlaying(with proxy: ScrollViewProxy) {
        guard let activeID = transcriptSections.first(where: \.isNowPlaying)?.id else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(activeID, anchor: .top)
        }
    }

    private struct AudioBookTranscriptSection: Identifiable {
        let id: String
        let heading: String?
        let body: String
        let segments: [StorySegmentTiming]
        let isNowPlaying: Bool
        let allowsWordLookup: Bool
    }

    private var transcriptSections: [AudioBookTranscriptSection] {
        switch navItem.kind {
        case .cover:
            let overview = story.storyOverviewText ?? story.title
            return [
                AudioBookTranscriptSection(
                    id: "cover",
                    heading: nil,
                    body: overview,
                    segments: [],
                    isNowPlaying: false,
                    allowsWordLookup: false
                )
            ]

        case .readingMatter:
            guard let page = adapter.readingMatterPage(for: navItem.spineItem) else {
                return [
                    AudioBookTranscriptSection(
                        id: "reading-matter",
                        heading: nil,
                        body: "No reading matter text available.",
                        segments: [],
                        isNowPlaying: false,
                        allowsWordLookup: false
                    )
                ]
            }
            let targetBody = page.bodyTarget?.nilIfEmptyAudioBook
            let body = targetBody
                ?? page.bodyNative?.nilIfEmptyAudioBook
                ?? ""
            return [
                AudioBookTranscriptSection(
                    id: "reading-matter",
                    heading: page.titleTarget,
                    body: body,
                    segments: [],
                    isNowPlaying: false,
                    allowsWordLookup: targetBody != nil
                )
            ]

        case .chapter:
            guard let chapterIndex = navItem.chapterIndex,
                  let chapter = story.chapters[safeAudioBook: chapterIndex] else {
                return []
            }

            var sections: [AudioBookTranscriptSection] = []

            if chapter.hasChapterIntroContent,
               let introText = chapter.chapterIntroText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !introText.isEmpty {
                let isIntroCurrent = currentClip?.isChapterIntro == true
                    && currentClip?.chapterIndex == chapterIndex
                let introSegments: [StorySegmentTiming]
                if isIntroCurrent,
                   let timings = chapter.chapterIntroWordTimings,
                   !timings.isEmpty {
                    introSegments = [
                        StorySegmentTiming(
                            speaker: "",
                            text: introText,
                            startTime: 0,
                            endTime: .greatestFiniteMagnitude,
                            timings: timings
                        )
                    ]
                } else {
                    introSegments = []
                }
                sections.append(
                    AudioBookTranscriptSection(
                        id: "chapter-\(chapterIndex)-intro",
                        heading: isIntroCurrent ? "Chapter Intro · Now Playing" : "Chapter Intro",
                        body: introText,
                        segments: introSegments,
                        isNowPlaying: isIntroCurrent,
                        allowsWordLookup: true
                    )
                )
            }

            let scenes = chapter.scenes
                .filter(\.hasNarrationAudio)
                .sorted { $0.sceneIndex < $1.sceneIndex }

            if scenes.isEmpty, sections.isEmpty {
                let body = chapter.bodyScriptOrNarrativeForAlignment
                let segments = ScriptParser.parseSegments(
                    scriptText: body,
                    globalTimings: chapter.bodyWordTimingsForPlayback
                )
                let isCurrent = currentClip?.chapterIndex == chapterIndex
                    && currentClip?.isChapterIntro != true
                return [
                    AudioBookTranscriptSection(
                        id: "chapter-\(chapterIndex)",
                        heading: "Chapter",
                        body: body,
                        segments: isCurrent ? segments : [],
                        isNowPlaying: isCurrent,
                        allowsWordLookup: true
                    )
                ].filter { !$0.body.isEmpty }
            }

            sections.append(contentsOf: scenes.compactMap { scene in
                let isCurrent = currentClip?.chapterIndex == chapterIndex
                    && currentClip?.isChapterIntro != true
                    && currentClip?.sceneIndex == scene.sceneIndex
                let heading = isCurrent
                    ? "Scene \(scene.sceneIndex + 1) · Now Playing"
                    : "Scene \(scene.sceneIndex + 1)"
                let text = scene.spokenTranscriptText(preferences: story.preferences)
                guard !text.isEmpty else { return nil }
                return AudioBookTranscriptSection(
                    id: "chapter-\(chapterIndex)-scene-\(scene.sceneIndex)",
                    heading: heading,
                    body: text,
                    segments: isCurrent ? scene.transcriptSegments(preferences: story.preferences) : [],
                    isNowPlaying: isCurrent,
                    allowsWordLookup: true
                )
            })

            return sections
        }
    }
}

private extension String {
    var nilIfEmptyAudioBook: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Collection {
    subscript(safeAudioBook index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

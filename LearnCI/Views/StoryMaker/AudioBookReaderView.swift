import SwiftUI
import Combine

struct AudioBookReaderView: View {
    let story: Story

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
    @State private var showSleepTimer = false
    @State private var showTracklist = false
    @State private var prefetchingClipIDs: Set<String> = []
    @State private var lockScreenArtwork: UIImage?
    @State private var sleepTimerMode: AudioBookSleepTimerMode = .inactive
    @State private var sleepTimerEndDate: Date?

    @Bindable private var audioManager = AudioManager.shared
    private let sleepTimerTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(story: Story) {
        self.story = story
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
        if let chapterIndex = currentChapterIndex,
           let item = navItems.first(where: { $0.kind == .chapter && $0.chapterIndex == chapterIndex }) {
            return item
        }
        return navItems.first
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSleepTimer = true
                } label: {
                    Image(systemName: sleepTimerMode == .inactive ? "moon.zzz" : "moon.zzz.fill")
                }
                .accessibilityLabel("Sleep Timer")
            }
        }
        .onAppear(perform: prepareReaderIfNeeded)
        .onDisappear {
            cancelSleepTimer()
            audioManager.stopAudio()
        }
        .onChange(of: currentClipIndex) { _, _ in
            syncSelectionToCurrentClip()
            refreshChapterDuration()
            loadLockScreenArtwork()
            updateNowPlayingMetadata()
        }
        .onChange(of: selectedNavItemID) { _, _ in
            loadLockScreenArtwork()
        }
        .onChange(of: audioManager.streamFinished) { _, finished in
            guard finished else { return }
            advanceAfterClipFinished()
        }
        .onChange(of: audioManager.streamCurrentTime) { _, time in
            guard audioManager.streamPlayer != nil, currentChapterIndex != nil else { return }
            sliderValue = currentClipStartOffset + time
            updateNowPlayingMetadata()
        }
        .onReceive(sleepTimerTicker) { _ in
            guard let endDate = sleepTimerEndDate, Date() >= endDate else { return }
            fireSleepTimer()
        }
        .onChange(of: audioManager.streamDuration) { _, streamDuration in
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
        .sheet(isPresented: $showSleepTimer) {
            AudioBookSleepTimerSheet(
                mode: $sleepTimerMode,
                onSelect: applySleepTimer
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showTracklist) {
            tracklistSheet
                .presentationDetents([.medium, .large])
        }
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    if let item = selectedNavItem {
                        currentItemHero(item)
                    }

                    if isBufferingPlayback {
                        audioLoadingBanner
                    }

                    spineNavigationSection
                    Color.clear.frame(height: 140)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            playerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { podcastBackground }
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
                duration: max(duration, 1),
                playbackRate: $playbackRate,
                ambientVolume: .constant(0),
                isAmbientPlaying: false,
                canSeek: selectedNavItem?.kind == .chapter && !isBufferingPlayback,
                canControlPlayback: !isBufferingPlayback,
                isBuffering: isBufferingPlayback,
                bufferingLabel: loadingAudioLabel ?? "Loading audio…",
                onPlayPause: togglePlay,
                onSkipForward: skipForward,
                onSkipBackward: skipBackward,
                onSeek: seekToChapterTime,
                onChangeRate: setRate,
                onNextChapter: nextClipAction,
                onPreviousChapter: previousClipAction,
                onSkipPreviousChapter: skipToPreviousChapterAction,
                onSkipNextChapter: skipToNextChapterAction,
                onShowSpine: { showTracklist = true }
            )
            .disabled(isBufferingPlayback)
        }
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
        guard item.kind == .chapter, let chapterIndex = item.chapterIndex else { return false }
        guard isPlaying else { return false }
        return currentChapterIndex == chapterIndex
    }

    private func bootstrapSelection() {
        if let chapterIndex = currentChapterIndex,
           let item = navItems.first(where: { $0.kind == .chapter && $0.chapterIndex == chapterIndex }) {
            selectedNavItemID = item.id
        } else {
            selectedNavItemID = navItems.first?.id
        }
    }

    private func syncSelectionToCurrentClip() {
        guard let chapterIndex = currentChapterIndex,
              let item = navItems.first(where: { $0.kind == .chapter && $0.chapterIndex == chapterIndex }) else { return }
        selectedNavItemID = item.id
    }

    private func selectNavItem(_ item: AudioBookNavItem) {
        selectedNavItemID = item.id
        switch item.kind {
        case .chapter:
            if let clipIndex = item.firstClipIndex {
                playClip(at: clipIndex, autoplay: true)
            }
        case .cover, .readingMatter:
            if audioManager.isStreaming {
                audioManager.pauseStream()
                isPlaying = false
            }
        }
    }

    private func togglePlay() {
        guard selectedNavItem?.kind == .chapter || currentChapterIndex != nil else {
            if let firstChapter = navItems.first(where: { $0.kind == .chapter }),
               let clipIndex = firstChapter.firstClipIndex {
                selectNavItem(firstChapter)
                playClip(at: clipIndex, autoplay: true)
            }
            return
        }

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
        }
    }

    private func skipForward() {
        guard selectedNavItem?.kind == .chapter else { return }
        seekToChapterTime(min(sliderValue + 15, duration))
    }

    private func skipBackward() {
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
            audioManager.playStream()
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
        showSleepTimer = false
    }

    private func cancelSleepTimer() {
        sleepTimerMode = .inactive
        sleepTimerEndDate = nil
    }

    private func fireSleepTimer() {
        audioManager.pauseStream()
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
        audioManager.setStreamRate(rate)
    }

    private var currentChapterIndex: Int? {
        guard clips.indices.contains(currentClipIndex) else { return nil }
        return clips[currentClipIndex].chapterIndex
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

private enum AudioBookSleepTimerMode: Equatable {
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
                Text(section.body)
                    .font(.body)
                    .lineSpacing(6)
                    .foregroundStyle(section.isNowPlaying ? .primary : .secondary)
                    .textSelection(.enabled)
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
                    isNowPlaying: false
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
                        isNowPlaying: false
                    )
                ]
            }
            let body = page.bodyTarget?.nilIfEmptyAudioBook
                ?? page.bodyNative?.nilIfEmptyAudioBook
                ?? ""
            return [
                AudioBookTranscriptSection(
                    id: "reading-matter",
                    heading: page.titleTarget,
                    body: body,
                    segments: [],
                    isNowPlaying: false
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
                        isNowPlaying: isIntroCurrent
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
                        isNowPlaying: isCurrent
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
                    isNowPlaying: isCurrent
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

import SwiftUI
import Combine

struct PictureBookReaderView: View {
    let story: Story

    @Environment(\.dismiss) private var dismiss
    @State private var currentSpreadIndex = 0
    @State private var currentClipIndex = 0
    @State private var isPlaying = false
    @State private var isDownloadingAudio = false
    @State private var sliderValue = 0.0
    @State private var duration = 0.0
    @State private var playbackRate: Float = 1.0
    @State private var showSpine = false
    @State private var isLoadingBook = true
    @State private var loadingIssue: StoryReaderRequirementIssue?
    @State private var spreads: [PictureBookSpreadModel]
    @State private var clips: [StorySceneAudioClip]
    @State private var spreadIndexToClipIndex: [Int: Int]
    @State private var clipIndexToSpreadIndex: [Int: Int]
    @State private var selectedLanguage: StorySessionView.DisplayLanguage = .target
    @State private var supplementalPlayback = StorySupplementalAudioPlayback()

    private var audioManager = AudioManager.shared
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    init(story: Story) {
        self.story = story
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
        .onAppear(perform: loadBookIfNeeded)
        .sheet(isPresented: $showSpine) {
            PictureBookSpineSheet(
                spreads: spreads,
                currentSpreadIndex: currentSpreadIndex
            ) { index in
                showSpine = false
                goToSpread(index)
            }
            .presentationDetents([.medium, .large])
        }
        .mediaPlaybackLifecycle(
            onUserLeave: {
                supplementalPlayback.stop()
                audioManager.stopAudio()
            },
            onEnterBackground: { audioManager.updateStreamNowPlayingInfo() }
        )
        .onChange(of: currentSpreadIndex) { _, _ in
            prepareSupplementalForCurrentSpread()
        }
        .onChange(of: selectedLanguage) { _, _ in
            guard isOnReadingMatterSpread else { return }
            let wasPlaying = supplementalPlayback.isPlaying
            prepareSupplementalForCurrentSpread()
            if wasPlaying {
                supplementalPlayback.syncPlayback(
                    shouldPlay: true,
                    speakableText: currentReadingMatterSpeakableText
                )
            }
        }
        .onReceive(timer) { _ in
            if isOnReadingMatterSpread {
                supplementalPlayback.syncStreamState()
                sliderValue = supplementalPlayback.currentTime
                if supplementalPlayback.duration > 0 {
                    duration = supplementalPlayback.duration
                }
                isPlaying = supplementalPlayback.isPlaying
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
            currentSpreadIndex = 0
            currentClipIndex = 0
            isLoadingBook = false
            prepareSupplementalForCurrentSpread()
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
                        selectedLanguage: selectedLanguage,
                        readingMatterPlayback: isOnReadingMatterSpread ? supplementalPlayback : nil
                    )
                    .id("\(spreads[currentSpreadIndex].id)-\(selectedLanguage.rawValue)")
                    .transition(.opacity)
                }
            }

            VStack(spacing: 10) {
                playbackControls
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
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
                duration: max(isOnReadingMatterSpread ? supplementalPlayback.duration : duration, 1),
                playbackRate: $playbackRate,
                ambientVolume: .constant(0),
                isAmbientPlaying: false,
                canSeek: isOnReadingMatterSpread ? supplementalPlayback.canSeek : audioManager.streamPlayer != nil,
                canControlPlayback: canControlSpreadPlayback,
                playbackContextLabel: spreadPlaybackContextLabel,
                isBuffering: supplementalPlayback.isLoading,
                bufferingLabel: "Loading audio…",
                onPlayPause: togglePlay,
                onSkipForward: skipForward,
                onSkipBackward: skipBackward,
                onSeek: seekTo,
                onChangeRate: setRate,
                onNextChapter: currentSpreadIndex < spreads.count - 1 ? {
                    goToSpread(currentSpreadIndex + 1)
                } : nil,
                onPreviousChapter: currentSpreadIndex > 0 ? {
                    goToSpread(currentSpreadIndex - 1)
                } : nil,
                onShowSpine: { showSpine = true }
            )
            .disabled(isDownloadingAudio || supplementalPlayback.isLoading)
        }
    }

    private var currentSpread: PictureBookSpreadModel? {
        spreads[safeForPictureBook: currentSpreadIndex]
    }

    private var isOnReadingMatterSpread: Bool {
        if case .readingMatterPage = currentSpread?.spineItem { return true }
        return false
    }

    private var preferNativeLanguage: Bool {
        selectedLanguage == .native
    }

    private var canControlSpreadPlayback: Bool {
        if isOnReadingMatterSpread {
            return currentReadingMatterCanPlay
        }
        if case .cover = currentSpread?.spineItem {
            return firstPlayableClipIndex != nil
        }
        return currentSpread?.isScene == true
    }

    private var spreadPlaybackContextLabel: String? {
        guard isOnReadingMatterSpread, currentReadingMatterCanPlay else { return nil }
        return supplementalPlayback.isPlaying ? "Reading Matter · Now Playing" : "Reading Matter"
    }

    private var currentReadingMatterCanPlay: Bool {
        guard let page = currentSpread?.readingMatterPage else { return false }
        return page.hasGeneratedAudio(preferNative: preferNativeLanguage) || currentReadingMatterSpeakableText != nil
    }

    private var currentReadingMatterSpeakableText: String? {
        guard let spread = currentSpread,
              let page = spread.readingMatterPage else { return nil }
        var parts: [String] = []
        if let title = spread.displayMatterTitle(language: selectedLanguage) {
            parts.append(title)
        }
        if let body = spread.displayBody(language: selectedLanguage) {
            parts.append(body)
        }
        let text = parts.joined(separator: ". ")
        return text.isEmpty ? nil : text
    }

    private func prepareSupplementalForCurrentSpread() {
        supplementalPlayback.onFinished = nil
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
    }

    private func stopSupplementalPlayback() {
        supplementalPlayback.stop()
        if isOnReadingMatterSpread {
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
        case .scene:
            return "Scene"
        }
    }

    private func goToSpread(_ index: Int) {
        guard spreads.indices.contains(index) else { return }

        let wasPlaying = isPlaying
        stopSupplementalPlayback()
        if !spreads[index].isScene {
            audioManager.stopAudio()
        }

        withAnimation(.easeOut(duration: 0.18)) {
            currentSpreadIndex = index
        }

        prepareSupplementalForCurrentSpread()

        guard wasPlaying else { return }

        if isOnReadingMatterSpread {
            supplementalPlayback.syncPlayback(
                shouldPlay: true,
                speakableText: currentReadingMatterSpeakableText
            )
            isPlaying = supplementalPlayback.isPlaying
            return
        }

        guard let targetClipIndex = spreadIndexToClipIndex[index] else {
            isPlaying = false
            return
        }
        playClip(at: targetClipIndex, autoplay: true)
    }

    private func togglePlay() {
        if isOnReadingMatterSpread {
            let shouldPlay = !supplementalPlayback.isPlaying
            supplementalPlayback.syncPlayback(
                shouldPlay: shouldPlay,
                speakableText: currentReadingMatterSpeakableText
            )
            isPlaying = supplementalPlayback.isPlaying
            return
        }

        if audioManager.streamPlayer == nil {
            let clipIndex = spreadIndexToClipIndex[currentSpreadIndex] ?? firstPlayableClipIndex
            if let clipIndex {
                playClip(at: clipIndex, autoplay: true)
            }
            return
        }

        if audioManager.isStreaming {
            audioManager.pauseStream()
            isPlaying = false
        } else {
            audioManager.playStream()
            isPlaying = true
        }
        audioManager.updateStreamNowPlayingInfo()
    }

    private func skipForward() {
        guard isOnReadingMatterSpread, supplementalPlayback.canSeek else { return }
        seekTo(min(sliderValue + 10, max(supplementalPlayback.duration, 1)))
    }

    private func skipBackward() {
        guard isOnReadingMatterSpread, supplementalPlayback.canSeek else { return }
        seekTo(max(0, sliderValue - 10))
    }

    private func seekTo(_ value: Double) {
        if isOnReadingMatterSpread, supplementalPlayback.canSeek {
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
        if isOnReadingMatterSpread {
            supplementalPlayback.setRate(rate)
        } else {
            audioManager.setStreamRate(rate)
        }
    }

    private var firstPlayableClipIndex: Int? {
        clips.isEmpty ? nil : 0
    }

    private func playClip(at index: Int, autoplay: Bool) {
        guard clips.indices.contains(index) else { return }
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
            playLocal(url: cachedURL, clip: clip, autoplay: autoplay)
            return
        }

        isDownloadingAudio = true
        Task { await downloadAndPlay(clip: clip, localURL: localURL, autoplay: autoplay) }
    }

    private func playLocal(url: URL, clip: StorySceneAudioClip, autoplay: Bool) {
        audioManager.streamAudio(url: url)
        audioManager.setStreamRate(playbackRate)
        duration = clip.duration ?? audioManager.streamDuration
        sliderValue = 0
        audioManager.updateStreamNowPlayingInfo(title: clip.title, artist: story.title, artworkImage: nil)
        if autoplay {
            audioManager.playStream()
            isPlaying = true
        }
    }

    private func downloadAndPlay(clip: StorySceneAudioClip, localURL: URL, autoplay: Bool) async {
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
                playLocal(url: correctURL, clip: clip, autoplay: autoplay)
            }
        } catch {
            await MainActor.run { isDownloadingAudio = false }
        }
    }

    private func advanceAfterClipFinished() {
        audioManager.streamFinished = false
        guard currentClipIndex < clips.count - 1 else {
            isPlaying = false
            if let backMatterIndex = spreads.indices.dropFirst(currentSpreadIndex + 1).first(where: {
                if case .readingMatterPage = spreads[$0].spineItem { return true }
                return false
            }) {
                withAnimation(.easeOut(duration: 0.18)) {
                    currentSpreadIndex = backMatterIndex
                }
            }
            return
        }
        playClip(at: currentClipIndex + 1, autoplay: true)
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
                    chapterIndex: nil,
                    chapterTitle: nil,
                    sceneTitle: nil,
                    spinePrimaryTitle: story.title,
                    spineContextLabel: "Cover",
                    title: story.title,
                    subtitle: "\(story.language.displayName) · Level \(story.level)",
                    body: nil,
                    readingMatterPage: nil,
                    scene: nil,
                    panel: nil,
                    layoutPanels: [],
                    audioClip: nil,
                    imageURL: coverURL(for: story)
                )
            case .readingMatterPage:
                guard let page = adapter.readingMatterPage(for: item) else { return nil }
                let title = page.titleTarget?.nilIfEmptyForPictureBook
                    ?? page.titleNative?.nilIfEmptyForPictureBook
                    ?? page.id.nilIfEmptyForPictureBook
                return PictureBookSpreadModel(
                    id: item.id,
                    spineItem: item,
                    spreadIndex: spreadIndex,
                    storyTitle: story.title,
                    chapterIndex: nil,
                    chapterTitle: nil,
                    sceneTitle: nil,
                    spinePrimaryTitle: StoryReadingSpineTitles.readingMatterTitle(for: page),
                    spineContextLabel: "Reading Matter",
                    title: title,
                    subtitle: nil,
                    body: page.bodyTarget?.nilIfEmptyForPictureBook,
                    readingMatterPage: page,
                    scene: nil,
                    panel: nil,
                    layoutPanels: [],
                    audioClip: nil,
                    imageURL: coverURL(for: story)
                )
            case .chapter:
                return nil
            case .scene(let chapterIndex, let sceneIndex):
                guard let scene = adapter.scene(for: item) else { return nil }
                let chapter = story.chapters[safeForPictureBook: chapterIndex]
                let chapterTitle = chapter?.titleTargetLanguage.nilIfEmptyForPictureBook
                let breakdownTitle = StoryReadingSpineTitles.sceneTitleFromBreakdown(
                    story: story,
                    chapterIndex: chapterIndex,
                    sceneIndex: sceneIndex
                )
                let sceneTitle = StoryReadingSpineTitles.sceneTitle(
                    from: scene,
                    sceneIndex: sceneIndex,
                    breakdownTitle: breakdownTitle
                )
                return PictureBookSpreadModel(
                    id: item.id,
                    spineItem: item,
                    spreadIndex: spreadIndex,
                    storyTitle: story.title,
                    chapterIndex: chapterIndex,
                    chapterTitle: chapterTitle,
                    sceneTitle: sceneTitle,
                    spinePrimaryTitle: sceneTitle,
                    spineContextLabel: StoryReadingSpineTitles.sceneContextLabel(
                        chapter: chapter,
                        chapterIndex: chapterIndex,
                        sceneIndex: sceneIndex
                    ),
                    title: chapterTitle,
                    subtitle: nil,
                    body: scene.captionTarget?.nilIfEmptyForPictureBook,
                    readingMatterPage: nil,
                    scene: scene,
                    panel: panel(for: item, in: story.storyLayout),
                    layoutPanels: layoutPanels(for: item, story: story, adapter: adapter),
                    audioClip: clipsBySceneID[item.id],
                    imageURL: adapter.sceneImageURL(scene: scene, chapterIndex: chapterIndex)
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
    let chapterIndex: Int?
    let chapterTitle: String?
    let sceneTitle: String?
    let spinePrimaryTitle: String
    let spineContextLabel: String
    let title: String?
    let subtitle: String?
    let body: String?
    let readingMatterPage: ReadingMatterPage?
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
                    return chapter.titleTargetLanguage.nilIfEmptyForPictureBook
                case .native:
                    let english = chapter.titleEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
                    return english.nilIfEmptyForPictureBook ?? chapter.titleTargetLanguage.nilIfEmptyForPictureBook
                }
            }()
            return [resolvedChapterTitle, sceneTitle]
                .compactMap { $0?.nilIfEmptyForPictureBook }
                .joined(separator: " / ")
                .nilIfEmptyForPictureBook
        }
    }

    func displayBody(language: StorySessionView.DisplayLanguage) -> String? {
        switch spineItem {
        case .readingMatterPage:
            guard let page = readingMatterPage else { return body }
            switch language {
            case .target:
                return page.bodyTarget?.nilIfEmptyForPictureBook
            case .native:
                return page.bodyNative?.nilIfEmptyForPictureBook ?? page.bodyTarget?.nilIfEmptyForPictureBook
            }
        case .scene:
            guard let scene else { return body }
            return scene.pictureBookPreviewText(english: language == .native)
        default:
            return body
        }
    }

    func displayMatterTitle(language: StorySessionView.DisplayLanguage) -> String? {
        guard let page = readingMatterPage else { return title?.nilIfEmptyForPictureBook }
        switch language {
        case .target:
            return page.titleTarget?.nilIfEmptyForPictureBook
        case .native:
            return page.titleNative?.nilIfEmptyForPictureBook ?? page.titleTarget?.nilIfEmptyForPictureBook
        }
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

private struct PictureBookSpineSheet: View {
    let spreads: [PictureBookSpreadModel]
    let currentSpreadIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            List(Array(spreads.enumerated()), id: \.element.id) { index, spread in
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
            .navigationTitle("Story Spine")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func icon(for spread: PictureBookSpreadModel) -> String {
        switch spread.spineItem {
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

private struct PictureBookSpreadView: View {
    let spread: PictureBookSpreadModel
    let selectedLanguage: StorySessionView.DisplayLanguage
    var readingMatterPlayback: StorySupplementalAudioPlayback? = nil

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
                    case .scene:
                        sceneLayout(in: safeFrame)
                    case .chapter:
                        EmptyView()
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
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
                    if case .readingMatterPage = spread.spineItem,
                       selectedLanguage == .target,
                       let playback = readingMatterPlayback,
                       playback.isUsingGeneratedAudio,
                       !playback.wordTimings.isEmpty {
                        TimedTextView(
                            segment: StorySegmentTiming(
                                speaker: "",
                                text: body,
                                startTime: 0,
                                endTime: .greatestFiniteMagnitude,
                                timings: playback.wordTimings
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
        .frame(minWidth: frame.width, maxWidth: frame.width, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
        .clipped()
    }

    private func coverLayout(in frame: CGRect) -> some View {
        ZStack(alignment: .bottomLeading) {
            PictureBookImage(url: spread.imageURL, cropRegion: .center)
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
        .frame(maxWidth: 520, maxHeight: maxHeight, alignment: .leading)
        .background(.black.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PictureBookImage: View {
    let url: URL?
    let cropRegion: CropRegion

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cropRegion.pictureBookAlignment)
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
    func pictureBookPreviewText(english: Bool) -> String? {
        var lines: [String] = []

        if english {
            if let caption = captionNative?.nilIfEmptyForPictureBook {
                lines.append(caption)
            }
            for dialogue in dialogues {
                guard !dialogue.character.isEmpty else { continue }
                let line = dialogue.textEnglish?.nilIfEmptyForPictureBook
                    ?? dialogue.text.nilIfEmptyForPictureBook
                guard let line else { continue }
                lines.append("\(dialogue.character): \(line)")
            }
            if lines.isEmpty {
                let script = scriptEnglish?.nilIfEmptyForPictureBook
                    ?? scriptTargetLanguage?.nilIfEmptyForPictureBook
                if let script { lines.append(script) }
            }
        } else {
            if let caption = captionTarget?.nilIfEmptyForPictureBook {
                lines.append(caption)
            }
            for dialogue in dialogues {
                guard !dialogue.character.isEmpty,
                      let line = dialogue.text.nilIfEmptyForPictureBook else { continue }
                lines.append("\(dialogue.character): \(line)")
            }
            if lines.isEmpty, let script = scriptTargetLanguage?.nilIfEmptyForPictureBook {
                lines.append(script)
            }
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

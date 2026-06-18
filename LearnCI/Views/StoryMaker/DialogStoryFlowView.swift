import SwiftUI
import Combine

/// Spine-driven dialog story flow: cover, reading matter, and chapter intros as
/// full-screen steps; scene dialogue in an embedded `DialogSessionView`.
struct DialogStoryFlowView: View {
    let story: Story
    private let initialSpineIndex: Int
    private let initialPlaybackPosition: Double?
    private let onProgressChange: ((StoryReaderProgressUpdate) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var spineIndex = 0
    @State private var displayLanguage: StorySessionView.DisplayLanguage = .target
    @State private var playbackRate: Float = 1.0
    @State private var flowPhase: FlowPhase = .spine
    @State private var chapterHeroImage: UIImage?
    @State private var supplementalPlayback = StorySupplementalAudioPlayback()
    @State private var sliderValue: Double = 0
    @State private var lastSavedPlaybackSecond = -1

    private let spinePlaybackTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

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
        _spineIndex = State(initialValue: max(0, initialSpineIndex))
    }

    private enum FlowPhase: Equatable {
        case spine
        case dialogue(chapterIndex: Int)
    }

    private var adapter: StoryReaderDataAdapter {
        StoryReaderDataAdapter(story: story)
    }

    private var spineItems: [StoryReadingSpineItem] {
        adapter.items(for: .dialogStory)
    }

    private var currentSpineItem: StoryReadingSpineItem? {
        guard spineItems.indices.contains(spineIndex) else { return nil }
        return spineItems[spineIndex]
    }

    private var showEnglish: Bool {
        displayLanguage == .native
    }

    var body: some View {
        Group {
            if let issue = adapter.requirementIssue(for: .dialogStory) {
                StoryReaderUnavailableView(title: issue.title, message: issue.message)
            } else {
                flowBody
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            reconcileSpinePosition()
        }
        .mediaPlaybackLifecycle(
            onUserLeave: {
                supplementalPlayback.stop()
                AudioManager.shared.stopAudio()
            },
            onEnterBackground: { AudioManager.shared.updateNowPlayingInfo() }
        )
        .onReceive(spinePlaybackTimer) { _ in
            guard flowPhase == .spine, isOnSupplementalSpineItem else { return }
            supplementalPlayback.syncStreamState()
            sliderValue = supplementalPlayback.currentTime
            saveTimedReadingProgressIfNeeded(position: sliderValue)
        }
        .onChange(of: spineIndex) { _, _ in
            saveReadingProgress()
        }
    }

    private var flowBody: some View {
        VStack(spacing: 0) {
            flowHeader
            phaseContent
            flowFooter
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch flowPhase {
        case .spine:
            spineStepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .dialogue(let chapterIndex):
            DialogSessionView(
                story: story,
                chapterIndex: chapterIndex,
                showEnglish: Binding(
                    get: { showEnglish },
                    set: { displayLanguage = $0 ? .native : .target }
                ),
                playbackRate: $playbackRate,
                onChapterDialogueComplete: { finishDialogue(for: chapterIndex) }
            )
        }
    }

    @ViewBuilder
    private var spineStepContent: some View {
        switch currentSpineItem {
        case .cover:
            dialogCoverPage
        case .readingMatterPage:
            dialogReadingMatterPage
        case .chapter(let index):
            if chapterHasIntroContent(at: index) {
                chapterIntroContent(chapterIndex: index)
            } else {
                Color.clear.onAppear { beginDialogue(for: index) }
            }
        case .scene, .none:
            if spineIndex >= spineItems.count {
                completionView
            } else {
                Color.clear.onAppear { reconcileSpinePosition() }
            }
        }
    }

    private var flowHeader: some View {
        HStack(spacing: 12) {
            Button {
                AudioManager.shared.stopAudio()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 42, height: 42)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(story.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(phaseSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if case .dialogue = flowPhase {
                Menu {
                    Button("0.75x") { playbackRate = 0.75 }
                    Button("1.0x") { playbackRate = 1.0 }
                    Button("1.25x") { playbackRate = 1.25 }
                    Button("1.5x") { playbackRate = 1.5 }
                } label: {
                    Text("\(String(format: "%.1f", playbackRate))x")
                        .font(.caption.bold())
                        .frame(width: 48, height: 36)
                }
            }

            Button {
                displayLanguage = displayLanguage == .native ? .target : .native
            } label: {
                Text(showEnglish ? "EN" : story.languageRaw.uppercased())
                    .font(.caption.bold())
                    .frame(width: 44, height: 36)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private var flowFooter: some View {
        if flowPhase == .spine {
            if spineIndex >= spineItems.count {
                EmptyView()
            } else if showsSpineAudioPlayer {
                spineAudioPlayerBar
            } else {
                HStack {
                    Spacer()
                    Button(spineContinueTitle) {
                        advanceSpineStep()
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .padding(16)
                .background(.thinMaterial)
            }
        }
    }

    private var showsSpineAudioPlayer: Bool {
        if case .readingMatterPage = currentSpineItem { return true }
        if case .chapter(let index) = currentSpineItem, chapterHasIntroContent(at: index) { return true }
        return false
    }

    private var isOnSupplementalSpineItem: Bool {
        if case .readingMatterPage = currentSpineItem { return true }
        if case .chapter(let index) = currentSpineItem, chapterHasIntroContent(at: index) { return true }
        return false
    }

    private var spineAudioPlayerBar: some View {
        AudioPlayerBar(
            isPlaying: Binding(
                get: { supplementalPlayback.isPlaying },
                set: { shouldPlay in
                    supplementalPlayback.syncPlayback(
                        shouldPlay: shouldPlay,
                        speakableText: currentSupplementalSpeakableText
                    )
                }
            ),
            sliderValue: $sliderValue,
            duration: max(supplementalPlayback.duration, 1),
            playbackRate: $playbackRate,
            ambientVolume: .constant(0),
            isAmbientPlaying: false,
            canSeek: supplementalPlayback.canSeek,
            canControlPlayback: canControlSpinePlayback,
            playbackContextLabel: spinePlaybackContextLabel,
            isBuffering: supplementalPlayback.isLoading,
            bufferingLabel: "Loading audio…",
            onPlayPause: toggleSpinePlayback,
            onSkipForward: skipSpineForward,
            onSkipBackward: skipSpineBackward,
            onSeek: seekSpinePlayback,
            onChangeRate: setSpinePlaybackRate,
            onNextChapter: spineStepNavigationHandler(delta: 1),
            onPreviousChapter: spineStepNavigationHandler(delta: -1)
        )
        .disabled(supplementalPlayback.isLoading)
        .ignoresSafeArea(edges: .bottom)
    }

    private var canControlSpinePlayback: Bool {
        if case .readingMatterPage = currentSpineItem {
            return currentReadingMatterCanPlay
        }
        if case .chapter(let index) = currentSpineItem {
            return chapterHasIntroContent(at: index)
        }
        return false
    }

    private var spinePlaybackContextLabel: String? {
        if case .readingMatterPage = currentSpineItem {
            guard currentReadingMatterCanPlay else { return nil }
            return supplementalPlayback.isPlaying ? "Reading Matter · Now Playing" : "Reading Matter"
        }
        if case .chapter(let index) = currentSpineItem, chapterHasIntroContent(at: index) {
            return supplementalPlayback.isPlaying ? "Chapter Intro · Now Playing" : "Chapter Intro"
        }
        return nil
    }

    private var spineContinueTitle: String {
        if case .chapter = currentSpineItem {
            return "Start Dialogue"
        }
        if spineIndex == spineItems.count - 1 {
            return "Done"
        }
        return "Continue"
    }

    private func spineStepNavigationHandler(delta: Int) -> (() -> Void)? {
        if delta > 0 {
            return { advanceSpineStep() }
        }
        guard spineIndex > 0 else { return nil }
        return { goToPreviousSpineStep() }
    }

    private func toggleSpinePlayback() {
        let shouldPlay = !supplementalPlayback.isPlaying
        supplementalPlayback.syncPlayback(
            shouldPlay: shouldPlay,
            speakableText: currentSupplementalSpeakableText
        )
    }

    private func skipSpineForward() {
        guard supplementalPlayback.canSeek else { return }
        seekSpinePlayback(min(sliderValue + 10, max(supplementalPlayback.duration, 1)))
    }

    private func skipSpineBackward() {
        guard supplementalPlayback.canSeek else { return }
        seekSpinePlayback(max(0, sliderValue - 10))
    }

    private func seekSpinePlayback(_ value: Double) {
        supplementalPlayback.seek(to: value)
        sliderValue = value
    }

    private func setSpinePlaybackRate(_ rate: Float) {
        playbackRate = rate
        supplementalPlayback.setRate(rate)
    }

    private func stopSpinePlayback() {
        supplementalPlayback.stop()
        sliderValue = 0
    }

    private var currentSupplementalSpeakableText: String? {
        if case .readingMatterPage = currentSpineItem {
            return currentReadingMatterSpeakableText
        }
        if case .chapter(let index) = currentSpineItem,
           let chapter = story.chapters[safeDialogFlow: index] {
            return StorySupplementalAudioPlayback.chapterIntroSpeakableText(
                chapter: chapter,
                preferNative: showEnglish
            )
        }
        return nil
    }

    private func prepareSupplementalPlaybackForCurrentSpineItem() {
        supplementalPlayback.bind(story: story)
        supplementalPlayback.setRate(playbackRate)
        supplementalPlayback.onFinished = nil

        if let item = currentSpineItem,
           case .readingMatterPage(let pageIndex, _) = item,
           let page = adapter.readingMatterPage(for: item) {
            supplementalPlayback.prepareReadingMatter(
                pageIndex: pageIndex,
                page: page,
                preferNative: showEnglish
            )
            return
        }

        if case .chapter(let index) = currentSpineItem,
           let chapter = story.chapters[safeDialogFlow: index],
           chapterHasIntroContent(at: index) {
            supplementalPlayback.prepareChapterIntro(
                chapterIndex: index,
                chapter: chapter,
                preferNative: showEnglish
            )
        }
    }

    private func goToPreviousSpineStep() {
        stopSpinePlayback()
        AudioManager.shared.stopAudio()

        guard spineIndex > 0 else { return }
        spineIndex -= 1
        flowPhase = .spine
        reconcileSpinePosition()
    }

    private var phaseSubtitle: String {
        switch flowPhase {
        case .dialogue:
            return "Dialog"
        case .spine:
            guard let item = currentSpineItem else { return "Complete" }
            switch item {
            case .cover:
                return "Cover"
            case .readingMatterPage:
                if let page = adapter.readingMatterPage(for: item) {
                    return readingMatterTitle(for: page) ?? "Reading Matter"
                }
                return "Reading Matter"
            case .chapter(let index):
                return chapterSubtitle(for: index)
            case .scene:
                return "Dialog"
            }
        }
    }

    private var dialogCoverPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Color.accentColor.opacity(0.18)
                    case .empty:
                        Color(.secondarySystemBackground).overlay { ProgressView() }
                    @unknown default:
                        Color(.secondarySystemBackground)
                    }
                }
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(story.title)
                    .font(.system(size: 32, weight: .bold, design: .serif))

                Text("\(story.language.displayName) · Level \(story.level)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Color.clear.frame(height: 80)
            }
            .padding()
        }
    }

    @ViewBuilder
    private var dialogReadingMatterPage: some View {
        if let item = currentSpineItem,
           case .readingMatterPage(let pageIndex, _) = item,
           let page = adapter.readingMatterPage(for: item) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let title = readingMatterTitle(for: page) {
                        Text(title)
                            .font(.title2.weight(.bold))
                    }
                    if let body = readingMatterBody(for: page) {
                        if supplementalPlayback.isUsingGeneratedAudio,
                           !supplementalPlayback.wordTimings.isEmpty,
                           !showEnglish {
                            TimedTextView(
                                segment: StorySegmentTiming(
                                    speaker: "",
                                    text: body,
                                    startTime: 0,
                                    endTime: .greatestFiniteMagnitude,
                                    timings: supplementalPlayback.wordTimings
                                ),
                                currentTime: supplementalPlayback.currentTime,
                                includesPadding: false
                            )
                        } else {
                            if showEnglish {
                                Text(body)
                                    .font(.body)
                                    .lineSpacing(8)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            } else {
                                TappableStoryText(
                                    text: body,
                                    font: .body,
                                    lineSpacing: 8,
                                    foregroundColor: .primary
                                )
                            }
                        }
                    }
                    Color.clear.frame(height: 80)
                }
                .padding()
            }
            .onAppear {
                prepareSupplementalPlaybackForCurrentSpineItem()
            }
            .onDisappear {
                supplementalPlayback.stop()
            }
            .onChange(of: displayLanguage) { _, _ in
                let wasPlaying = supplementalPlayback.isPlaying
                prepareSupplementalPlaybackForCurrentSpineItem()
                if wasPlaying {
                    supplementalPlayback.syncPlayback(
                        shouldPlay: true,
                        speakableText: currentReadingMatterSpeakableText
                    )
                }
            }
        } else {
            StoryReaderUnavailableView(
                title: "Reading Matter Missing",
                message: "This reading matter page could not be loaded."
            )
        }
    }

    private func chapterIntroContent(chapterIndex: Int) -> some View {
        Group {
            if let chapter = story.chapters[safeDialogFlow: chapterIndex] {
                ChapterInfoCardView(
                    chapter: chapter,
                    heroImage: chapterHeroImage,
                    selectedLanguage: $displayLanguage,
                    playbackTime: supplementalPlayback.currentTime
                )
                .onAppear {
                    loadChapterHeroImage(for: chapter)
                    prepareSupplementalPlaybackForCurrentSpineItem()
                }
                .onChange(of: displayLanguage) { _, _ in
                    let wasPlaying = supplementalPlayback.isPlaying
                    prepareSupplementalPlaybackForCurrentSpineItem()
                    if wasPlaying {
                        supplementalPlayback.syncPlayback(
                            shouldPlay: true,
                            speakableText: currentSupplementalSpeakableText
                        )
                    }
                }
            } else {
                StoryReaderUnavailableView(
                    title: "Chapter Missing",
                    message: "This chapter could not be loaded."
                )
            }
        }
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text("Story Complete")
                .font(.title2.weight(.bold))
            Button("Done") {
                AudioManager.shared.stopAudio()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var coverURL: URL? {
        if let remoteCoverPath = story.remoteCoverPath?.dialogFlowTrimmedNil {
            return AppConfig.chapterCoverURL(remoteCoverPath)
        }
        if let coverArt = story.coverArt?.dialogFlowTrimmedNil {
            return AppConfig.chapterCoverURL(coverArt)
        }
        return story.chapters.first.flatMap { chapter in
            chapter.coverUrl?.dialogFlowTrimmedNil.flatMap(AppConfig.chapterCoverURL)
        }
    }

    private func readingMatterTitle(for page: ReadingMatterPage) -> String? {
        if showEnglish {
            return page.titleNative?.dialogFlowTrimmedNil ?? page.titleTarget?.dialogFlowTrimmedNil
        }
        return page.titleTarget?.dialogFlowTrimmedNil
    }

    private func readingMatterBody(for page: ReadingMatterPage) -> String? {
        if showEnglish {
            return page.bodyNative?.dialogFlowTrimmedNil ?? page.bodyTarget?.dialogFlowTrimmedNil
        }
        return page.bodyTarget?.dialogFlowTrimmedNil
    }

    private var currentReadingMatterCanPlay: Bool {
        guard let item = currentSpineItem,
              let page = adapter.readingMatterPage(for: item) else { return false }
        return page.hasGeneratedAudio(preferNative: showEnglish) || currentReadingMatterSpeakableText != nil
    }

    private var currentReadingMatterSpeakableText: String? {
        guard let item = currentSpineItem,
              let page = adapter.readingMatterPage(for: item) else { return nil }
        var parts: [String] = []
        if let title = readingMatterTitle(for: page) { parts.append(title) }
        if let body = readingMatterBody(for: page) { parts.append(body) }
        let text = parts.joined(separator: ". ")
        return text.isEmpty ? nil : text
    }

    private func chapterSubtitle(for index: Int) -> String {
        guard let chapter = story.chapters[safeDialogFlow: index] else {
            return "Chapter \(index + 1)"
        }
        let title = showEnglish
            ? (chapter.titleEnglish.dialogFlowTrimmedNil ?? chapter.titleTargetLanguage)
            : chapter.titleTargetLanguage
        return "Chapter \(index + 1) · \(title)"
    }

    private func chapterHasIntroContent(at index: Int) -> Bool {
        guard let chapter = story.chapters[safeDialogFlow: index] else { return false }
        let hasAudio = !(chapter.chapterIntroAudioUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasText = !(chapter.chapterIntroText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasAudio || hasText
    }

    private func loadChapterHeroImage(for chapter: StoryChapter) {
        guard let urlString = chapter.coverUrl,
              let url = AppConfig.chapterCoverURL(urlString) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data, let image = UIImage(data: data) {
                DispatchQueue.main.async { chapterHeroImage = image }
            }
        }.resume()
    }

    private func reconcileSpinePosition() {
        guard flowPhase == .spine else { return }
        if !spineItems.indices.contains(spineIndex), !spineItems.isEmpty {
            spineIndex = 0
        }
        saveReadingProgress()

        while spineIndex < spineItems.count {
            let item = spineItems[spineIndex]
            switch item {
            case .chapter(let index):
                if chapterHasIntroContent(at: index) {
                    return
                }
                beginDialogue(for: index)
                return
            case .scene(let chapterIndex, _):
                beginDialogue(for: chapterIndex)
                return
            case .cover, .readingMatterPage:
                return
            }
        }
    }

    private func advanceSpineStep() {
        stopSpinePlayback()
        AudioManager.shared.stopAudio()

        guard let item = currentSpineItem else {
            dismiss()
            return
        }

        switch item {
        case .cover, .readingMatterPage:
            spineIndex += 1
            if spineIndex >= spineItems.count {
                dismiss()
                return
            }
            reconcileSpinePosition()
        case .chapter(let index):
            beginDialogue(for: index)
        case .scene:
            reconcileSpinePosition()
        }
    }

    private func beginDialogue(for chapterIndex: Int) {
        stopSpinePlayback()
        AudioManager.shared.stopAudio()
        saveReadingProgress()
        flowPhase = .dialogue(chapterIndex: chapterIndex)
    }

    private func finishDialogue(for chapterIndex: Int) {
        AudioManager.shared.stopAudio()
        flowPhase = .spine

        if spineIndex < spineItems.count,
           case .chapter(let index) = spineItems[spineIndex],
           index == chapterIndex {
            spineIndex += 1
        }

        while spineIndex < spineItems.count {
            if case .scene(let index, _) = spineItems[spineIndex], index == chapterIndex {
                spineIndex += 1
            } else {
                break
            }
        }

        reconcileSpinePosition()
    }

    private func saveReadingProgress() {
        guard spineItems.indices.contains(spineIndex) else { return }
        onProgressChange?(StoryReaderProgressUpdate(
            index: spineIndex,
            total: spineItems.count,
            chapterIndex: progressChapterIndex,
            sceneIndex: progressSceneIndex,
            position: sliderValue > 0 ? sliderValue : nil
        ))
    }

    private func saveTimedReadingProgressIfNeeded(position: Double) {
        let second = Int(position.rounded())
        guard second != lastSavedPlaybackSecond else { return }
        lastSavedPlaybackSecond = second
        saveReadingProgress()
    }

    private var progressChapterIndex: Int? {
        switch currentSpineItem {
        case .chapter(let index), .scene(let index, _):
            return index
        default:
            if case .dialogue(let chapterIndex) = flowPhase {
                return chapterIndex
            }
            return nil
        }
    }

    private var progressSceneIndex: Int? {
        if case .scene(_, let sceneIndex) = currentSpineItem {
            return sceneIndex
        }
        return nil
    }
}

private extension Collection {
    subscript(safeDialogFlow index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var dialogFlowTrimmedNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

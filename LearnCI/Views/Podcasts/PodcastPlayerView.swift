import SwiftUI
import SwiftData
import Combine

private enum PodcastPlaybackMode: String, CaseIterable, Identifiable {
    case watch = "Watch"
    case study = "Study"

    var id: String { rawValue }
}

private enum PodcastStudyPaneMode: String, CaseIterable, Identifiable {
    case studyBlock = "Study Block"
    case transcript = "Transcript"
    case timing = "Timing"

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
    @State private var studyPaneDisplayMode: PodcastStudyPaneMode = .studyBlock
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
    @State private var showClearTranscriptConfirm = false
    @State private var showRegenerateTranscriptConfirm = false
    @State private var contentStartEntryText = ""

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
            syncContentStartEntryFromEpisode()
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
                Task {
                    await bootstrapStudyModeIfNeeded()
                    ensurePlaybackAtStudyContentStart()
                }
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
        .confirmationDialog(
            "Clear transcript?",
            isPresented: $showClearTranscriptConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Transcript", role: .destructive) {
                Task { await clearStudyTranscript() }
            }
        } message: {
            Text("Removes the saved study transcript for this episode. Adjust the content start mark if needed, then generate again.")
        }
        .confirmationDialog(
            "Regenerate transcript with AI?",
            isPresented: $showRegenerateTranscriptConfirm,
            titleVisibility: .visible
        ) {
            Button("Regenerate with AI") {
                Task { await regenerateStudyTranscript() }
            }
        } message: {
            Text("Clears the current transcript and runs Whisper again using your current content start mark.")
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
                VStack(alignment: .leading, spacing: 12) {
                    studyPaneModePicker

                    switch studyPaneDisplayMode {
                    case .studyBlock, .transcript:
                        ContentUnavailableView(
                            "Study Mode Unavailable",
                            systemImage: "waveform",
                            description: Text(message)
                        )
                    case .timing:
                        podcastTimingModeView
                    }
                }
            case .loaded:
                if let session = studySessionViewModel {
                    VStack(alignment: .leading, spacing: 12) {
                        studyPaneModePicker

                        switch studyPaneDisplayMode {
                        case .studyBlock:
                            if let note = studyCoverageNote {
                                Label(note, systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

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
                        case .transcript:
                            podcastTranscriptModeView(session: session)
                        case .timing:
                            podcastTimingModeView
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        studyPaneModePicker

                        switch studyPaneDisplayMode {
                        case .studyBlock, .transcript:
                            ContentUnavailableView(
                                "Study Mode Unavailable",
                                systemImage: "waveform",
                                description: Text("No transcript blocks were produced for this episode.")
                            )
                        case .timing:
                            podcastTimingModeView
                        }
                    }
                }
            }
        }
    }

    private var studyPaneModePicker: some View {
        Picker("Study view", selection: $studyPaneDisplayMode) {
            ForEach(PodcastStudyPaneMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var podcastTimingModeView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let note = studyCoverageNote {
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            studyTranscriptActions

            studyContentStartSection

            if studyLoadState == .loaded {
                studyTranscriptSyncSection
            } else {
                Text("Generate or load a transcript to use the alignment timeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

            if offer.descriptionAttempted {
                Label("A transcript link in the episode description could not be used.", systemImage: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var studyContentStart: TimeInterval {
        PodcastStudyContentStart.effectiveStart(for: episode)
    }

    private var studyContentStartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Transcript timing", systemImage: "flag.fill")
                .font(.caption.weight(.semibold))

            Text("AI start controls where Whisper begins. Sync shift nudges loaded transcript timestamps without regenerating.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            studyTimingValuesReadout

            Text("AI transcript start")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Text("Where study content begins on the episode. Whisper records from ~20s before this. Regenerate after changing.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("MM:SS or seconds", text: $contentStartEntryText)
                    .font(.caption.monospacedDigit())
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)

                Button("Set") {
                    applyContentStartFromEntry()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 8) {
                Button {
                    nudgeContentStart(by: -10)
                } label: {
                    Text("-10s").font(.caption2.weight(.semibold))
                }
                .buttonStyle(.bordered)

                Button {
                    nudgeContentStart(by: -1)
                } label: {
                    Text("-1s").font(.caption2.weight(.semibold))
                }
                .buttonStyle(.bordered)

                Button {
                    markStudyContentStartFromPlayhead()
                } label: {
                    Label("Use playhead", systemImage: "play.fill")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.bordered)

                Button {
                    nudgeContentStart(by: 1)
                } label: {
                    Text("+1s").font(.caption2.weight(.semibold))
                }
                .buttonStyle(.bordered)

                Button {
                    nudgeContentStart(by: 10)
                } label: {
                    Text("+10s").font(.caption2.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            if studyContentStart > 0 {
                Button("Clear start mark") {
                    clearStudyContentStart()
                }
                .font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var studyTimingValuesReadout: some View {
        VStack(alignment: .leading, spacing: 6) {
            timingValueRow(
                title: "AI transcript start",
                value: studyContentStart > 0
                    ? PodcastStudyContentStart.formattedTimestampWithSeconds(studyContentStart)
                    : "Not set (0s)",
                hint: "studyContentStartSeconds"
            )

            if studyContentStart > 0 {
                timingValueRow(
                    title: "Whisper clip from",
                    value: PodcastStudyContentStart.formattedTimestampWithSeconds(
                        PodcastStudyContentStart.whisperExportStart(for: episode)
                    ),
                    hint: "20s lead-in before AI start"
                )
            }

            timingValueRow(
                title: "Sync shift",
                value: PodcastStudyContentStart.formattedSignedOffset(episode.studyTranscriptOffsetSeconds),
                hint: "studyTranscriptOffsetSeconds · drag timeline to change"
            )

            if let firstBlock = makeBaseStudyBlocks().first {
                let displayStart = firstBlock.mediaStart + episode.studyTranscriptOffsetSeconds
                timingValueRow(
                    title: "First highlight at",
                    value: PodcastStudyContentStart.formattedTimestampWithSeconds(displayStart),
                    hint: "raw \(PodcastStudyContentStart.formattedTimestampWithSeconds(firstBlock.mediaStart)) + shift"
                )
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.systemBackground).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func timingValueRow(title: String, value: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var studyTranscriptSyncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Align transcript to audio", systemImage: "waveform.path.ecg")
                .font(.caption.weight(.semibold))

            Text("White bars = audio. Teal = transcript. Drag teal strip to align. Use Pan / zoom controls below the waveform.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            let alignedBlocks = makeFocusStudyBlocks()
            if !alignedBlocks.isEmpty {
                PodcastTimingTranscriptSnippet(
                    blocks: alignedBlocks,
                    playbackTime: audioManager.streamCurrentTime,
                    onSeek: { time in
                        if let session = studySessionViewModel,
                           let index = blockIndex(for: time, in: session.blocks) {
                            session.goToBlock(at: index, autoPlay: false)
                        }
                        seekTo(time)
                    }
                )
            }

            if let url = episode.playableAudioURL, !makeBaseStudyBlocks().isEmpty {
                PodcastTranscriptSyncTimelineView(
                    audioURL: url,
                    duration: max(duration, audioManager.streamDuration),
                    currentTime: audioManager.streamCurrentTime,
                    blocks: makeBaseStudyBlocks(),
                    transcriptOffset: episode.studyTranscriptOffsetSeconds,
                    contentStart: studyContentStart,
                    onSeek: { time in
                        seekTo(time)
                    },
                    onOffsetChange: { offset in
                        setTranscriptOffset(to: offset)
                    }
                )
            }

            HStack(spacing: 8) {
                Button {
                    alignTranscriptToCurrentPlayback()
                } label: {
                    Label("Snap to playhead", systemImage: "scope")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)

                if abs(episode.studyTranscriptOffsetSeconds) > 0.05 {
                    Button("Reset shift") {
                        resetTranscriptOffset()
                    }
                    .font(.caption)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var studyTranscriptActions: some View {
        HStack(spacing: 8) {
            Button(role: .destructive) {
                showClearTranscriptConfirm = true
            } label: {
                Label("Clear Transcript", systemImage: "trash")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)

            if OpenAIAPIKeyStorage.isConfigured {
                Button {
                    showRegenerateTranscriptConfirm = true
                } label: {
                    Label("Regenerate with AI", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
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
    private func resetStudyTranscriptState() {
        studyWords = []
        studyCues = []
        studyCachedBlocks = []
        studyCachedCues = []
        studyTranslations = [:]
        studyTranslationState = .idle
        studyCoverageNote = nil
        studyTranscriptSource = nil
        studySessionViewModel = nil
        whisperOffer = nil
        isGeneratingWhisper = false
        studyLoadState = .idle
    }

    @MainActor
    private func clearStudyTranscript() async {
        let language = episode.show?.language ?? .spanish
        transcriptService.clearCachedTranscript(
            episode: episode,
            language: language,
            modelContext: modelContext
        )
        resetStudyTranscriptState()
        didBootstrapStudyMode = false
        showToast("Transcript cleared")
        await bootstrapStudyModeIfNeeded(force: true)
    }

    @MainActor
    private func regenerateStudyTranscript() async {
        let language = episode.show?.language ?? .spanish
        transcriptService.clearCachedTranscript(
            episode: episode,
            language: language,
            modelContext: modelContext
        )
        resetStudyTranscriptState()
        didBootstrapStudyMode = false
        await startWhisperTranscription()
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
                feedAttempted: episode.hasFeedTranscript,
                descriptionAttempted: !episode.episodeDescription.isEmpty
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
            ensurePlaybackAtStudyContentStart()
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
        case .description:
            studyCoverageNote = "Using transcript linked in the episode description."
        case .whisper:
            var whisperNote = "Generated with AI (Whisper)."
            if studyContentStart > 0 {
                let stamp = PodcastStudyContentStart.formattedTimestamp(studyContentStart)
                whisperNote += " Transcribed from your content start mark at \(stamp)."
            }
            if let skippedAds = result.skippedAdSegmentCount, skippedAds > 0 {
                let label = skippedAds == 1 ? "segment" : "segments"
                whisperNote += " Skipped \(skippedAds) ad \(label) marked in show notes."
            }
            if let covers = result.coversDurationSeconds {
                let minutes = Int(covers / 60)
                studyCoverageNote = "\(whisperNote) Covers the first \(minutes) minutes."
            } else {
                studyCoverageNote = whisperNote
            }
        case .cache:
            studyCoverageNote = nil
        }

        if studyContentStart > 0 {
            let stamp = PodcastStudyContentStart.formattedTimestamp(studyContentStart)
            let startNote = "Content starts at \(stamp)."
            if studyCoverageNote?.contains(startNote) != true {
                studyCoverageNote = studyCoverageNote.map { "\($0) \(startNote)" } ?? startNote
            }
        }
    }

    @MainActor
    @discardableResult
    private func hydrateStudyModeFromCacheIfAvailable() -> Bool {
        let languageCode = (episode.show?.language ?? .spanish).rawValue
        let cacheKey = MediaTranscriptCache.makeCacheKey(
            consumptionUrl: episode.audioUrl,
            languageCode: languageCode,
            contentStartSeconds: studyContentStart
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
        } else if !activeStudyWords.isEmpty {
            let source = PodcastStudyBlockSource(
                episode: episode,
                words: activeStudyWords,
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
        let cues = if !studyCues.isEmpty { studyCues } else { studyCachedCues }
        return PodcastStudyContentStart.filterCuesAtOrAfter(cues, start: studyContentStart)
    }

    private var activeStudyWords: [WordTiming] {
        PodcastStudyContentStart.filterWordsAtOrAfter(studyWords, start: studyContentStart)
    }

    private func makeBaseStudyBlocks() -> [StudyBlock] {
        if !activeStudyCues.isEmpty {
            let blocks = CaptionTranscriptProvider(
                cues: activeStudyCues,
                translationForCue: translationForCue,
                focusWindowSize: studyFocusWindowSize
            ).makeBlocks()
            return applyTranslations(to: blocks)
        }
        if !activeStudyWords.isEmpty {
            let blocks = WhisperTranscriptProvider(
                words: activeStudyWords,
                translationForSentenceRange: { start, end in
                    studyTranslations["\(start)-\(end)"]
                },
                focusWindowSize: studyFocusWindowSize
            ).makeBlocks()
            return applyTranslations(to: blocks)
        }
        if !studyCachedBlocks.isEmpty {
            let blocks = PodcastStudyContentStart.filterBlocksAtOrAfter(
                studyCachedBlocks,
                start: studyContentStart
            )
            return applyTranslations(to: blocks)
        }
        return []
    }

    private func makeFocusStudyBlocks() -> [StudyBlock] {
        applyTimingOffset(to: makeBaseStudyBlocks())
    }

    private func applyTimingOffset(to blocks: [StudyBlock]) -> [StudyBlock] {
        PodcastStudyContentStart.applyTimingOffset(
            to: blocks,
            offset: episode.studyTranscriptOffsetSeconds
        )
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
                episode: episode,
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

    private func alignTranscriptToCurrentPlayback() {
        guard let session = studySessionViewModel else {
            showToast("Load a transcript first")
            return
        }

        session.syncCurrentBlockToPlaybackTime()
        guard let block = session.currentBlock else {
            showToast("No transcript block at the current playback time")
            return
        }

        let playbackTime = audioManager.streamCurrentTime
        let delta = playbackTime - block.mediaStart
        guard abs(delta) > 0.05 else {
            showToast("Highlight already matches playback")
            return
        }

        setTranscriptOffset(to: episode.studyTranscriptOffsetSeconds + delta)
        studySessionViewModel?.syncCurrentBlockToPlaybackTime()
        showToast("Matched — shifted \(PodcastStudyContentStart.formattedSignedOffset(delta))")
    }

    private func setTranscriptOffset(to offset: TimeInterval) {
        let clamped = min(600, max(-600, offset))
        guard abs(clamped - episode.studyTranscriptOffsetSeconds) > 0.01 else { return }
        episode.studyTranscriptOffsetSeconds = clamped
        episode.isSynced = false
        try? modelContext.save()

        if studyLoadState == .loaded {
            refreshStudySessionBlocks()
            studySessionViewModel?.syncCurrentBlockToPlaybackTime()
        }
    }

    private func resetTranscriptOffset() {
        guard abs(episode.studyTranscriptOffsetSeconds) > 0.05 else { return }
        setTranscriptOffset(to: 0)
        showToast("Transcript alignment reset")
    }

    private func syncContentStartEntryFromEpisode() {
        contentStartEntryText = studyContentStart > 0
            ? PodcastStudyContentStart.formattedTimestamp(studyContentStart)
            : ""
    }

    private func applyContentStartFromEntry() {
        guard let seconds = PodcastStudyContentStart.parseTimestampEntry(contentStartEntryText) else {
            showToast("Enter time as MM:SS, H:MM:SS, or seconds")
            return
        }
        applyContentStartAt(seconds: seconds)
    }

    private func markStudyContentStartFromPlayhead() {
        applyContentStartAt(seconds: max(0, audioManager.streamCurrentTime))
    }

    private func nudgeContentStart(by delta: TimeInterval) {
        let base = studyContentStart > 0 ? studyContentStart : audioManager.streamCurrentTime
        applyContentStartAt(seconds: max(0, base + delta))
    }

    private func applyContentStartAt(seconds: TimeInterval) {
        let previousStart = episode.studyContentStartSeconds
        let clamped: TimeInterval
        if duration > 1 {
            clamped = min(max(0, seconds), duration - 0.5)
        } else {
            clamped = max(0, seconds)
        }
        episode.studyContentStartSeconds = clamped
        episode.isSynced = false
        try? modelContext.save()
        syncContentStartEntryFromEpisode()

        let stamp = PodcastStudyContentStart.formattedTimestamp(clamped)
        let startChanged = abs(clamped - previousStart) > 1

        if startChanged {
            let language = episode.show?.language ?? .spanish
            transcriptService.clearCachedTranscripts(
                episode: episode,
                language: language,
                modelContext: modelContext
            )
            resetStudyTranscriptState()
            didBootstrapStudyMode = false
            showToast("AI start set to \(stamp). Regenerate transcript.")
            Task { await bootstrapStudyModeIfNeeded(force: true) }
            return
        }

        showToast("AI start set to \(stamp)")
    }

    private func clearStudyContentStart() {
        guard studyContentStart > 0 else { return }
        episode.studyContentStartSeconds = 0
        episode.isSynced = false
        try? modelContext.save()
        syncContentStartEntryFromEpisode()

        let language = episode.show?.language ?? .spanish
        transcriptService.clearCachedTranscripts(
            episode: episode,
            language: language,
            modelContext: modelContext
        )
        resetStudyTranscriptState()
        didBootstrapStudyMode = false
        showToast("Content start cleared. Regenerate transcript to include earlier audio.")
        Task { await bootstrapStudyModeIfNeeded(force: true) }
    }

    private func ensurePlaybackAtStudyContentStart() {
        guard studyContentStart > 1 else { return }
        if audioManager.streamCurrentTime < studyContentStart - 0.5 {
            seekTo(studyContentStart)
        }
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

        isPlaying = false
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
            }
            audioManager.playStream()
            isPlaying = audioManager.isStreaming
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

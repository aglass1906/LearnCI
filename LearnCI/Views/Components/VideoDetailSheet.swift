import SwiftUI
import SwiftData

struct VideoDetailSheet: View {
    let video: YouTubeVideo
    let startInStudyMode: Bool
    let onWatch: () -> Void
    let onLogTime: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(SavedStudyWordManager.self) private var savedStudyWordManager
    @Environment(MediaStudyStore.self) private var mediaStudyStore
    @Query private var allProfiles: [UserProfile]

    private let captionService = YouTubeCaptionService()
    private let openAIService = OpenAIService()

    private var favoriteVideoUrl: String {
        "https://www.youtube.com/watch?v=\(video.id)"
    }

    @State private var watchDuration: TimeInterval = 0
    @State private var hasLoggedTime = false
    @State private var studyViewModel: YouTubeStudyViewModel
    @State private var seekRequest: Double?
    @State private var playbackRateRequest: Float?
    @State private var playRequest: Bool?
    @State private var pauseRequest: Bool?
    @State private var seekAndPlayRequest: Double?
    @State private var didBootstrapStudyMode = false
    @State private var isLookingUpWord = false
    @State private var translationRequestsInFlight: Set<Int> = []
    @State private var studyPaneDisplayMode: StudyPaneDisplayMode = .focus
    @State private var studyContextWindowSize: YouTubeStudyPanel.ContextWindowSize = .small
    @State private var showInSheetOptions = false
    @State private var showSessionSetup = false
    @State private var showNotes = false
    @State private var studySessionViewModel: StudySessionViewModel?
    @State private var youtubeStudyMediaPlayer = YouTubeStudyMediaPlayer()
    @State private var studyFocusWindowSize: StudyFocusWindowSize = .sentence
    @State private var layoutSize: CGSize = .zero
    @State private var savedStudyRevision = 0
    @State private var mediaStudyRevision = 0
    @State private var didApplyInitialStudyMode = false

    private let playbackRates: [Float] = [0.75, 1.0, 1.25, 1.5]

    private enum StudyPaneDisplayMode: String {
        case focus = "Focus"
        case context = "Context"
        case transcript = "Transcript"
    }

    private var currentUserProfile: UserProfile? {
        allProfiles.first { $0.userID == authManager.currentUser }
    }

    private var compactStudyChrome: Bool {
        usesStudyLandscapeLayout(for: layoutSize)
    }

    private var showsTranscriptBelowStudyBlock: Bool {
        studyPaneDisplayMode == .transcript
    }

    init(
        video: YouTubeVideo,
        startInStudyMode: Bool = false,
        onWatch: @escaping () -> Void,
        onLogTime: @escaping (Int) -> Void
    ) {
        self.video = video
        self.startInStudyMode = startInStudyMode
        self.onWatch = onWatch
        self.onLogTime = onLogTime
        _studyViewModel = State(initialValue: YouTubeStudyViewModel(video: video))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                Group {
                    if usesStudyLandscapeLayout(for: geometry.size) {
                        studyLandscapeLayout
                    } else {
                        standardLayout
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .onAppear {
                    layoutSize = geometry.size
                }
                .onChange(of: geometry.size) { _, newSize in
                    layoutSize = newSize
                }
            }
            .overlay(alignment: .topLeading) {
                if compactStudyChrome {
                    Button("Close") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
            }
            .navigationTitle(compactStudyChrome ? "" : video.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(compactStudyChrome ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if !compactStudyChrome {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
                if !compactStudyChrome {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        playbackSpeedToolbarMenu
                        modeToolbarButton(
                            mode: .watch,
                            icon: "eye.fill",
                            accessibilityLabel: "Watch mode"
                        )
                        modeToolbarButton(
                            mode: .study,
                            icon: "captions.bubble.fill",
                            accessibilityLabel: "Study mode"
                        )
                        FavoriteButton(
                            consumptionUrl: favoriteVideoUrl,
                            type: .youtube,
                            title: video.title,
                            author: video.channelTitle,
                            subtitle: video.durationInMinutes > 0 ? "\(video.durationInMinutes) min" : nil,
                            imageUrl: video.thumbnailURL
                        )
                        .font(.title3)
                    }
                }
            }
            .onAppear {
                wireYouTubeStudyMediaPlayer()
                hydrateStudyModeFromCacheIfAvailable()
                if studyViewModel.mode == .study {
                    syncStudySessionViewModel()
                }
                if startInStudyMode && !didApplyInitialStudyMode && studyViewModel.mode == .watch {
                    didApplyInitialStudyMode = true
                    setViewingMode(.study)
                }
            }
            .task {
                await bootstrapStudyModeIfNeeded()
            }
            .sheet(
                isPresented: Binding(
                    get: { studyViewModel.selectedLookup != nil },
                    set: { isPresented in
                        if !isPresented {
                            studyViewModel.clearLookup()
                            isLookingUpWord = false
                        }
                    }
                )
            ) {
                if let selectedLookup = studyViewModel.selectedLookup {
                    WordLookupSheet(
                        word: selectedLookup.word,
                        languageLabel: lookupSourceLanguageName,
                        translation: studyViewModel.lookupResult?.translation,
                        partOfSpeech: studyViewModel.lookupResult?.partOfSpeech,
                        isLoading: isLookingUpWord,
                        seekTime: selectedLookup.cueIndex.flatMap { cueIndex in
                            studyViewModel.activeCues.first(where: { $0.index == cueIndex })?.startTime
                        },
                        onSeek: { time in
                            seekPlayer(to: time)
                        },
                        onMarkForStudy: {
                            markWordForStudy(
                                word: selectedLookup.word,
                                cueIndex: selectedLookup.cueIndex,
                                contextText: selectedLookup.contextText
                            )
                        },
                        isMarkedForStudy: isWordMarkedForStudy(selectedLookup.word)
                    )
                    .presentationDetents([.medium])
                }
            }
            .sheet(isPresented: $showSessionSetup) {
                if let session = studySessionViewModel {
                    StudySessionSetupSheet(
                        blocks: session.blocks,
                        currentBlockIndex: session.currentBlockIndex,
                        onStart: { definition in
                            session.startSession(definition)
                            saveSessionRecord(definition: definition)
                            let state = mediaStudyStore.markStudying(
                                video: video,
                                userID: authManager.currentUser,
                                in: modelContext
                            )
                            mediaStudyStore.updateProgress(
                                state,
                                positionSeconds: studyViewModel.playback.currentTime,
                                totalBlockCount: session.blocks.count,
                                in: modelContext
                            )
                            mediaStudyRevision += 1
                        }
                    )
                }
            }
            .sheet(isPresented: $showNotes) {
                if let session = studySessionViewModel,
                   let block = session.currentBlock,
                   let userID = authManager.currentUser {
                    StudyNotesSheet(
                        resource: session.resource,
                        block: block,
                        currentMediaTime: session.mediaPlayer.currentTime,
                        userID: userID,
                        onSeek: seekPlayer
                    )
                }
            }
            .onDisappear {
                if !hasLoggedTime && watchDuration > 10 {
                    let minutes = Int(max(1, watchDuration / 60))
                    onLogTime(minutes)
                }
                // Refresh progress only for videos already being studied —
                // plain watching must never add a Studying row.
                if let state = mediaStudyStore.studyState(
                    resourceType: .youtube,
                    resourceId: video.id,
                    userID: authManager.currentUser,
                    in: modelContext
                ) {
                    mediaStudyStore.updateProgress(
                        state,
                        positionSeconds: studyViewModel.playback.currentTime,
                        durationSeconds: Double(video.durationInSeconds),
                        completedBlockCount: studySessionViewModel.map { $0.completedBlockIndices.count },
                        in: modelContext
                    )
                }
            }
        }
    }

    private func usesStudyLandscapeLayout(for size: CGSize) -> Bool {
        studyViewModel.mode == .study && AdaptiveLayoutPolicy.usesLearningSplit(for: size)
    }

    private var standardLayout: some View {
        VStack(spacing: 0) {
            topSection

            Divider()
                .padding(.horizontal)

            detailScrollContent
        }
    }

    private var studyLandscapeLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            studyLandscapeMediaColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)

            Divider()

            studyLandscapeStudyColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var studyLandscapeMediaColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            youtubePlayer
                .padding(.horizontal)
                .padding(.top, compactStudyChrome ? 0 : 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            compactInSheetHeader
                .background(Color(UIColor.systemBackground))
        }
        .safeAreaPadding(.top, compactStudyChrome ? 8 : 0)
    }

    private var studyLandscapeStudyColumn: some View {
        studyLandscapeStudyDetail
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(UIColor.systemBackground))
    }

    private var studyLandscapeStudyDetail: some View {
        studyContent(fillsAvailableHeight: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }

    private var compactInSheetHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                sheetWatchTimeLabel
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            inSheetOptionsMenu
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var sheetWatchTimeLabel: some View {
        if watchDuration > 0 {
            let watchedMinutes = max(1, Int(watchDuration / 60))
            HStack(spacing: 4) {
                Image(systemName: "timer")
                Text("Watched \(watchedMinutes) min")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var inSheetOptionsMenu: some View {
        Button {
            showInSheetOptions = true
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Study options")
        .sheet(isPresented: $showInSheetOptions) {
            inSheetOptionsSheet
        }
    }

    private var inSheetOptionsSheet: some View {
        NavigationStack {
            List {
                Section("Video") {
                    LabeledContent("Channel", value: video.channelTitle)
                    if video.durationInMinutes > 0 {
                        LabeledContent("Length", value: "\(video.durationInMinutes) min")
                    }
                }

                if studyViewModel.canEnterStudyMode {
                    NavigationLink("Study View") {
                        inSheetStudyViewOptionsList
                    }
                    NavigationLink("Captions") {
                        inSheetCaptionsInfoList
                    }
                    NavigationLink("Track") {
                        inSheetTrackPickerList
                    }
                }

                if !video.chapters.isEmpty {
                    NavigationLink("Chapters") {
                        inSheetChaptersList
                    }
                }
            }
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showInSheetOptions = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var inSheetStudyViewOptionsList: some View {
        List {
            studyPaneListRow(.focus, icon: "text.book.closed")
            studyPaneListRow(.context, icon: "text.bubble")
            studyPaneListRow(.transcript, icon: "list.bullet.rectangle")
        }
        .navigationTitle("Study View")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var inSheetCaptionsInfoList: some View {
        List {
            if let selectedTrack = studyViewModel.selectedTrack {
                LabeledContent("Current track", value: selectedTrack.displayLabel)
            } else {
                LabeledContent("Current track", value: "None selected")
            }

            if let preferredStudyLanguageName, !selectedTrackMatchesTargetLanguage {
                LabeledContent("Target language", value: preferredStudyLanguageName)
            }
        }
        .navigationTitle("Captions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var inSheetTrackPickerList: some View {
        List {
            ForEach(studyViewModel.availableTracks) { track in
                Button {
                    Task {
                        await switchStudyTrack(to: track)
                        showInSheetOptions = false
                    }
                } label: {
                    HStack {
                        Text(trackMenuTitle(for: track))
                        Spacer()
                        if track.id == studyViewModel.selectedTrack?.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .disabled(studyViewModel.captionLoadState == .loading)
            }
        }
        .navigationTitle("Track")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var inSheetChaptersList: some View {
        List {
            ForEach(video.chapters) { chapter in
                Button {
                    seekPlayer(to: chapter.startTime)
                    showInSheetOptions = false
                } label: {
                    HStack {
                        Text("\(chapter.formattedTimestamp)  \(chapter.title)")
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if chapter.id == currentChapter?.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle("Chapters")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func studyPaneListRow(_ mode: StudyPaneDisplayMode, icon: String) -> some View {
        Button {
            studyPaneDisplayMode = mode
            showInSheetOptions = false
        } label: {
            HStack {
                Label(mode.rawValue, systemImage: icon)
                Spacer()
                if studyPaneDisplayMode == mode {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var detailScrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compactStudyChrome ? 10 : 16) {
                if !compactStudyChrome {
                    studyStatusBanner
                    studyThisSection
                }

                if studyViewModel.mode == .study {
                    studyContent()
                } else {
                    watchContent
                }

                if !compactStudyChrome {
                    actionButtons
                }
            }
            .padding(compactStudyChrome ? 12 : 16)
        }
    }

    private var youtubePlayer: some View {
        YouTubePlayerView(
            videoID: video.id,
            videoURL: video.videoStreamURL,
            watchDuration: $watchDuration,
            seekRequest: $seekRequest,
            playbackRateRequest: $playbackRateRequest,
            playRequest: $playRequest,
            pauseRequest: $pauseRequest,
            seekAndPlayRequest: $seekAndPlayRequest,
            initialPlaybackTime: studyViewModel.playback.currentTime,
            initialPlaybackRate: studyViewModel.playback.playbackRate,
            shouldResumePlayback: studyViewModel.playback.isPlaying,
            onPlaybackSnapshot: handlePlaybackSnapshot
        )
        .cornerRadius(12)
        .shadow(radius: 5)
    }

    private var topSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            youtubePlayer
                .frame(height: 220)

            compactInSheetHeader
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var playbackSpeedToolbarMenu: some View {
        Menu {
            ForEach(playbackRates, id: \.self) { rate in
                Button {
                    setPlayerPlaybackRate(rate)
                } label: {
                    if isSelectedPlaybackRate(rate) {
                        Label(String(format: "%.2gx", rate), systemImage: "checkmark")
                    } else {
                        Text(String(format: "%.2gx", rate))
                    }
                }
            }
        } label: {
            Image(systemName: "speedometer")
        }
        .accessibilityLabel("Playback speed")
    }

    private func modeToolbarButton(
        mode: YouTubeStudyMode,
        icon: String,
        accessibilityLabel: String
    ) -> some View {
        let isSelected = studyViewModel.mode == mode

        return Button {
            setViewingMode(mode)
        } label: {
            Image(systemName: icon)
                .foregroundStyle(isSelected ? .blue : .primary)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func setViewingMode(_ newMode: YouTubeStudyMode) {
        studyViewModel.setMode(newMode)

        if newMode == .study {
            studyPaneDisplayMode = .focus
            // Entering study mode is a deliberate study action — track it.
            mediaStudyStore.markStudying(
                video: video,
                userID: authManager.currentUser,
                in: modelContext
            )
            mediaStudyRevision += 1
            Task {
                await bootstrapStudyModeIfNeeded(force: !studyViewModel.canEnterStudyMode)
                await ensureTranslationsForCurrentCue()
                syncStudySessionViewModel()
            }
        } else {
            studySessionViewModel?.playbackController.stopBlockPlayback()
        }
    }

    private func isSelectedPlaybackRate(_ rate: Float) -> Bool {
        abs(studyViewModel.playback.playbackRate - rate) < 0.01
    }

    @ViewBuilder
    private var studyStatusBanner: some View {
        switch studyViewModel.captionLoadState {
        case .loading:
            Label("Checking captions for study mode…", systemImage: "captions.bubble")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            statusCard(icon: "exclamationmark.triangle.fill", text: message, color: .orange)
        case .loaded:
            switch studyViewModel.availability {
            case .available:
                if studyViewModel.mode == .watch {
                    statusCard(icon: "sparkles.tv.fill", text: "Study mode is ready for this video.", color: .blue)
                }
            case .unavailable(let reason):
                statusCard(icon: "captions.bubble.fill", text: reason, color: .secondary)
            case .unknown:
                EmptyView()
            }
        case .idle:
            if case let .unavailable(reason) = studyViewModel.availability {
                statusCard(icon: "captions.bubble.fill", text: reason, color: .secondary)
            }
        }
    }

    private func statusCard(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var watchContent: some View {
        if !video.description.isEmpty {
            Text(video.description)
                .font(.body)
        }
    }

    @ViewBuilder
    private func studyContent(fillsAvailableHeight: Bool = false) -> some View {
        switch studyViewModel.captionLoadState {
        case .idle, .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading caption tracks and transcript…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        case .failed(let message):
            ContentUnavailableView(
                "Study Mode Unavailable",
                systemImage: "captions.bubble",
                description: Text(message)
            )
        case .loaded:
            if studyViewModel.canEnterStudyMode {
                if studyPaneDisplayMode == .focus, let session = studySessionViewModel {
                    StudySessionShell(
                        session: session,
                        userID: authManager.currentUser,
                        focusWindowSize: $studyFocusWindowSize,
                        translationState: studyViewModel.translationLoadState,
                        showsTranscript: showsTranscriptBelowStudyBlock,
                        fillsAvailableHeight: fillsAvailableHeight,
                        transcript: {
                            transcriptPanel
                        },
                        onWordTap: { word in
                            lookupWordInFocus(word)
                        },
                        onDefineSession: { showSessionSetup = true },
                        onNotes: { showNotes = true },
                        onFocusWindowSizeChange: applyFocusWindowSize
                    )
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: fillsAvailableHeight ? .infinity : nil,
                        alignment: .topLeading
                    )
                } else {
                    YouTubeStudyPanel(
                        displayMode: studyPaneDisplayMode == .transcript ? .transcript : .context,
                        contextWindowSize: studyContextWindowSize,
                        trackLabel: studyViewModel.selectedTrack?.displayLabel,
                        activeCue: studyViewModel.contextCue,
                        activeCueTranslation: studyViewModel.contextCue.flatMap { studyViewModel.translatedCue(for: $0)?.text },
                        cues: studyViewModel.activeCues,
                        activeCueID: studyViewModel.activeCue?.id,
                        translationState: studyViewModel.translationLoadState,
                        translationForCue: { cue in
                            studyViewModel.translatedCue(for: cue)?.text
                        },
                        onContextWindowSizeChange: { studyContextWindowSize = $0 },
                        onSeek: seekPlayer,
                        onWordTap: lookupWord
                    )
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: fillsAvailableHeight ? .infinity : nil,
                        alignment: .topLeading
                    )
                }


                if !compactStudyChrome, !video.description.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("About This Video")
                            .font(.headline)
                        Text(video.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            } else {
                ContentUnavailableView(
                    "Study Mode Unavailable",
                    systemImage: "captions.bubble",
                    description: Text(unavailableReason)
                )
            }
        }
    }

    private var currentMediaStudyState: MediaStudyState? {
        _ = mediaStudyRevision
        return mediaStudyStore.studyState(
            resourceType: .youtube,
            resourceId: video.id,
            userID: authManager.currentUser,
            in: modelContext
        )
    }

    @ViewBuilder
    private var studyThisSection: some View {
        if let state = currentMediaStudyState {
            HStack(spacing: 10) {
                Image(systemName: "book.pages.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(studyingProgressText(for: state))
                        .font(.caption.weight(.semibold))
                    ProgressView(value: state.progressFraction)
                        .tint(.accentColor)
                }
                Spacer()
                Button("Remove") {
                    mediaStudyStore.unstudy(state, in: modelContext)
                    mediaStudyRevision += 1
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        } else {
            Button {
                mediaStudyStore.markStudying(
                    video: video,
                    userID: authManager.currentUser,
                    in: modelContext
                )
                mediaStudyRevision += 1
            } label: {
                Label("Study This Video", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(10)
            }
        }
    }

    private func studyingProgressText(for state: MediaStudyState) -> String {
        guard state.durationSeconds > 0 else { return "Studying" }
        let positionMinutes = Int(state.lastPositionSeconds / 60)
        let totalMinutes = max(1, Int(state.durationSeconds / 60))
        return "Studying · \(positionMinutes)m of \(totalMinutes)m"
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: {
                onLogTime(Int(max(1, watchDuration / 60)))
                hasLoggedTime = true
            }) {
                Label("Log Watch Time Now", systemImage: "clock.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }

            Button(action: onWatch) {
                Label("Open in YouTube App", systemImage: "arrow.up.right.video.fill")
                    .font(.headline)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
            }
        }
        .padding(.top)
    }

    private var unavailableReason: String {
        if case let .unavailable(reason) = studyViewModel.availability {
            return reason
        }
        return "No captioned study data is available for this video."
    }

    @MainActor
    private func bootstrapStudyModeIfNeeded(force: Bool = false) async {
        guard force || !didBootstrapStudyMode else { return }
        didBootstrapStudyMode = true
        Logger.debug("Bootstrapping study mode for video \(video.id)", category: .youtube)

        let hydratedFromCache = hydrateStudyModeFromCacheIfAvailable()
        if !hydratedFromCache {
            studyViewModel.setCaptionLoadState(.loading)
        }

        do {
            let tracks = try await captionService.discoverTracks(videoID: video.id)
            studyViewModel.seedAvailableTracks(tracks)
            Logger.info("Discovered \(tracks.count) study tracks for video \(video.id)", category: .youtube)

            guard let selectedTrack = YouTubeCaptionService.selectPreferredTrack(
                from: tracks,
                preferredLanguageCode: preferredStudyLanguageCode
            ) else {
                throw YouTubeCaptionServiceError.trackNotFound
            }

            try await loadStudyTrack(selectedTrack, preferCached: !force)
        } catch {
            Logger.error("Study mode bootstrap failed for video \(video.id): \(error.localizedDescription)", category: .youtube)
            if hydrateStudyModeFromCacheIfAvailable() {
                Logger.warning("Recovered study mode from cached transcript after failure for video \(video.id)", category: .youtube)
            } else {
                studyViewModel.setCaptionLoadState(.failed(message: error.localizedDescription))
                studyViewModel.setStudyUnavailable(reason: error.localizedDescription)
            }
        }
    }

    @MainActor
    @discardableResult
    private func hydrateStudyModeFromCacheIfAvailable() -> Bool {
        guard let (cachedTrack, cachedCaption) = bestCachedCaption() else { return false }

        let cachedTranslation = fetchLatestTranslationCache(for: cachedTrack)
        studyViewModel.seedAvailableTracks(fetchCaptionCaches().compactMap(\.track))
        studyViewModel.selectTrack(id: cachedTrack.id)
        studyViewModel.hydrateFromCaches(
            captionCache: cachedCaption,
            translationCache: cachedTranslation
        )
        studyViewModel.setCaptionLoadState(.loaded)
        Logger.info("Loaded study transcript from cache for video \(video.id)", category: .youtube)
        if studyViewModel.mode == .study {
            syncStudySessionViewModel()
        }
        return true
    }

    @MainActor
    private func switchStudyTrack(to track: YouTubeCaptionTrack) async {
        guard track.id != studyViewModel.selectedTrack?.id else { return }

        do {
            try await loadStudyTrack(track, preferCached: true)
            await ensureTranslationsForCurrentCue()
        } catch {
            studyViewModel.setCaptionLoadState(.failed(message: error.localizedDescription))
            Logger.error(
                "Study track switch failed for video \(video.id) [\(track.languageCode)]: \(error.localizedDescription)",
                category: .youtube
            )
        }
    }

    private func handlePlaybackSnapshot(_ snapshot: YouTubePlayerPlaybackSnapshot) {
        let previousActiveCueID = studyViewModel.activeCue?.id
        studyViewModel.updatePlayback(
            currentTime: snapshot.currentTime,
            duration: snapshot.duration,
            isPlaying: snapshot.isPlaying,
            playbackRate: snapshot.playbackRate
        )
        youtubeStudyMediaPlayer.applySnapshot(
            currentTime: snapshot.currentTime,
            duration: snapshot.duration,
            isPlaying: snapshot.isPlaying,
            playbackRate: snapshot.playbackRate
        )

        if studyViewModel.mode == .study {
            studySessionViewModel?.handlePlaybackTime(
                snapshot.currentTime,
                isPlaying: snapshot.isPlaying
            )
            if studyViewModel.activeCue?.id != previousActiveCueID {
                Task {
                    await ensureTranslationsForCurrentCue()
                    refreshStudySessionBlocks()
                }
            }
        }
    }

    private var transcriptPanel: some View {
        YouTubeStudyPanel(
            displayMode: .transcript,
            contextWindowSize: studyContextWindowSize,
            trackLabel: studyViewModel.selectedTrack?.displayLabel,
            activeCue: studyViewModel.contextCue,
            activeCueTranslation: studyViewModel.contextCue.flatMap { studyViewModel.translatedCue(for: $0)?.text },
            cues: studyViewModel.activeCues,
            activeCueID: studySessionViewModel?.currentBlock?.id ?? studyViewModel.activeCue?.id,
            translationState: studyViewModel.translationLoadState,
            translationForCue: { cue in
                studyViewModel.translatedCue(for: cue)?.text
            },
            onContextWindowSizeChange: { studyContextWindowSize = $0 },
            onSeek: { time in
                seekPlayer(to: time)
                studySessionViewModel?.syncCurrentBlockToPlaybackTime()
            },
            onWordTap: lookupWord
        )
    }

    private func wireYouTubeStudyMediaPlayer() {
        youtubeStudyMediaPlayer.onSeek = { time in
            seekPlayer(to: time)
        }
        youtubeStudyMediaPlayer.onSeekAndPlay = { time in
            seekAndPlayRequest = time
        }
        youtubeStudyMediaPlayer.onPlay = {
            playRequest = true
        }
        youtubeStudyMediaPlayer.onPause = {
            pauseRequest = true
        }
        youtubeStudyMediaPlayer.onSetRate = { rate in
            setPlayerPlaybackRate(rate)
        }
    }

    private func syncStudySessionViewModel() {
        guard studyViewModel.canEnterStudyMode, !studyViewModel.activeCues.isEmpty else {
            studySessionViewModel = nil
            return
        }

        let source = YouTubeStudyBlockSource(
            video: video,
            cues: studyViewModel.activeCues,
            languageCode: studyViewModel.selectedTrack?.languageCode,
            focusWindowSize: studyFocusWindowSize,
            translationForCue: { cue in
                studyViewModel.translatedCue(for: cue)?.text
            },
            mediaPlayer: youtubeStudyMediaPlayer
        )
        let session = StudySessionViewModel(source: source)
        if let activeCue = studyViewModel.activeCue,
           let blockIndex = session.blockIndex(for: activeCue) {
            session.goToBlock(at: blockIndex, autoPlay: false)
        } else {
            session.syncCurrentBlockToPlaybackTime()
        }
        studySessionViewModel = session
    }

    private func refreshStudySessionBlocks() {
        guard let session = studySessionViewModel else {
            syncStudySessionViewModel()
            return
        }
        let blocks = makeFocusStudyBlocks()
        session.rebuildBlocks(blocks, anchorTime: session.mediaPlayer.currentTime)
    }

    private func applyFocusWindowSize(_ size: StudyFocusWindowSize) {
        studyFocusWindowSize = size
        guard let session = studySessionViewModel else { return }
        let blocks = makeFocusStudyBlocks()
        session.rebuildBlocks(blocks, anchorTime: session.mediaPlayer.currentTime)
    }

    private func makeFocusStudyBlocks() -> [StudyBlock] {
        CaptionTranscriptProvider(
            cues: studyViewModel.activeCues,
            translationForCue: { cue in
                studyViewModel.translatedCue(for: cue)?.text
            },
            focusWindowSize: studyFocusWindowSize
        ).makeBlocks()
    }

    private func lookupWordInFocus(_ word: String) {
        guard let block = studySessionViewModel?.currentBlock else { return }
        let cue: YouTubeCaptionCue
        let blockCues = studyViewModel.activeCues.filter { block.contains(cueIndex: $0.index) }
        let matchingCues = blockCues.filter {
            $0.normalizedText.localizedCaseInsensitiveContains(word)
        }
        if let activeCue = studyViewModel.activeCue,
           block.contains(cueIndex: activeCue.index),
           activeCue.normalizedText.localizedCaseInsensitiveContains(word) {
            cue = activeCue
        } else if let matchingCue = matchingCues.first {
            cue = matchingCue
        } else if let cueStartIndex = block.cueStartIndex,
                  studyViewModel.activeCues.indices.contains(cueStartIndex) {
            cue = studyViewModel.activeCues[cueStartIndex]
        } else {
            cue = YouTubeCaptionCue(
                index: block.index,
                startTime: block.mediaStart,
                endTime: block.mediaEnd,
                text: block.targetText
            )
        }
        lookupWord(word, cue: cue)
    }

    private func markWordForStudy(word: String, cueIndex: Int?, contextText: String?) {
        guard let userID = authManager.currentUser,
              let session = studySessionViewModel else { return }
        let blockIndex = cueIndex ?? session.currentBlockIndex
        let mediaTime = session.mediaPlayer.currentTime
        let block = session.currentBlock
        let selectedCue = cueIndex.flatMap { cueIndex in
            studyViewModel.activeCues.first(where: { $0.index == cueIndex })
        }
        let capture = SavedStudyWordCapture(
            userID: userID,
            word: word,
            translation: studyViewModel.lookupResult?.translation,
            lemma: nil,
            sentenceTarget: contextText ?? selectedCue?.normalizedText ?? block?.targetText,
            sentenceNative: selectedCue.flatMap { studyViewModel.translatedCue(for: $0)?.text } ?? block?.nativeText,
            languageCode: session.resource.languageCode ?? lookupLanguageCode,
            level: nil,
            partOfSpeech: studyViewModel.lookupResult?.partOfSpeech,
            verbTense: nil,
            grammarNotes: nil,
            sourceType: .youtube,
            sourceId: session.resource.resourceId,
            sourceTitle: session.resource.title,
            sourceUrl: session.resource.consumptionUrl,
            blockIndex: blockIndex,
            mediaStart: selectedCue?.startTime ?? block?.mediaStart ?? mediaTime,
            mediaEnd: selectedCue?.endTime ?? block?.mediaEnd,
            audioWordFile: nil,
            audioSentenceFile: nil,
            deckFolderName: nil
        )
        savedStudyWordManager.toggleSave(capture: capture, in: modelContext)
        savedStudyRevision += 1
    }

    private var lookupLanguageCode: String {
        currentUserProfile?.currentLanguage.code ?? "es"
    }

    private func isWordMarkedForStudy(_ word: String) -> Bool {
        _ = savedStudyRevision
        guard let userID = authManager.currentUser,
              let session = studySessionViewModel else { return false }
        return savedStudyWordManager.isSaved(
            word: word,
            userID: userID,
            languageCode: session.resource.languageCode ?? lookupLanguageCode,
            sourceType: .youtube,
            sourceId: session.resource.resourceId,
            in: modelContext
        )
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
    }

    @MainActor
    private func ensureTranslationsForCurrentCue() async {
        guard let track = studyViewModel.selectedTrack else { return }
        guard let activeCue = studyViewModel.activeCue else { return }

        let candidateCues = studyViewModel.activeCues.filter { cue in
            abs(cue.index - activeCue.index) <= 2 &&
            studyViewModel.translatedCue(for: cue) == nil &&
            !translationRequestsInFlight.contains(cue.index)
        }

        guard !candidateCues.isEmpty else { return }

        translationRequestsInFlight.formUnion(candidateCues.map(\.index))
        studyViewModel.setTranslationLoadState(.loading)

        do {
            let translated = try await openAIService.translateCaptionCueBatch(
                cues: candidateCues,
                sourceLanguage: track.languageName
            )
            mergeTranslatedCues(translated, for: track)
            studyViewModel.setTranslationLoadState(.loaded)
        } catch {
            if studyViewModel.translatedCues.isEmpty {
                studyViewModel.setTranslationLoadState(.failed(message: error.localizedDescription))
            }
        }

        translationRequestsInFlight.subtract(candidateCues.map(\.index))
    }

    @MainActor
    private func lookupWord(_ word: String, cue: YouTubeCaptionCue) {
        studyViewModel.selectWord(word, cueIndex: cue.index, contextText: cue.normalizedText)

        let sourceLanguageCode = studyViewModel.selectedTrack?.languageCode ?? preferredStudyLanguageCode ?? "und"
        if let cachedLookup = fetchWordLookupCache(
            word: word,
            sourceLanguageCode: sourceLanguageCode,
            contextText: cue.normalizedText
        ) {
            studyViewModel.applyLookupResult(
                word: cachedLookup.word,
                translation: cachedLookup.translation,
                partOfSpeech: cachedLookup.partOfSpeech,
                contextText: cachedLookup.contextText
            )
            isLookingUpWord = false
            Logger.debug("Loaded cached word lookup for '\(word)' [\(sourceLanguageCode)]", category: .youtube)
            return
        }

        isLookingUpWord = true
        Logger.debug(
            "Requesting word lookup for '\(word)' using source language '\(lookupPromptLanguageName)'",
            category: .youtube
        )
        Task {
            do {
                let result = try await openAIService.translateWord(
                    word,
                    language: lookupPromptLanguageName,
                    context: cue.normalizedText
                )
                await MainActor.run {
                    saveWordLookup(
                        word: word,
                        sourceLanguageCode: sourceLanguageCode,
                        contextText: cue.normalizedText,
                        translation: result.translation,
                        partOfSpeech: result.partOfSpeech
                    )
                    studyViewModel.applyLookupResult(
                        word: word,
                        translation: result.translation,
                        partOfSpeech: result.partOfSpeech,
                        contextText: cue.normalizedText
                    )
                    isLookingUpWord = false
                    Logger.debug("Resolved word lookup for '\(word)' to '\(result.translation)'", category: .youtube)
                }
            } catch {
                await MainActor.run {
                    let errorMessage = String(describing: error)
                    studyViewModel.applyLookupResult(
                        word: word,
                        translation: "Translation unavailable",
                        partOfSpeech: nil,
                        contextText: cue.normalizedText
                    )
                    isLookingUpWord = false
                    Logger.error("Word lookup failed for '\(word)': \(errorMessage)", category: .youtube)
                }
            }
        }
    }

    private func seekPlayer(to time: Double) {
        studyViewModel.requestSeek(to: time)
        seekRequest = studyViewModel.consumePendingSeek()
    }

    private func setPlayerPlaybackRate(_ rate: Float) {
        studyViewModel.requestPlaybackRate(rate)
        playbackRateRequest = studyViewModel.consumePendingPlaybackRate()
    }

    @MainActor
    private func loadStudyTrack(_ track: YouTubeCaptionTrack, preferCached: Bool) async throws {
        translationRequestsInFlight = []
        isLookingUpWord = false
        studyViewModel.prepareForTrackChange(id: track.id)

        Logger.debug(
            "Loading study track \(track.id) [\(track.languageCode)] for video \(video.id)",
            category: .youtube
        )

        if preferCached, let cachedCaption = fetchCaptionCache(for: track) {
            let cachedTranslation = fetchLatestTranslationCache(for: track)
            studyViewModel.hydrateFromCaches(
                captionCache: cachedCaption,
                translationCache: cachedTranslation
            )
            studyViewModel.setCaptionLoadState(.loaded)
            Logger.info("Loaded study transcript from cache for video \(video.id)", category: .youtube)
            if studyViewModel.mode == .study {
                syncStudySessionViewModel()
            }
            return
        }

        let cues = try await captionService.fetchCues(for: track)
        studyViewModel.applyTranscript(cues: cues, track: track)
        if studyViewModel.mode == .study {
            syncStudySessionViewModel()
        }
        saveCaptionCache(track: track, cues: cues)
        Logger.info("Fetched \(cues.count) study cues for video \(video.id)", category: .youtube)

        if let translationCache = fetchLatestTranslationCache(for: track) {
            studyViewModel.applyTranslatedCues(translationCache.translatedCues)
            Logger.debug(
                "Loaded \(translationCache.translatedCues.count) translated cues from cache for video \(video.id)",
                category: .youtube
            )
        } else {
            studyViewModel.applyTranslatedCues([])
        }
    }

    private var currentChapter: YouTubeVideoChapter? {
        let chapters = video.chapters
        guard !chapters.isEmpty else { return nil }

        let currentTime = studyViewModel.playback.currentTime
        return chapters.last(where: { $0.startTime <= currentTime + 0.25 }) ?? chapters.first
    }

    private var preferredStudyLanguageCode: String? {
        currentUserProfile?.currentLanguage.rawValue ?? video.language?.rawValue
    }

    private var preferredStudyLanguageName: String? {
        currentUserProfile?.currentLanguage.displayName ?? video.language?.displayName
    }

    private var selectedTrackMatchesTargetLanguage: Bool {
        guard let preferredStudyLanguageCode,
              let selectedTrack = studyViewModel.selectedTrack else {
            return true
        }

        return normalizedLanguageCode(selectedTrack.languageCode) == normalizedLanguageCode(preferredStudyLanguageCode)
    }

    private func trackMenuTitle(for track: YouTubeCaptionTrack) -> String {
        if normalizedLanguageCode(track.languageCode) == normalizedLanguageCode(preferredStudyLanguageCode) {
            return "\(track.displayLabel) • Target"
        }

        return track.displayLabel
    }

    private func normalizedLanguageCode(_ code: String?) -> String {
        guard let code else { return "" }
        return code
            .split(separator: "-")
            .first
            .map(String.init)?
            .lowercased() ?? code.lowercased()
    }

    private var lookupSourceLanguageName: String {
        studyViewModel.selectedTrack?.languageName ?? video.language?.displayName ?? "Caption"
    }

    private var lookupPromptLanguageName: String {
        lookupSourceLanguageName
            .replacingOccurrences(
                of: #"\s*\(auto-generated\)\s*$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func fetchLatestCaptionCache() -> YouTubeCaptionCache? {
        fetchCaptionCaches().first
    }

    @MainActor
    private func fetchCaptionCaches() -> [YouTubeCaptionCache] {
        let videoID = video.id
        let descriptor = FetchDescriptor<YouTubeCaptionCache>(
            predicate: #Predicate { cache in
                cache.videoID == videoID
            },
            sortBy: [SortDescriptor(\YouTubeCaptionCache.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    @MainActor
    private func fetchCaptionCache(for track: YouTubeCaptionTrack) -> YouTubeCaptionCache? {
        fetchCaptionCaches().first(where: {
            $0.trackID == track.id && $0.sourceLanguageCode == track.languageCode
        })
    }

    @MainActor
    private func bestCachedCaption() -> (YouTubeCaptionTrack, YouTubeCaptionCache)? {
        let caches = fetchCaptionCaches()
        let tracks = caches.compactMap(\.track)
        guard let bestTrack = YouTubeCaptionService.selectPreferredTrack(
            from: tracks,
            preferredLanguageCode: preferredStudyLanguageCode
        ), let bestCache = fetchCaptionCache(for: bestTrack) else {
            return nil
        }
        return (bestTrack, bestCache)
    }

    @MainActor
    private func fetchLatestTranslationCache(for track: YouTubeCaptionTrack) -> YouTubeCaptionTranslationCache? {
        let videoID = video.id
        let descriptor = FetchDescriptor<YouTubeCaptionTranslationCache>(
            predicate: #Predicate { cache in
                cache.videoID == videoID
            },
            sortBy: [SortDescriptor(\YouTubeCaptionTranslationCache.updatedAt, order: .reverse)]
        )

        guard let caches = try? modelContext.fetch(descriptor) else { return nil }
        return caches.first(where: {
            $0.trackID == track.id &&
            $0.sourceLanguageCode == track.languageCode &&
            $0.targetLanguageCode == "en"
        })
    }

    @MainActor
    private func saveCaptionCache(track: YouTubeCaptionTrack, cues: [YouTubeCaptionCue]) {
        if let existing = fetchCaptionCache(for: track) {
            existing.replace(track: track, cues: cues)
        } else {
            modelContext.insert(
                YouTubeCaptionCache(
                    videoID: video.id,
                    track: track,
                    cues: cues
                )
            )
        }
        try? modelContext.save()
    }

    @MainActor
    private func mergeTranslatedCues(_ translatedCues: [YouTubeTranslatedCue], for track: YouTubeCaptionTrack) {
        let existingCache = fetchLatestTranslationCache(for: track)
        let existingTranslated = existingCache?.translatedCues ?? studyViewModel.translatedCues

        let merged = Dictionary(
            uniqueKeysWithValues: (existingTranslated + translatedCues).map { ($0.cueIndex, $0) }
        )
        .values
        .sorted { $0.cueIndex < $1.cueIndex }

        if let existingCache {
            existingCache.replaceTranslatedCues(merged)
        } else {
            modelContext.insert(
                YouTubeCaptionTranslationCache(
                    videoID: video.id,
                    trackID: track.id,
                    sourceLanguageCode: track.languageCode,
                    targetLanguageCode: "en",
                    translatedCues: merged
                )
            )
        }

        try? modelContext.save()
        studyViewModel.applyTranslatedCues(merged)
    }

    @MainActor
    private func fetchWordLookupCache(
        word: String,
        sourceLanguageCode: String,
        contextText: String?
    ) -> YouTubeWordLookupCache? {
        let videoID = video.id
        let descriptor = FetchDescriptor<YouTubeWordLookupCache>(
            predicate: #Predicate { cache in
                cache.videoID == videoID
            },
            sortBy: [SortDescriptor(\YouTubeWordLookupCache.updatedAt, order: .reverse)]
        )

        let targetCacheKey = YouTubeWordLookupCache.makeCacheKey(
            videoID: videoID,
            sourceLanguageCode: sourceLanguageCode,
            word: word,
            contextText: contextText
        )

        guard let caches = try? modelContext.fetch(descriptor) else { return nil }
        return caches.first(where: { $0.cacheKey == targetCacheKey })
    }

    @MainActor
    private func saveWordLookup(
        word: String,
        sourceLanguageCode: String,
        contextText: String?,
        translation: String,
        partOfSpeech: String?
    ) {
        if let existing = fetchWordLookupCache(
            word: word,
            sourceLanguageCode: sourceLanguageCode,
            contextText: contextText
        ) {
            existing.applyResult(translation: translation, partOfSpeech: partOfSpeech)
        } else {
            modelContext.insert(
                YouTubeWordLookupCache(
                    videoID: video.id,
                    sourceLanguageCode: sourceLanguageCode,
                    word: word,
                    contextText: contextText,
                    translation: translation,
                    partOfSpeech: partOfSpeech
                )
            )
        }
        try? modelContext.save()
    }
}

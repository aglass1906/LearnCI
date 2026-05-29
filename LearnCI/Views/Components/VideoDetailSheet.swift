import SwiftUI
import SwiftData

struct VideoDetailSheet: View {
    let video: YouTubeVideo
    let onWatch: () -> Void
    let onLogTime: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
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
    @State private var didBootstrapStudyMode = false
    @State private var isLookingUpWord = false
    @State private var translationRequestsInFlight: Set<Int> = []
    @State private var studyPaneDisplayMode: StudyPaneDisplayMode = .context
    @State private var studyContextWindowSize: YouTubeStudyPanel.ContextWindowSize = .small

    private let playbackRates: [Float] = [0.75, 1.0, 1.25, 1.5]

    private enum StudyPaneDisplayMode: String {
        case context = "Context"
        case transcript = "Transcript"
    }

    private var currentUserProfile: UserProfile? {
        allProfiles.first { $0.userID == authManager.currentUser }
    }

    init(
        video: YouTubeVideo,
        onWatch: @escaping () -> Void,
        onLogTime: @escaping (Int) -> Void
    ) {
        self.video = video
        self.onWatch = onWatch
        self.onLogTime = onLogTime
        _studyViewModel = State(initialValue: YouTubeStudyViewModel(video: video))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topSection

                Divider()
                    .padding(.horizontal)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        studyStatusBanner

                        if studyViewModel.mode == .study {
                            studyContent
                        } else {
                            watchContent
                        }

                        actionButtons
                    }
                    .padding()
                }
            }
            .navigationTitle(video.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
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
            .onAppear {
                hydrateStudyModeFromCacheIfAvailable()
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
                        }
                    )
                    .presentationDetents([.medium])
                }
            }
            .onDisappear {
                if !hasLoggedTime && watchDuration > 10 {
                    let minutes = Int(max(1, watchDuration / 60))
                    onLogTime(minutes)
                }
            }
        }
    }

    private var topSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            YouTubePlayerView(
                videoID: video.id,
                videoURL: video.videoStreamURL,
                watchDuration: $watchDuration,
                seekRequest: $seekRequest,
                playbackRateRequest: $playbackRateRequest,
                onPlaybackSnapshot: handlePlaybackSnapshot
            )
            .frame(height: 220)
            .cornerRadius(12)
            .shadow(radius: 5)

            compactInSheetHeader
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var compactInSheetHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(video.channelTitle)
                            .lineLimit(1)

                        if video.durationInMinutes > 0 {
                            Text("•")
                            Text("\(video.durationInMinutes) min")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    if !video.chapters.isEmpty {
                        chapterMenu
                    }
                    watchStatsBadge
                }
            }

            if studyViewModel.mode == .study, studyViewModel.canEnterStudyMode {
                studyTrackControls
                studyPaneToggle
            }
        }
    }

    private var chapterMenu: some View {
        let chapters = video.chapters

        return Menu {
            ForEach(chapters) { chapter in
                Button {
                    seekPlayer(to: chapter.startTime)
                } label: {
                    if chapter.id == currentChapter?.id {
                        Label(
                            "\(chapter.formattedTimestamp)  \(chapter.title)",
                            systemImage: "checkmark"
                        )
                    } else {
                        Text("\(chapter.formattedTimestamp)  \(chapter.title)")
                    }
                }
            }
        } label: {
            Label("Chapters", systemImage: "list.bullet.rectangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(Capsule())
        }
        .accessibilityLabel("Jump to chapter")
    }

    @ViewBuilder
    private var studyTrackControls: some View {
        if let selectedTrack = studyViewModel.selectedTrack {
            HStack(spacing: 8) {
                currentTrackBadge(for: selectedTrack)

                if studyViewModel.availableTracks.count > 1 {
                    trackPickerMenu
                }

                Spacer(minLength: 0)

                if let preferredStudyLanguageName, !selectedTrackMatchesTargetLanguage {
                    Text("Target: \(preferredStudyLanguageName)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func currentTrackBadge(for track: YouTubeCaptionTrack) -> some View {
        Label(track.displayLabel, systemImage: "captions.bubble.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(selectedTrackMatchesTargetLanguage ? .blue : .orange)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(trackBadgeBackgroundColor)
            .clipShape(Capsule())
    }

    private var trackPickerMenu: some View {
        Menu {
            ForEach(studyViewModel.availableTracks) { track in
                Button {
                    Task {
                        await switchStudyTrack(to: track)
                    }
                } label: {
                    if track.id == studyViewModel.selectedTrack?.id {
                        Label(trackMenuTitle(for: track), systemImage: "checkmark")
                    } else {
                        Text(trackMenuTitle(for: track))
                    }
                }
                .disabled(studyViewModel.captionLoadState == .loading)
            }
        } label: {
            Label("Track", systemImage: "globe")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(Capsule())
        }
        .accessibilityLabel("Change caption track")
        .disabled(studyViewModel.captionLoadState == .loading)
    }

    private var studyPaneToggle: some View {
        HStack(spacing: 8) {
            studyPaneButton(.context, icon: "text.bubble")
            studyPaneButton(.transcript, icon: "list.bullet.rectangle")
        }
        .padding(4)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(Capsule())
    }

    private func studyPaneButton(_ mode: StudyPaneDisplayMode, icon: String) -> some View {
        let isSelected = studyPaneDisplayMode == mode

        return Button {
            studyPaneDisplayMode = mode
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(mode.rawValue)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? .white : .primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
            studyPaneDisplayMode = .context
            Task {
                await bootstrapStudyModeIfNeeded(force: !studyViewModel.canEnterStudyMode)
                await ensureTranslationsForCurrentCue()
            }
        }
    }

    private func isSelectedPlaybackRate(_ rate: Float) -> Bool {
        abs(studyViewModel.playback.playbackRate - rate) < 0.01
    }

    @ViewBuilder
    private var watchStatsBadge: some View {
        if watchDuration > 0 {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                Text("Watching: \(Int(watchDuration))s")
            }
            .font(.caption)
            .foregroundStyle(.blue)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color.blue.opacity(0.1))
            .clipShape(Capsule())
        }
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
    private var studyContent: some View {
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
                YouTubeStudyPanel(
                    displayMode: studyPaneDisplayMode == .context ? .context : .transcript,
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

                if !video.description.isEmpty {
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

        if studyViewModel.mode == .study,
           studyViewModel.activeCue?.id != previousActiveCueID {
            Task {
                await ensureTranslationsForCurrentCue()
            }
        }
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
            return
        }

        let cues = try await captionService.fetchCues(for: track)
        studyViewModel.applyTranscript(cues: cues, track: track)
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

    private var trackBadgeBackgroundColor: Color {
        selectedTrackMatchesTargetLanguage ? Color.blue.opacity(0.12) : Color.orange.opacity(0.14)
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

import SwiftUI
import SwiftData

struct LearnHubView: View {
    let columns = [
        GridItem(.flexible(), spacing: 16)
    ]

    @Environment(AuthManager.self) private var authManager

    @Query(sort: \StoryStudyState.updatedAt, order: .reverse) private var allStudyStates: [StoryStudyState]
    @Query(sort: \MediaStudyState.updatedAt, order: .reverse) private var allMediaStudyStates: [MediaStudyState]

    private var studyStates: [StoryStudyState] {
        allStudyStates.filter { $0.isActive && $0.userID == authManager.currentUser }
    }

    private var mediaStudyStates: [MediaStudyState] {
        allMediaStudyStates.filter { $0.isActive && $0.userID == authManager.currentUser }
    }

    private var studyingSubtitle: String {
        let count = studyStates.count + mediaStudyStates.count
        return count == 0
            ? "Stories, videos, and podcasts you're studying"
            : "\(count) in progress — resume where you left off"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        NavigationLink(destination: ContinueListeningView()) {
                            HubPanelHero(
                                title: "Continue Listening",
                                subtitle: "Resume stories and podcasts where you left off",
                                icon: "play.circle.fill",
                                gradient: Gradient(colors: [.indigo, .purple])
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: PlaybackQueueView()) {
                            HubPanelHero(
                                title: "Listening Queue",
                                subtitle: "Manage what is playing and coming next",
                                icon: "text.line.first.and.arrowtriangle.forward",
                                gradient: Gradient(colors: [.cyan, .blue])
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: AboutCIView()) {
                            HubPanelHero(
                                title: "Comprehensive Learning",
                                subtitle: "Study the method behind input-first language learning",
                                icon: "book.closed.fill",
                                gradient: Gradient(colors: [.blue, .teal])
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: StudyingView()) {
                            HubPanelHero(
                                title: "Studying",
                                subtitle: studyingSubtitle,
                                icon: "book.pages.fill",
                                gradient: Gradient(colors: [.purple, .indigo])
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: SavedStudyWordsView()) {
                            HubPanelHero(
                                title: "Saved Study Words",
                                subtitle: "Review words saved from flashcards, stories, YouTube, and podcasts",
                                icon: "star.text.square.fill",
                                gradient: Gradient(colors: [.yellow, .orange])
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Learn")
            .navigationBarTitleDisplayMode(.large)
        }
    }

}

/// Dedicated screen listing every input item currently in Study Mode —
/// stories, YouTube videos, and podcast episodes — merged and sorted by
/// most recently studied.
struct StudyingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(StoryPathProgressStore.self) private var pathProgressStore
    @Environment(MediaStudyStore.self) private var mediaStudyStore

    @Query private var stories: [Story]
    @Query private var episodes: [PodcastEpisode]
    @Query private var allProfiles: [UserProfile]
    @Query(sort: \StoryStudyState.updatedAt, order: .reverse) private var allStudyStates: [StoryStudyState]
    @Query(sort: \MediaStudyState.updatedAt, order: .reverse) private var allMediaStudyStates: [MediaStudyState]

    @State private var selectedVideo: YouTubeVideo?

    private enum StudyingItem: Identifiable {
        case story(StoryStudyState)
        case media(MediaStudyState)

        var id: UUID {
            switch self {
            case .story(let state): return state.id
            case .media(let state): return state.id
            }
        }

        var updatedAt: Date {
            switch self {
            case .story(let state): return state.updatedAt
            case .media(let state): return state.updatedAt
            }
        }
    }

    private var items: [StudyingItem] {
        let storyItems = allStudyStates
            .filter { $0.isActive && $0.userID == authManager.currentUser }
            .map(StudyingItem.story)
        let mediaItems = allMediaStudyStates
            .filter { $0.isActive && $0.userID == authManager.currentUser }
            .map(StudyingItem.media)
        return (storyItems + mediaItems).sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("Nothing in Study Mode", systemImage: "book.pages")
                } description: {
                    Text("Open a story, video, or podcast and tap \u{201C}Study This\u{201D} to begin a guided study session.")
                }
            } else {
                List {
                    ForEach(items) { item in
                        rowView(for: item)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    remove(item)
                                } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Studying")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedVideo) { video in
            VideoDetailSheet(
                video: video,
                startInStudyMode: true,
                onWatch: {
                    if let url = URL(string: "https://www.youtube.com/watch?v=\(video.id)") {
                        UIApplication.shared.open(url)
                    }
                    selectedVideo = nil
                },
                onLogTime: { minutes in
                    logVideoWatchTime(minutes, video: video)
                    selectedVideo = nil
                }
            )
        }
    }

    @ViewBuilder
    private func rowView(for item: StudyingItem) -> some View {
        switch item {
        case .story(let state):
            storyRowView(for: state)
        case .media(let state):
            mediaRowView(for: state)
        }
    }

    @ViewBuilder
    private func storyRowView(for state: StoryStudyState) -> some View {
        if let story = story(withID: state.storyID) {
            NavigationLink {
                StoryPathContainerView(story: story)
            } label: {
                StudyingRow(state: state, story: story)
            }
            .buttonStyle(.plain)
        } else {
            StudyingRow(state: state, story: nil).opacity(0.6)
        }
    }

    @ViewBuilder
    private func mediaRowView(for state: MediaStudyState) -> some View {
        switch state.resourceType {
        case .youtube:
            Button {
                selectedVideo = makeVideo(from: state)
            } label: {
                MediaStudyingRow(state: state, episode: nil)
            }
            .buttonStyle(.plain)
        case .podcast:
            if let episode = episode(withID: state.resourceId) {
                NavigationLink {
                    PodcastPlayerView(episode: episode)
                } label: {
                    MediaStudyingRow(state: state, episode: episode)
                }
                .buttonStyle(.plain)
            } else {
                MediaStudyingRow(state: state, episode: nil).opacity(0.6)
            }
        default:
            MediaStudyingRow(state: state, episode: nil).opacity(0.6)
        }
    }

    private func remove(_ item: StudyingItem) {
        switch item {
        case .story(let state):
            pathProgressStore.unstudy(state, in: modelContext)
        case .media(let state):
            mediaStudyStore.unstudy(state, in: modelContext)
        }
    }

    private func story(withID storyID: String) -> Story? {
        guard let uuid = UUID(uuidString: storyID) else { return nil }
        return stories.first(where: { $0.id == uuid })
    }

    private func episode(withID resourceId: String) -> PodcastEpisode? {
        guard let uuid = UUID(uuidString: resourceId) else { return nil }
        return episodes.first(where: { $0.id == uuid })
    }

    /// Videos aren't persisted anywhere, so the sheet is rebuilt from the
    /// study-state snapshot (same pattern as FavoritesView.openBuiltinVideo).
    private func makeVideo(from state: MediaStudyState) -> YouTubeVideo {
        YouTubeVideo(
            id: state.resourceId,
            title: state.title,
            description: "",
            thumbnailURL: state.artworkUrl ?? "https://img.youtube.com/vi/\(state.resourceId)/mqdefault.jpg",
            channelTitle: state.subtitle ?? "YouTube",
            duration: "PT0S",
            publishedAt: state.startedAt
        )
    }

    private func logVideoWatchTime(_ minutes: Int, video: YouTubeVideo) {
        guard minutes > 0 else { return }
        let language = allProfiles.first { $0.userID == authManager.currentUser }?.currentLanguage ?? .spanish
        let activity = UserActivity(
            date: Date(),
            minutes: minutes,
            activityType: .watchingVideos,
            language: language,
            userID: authManager.currentUser,
            comment: "\(video.title) [ID:\(video.id)]"
        )
        modelContext.insert(activity)
        try? modelContext.save()
    }
}

private struct StudyingRow: View {
    let state: StoryStudyState
    var story: Story?

    private var lastTouchedText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: state.updatedAt, relativeTo: Date())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            StoryCoverThumbnail(story: story)
                .overlay(alignment: .bottomTrailing) {
                    StudyMediaTypeBadge(systemImage: "book.closed.fill")
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(state.storyTitle)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Scene \(state.currentOrdinal + 1) of \(max(1, state.totalChunks))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: state.progressFraction)
                    .tint(.accentColor)
                Text("Last studied \(lastTouchedText)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .layoutPriority(1)
            Spacer()
            Image(systemName: "arrow.right.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Row for a YouTube video or podcast episode in Study Mode. Prefers the
/// live episode's playback position over the snapshot when it resolves.
private struct MediaStudyingRow: View {
    let state: MediaStudyState
    var episode: PodcastEpisode?

    private var isPodcast: Bool { state.resourceType == .podcast }

    private var positionSeconds: Double {
        if let episode { return episode.playbackPosition }
        return state.lastPositionSeconds
    }

    private var durationSeconds: Double {
        if let episode, episode.duration > 0 { return episode.duration }
        return state.durationSeconds
    }

    private var progressFraction: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(1, max(0, positionSeconds / durationSeconds))
    }

    private var captionText: String {
        var parts: [String] = [isPodcast ? "Podcast" : "Video"]
        if let subtitle = state.subtitle, !subtitle.isEmpty {
            parts.append(subtitle)
        }
        if durationSeconds > 0 {
            parts.append("\(Int(positionSeconds / 60))m of \(max(1, Int(durationSeconds / 60)))m")
        }
        return parts.joined(separator: " · ")
    }

    private var lastTouchedText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: state.updatedAt, relativeTo: Date())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            artwork
                .overlay(alignment: .bottomTrailing) {
                    StudyMediaTypeBadge(systemImage: isPodcast ? "mic.fill" : "play.fill")
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(state.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(captionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if durationSeconds > 0 {
                    ProgressView(value: progressFraction)
                        .tint(.accentColor)
                }
                Text("Last studied \(lastTouchedText)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .layoutPriority(1)
            Spacer()
            Image(systemName: "arrow.right.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var artwork: some View {
        if let urlString = state.artworkUrl, let url = URL(string: urlString) {
            CachedAsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                fallbackArtwork
            }
            .frame(width: 52, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            fallbackArtwork
        }
    }

    private var fallbackArtwork: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                LinearGradient(
                    colors: isPodcast ? [.orange.opacity(0.75), .orange] : [.red.opacity(0.75), .red],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 52, height: 68)
            .overlay(
                Image(systemName: isPodcast ? "mic.fill" : "play.rectangle.fill")
                    .foregroundStyle(.white)
                    .font(.title2)
            )
    }
}

/// 52×68 story cover for Studying rows: local cover file first, then the
/// remote Supabase cover via CachedAsyncImage, falling back to the accent
/// gradient. Read-only — no download-and-cache side effects.
private struct StoryCoverThumbnail: View {
    var story: Story?
    @State private var localImage: UIImage?

    var body: some View {
        Group {
            if let image = localImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if let remoteURL {
                CachedAsyncImage(url: remoteURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    fallbackArtwork
                }
                .frame(width: 52, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                fallbackArtwork
            }
        }
        .task(id: story?.id) {
            loadLocalImage()
        }
    }

    private var remoteURL: URL? {
        if let path = story?.remoteCoverPath, !path.isEmpty {
            return AppConfig.chapterCoverURL(path)
        }
        // coverArt occasionally holds a full URL rather than a local filename.
        if let coverArt = story?.coverArt, coverArt.hasPrefix("http") {
            return URL(string: coverArt)
        }
        return nil
    }

    private func loadLocalImage() {
        guard let coverFilename = story?.coverArt, !coverFilename.isEmpty,
              !coverFilename.hasPrefix("http") else { return }
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let localURL = documentsDirectory.appendingPathComponent(coverFilename)
        localImage = UIImage(contentsOfFile: localURL.path)
    }

    private var fallbackArtwork: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(LinearGradient(colors: [.accentColor.opacity(0.75), .accentColor], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 52, height: 68)
            .overlay(
                Image(systemName: "book.pages.fill")
                    .foregroundStyle(.white)
                    .font(.title2)
            )
    }
}

/// Tiny corner badge identifying the media type of a Studying row.
private struct StudyMediaTypeBadge: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Color.black.opacity(0.65), in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
            .padding(2)
    }
}

#Preview {
    LearnHubView()
        .modelContainer(
            for: [
                Story.self,
                StoryPathProgress.self,
                StoryStudyState.self,
                MediaStudyState.self,
                PodcastShow.self,
                PodcastEpisode.self,
                UserProfile.self
            ],
            inMemory: true
        )
        .environment(AuthManager())
        .environment(StoryPathProgressStore())
        .environment(MediaStudyStore())
}

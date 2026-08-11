import SwiftData
import SwiftUI

struct ContinueListeningView: View {
    @Environment(AuthManager.self) private var authManager
    @Query private var stories: [Story]
    @Query private var episodes: [PodcastEpisode]
    @Query(sort: \MediaPlaybackState.updatedAt, order: .reverse) private var mediaPlaybackStates: [MediaPlaybackState]
    @State private var selectedVideo: YouTubeVideo?

    private enum Item: Identifiable {
        case story(Story, StoryReaderProgress)
        case podcast(PodcastEpisode)
        case youtube(MediaPlaybackState)

        var id: String {
            switch self {
            case .story(let story, _): return "story:\(story.id)"
            case .podcast(let episode): return "podcast:\(episode.id)"
            case .youtube(let state): return "youtube:\(state.resourceId)"
            }
        }

        var updatedAt: Date {
            switch self {
            case .story(_, let progress): return progress.updatedAt
            case .podcast(let episode): return episode.publishedDate
            case .youtube(let state): return state.updatedAt
            }
        }
    }

    private var items: [Item] {
        let storyItems = stories.compactMap { story -> Item? in
            guard story.userID.isEmpty || story.userID == authManager.currentUser else { return nil }
            guard let progress = StoryReaderProgressStore.progress(
                for: story.id,
                readerKind: .audioPlayback
            ), SharedListeningEligibility.canResumeStory(progress) else { return nil }
            return .story(story, progress)
        }

        let podcastItems = episodes.compactMap { episode -> Item? in
            guard SharedListeningEligibility.canResumePodcast(
                position: episode.playbackPosition,
                duration: episode.duration,
                isPlayed: episode.isPlayed
            ) else { return nil }
            guard episode.show?.userID == nil || episode.show?.userID == authManager.currentUser else { return nil }
            return .podcast(episode)
        }

        let youtubeItems = mediaPlaybackStates.compactMap { state -> Item? in
            guard state.userID == authManager.currentUser,
                  state.resourceType == .youtube,
                  MediaPlaybackStore.canResume(state) else { return nil }
            return .youtube(state)
        }

        return Array((storyItems + podcastItems + youtubeItems).sorted { $0.updatedAt > $1.updatedAt }.prefix(8))
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to Resume", systemImage: "play.circle")
                } description: {
                    Text("Stories, podcasts, and videos appear here after you begin playing them.")
                }
            } else {
                List(items) { item in
                    row(for: item)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Continue Listening")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedVideo) { video in
            VideoDetailSheet(
                video: video,
                onWatch: { openInYouTube(video) },
                onLogTime: { _ in }
            )
        }
    }

    @ViewBuilder
    private func row(for item: Item) -> some View {
        switch item {
        case .story(let story, let progress):
            NavigationLink(destination: StoryAudioPlaybackView(story: story)) {
                listeningRow(
                    title: story.title,
                    subtitle: StoryReaderProgressStore.resumeLabel(
                        for: progress,
                        readerKind: .audioPlayback
                    ),
                    icon: "book.fill",
                    progress: storyProgressFraction(progress)
                )
            }

        case .podcast(let episode):
            NavigationLink(destination: PodcastPlayerView(episode: episode)) {
                listeningRow(
                    title: episode.title,
                    subtitle: episode.show?.title ?? "Podcast",
                    icon: "mic.fill",
                    progress: episode.duration > 0 ? episode.playbackPosition / episode.duration : nil
                )
            }

        case .youtube(let state):
            Button {
                selectedVideo = makeVideo(from: state)
            } label: {
                listeningRow(
                    title: state.title,
                    subtitle: state.subtitle ?? "YouTube",
                    icon: "play.rectangle.fill",
                    progress: state.progressFraction
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func listeningRow(
        title: String,
        subtitle: String,
        icon: String,
        progress: Double?
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 36, height: 36)
                .foregroundStyle(.white)
                .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let progress {
                    ProgressView(value: min(1, max(0, progress)))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func storyProgressFraction(_ progress: StoryReaderProgress) -> Double? {
        guard let total = progress.total, total > 0 else { return nil }
        return Double(progress.index + 1) / Double(total)
    }

    private func makeVideo(from state: MediaPlaybackState) -> YouTubeVideo {
        YouTubeVideo(
            id: state.resourceId,
            title: state.title,
            description: "",
            thumbnailURL: state.artworkUrl ?? "https://img.youtube.com/vi/\(state.resourceId)/mqdefault.jpg",
            channelTitle: state.subtitle ?? "YouTube",
            duration: Self.iso8601Duration(seconds: state.durationSeconds),
            publishedAt: state.startedAt
        )
    }

    private func openInYouTube(_ video: YouTubeVideo) {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(video.id)") else { return }
        UIApplication.shared.open(url)
    }

    private static func iso8601Duration(seconds: Double) -> String {
        "PT\(max(0, Int(seconds.rounded())))S"
    }
}

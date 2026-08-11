import SwiftData
import SwiftUI

struct ContinueListeningView: View {
    @Environment(AuthManager.self) private var authManager
    @Query private var stories: [Story]
    @Query private var episodes: [PodcastEpisode]

    private enum Item: Identifiable {
        case story(Story, StoryReaderProgress)
        case podcast(PodcastEpisode)

        var id: String {
            switch self {
            case .story(let story, _): return "story:\(story.id)"
            case .podcast(let episode): return "podcast:\(episode.id)"
            }
        }

        var updatedAt: Date {
            switch self {
            case .story(_, let progress): return progress.updatedAt
            case .podcast(let episode): return episode.publishedDate
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

        return Array((storyItems + podcastItems).sorted { $0.updatedAt > $1.updatedAt }.prefix(8))
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to Resume", systemImage: "play.circle")
                } description: {
                    Text("Stories and podcasts appear here after you begin listening.")
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
}

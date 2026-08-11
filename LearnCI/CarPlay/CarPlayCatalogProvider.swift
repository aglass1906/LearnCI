import Foundation
import SwiftData

@MainActor
final class CarPlayCatalogProvider {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func stories(limit: Int = 40) -> [CarPlayMediaItem] {
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<Story>(
            sortBy: [SortDescriptor(\Story.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        guard let stories = try? context.fetch(descriptor) else { return [] }
        return stories.compactMap(makeStoryItem)
    }

    func podcasts(limit: Int = 40) -> [CarPlayMediaItem] {
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<PodcastEpisode>(
            sortBy: [SortDescriptor(\PodcastEpisode.publishedDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        guard let episodes = try? context.fetch(descriptor) else { return [] }
        return episodes.compactMap(makePodcastItem)
    }

    func listenNow(limit: Int = 12) -> [CarPlayMediaItem] {
        let combined = Array(stories(limit: limit)) + Array(podcasts(limit: limit))
        return Array(combined.sorted { $0.date > $1.date }.prefix(limit))
    }

    func restorableQueueItems() -> [CarPlayMediaItem] {
        let context = ModelContext(modelContainer)
        let stories = (try? context.fetch(FetchDescriptor<Story>())) ?? []
        let episodes = (try? context.fetch(FetchDescriptor<PodcastEpisode>())) ?? []

        let storyItems = stories.flatMap { story -> [CarPlayMediaItem] in
            var items: [CarPlayMediaItem] = []
            if let root = makeStoryItem(story) { items.append(root) }
            let adapter = StoryReaderDataAdapter(story: story)
            items.append(contentsOf: adapter.audioBookPlaybackClips().compactMap { clip in
                guard let url = StoryReaderDataAdapter.cachedAudioURL(
                    storyID: story.id,
                    clip: clip,
                    storyUpdatedAt: story.updatedAt
                ) ?? StoryReaderDataAdapter.remoteAudioURL(for: clip.urlString) else { return nil }
                return CarPlayMediaItem(
                    id: "story:\(story.id.uuidString):\(clip.id)",
                    kind: .story,
                    title: clip.title,
                    subtitle: story.title,
                    url: url,
                    duration: 0,
                    resumePosition: 0,
                    date: story.updatedAt ?? story.createdAt,
                    artworkURL: storyArtworkURL(for: story)
                )
            })
            return items
        }
        return storyItems + episodes.compactMap(makePodcastItem)
    }

    private func makeStoryItem(_ story: Story) -> CarPlayMediaItem? {
        guard let url = storyAudioURL(for: story) else { return nil }
        return CarPlayMediaItem(
            id: "story:\(story.id.uuidString)",
            kind: .story,
            title: story.title,
            subtitle: "\(story.languageBadgeAbbrev) · LearnCI Story",
            url: url,
            duration: 0,
            resumePosition: 0,
            date: story.updatedAt ?? story.createdAt,
            artworkURL: storyArtworkURL(for: story)
        )
    }

    private func makePodcastItem(_ episode: PodcastEpisode) -> CarPlayMediaItem? {
        guard let url = episode.playableAudioURL else { return nil }
        return CarPlayMediaItem(
            id: "podcast:\(episode.id.uuidString)",
            kind: .podcast,
            title: episode.title,
            subtitle: episode.show?.title ?? "Podcast",
            url: url,
            duration: episode.duration,
            resumePosition: episode.playbackPosition,
            date: episode.publishedDate,
            artworkURL: episode.show?.artworkUrl.flatMap(URL.init(string:))
        )
    }

    private func storyAudioURL(for story: Story) -> URL? {
        if let filename = story.audioFilename?.trimmingCharacters(in: .whitespacesAndNewlines),
           !filename.isEmpty {
            let localURL = URL.documentsDirectory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: localURL.path) {
                return localURL
            }
        }

        guard let remotePath = story.remoteAudioPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !remotePath.isEmpty else { return nil }
        return StoryReaderDataAdapter.remoteAudioURL(for: remotePath)
    }

    private func storyArtworkURL(for story: Story) -> URL? {
        if let coverArt = story.coverArt, let url = URL(string: coverArt), url.scheme != nil {
            return url
        }
        guard let path = story.remoteCoverPath, !path.isEmpty else { return nil }
        if let url = URL(string: path), url.scheme != nil { return url }
        return URL(string: "\(AppConfig.supabaseProjectURL)/storage/v1/object/public/story-covers/\(path)")
    }
}

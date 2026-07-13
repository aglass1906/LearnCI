import Foundation
import SwiftData

/// Study Mode tracking for non-story media (YouTube videos, podcast
/// episodes). Companion to `StoryPathProgressStore`, which owns the
/// story-shaped state — this store owns `MediaStudyState` rows only.
@Observable
@MainActor
final class MediaStudyStore {
    init() {}

    /// The active Study Mode state for a media item, if any.
    func studyState(
        resourceType: StudyResourceType,
        resourceId: String,
        userID: String?,
        in context: ModelContext
    ) -> MediaStudyState? {
        let typeRaw = resourceType.rawValue
        let descriptor = FetchDescriptor<MediaStudyState>(
            predicate: #Predicate {
                $0.resourceTypeRaw == typeRaw &&
                $0.resourceId == resourceId &&
                $0.userID == userID &&
                $0.isActive == true
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// All active media study states for the user, most-recently-touched
    /// first. Merged with story study states on the Learn tab's Studying list.
    func activeStudyStates(
        for userID: String?,
        in context: ModelContext,
        limit: Int = 50
    ) -> [MediaStudyState] {
        var descriptor = FetchDescriptor<MediaStudyState>(
            predicate: #Predicate {
                $0.userID == userID &&
                $0.isActive == true
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Mark a YouTube video as being studied. Idempotent: an existing active
    /// row just gets its snapshots refreshed and floats to the top.
    @discardableResult
    func markStudying(
        video: YouTubeVideo,
        userID: String?,
        in context: ModelContext
    ) -> MediaStudyState {
        if let existing = studyState(resourceType: .youtube, resourceId: video.id, userID: userID, in: context) {
            existing.title = video.title
            existing.subtitle = video.channelTitle
            existing.artworkUrl = video.thumbnailURL
            if video.durationInSeconds > 0 {
                existing.durationSeconds = Double(video.durationInSeconds)
            }
            existing.updatedAt = Date()
            existing.isSynced = false
            try? context.save()
            return existing
        }
        let state = MediaStudyState(
            userID: userID,
            resourceType: .youtube,
            resourceId: video.id,
            consumptionUrl: "https://www.youtube.com/watch?v=\(video.id)",
            title: video.title,
            subtitle: video.channelTitle,
            artworkUrl: video.thumbnailURL,
            durationSeconds: Double(max(0, video.durationInSeconds))
        )
        context.insert(state)
        try? context.save()
        return state
    }

    /// Mark a podcast episode as being studied. Idempotent, keyed by episode.
    @discardableResult
    func markStudying(
        episode: PodcastEpisode,
        userID: String?,
        in context: ModelContext
    ) -> MediaStudyState {
        if let existing = studyState(resourceType: .podcast, resourceId: episode.id.uuidString, userID: userID, in: context) {
            existing.title = episode.title
            existing.subtitle = episode.show?.title
            existing.artworkUrl = episode.show?.artworkUrl
            if episode.duration > 0 {
                existing.durationSeconds = episode.duration
            }
            existing.lastPositionSeconds = episode.playbackPosition
            existing.updatedAt = Date()
            existing.isSynced = false
            try? context.save()
            return existing
        }
        let state = MediaStudyState(
            userID: userID,
            resourceType: .podcast,
            resourceId: episode.id.uuidString,
            consumptionUrl: episode.audioUrl,
            title: episode.title,
            subtitle: episode.show?.title,
            artworkUrl: episode.show?.artworkUrl,
            durationSeconds: max(0, episode.duration),
            lastPositionSeconds: max(0, episode.playbackPosition)
        )
        context.insert(state)
        try? context.save()
        return state
    }

    /// Record the latest playback position / block progress. Only non-nil
    /// arguments are applied; a duration of 0 (unknown) never overwrites a
    /// known one.
    func updateProgress(
        _ state: MediaStudyState,
        positionSeconds: Double? = nil,
        durationSeconds: Double? = nil,
        completedBlockCount: Int? = nil,
        totalBlockCount: Int? = nil,
        in context: ModelContext
    ) {
        if let positionSeconds {
            state.lastPositionSeconds = max(0, positionSeconds)
        }
        if let durationSeconds, durationSeconds > 0 {
            state.durationSeconds = durationSeconds
        }
        if let completedBlockCount {
            state.completedBlockCount = completedBlockCount
        }
        if let totalBlockCount, totalBlockCount > 0 {
            state.totalBlockCount = totalBlockCount
        }
        state.updatedAt = Date()
        state.isSynced = false
        try? context.save()
    }

    /// User chose to un-study a media item: drop the state row only.
    /// Session records, notes, and marked words are history and stay put.
    func unstudy(_ state: MediaStudyState, in context: ModelContext) {
        context.delete(state)
        try? context.save()
    }
}

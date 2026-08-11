import Foundation
import SwiftData

@Observable
@MainActor
final class MediaPlaybackStore {
    static let minimumResumePosition: Double = 10
    static let completionFraction: Double = 0.95
    static let completionWindow: Double = 30

    func state(
        resourceType: StudyResourceType,
        resourceId: String,
        userID: String?,
        in context: ModelContext
    ) -> MediaPlaybackState? {
        let typeRaw = resourceType.rawValue
        let descriptor = FetchDescriptor<MediaPlaybackState>(
            predicate: #Predicate {
                $0.resourceTypeRaw == typeRaw &&
                $0.resourceId == resourceId &&
                $0.userID == userID
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.first
    }

    func resumePosition(
        for video: YouTubeVideo,
        userID: String?,
        in context: ModelContext
    ) -> Double {
        state(resourceType: .youtube, resourceId: video.id, userID: userID, in: context)?.lastPositionSeconds ?? 0
    }

    func saveVideoProgress(
        video: YouTubeVideo,
        userID: String?,
        positionSeconds: Double,
        durationSeconds: Double,
        in context: ModelContext
    ) {
        let position = max(0, positionSeconds)
        let duration = max(Double(video.durationInSeconds), durationSeconds)

        if Self.isComplete(position: position, duration: duration) {
            if let existing = state(resourceType: .youtube, resourceId: video.id, userID: userID, in: context) {
                context.delete(existing)
                try? context.save()
            }
            return
        }

        guard position >= Self.minimumResumePosition else { return }

        if let existing = state(resourceType: .youtube, resourceId: video.id, userID: userID, in: context) {
            existing.title = video.title
            existing.subtitle = video.channelTitle
            existing.artworkUrl = video.thumbnailURL
            existing.lastPositionSeconds = position
            if duration > 0 { existing.durationSeconds = duration }
            existing.updatedAt = Date()
        } else {
            context.insert(MediaPlaybackState(
                userID: userID,
                resourceType: .youtube,
                resourceId: video.id,
                title: video.title,
                subtitle: video.channelTitle,
                artworkUrl: video.thumbnailURL,
                durationSeconds: duration,
                lastPositionSeconds: position
            ))
        }
        try? context.save()
    }

    static func canResume(_ state: MediaPlaybackState) -> Bool {
        state.lastPositionSeconds >= minimumResumePosition &&
        !isComplete(position: state.lastPositionSeconds, duration: state.durationSeconds)
    }

    private static func isComplete(position: Double, duration: Double) -> Bool {
        guard duration > 0 else { return false }
        return position / duration >= completionFraction || duration - position <= completionWindow
    }
}

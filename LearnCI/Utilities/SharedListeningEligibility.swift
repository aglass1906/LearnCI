import Foundation

enum SharedListeningEligibility {
    static func canResumePodcast(position: Double, duration: Double, isPlayed: Bool) -> Bool {
        guard position > 1, !isPlayed else { return false }
        guard duration > 0 else { return true }
        return position < duration - 30 && position / duration <= 0.95
    }

    static func canResumeStory(_ progress: StoryReaderProgress?) -> Bool {
        progress?.isResumable == true
    }
}

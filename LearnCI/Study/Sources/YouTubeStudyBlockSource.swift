import Foundation

@MainActor
final class YouTubeStudyBlockSource: StudyBlockSource {
    let resource: StudyResourceRef
    let blocks: [StudyBlock]
    let mediaPlayer: any StudyMediaPlayer

    init(
        video: YouTubeVideo,
        cues: [YouTubeCaptionCue],
        languageCode: String?,
        focusWindowSize: StudyFocusWindowSize = .sentence,
        translationForCue: @escaping (YouTubeCaptionCue) -> String?,
        mediaPlayer: YouTubeStudyMediaPlayer
    ) {
        self.resource = StudyResourceRef.youtube(
            videoID: video.id,
            title: video.title,
            languageCode: languageCode
        )
        self.blocks = CaptionTranscriptProvider(
            cues: cues,
            translationForCue: translationForCue,
            focusWindowSize: focusWindowSize
        ).makeBlocks()
        self.mediaPlayer = mediaPlayer
    }
}

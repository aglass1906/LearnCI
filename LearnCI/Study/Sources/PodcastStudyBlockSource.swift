import Foundation

@MainActor
final class PodcastStudyBlockSource: StudyBlockSource {
    let resource: StudyResourceRef
    let blocks: [StudyBlock]
    let mediaPlayer: any StudyMediaPlayer

    init(
        episode: PodcastEpisode,
        cues: [YouTubeCaptionCue],
        languageCode: String?,
        focusWindowSize: StudyFocusWindowSize = .sentence,
        translationForCue: @escaping (YouTubeCaptionCue) -> String? = { _ in nil },
        mediaPlayer: AVPlayerStudyMediaPlayer
    ) {
        self.resource = StudyResourceRef.podcast(
            episodeId: episode.id,
            audioUrl: episode.audioUrl,
            title: episode.title,
            languageCode: languageCode
        )
        self.blocks = CaptionTranscriptProvider(
            cues: cues,
            translationForCue: translationForCue,
            focusWindowSize: focusWindowSize
        ).makeBlocks()
        self.mediaPlayer = mediaPlayer
    }

    init(
        episode: PodcastEpisode,
        words: [WordTiming],
        languageCode: String?,
        focusWindowSize: StudyFocusWindowSize = .sentence,
        translationsBySentenceRange: [String: String] = [:],
        mediaPlayer: AVPlayerStudyMediaPlayer
    ) {
        self.resource = StudyResourceRef.podcast(
            episodeId: episode.id,
            audioUrl: episode.audioUrl,
            title: episode.title,
            languageCode: languageCode
        )
        self.blocks = WhisperTranscriptProvider(
            words: words,
            translationForSentenceRange: { start, end in
                translationsBySentenceRange["\(start)-\(end)"]
            },
            focusWindowSize: focusWindowSize
        ).makeBlocks()
        self.mediaPlayer = mediaPlayer
    }

    init(
        episode: PodcastEpisode,
        cachedBlocks: [StudyBlock],
        mediaPlayer: AVPlayerStudyMediaPlayer
    ) {
        self.resource = StudyResourceRef.podcast(
            episodeId: episode.id,
            audioUrl: episode.audioUrl,
            title: episode.title,
            languageCode: episode.show?.language.rawValue
        )
        self.blocks = cachedBlocks
        self.mediaPlayer = mediaPlayer
    }
}

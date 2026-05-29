import Foundation
import Observation

enum YouTubeStudyMode: String, CaseIterable, Identifiable {
    case watch = "Watch"
    case study = "Study"

    var id: String { rawValue }
}

enum YouTubeStudyAvailability: Equatable {
    case unknown
    case available
    case unavailable(reason: String)
}

enum YouTubeStudyLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(message: String)
}

struct YouTubeStudyPlaybackState: Equatable {
    var currentTime: Double = 0
    var duration: Double = 0
    var playbackRate: Float = 1.0
    var isPlaying: Bool = false
}

struct YouTubeWordLookupSelection: Equatable {
    let word: String
    let cueIndex: Int?
    let contextText: String?
}

struct YouTubeWordLookupResult: Equatable {
    let word: String
    let translation: String
    let partOfSpeech: String?
    let contextText: String?
}

@Observable
class YouTubeStudyViewModel {
    let video: YouTubeVideo

    private(set) var mode: YouTubeStudyMode = .watch
    private(set) var availability: YouTubeStudyAvailability = .unknown
    private(set) var captionLoadState: YouTubeStudyLoadState = .idle
    private(set) var translationLoadState: YouTubeStudyLoadState = .idle
    private(set) var availableTracks: [YouTubeCaptionTrack] = []
    private(set) var activeCues: [YouTubeCaptionCue] = []
    private(set) var translatedCues: [YouTubeTranslatedCue] = []
    private(set) var playback = YouTubeStudyPlaybackState()
    private(set) var pendingSeekTime: Double?
    private(set) var pendingPlaybackRate: Float?
    private(set) var selectedLookup: YouTubeWordLookupSelection?
    private(set) var lookupResult: YouTubeWordLookupResult?

    var selectedTrackID: String?

    init(video: YouTubeVideo) {
        self.video = video
    }

    var selectedTrack: YouTubeCaptionTrack? {
        guard let selectedTrackID else { return nil }
        return availableTracks.first(where: { $0.id == selectedTrackID })
    }

    var canEnterStudyMode: Bool {
        if case .available = availability {
            return true
        }
        return !availableTracks.isEmpty || !activeCues.isEmpty
    }

    var canAttemptStudyMode: Bool {
        if case .unavailable = availability {
            return false
        }
        return true
    }

    var activeCue: YouTubeCaptionCue? {
        activeCues.last(where: { $0.contains(time: playback.currentTime, slack: 0.05) })
    }

    /// Cue to show in the study context panel. Falls back to the nearest line when playback
    /// is between cues, before the first cue, or before the player reports its current time.
    var contextCue: YouTubeCaptionCue? {
        if let activeCue {
            return activeCue
        }
        return nearestCue(to: playback.currentTime)
    }

    private func nearestCue(to time: Double) -> YouTubeCaptionCue? {
        guard !activeCues.isEmpty else { return nil }

        if let nextCue = activeCues.first(where: { $0.startTime > time + 0.05 }) {
            return nextCue
        }

        return activeCues.last(where: { $0.startTime <= time + 0.05 }) ?? activeCues.first
    }

    func setMode(_ mode: YouTubeStudyMode) {
        guard mode == .watch || canAttemptStudyMode else { return }
        self.mode = mode
    }

    func seedAvailableTracks(_ tracks: [YouTubeCaptionTrack]) {
        availableTracks = tracks.sorted(by: Self.compareTracks)

        if let selectedTrackID, !availableTracks.contains(where: { $0.id == selectedTrackID }) {
            self.selectedTrackID = nil
        }
        if self.selectedTrackID == nil {
            self.selectedTrackID = availableTracks.first?.id
        }

        if !availableTracks.isEmpty || !activeCues.isEmpty {
            availability = .available
        }
    }

    func selectTrack(id: String) {
        guard availableTracks.contains(where: { $0.id == id }) else { return }
        selectedTrackID = id
    }

    func prepareForTrackChange(id: String) {
        guard availableTracks.contains(where: { $0.id == id }) else { return }
        selectedTrackID = id
        captionLoadState = .loading
        translationLoadState = .idle
        activeCues = []
        translatedCues = []
        selectedLookup = nil
        lookupResult = nil
        availability = .available
    }

    func setCaptionLoadState(_ state: YouTubeStudyLoadState) {
        captionLoadState = state
    }

    func setTranslationLoadState(_ state: YouTubeStudyLoadState) {
        translationLoadState = state
    }

    func setStudyUnavailable(reason: String) {
        availability = .unavailable(reason: reason)
        captionLoadState = .idle
        translationLoadState = .idle
        activeCues = []
        translatedCues = []
        if mode == .study {
            mode = .watch
        }
    }

    func applyTranscript(cues: [YouTubeCaptionCue], track: YouTubeCaptionTrack) {
        if !availableTracks.contains(track) {
            seedAvailableTracks(availableTracks + [track])
        } else if selectedTrackID == nil {
            selectedTrackID = track.id
        }

        activeCues = cues.sorted { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return lhs.index < rhs.index
            }
            return lhs.startTime < rhs.startTime
        }
        captionLoadState = .loaded
        availability = activeCues.isEmpty ? .unavailable(reason: "No captions available for this video.") : .available
    }

    func applyTranslatedCues(_ translatedCues: [YouTubeTranslatedCue]) {
        self.translatedCues = translatedCues.sorted { lhs, rhs in
            if lhs.cueIndex == rhs.cueIndex {
                return lhs.id < rhs.id
            }
            return lhs.cueIndex < rhs.cueIndex
        }
        translationLoadState = self.translatedCues.isEmpty ? .idle : .loaded
    }

    func translatedCue(for cue: YouTubeCaptionCue) -> YouTubeTranslatedCue? {
        translatedCues.first(where: { translatedCue in
            translatedCue.cueID == cue.id || translatedCue.cueIndex == cue.index
        })
    }

    func hydrateFromCaches(
        captionCache: YouTubeCaptionCache?,
        translationCache: YouTubeCaptionTranslationCache? = nil
    ) {
        if let captionCache, let track = captionCache.track {
            applyTranscript(cues: captionCache.cues, track: track)
        }
        if let translationCache {
            applyTranslatedCues(translationCache.translatedCues)
        }
    }

    func updatePlayback(
        currentTime: Double? = nil,
        duration: Double? = nil,
        isPlaying: Bool? = nil,
        playbackRate: Float? = nil
    ) {
        if let currentTime {
            playback.currentTime = max(0, currentTime)
        }
        if let duration {
            playback.duration = max(0, duration)
        }
        if let isPlaying {
            playback.isPlaying = isPlaying
        }
        if let playbackRate {
            playback.playbackRate = max(0.25, min(playbackRate, 2.0))
        }
    }

    func requestSeek(to time: Double) {
        pendingSeekTime = max(0, time)
    }

    func consumePendingSeek() -> Double? {
        defer { pendingSeekTime = nil }
        return pendingSeekTime
    }

    func requestPlaybackRate(_ rate: Float) {
        let clampedRate = max(0.25, min(rate, 2.0))
        pendingPlaybackRate = clampedRate
        playback.playbackRate = clampedRate
    }

    func consumePendingPlaybackRate() -> Float? {
        defer { pendingPlaybackRate = nil }
        return pendingPlaybackRate
    }

    func selectWord(_ word: String, cueIndex: Int? = nil, contextText: String? = nil) {
        selectedLookup = YouTubeWordLookupSelection(word: word, cueIndex: cueIndex, contextText: contextText)
        lookupResult = nil
    }

    func applyLookupResult(word: String, translation: String, partOfSpeech: String?, contextText: String?) {
        lookupResult = YouTubeWordLookupResult(
            word: word,
            translation: translation,
            partOfSpeech: partOfSpeech,
            contextText: contextText
        )
    }

    func clearLookup() {
        selectedLookup = nil
        lookupResult = nil
    }

    private static func compareTracks(_ lhs: YouTubeCaptionTrack, _ rhs: YouTubeCaptionTrack) -> Bool {
        if lhs.isDefault != rhs.isDefault {
            return lhs.isDefault && !rhs.isDefault
        }
        if lhs.isAutoGenerated != rhs.isAutoGenerated {
            return !lhs.isAutoGenerated && rhs.isAutoGenerated
        }
        if lhs.languageName == rhs.languageName {
            return lhs.id < rhs.id
        }
        return lhs.languageName < rhs.languageName
    }
}

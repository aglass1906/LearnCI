import AVFoundation
import Foundation
import SwiftData

enum PodcastTranscriptSource: String, Sendable {
    case cache
    case feed
    case description
    case whisper
}

enum PodcastTranscriptError: LocalizedError {
    case invalidAudioURL
    case downloadFailed
    case exportFailed
    case transcriptionEmpty
    case fileTooLarge
    case whisperConfirmationRequired

    var errorDescription: String? {
        switch self {
        case .invalidAudioURL:
            return "This episode does not have a playable audio URL."
        case .downloadFailed:
            return "Could not download episode audio for transcription."
        case .exportFailed:
            return "Could not prepare audio for transcription."
        case .transcriptionEmpty:
            return "Whisper did not return any words for this episode."
        case .fileTooLarge:
            return "This episode could not be compressed enough for Whisper. Study mode transcribes up to the first 15 minutes."
        case .whisperConfirmationRequired:
            return "AI transcription requires your confirmation before it starts."
        }
    }
}

struct PodcastTranscriptResult: Sendable {
    let source: PodcastTranscriptSource
    let words: [WordTiming]
    let cues: [YouTubeCaptionCue]
    let cachedBlocks: [StudyBlock]?
    let cachedWords: [WordTiming]?
    let cachedCues: [YouTubeCaptionCue]?
    let coversDurationSeconds: Double?
    let skippedAdSegmentCount: Int?
}

struct PodcastTranscriptWhisperOffer: Sendable {
    let title: String
    let message: String
    let feedAttempted: Bool
    let descriptionAttempted: Bool
}

enum PodcastTranscriptAvailability: Sendable {
    case ready(PodcastTranscriptResult)
    case whisperOffer(PodcastTranscriptWhisperOffer)
}

@MainActor
final class PodcastTranscriptService {
    private let openAIService = OpenAIService()
    private static let whisperMaxBytes = 24 * 1024 * 1024
    private static let defaultTrimDuration: TimeInterval = 15 * 60

    func loadAvailableTranscript(
        episode: PodcastEpisode,
        language: Language,
        modelContext: ModelContext
    ) async throws -> PodcastTranscriptAvailability {
        guard episode.playableAudioURL != nil else {
            throw PodcastTranscriptError.invalidAudioURL
        }

        let languageCode = language.rawValue
        let contentStart = PodcastStudyContentStart.effectiveStart(for: episode)
        if let cached = fetchCache(
            episode: episode,
            languageCode: languageCode,
            modelContext: modelContext
        ),
           !cached.blocks.isEmpty {
            Logger.info("Loaded podcast transcript from cache for episode \(episode.id)", category: .general)
            return .ready(
                PodcastTranscriptResult(
                    source: .cache,
                    words: [],
                    cues: [],
                    cachedBlocks: cached.blocks,
                    cachedWords: cached.words.isEmpty ? nil : cached.words,
                    cachedCues: cached.cues.isEmpty ? nil : cached.cues,
                    coversDurationSeconds: nil,
                    skippedAdSegmentCount: nil
                )
            )
        }

        var feedFailureReason: String?
        if episode.hasFeedTranscript,
           let transcriptUrl = episode.transcriptUrl {
            do {
                return .ready(
                    try await loadPublishedTranscript(
                        urlString: transcriptUrl,
                        type: episode.transcriptType,
                        episode: episode,
                        languageCode: languageCode,
                        modelContext: modelContext,
                        source: .feed
                    )
                )
            } catch {
                feedFailureReason = error.localizedDescription
                Logger.warning(
                    "Feed transcript unavailable for episode \(episode.id): \(error.localizedDescription)",
                    category: .general
                )
            }
        }

        var descriptionFailureReason: String?
        let descriptionLinks = PodcastFeedTranscriptParser.extractTranscriptLinks(
            from: episode.episodeDescription,
            preferredLanguageCode: languageCode
        )
        if let selectedDescriptionLink = PodcastFeedTranscriptParser.selectPreferredTranscript(
            from: descriptionLinks,
            preferredLanguageCode: languageCode
        ) {
            do {
                return .ready(
                    try await loadPublishedTranscript(
                        urlString: selectedDescriptionLink.url,
                        type: selectedDescriptionLink.type,
                        episode: episode,
                        languageCode: languageCode,
                        modelContext: modelContext,
                        source: .description,
                        persistFeedMetadata: true
                    )
                )
            } catch {
                descriptionFailureReason = error.localizedDescription
                Logger.warning(
                    "Description transcript unavailable for episode \(episode.id): \(error.localizedDescription)",
                    category: .general
                )
            }
        }

        return .whisperOffer(
            makeWhisperOffer(
                for: episode,
                feedFailureReason: feedFailureReason,
                descriptionFailureReason: descriptionFailureReason,
                descriptionLinksFound: !descriptionLinks.isEmpty
            )
        )
    }

    func whisperOffer(for episode: PodcastEpisode) -> PodcastTranscriptWhisperOffer {
        makeWhisperOffer(for: episode, feedFailureReason: nil)
    }

    private func loadPublishedTranscript(
        urlString: String,
        type: String?,
        episode: PodcastEpisode,
        languageCode: String,
        modelContext: ModelContext,
        source: PodcastTranscriptSource,
        persistFeedMetadata: Bool = false
    ) async throws -> PodcastTranscriptResult {
        let cues = try await PodcastFeedTranscriptParser.fetchAndParse(
            urlString: urlString,
            type: type,
            fallbackDuration: episode.duration
        )
        let contentStart = PodcastStudyContentStart.effectiveStart(for: episode)
        let filteredCues = PodcastStudyContentStart.filterCuesAtOrAfter(cues, start: contentStart)
        guard !filteredCues.isEmpty else {
            throw PodcastFeedTranscriptError.emptyTranscript
        }

        let blocks = CaptionTranscriptProvider(
            cues: filteredCues,
            translationForCue: { _ in nil }
        ).makeBlocks()

        persistCache(
            episode: episode,
            languageCode: languageCode,
            blocks: blocks,
            cues: filteredCues,
            modelContext: modelContext
        )

        if persistFeedMetadata, episode.transcriptUrl == nil {
            episode.transcriptUrl = urlString
            episode.transcriptType = type
            episode.isSynced = false
            try? modelContext.save()
        }

        let logLabel = source == .description ? "description" : "feed"
        Logger.info(
            "Loaded podcast \(logLabel) transcript for episode \(episode.id) (\(filteredCues.count) cues)",
            category: .general
        )

        return PodcastTranscriptResult(
            source: source,
            words: [],
            cues: filteredCues,
            cachedBlocks: nil,
            cachedWords: nil,
            cachedCues: nil,
            coversDurationSeconds: nil,
            skippedAdSegmentCount: nil
        )
    }

    func generateWhisperTranscript(
        episode: PodcastEpisode,
        language: Language,
        modelContext: ModelContext
    ) async throws -> PodcastTranscriptResult {
        try await transcribeWithWhisper(
            episode: episode,
            languageCode: language.rawValue,
            modelContext: modelContext
        )
    }

    /// Loads cache/feed when possible; does **not** run Whisper without explicit user confirmation.
    func loadOrTranscribe(
        episode: PodcastEpisode,
        language: Language,
        modelContext: ModelContext
    ) async throws -> PodcastTranscriptResult {
        switch try await loadAvailableTranscript(episode: episode, language: language, modelContext: modelContext) {
        case .ready(let result):
            return result
        case .whisperOffer:
            throw PodcastTranscriptError.whisperConfirmationRequired
        }
    }

    private func makeWhisperOffer(
        for episode: PodcastEpisode,
        feedFailureReason: String?,
        descriptionFailureReason: String? = nil,
        descriptionLinksFound: Bool = false,
        missingAPIKey: Bool = false
    ) -> PodcastTranscriptWhisperOffer {
        let longEpisode = episode.duration > 15 * 60
        var detailParts: [String] = []

        if episode.hasFeedTranscript {
            if let feedFailureReason {
                detailParts.append("The published feed transcript could not be loaded (\(feedFailureReason)).")
            } else {
                detailParts.append("The published feed transcript could not be loaded.")
            }
        }

        if descriptionLinksFound {
            if let descriptionFailureReason {
                detailParts.append("A transcript link in the episode description could not be loaded (\(descriptionFailureReason)).")
            } else {
                detailParts.append("A transcript link in the episode description could not be loaded.")
            }
        } else if !episode.hasFeedTranscript {
            detailParts.append("No transcript link was found in the podcast feed or episode description.")
        }

        detailParts.append(
            "Study mode can generate one with AI (Whisper) by downloading the episode audio. This may take a minute and uses your OpenAI quota."
        )

        if PodcastStudyContentStart.effectiveStart(for: episode) > 0 {
            let stamp = PodcastStudyContentStart.formattedTimestamp(episode.studyContentStartSeconds)
            detailParts.append("Content start is marked at \(stamp). Whisper transcribes from ~20s before that so opening words are not cut off.")
        } else {
            detailParts.append(
                "To skip an intro or ad, scrub to where the episode begins and tap Mark Content Start before generating."
            )
            detailParts.append(
                "Without a manual start mark, ad segments from show-note chapters may also be removed automatically."
            )
        }

        if longEpisode {
            detailParts.append("Episodes longer than 15 minutes are transcribed from the first 15 minutes only.")
        }

        if missingAPIKey || !OpenAIAPIKeyStorage.isConfigured {
            detailParts.append("An OpenAI API key is required in Profile → AI Settings.")
        }

        return PodcastTranscriptWhisperOffer(
            title: "Generate transcript with AI?",
            message: detailParts.joined(separator: " "),
            feedAttempted: episode.hasFeedTranscript,
            descriptionAttempted: descriptionLinksFound
        )
    }

    func updateCache(
        episode: PodcastEpisode,
        languageCode: String,
        blocks: [StudyBlock],
        words: [WordTiming]? = nil,
        cues: [YouTubeCaptionCue]? = nil,
        modelContext: ModelContext
    ) {
        persistCache(
            episode: episode,
            languageCode: languageCode,
            blocks: blocks,
            words: words,
            cues: cues,
            modelContext: modelContext
        )
    }

    func clearCachedTranscripts(
        episode: PodcastEpisode,
        language: Language,
        modelContext: ModelContext
    ) {
        let consumptionUrl = episode.audioUrl
        let languageCode = language.rawValue
        let descriptor = FetchDescriptor<MediaTranscriptCache>(
            predicate: #Predicate {
                $0.consumptionUrl == consumptionUrl && $0.languageCode == languageCode
            }
        )
        guard let cachedItems = try? modelContext.fetch(descriptor), !cachedItems.isEmpty else {
            return
        }
        for item in cachedItems {
            modelContext.delete(item)
        }
        try? modelContext.save()
        Logger.info("Cleared podcast study transcript cache for episode \(episode.id)", category: .general)
    }

    /// Backward-compatible alias used by the player UI.
    func clearCachedTranscript(
        episode: PodcastEpisode,
        language: Language,
        modelContext: ModelContext
    ) {
        clearCachedTranscripts(episode: episode, language: language, modelContext: modelContext)
    }

    private func transcribeWithWhisper(
        episode: PodcastEpisode,
        languageCode: String,
        modelContext: ModelContext
    ) async throws -> PodcastTranscriptResult {
        guard let remoteURL = episode.playableAudioURL else {
            throw PodcastTranscriptError.invalidAudioURL
        }

        let prepared = try await prepareWhisperAudio(from: remoteURL, episode: episode)
        defer { try? FileManager.default.removeItem(at: prepared.localURL) }

        let contentStart = PodcastStudyContentStart.effectiveStart(for: episode)
        let exportStart = PodcastStudyContentStart.whisperExportStart(for: episode)
        let rawWords = try await openAIService.generateWordTimings(
            for: prepared.localURL,
            languageCode: languageCode
        )
        guard !rawWords.isEmpty else {
            throw PodcastTranscriptError.transcriptionEmpty
        }

        let wordsWithEpisodeTimeline = PodcastStudyContentStart.offsetWords(rawWords, by: exportStart)

        let words: [WordTiming]
        let skippedAdSegments: Int
        if contentStart > 0 {
            // Manual content start already skips intro/ads; don't also apply chapter ad ranges.
            words = wordsWithEpisodeTimeline
            skippedAdSegments = 0
        } else {
            let adIntervals = PodcastAdSegmentDetector.adIntervals(
                from: episode.episodeDescription,
                episodeDuration: max(episode.duration, wordsWithEpisodeTimeline.last?.end ?? 0)
            )
            words = PodcastAdSegmentDetector.filterWords(
                wordsWithEpisodeTimeline,
                excludingAdIntervals: adIntervals
            )
            skippedAdSegments = adIntervals.count
        }
        guard !words.isEmpty else {
            throw PodcastTranscriptError.transcriptionEmpty
        }

        let blocks = WhisperTranscriptProvider(words: words, translationForSentenceRange: { _, _ in nil }).makeBlocks()
        persistCache(
            episode: episode,
            languageCode: languageCode,
            blocks: blocks,
            words: words,
            modelContext: modelContext
        )

        let adLogSuffix = skippedAdSegments > 0
            ? " (skipped \(skippedAdSegments) ad segment(s) from show notes)"
            : (contentStart > 0
                ? " (export from \(Int(exportStart.rounded()))s, study from \(Int(contentStart.rounded()))s)"
                : "")
        Logger.info(
            "Transcribed podcast episode \(episode.id) into \(blocks.count) study blocks via Whisper\(adLogSuffix)",
            category: .general
        )

        return PodcastTranscriptResult(
            source: .whisper,
            words: words,
            cues: [],
            cachedBlocks: nil,
            cachedWords: nil,
            cachedCues: nil,
            coversDurationSeconds: prepared.coversDurationSeconds,
            skippedAdSegmentCount: skippedAdSegments > 0 ? skippedAdSegments : nil
        )
    }

    private func fetchCache(
        episode: PodcastEpisode,
        languageCode: String,
        modelContext: ModelContext
    ) -> MediaTranscriptCache? {
        let cacheKey = MediaTranscriptCache.makeCacheKey(
            consumptionUrl: episode.audioUrl,
            languageCode: languageCode,
            contentStartSeconds: PodcastStudyContentStart.effectiveStart(for: episode)
        )
        let descriptor = FetchDescriptor<MediaTranscriptCache>(
            predicate: #Predicate { $0.cacheKey == cacheKey }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func persistCache(
        episode: PodcastEpisode,
        languageCode: String,
        blocks: [StudyBlock],
        words: [WordTiming]? = nil,
        cues: [YouTubeCaptionCue]? = nil,
        modelContext: ModelContext
    ) {
        let contentStart = PodcastStudyContentStart.effectiveStart(for: episode)
        if let existing = fetchCache(episode: episode, languageCode: languageCode, modelContext: modelContext) {
            existing.replace(blocks: blocks, words: words, cues: cues)
        } else {
            modelContext.insert(
                MediaTranscriptCache(
                    consumptionUrl: episode.audioUrl,
                    languageCode: languageCode,
                    contentStartSeconds: contentStart,
                    blocks: blocks,
                    words: words,
                    cues: cues
                )
            )
        }
        try? modelContext.save()
    }

    private struct PreparedAudio {
        let localURL: URL
        let coversDurationSeconds: Double?
    }

    private func prepareWhisperAudio(from remoteURL: URL, episode: PodcastEpisode) async throws -> PreparedAudio {
        let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
        let downloadedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(remoteURL.pathExtension.isEmpty ? "mp3" : remoteURL.pathExtension)

        try FileManager.default.moveItem(at: tempURL, to: downloadedURL)

        let asset = AVURLAsset(url: downloadedURL)
        let totalSeconds = CMTimeGetSeconds(try await asset.load(.duration))
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: downloadedURL.path)[.size] as? Int) ?? 0
        let contentStart = PodcastStudyContentStart.effectiveStart(for: episode)
        let exportStart = PodcastStudyContentStart.whisperExportStart(for: episode)
        let remainingSeconds = max(0, totalSeconds - exportStart)

        guard remainingSeconds > 0 else {
            throw PodcastTranscriptError.exportFailed
        }

        let exceedsDurationLimit = remainingSeconds > Self.defaultTrimDuration
        let exceedsSizeLimit = fileSize > Self.whisperMaxBytes

        if exportStart <= 0 && !exceedsDurationLimit && !exceedsSizeLimit {
            return PreparedAudio(localURL: downloadedURL, coversDurationSeconds: nil)
        }

        let preferredDuration = min(remainingSeconds, Self.defaultTrimDuration)
        let exportResult = try await exportAudioUnderWhisperLimit(
            from: downloadedURL,
            contentStart: exportStart,
            preferredDuration: preferredDuration
        )
        try? FileManager.default.removeItem(at: downloadedURL)

        let coversDuration = trimmedDurationSeconds(
            totalSeconds: remainingSeconds,
            exportedDuration: exportResult.durationSeconds
        )
        return PreparedAudio(localURL: exportResult.url, coversDurationSeconds: coversDuration)
    }

    private struct WhisperExportResult {
        let url: URL
        let durationSeconds: TimeInterval
    }

    private func trimmedDurationSeconds(
        totalSeconds: TimeInterval,
        exportedDuration: TimeInterval
    ) -> Double? {
        guard totalSeconds > exportedDuration + 1 else { return nil }
        return exportedDuration
    }

    private func exportAudioUnderWhisperLimit(
        from sourceURL: URL,
        contentStart: TimeInterval,
        preferredDuration: TimeInterval
    ) async throws -> WhisperExportResult {
        var duration = max(preferredDuration, Self.minimumWhisperDuration)
        let step = Self.whisperDurationStep

        while duration >= Self.minimumWhisperDuration {
            let exportedURL = try await exportTrimmedAudio(
                from: sourceURL,
                contentStart: contentStart,
                maxDuration: duration
            )
            let exportedSize = (try? FileManager.default.attributesOfItem(atPath: exportedURL.path)[.size] as? Int) ?? 0

            if exportedSize <= Self.whisperMaxBytes {
                return WhisperExportResult(url: exportedURL, durationSeconds: duration)
            }

            try? FileManager.default.removeItem(at: exportedURL)
            duration -= step
        }

        throw PodcastTranscriptError.fileTooLarge
    }

    private static let minimumWhisperDuration: TimeInterval = 5 * 60
    private static let whisperDurationStep: TimeInterval = 2 * 60

    private func exportTrimmedAudio(
        from sourceURL: URL,
        contentStart: TimeInterval,
        maxDuration: TimeInterval
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        let availableSeconds = max(0, totalSeconds - contentStart)
        return try await exportAudioRange(
            from: asset,
            start: contentStart,
            duration: min(maxDuration, availableSeconds)
        )
    }

    private func exportAudioRange(
        from asset: AVURLAsset,
        start: TimeInterval,
        duration: TimeInterval
    ) async throws -> URL {
        guard duration > 0 else {
            throw PodcastTranscriptError.exportFailed
        }

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw PodcastTranscriptError.exportFailed
        }

        guard let outputFileType = preferredExportFileType(for: exportSession) else {
            throw PodcastTranscriptError.exportFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension(for: outputFileType))

        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )

        await exportSession.export()

        guard exportSession.status == .completed else {
            throw PodcastTranscriptError.exportFailed
        }

        return outputURL
    }

    private func preferredExportFileType(for session: AVAssetExportSession) -> AVFileType? {
        let supported = session.supportedFileTypes
        if supported.contains(.m4a) { return .m4a }
        if supported.contains(.mp4) { return .mp4 }
        return supported.first
    }

    private func fileExtension(for fileType: AVFileType) -> String {
        switch fileType {
        case .m4a: return "m4a"
        case .mp4: return "mp4"
        case .mov: return "mov"
        case .wav: return "wav"
        case .mp3: return "mp3"
        default:
            let raw = fileType.rawValue.lowercased()
            if raw.contains("m4a") { return "m4a" }
            if raw.contains("mp4") { return "mp4" }
            return "m4a"
        }
    }
}

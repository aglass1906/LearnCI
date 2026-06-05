import AVFoundation
import Foundation
import SwiftData

enum PodcastTranscriptSource: String, Sendable {
    case cache
    case feed
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
            return "Episode audio is too large to transcribe in one request."
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
}

struct PodcastTranscriptWhisperOffer: Sendable {
    let title: String
    let message: String
    let feedAttempted: Bool
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
        if let cached = fetchCache(consumptionUrl: episode.audioUrl, languageCode: languageCode, modelContext: modelContext),
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
                    coversDurationSeconds: nil
                )
            )
        }

        var feedFailureReason: String?
        if episode.hasFeedTranscript,
           let transcriptUrl = episode.transcriptUrl {
            do {
                let cues = try await PodcastFeedTranscriptParser.fetchAndParse(
                    urlString: transcriptUrl,
                    type: episode.transcriptType,
                    fallbackDuration: episode.duration
                )
                guard !cues.isEmpty else {
                    throw PodcastFeedTranscriptError.emptyTranscript
                }

                let blocks = CaptionTranscriptProvider(
                    cues: cues,
                    translationForCue: { _ in nil }
                ).makeBlocks()

                persistCache(
                    consumptionUrl: episode.audioUrl,
                    languageCode: languageCode,
                    blocks: blocks,
                    cues: cues,
                    modelContext: modelContext
                )

                Logger.info(
                    "Loaded podcast feed transcript for episode \(episode.id) (\(cues.count) cues)",
                    category: .general
                )

                return .ready(
                    PodcastTranscriptResult(
                        source: .feed,
                        words: [],
                        cues: cues,
                        cachedBlocks: nil,
                        cachedWords: nil,
                        cachedCues: nil,
                        coversDurationSeconds: nil
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

        return .whisperOffer(
            makeWhisperOffer(for: episode, feedFailureReason: feedFailureReason)
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
        missingAPIKey: Bool = false
    ) -> PodcastTranscriptWhisperOffer {
        let longEpisode = episode.duration > 15 * 60
        var detailParts: [String] = []

        if episode.hasFeedTranscript {
            if let feedFailureReason {
                detailParts.append("The published transcript could not be loaded (\(feedFailureReason)).")
            } else {
                detailParts.append("The published transcript could not be loaded.")
            }
        } else {
            detailParts.append("This episode does not include a transcript link in the podcast feed.")
        }

        detailParts.append(
            "Study mode can generate one with AI (Whisper) by downloading the episode audio. This may take a minute and uses your OpenAI quota."
        )

        if longEpisode {
            detailParts.append("Episodes longer than 15 minutes are transcribed from the first 15 minutes only.")
        }

        if missingAPIKey || !OpenAIAPIKeyStorage.isConfigured {
            detailParts.append("An OpenAI API key is required in Profile → AI Settings.")
        }

        return PodcastTranscriptWhisperOffer(
            title: "Generate transcript with AI?",
            message: detailParts.joined(separator: " "),
            feedAttempted: episode.hasFeedTranscript
        )
    }

    func updateCache(
        consumptionUrl: String,
        languageCode: String,
        blocks: [StudyBlock],
        words: [WordTiming]? = nil,
        cues: [YouTubeCaptionCue]? = nil,
        modelContext: ModelContext
    ) {
        persistCache(
            consumptionUrl: consumptionUrl,
            languageCode: languageCode,
            blocks: blocks,
            words: words,
            cues: cues,
            modelContext: modelContext
        )
    }

    private func transcribeWithWhisper(
        episode: PodcastEpisode,
        languageCode: String,
        modelContext: ModelContext
    ) async throws -> PodcastTranscriptResult {
        guard let remoteURL = episode.playableAudioURL else {
            throw PodcastTranscriptError.invalidAudioURL
        }

        let prepared = try await prepareWhisperAudio(from: remoteURL)
        defer { try? FileManager.default.removeItem(at: prepared.localURL) }

        let words = try await openAIService.generateWordTimings(
            for: prepared.localURL,
            languageCode: languageCode
        )
        guard !words.isEmpty else {
            throw PodcastTranscriptError.transcriptionEmpty
        }

        let blocks = WhisperTranscriptProvider(words: words, translationForSentenceRange: { _, _ in nil }).makeBlocks()
        persistCache(
            consumptionUrl: episode.audioUrl,
            languageCode: languageCode,
            blocks: blocks,
            words: words,
            modelContext: modelContext
        )

        Logger.info(
            "Transcribed podcast episode \(episode.id) into \(blocks.count) study blocks via Whisper",
            category: .general
        )

        return PodcastTranscriptResult(
            source: .whisper,
            words: words,
            cues: [],
            cachedBlocks: nil,
            cachedWords: nil,
            cachedCues: nil,
            coversDurationSeconds: prepared.coversDurationSeconds
        )
    }

    private func fetchCache(
        consumptionUrl: String,
        languageCode: String,
        modelContext: ModelContext
    ) -> MediaTranscriptCache? {
        let cacheKey = MediaTranscriptCache.makeCacheKey(consumptionUrl: consumptionUrl, languageCode: languageCode)
        let descriptor = FetchDescriptor<MediaTranscriptCache>(
            predicate: #Predicate { $0.cacheKey == cacheKey }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func persistCache(
        consumptionUrl: String,
        languageCode: String,
        blocks: [StudyBlock],
        words: [WordTiming]? = nil,
        cues: [YouTubeCaptionCue]? = nil,
        modelContext: ModelContext
    ) {
        if let existing = fetchCache(consumptionUrl: consumptionUrl, languageCode: languageCode, modelContext: modelContext) {
            existing.replace(blocks: blocks, words: words, cues: cues)
        } else {
            modelContext.insert(
                MediaTranscriptCache(
                    consumptionUrl: consumptionUrl,
                    languageCode: languageCode,
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

    private func prepareWhisperAudio(from remoteURL: URL) async throws -> PreparedAudio {
        let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
        let downloadedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(remoteURL.pathExtension.isEmpty ? "mp3" : remoteURL.pathExtension)

        try FileManager.default.moveItem(at: tempURL, to: downloadedURL)

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: downloadedURL.path)[.size] as? Int) ?? 0
        if fileSize <= Self.whisperMaxBytes {
            return PreparedAudio(localURL: downloadedURL, coversDurationSeconds: nil)
        }

        let trimmedURL = try await exportTrimmedAudio(from: downloadedURL, maxDuration: Self.defaultTrimDuration)
        try? FileManager.default.removeItem(at: downloadedURL)
        return PreparedAudio(localURL: trimmedURL, coversDurationSeconds: Self.defaultTrimDuration)
    }

    private func exportTrimmedAudio(from sourceURL: URL, maxDuration: TimeInterval) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        let exportSeconds = min(maxDuration, totalSeconds)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetMediumQuality
        ) else {
            throw PodcastTranscriptError.exportFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: exportSeconds, preferredTimescale: 600)
        )

        await exportSession.export()

        guard exportSession.status == .completed else {
            throw PodcastTranscriptError.exportFailed
        }

        let exportedSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
        guard exportedSize <= Self.whisperMaxBytes else {
            throw PodcastTranscriptError.fileTooLarge
        }

        return outputURL
    }
}

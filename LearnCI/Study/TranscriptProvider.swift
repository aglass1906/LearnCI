import Foundation

protocol TranscriptProvider {
    func makeBlocks() -> [StudyBlock]
}

/// Maps YouTube caption cues (and optional translations) to study blocks.
struct CaptionTranscriptProvider: TranscriptProvider {
    let cues: [YouTubeCaptionCue]
    let translationForCue: (YouTubeCaptionCue) -> String?
    var focusWindowSize: StudyFocusWindowSize = .sentence

    func makeBlocks() -> [StudyBlock] {
        guard !cues.isEmpty else { return [] }

        let chunkSize = focusWindowSize.captionCount
        var blocks: [StudyBlock] = []
        var blockIndex = 0
        var startCueIndex = 0

        while startCueIndex < cues.count {
            let endCueIndex = min(startCueIndex + chunkSize - 1, cues.count - 1)
            let chunkCues = Array(cues[startCueIndex...endCueIndex])

            let targetText = chunkCues
                .map(\.normalizedText)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            let nativeLines = chunkCues.compactMap { cue -> String? in
                guard let line = translationForCue(cue)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !line.isEmpty else { return nil }
                return line
            }
            let nativeText = nativeLines.isEmpty ? nil : nativeLines.joined(separator: "\n")

            guard let firstCue = chunkCues.first else { break }

            let mediaStart = firstCue.startTime
            // End at the next cue's start so loop/playback does not bleed into unshown lines.
            // Caption endTime is often padded (≥1.5s) and runs past spoken words.
            let mediaEnd = Self.playbackEndTime(
                forChunkFrom: startCueIndex,
                through: endCueIndex,
                in: cues,
                minimumDuration: 0.15
            )

            blocks.append(
                StudyBlock(
                    id: "study-block-\(blockIndex)",
                    index: blockIndex,
                    targetText: targetText,
                    nativeText: nativeText,
                    mediaStart: mediaStart,
                    mediaEnd: mediaEnd,
                    cueStartIndex: startCueIndex,
                    cueEndIndex: endCueIndex
                )
            )

            blockIndex += 1
            startCueIndex += chunkSize
        }

        return blocks
    }

    static func blockIndex(forCueIndex cueIndex: Int, windowSize: StudyFocusWindowSize) -> Int {
        max(0, cueIndex / windowSize.captionCount)
    }

    /// Exclusive end boundary: next caption start when available, not padded cue endTime.
    static func playbackEndTime(
        forChunkFrom startCueIndex: Int,
        through endCueIndex: Int,
        in cues: [YouTubeCaptionCue],
        minimumDuration: Double
    ) -> Double {
        guard cues.indices.contains(startCueIndex),
              cues.indices.contains(endCueIndex) else { return 0 }

        let mediaStart = cues[startCueIndex].startTime
        if cues.indices.contains(endCueIndex + 1) {
            return max(mediaStart + minimumDuration, cues[endCueIndex + 1].startTime)
        }
        return max(mediaStart + minimumDuration, cues[endCueIndex].endTime)
    }
}

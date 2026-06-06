import Foundation

/// Groups Whisper word timings into study blocks via display lines and focus windows.
struct WhisperTranscriptProvider: TranscriptProvider {
    let words: [WordTiming]
    let translationForSentenceRange: (Int, Int) -> String?
    var focusWindowSize: StudyFocusWindowSize = .sentence

    func makeBlocks() -> [StudyBlock] {
        let lines = Self.groupIntoLines(words)
        guard !lines.isEmpty else { return [] }

        let chunkSize = focusWindowSize.captionCount
        var blocks: [StudyBlock] = []
        var blockIndex = 0
        var startLineIndex = 0

        while startLineIndex < lines.count {
            let endLineIndex = min(startLineIndex + chunkSize - 1, lines.count - 1)
            let chunk = Array(lines[startLineIndex...endLineIndex])

            let targetText = StudySubtitleText.mergedLines(
                chunk.map(\.text)
            ) ?? ""

            let nativeText = translationForSentenceRange(startLineIndex, endLineIndex)
                .flatMap { StudySubtitleText.normalizeMultiline($0) }

            let mediaStart = chunk.first?.start ?? 0
            let mediaEnd = Self.playbackEndTime(
                forLinesFrom: startLineIndex,
                through: endLineIndex,
                in: lines,
                minimumDuration: 0.25
            )

            blocks.append(
                StudyBlock(
                    id: "podcast-block-\(blockIndex)",
                    index: blockIndex,
                    targetText: targetText,
                    nativeText: nativeText,
                    mediaStart: mediaStart,
                    mediaEnd: mediaEnd,
                    cueStartIndex: startLineIndex,
                    cueEndIndex: endLineIndex
                )
            )

            blockIndex += 1
            startLineIndex += chunkSize
        }

        return blocks
    }

    struct SentenceSpan: Sendable {
        let text: String
        let start: Double
        let end: Double
        let wordStartIndex: Int
        let wordEndIndex: Int
    }

    struct LineSpan: Sendable {
        let text: String
        let start: Double
        let end: Double
        let wordStartIndex: Int
        let wordEndIndex: Int
    }

    static func groupIntoSentences(_ words: [WordTiming]) -> [SentenceSpan] {
        guard !words.isEmpty else { return [] }

        var sentences: [SentenceSpan] = []
        var buffer: [WordTiming] = []
        var bufferStartIndex = 0

        func flushBuffer(endIndex: Int) {
            guard !buffer.isEmpty else { return }
            let text = buffer.map(\.word).joined(separator: " ")
            let normalized = StudySubtitleText.normalizeLine(text)
            guard !normalized.isEmpty else {
                buffer.removeAll(keepingCapacity: true)
                return
            }
            sentences.append(
                SentenceSpan(
                    text: normalized,
                    start: buffer.first?.start ?? 0,
                    end: buffer.last?.end ?? buffer.first?.start ?? 0,
                    wordStartIndex: bufferStartIndex,
                    wordEndIndex: endIndex
                )
            )
            buffer.removeAll(keepingCapacity: true)
        }

        for (index, word) in words.enumerated() {
            if buffer.isEmpty {
                bufferStartIndex = index
            }
            buffer.append(word)

            if isSentenceEnd(word.word) || index == words.count - 1 {
                flushBuffer(endIndex: index)
            }
        }

        return sentences
    }

    static func groupIntoLines(_ words: [WordTiming], maxWordsPerLine: Int = 8) -> [LineSpan] {
        guard !words.isEmpty else { return [] }

        var lines: [LineSpan] = []

        for sentence in groupIntoSentences(words) {
            guard words.indices.contains(sentence.wordStartIndex),
                  words.indices.contains(sentence.wordEndIndex) else { continue }

            var batch: [WordTiming] = []
            var batchStartIndex = sentence.wordStartIndex

            func flushBatch(through wordIndex: Int) {
                guard !batch.isEmpty else { return }
                let text = StudySubtitleText.normalizeLine(batch.map(\.word).joined(separator: " "))
                guard !text.isEmpty else {
                    batch.removeAll(keepingCapacity: true)
                    return
                }
                lines.append(
                    LineSpan(
                        text: text,
                        start: batch.first?.start ?? 0,
                        end: batch.last?.end ?? batch.first?.start ?? 0,
                        wordStartIndex: batchStartIndex,
                        wordEndIndex: wordIndex
                    )
                )
                batch.removeAll(keepingCapacity: true)
            }

            for wordIndex in sentence.wordStartIndex...sentence.wordEndIndex {
                if batch.isEmpty {
                    batchStartIndex = wordIndex
                }
                batch.append(words[wordIndex])

                if batch.count >= maxWordsPerLine {
                    flushBatch(through: wordIndex)
                }
            }

            if !batch.isEmpty {
                flushBatch(through: sentence.wordEndIndex)
            }
        }

        return lines
    }

    static func isSentenceEnd(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        return ".!?…".contains(last)
    }

    static func playbackEndTime(
        forLinesFrom startLineIndex: Int,
        through endLineIndex: Int,
        in lines: [LineSpan],
        minimumDuration: Double
    ) -> Double {
        guard lines.indices.contains(startLineIndex),
              lines.indices.contains(endLineIndex) else { return 0 }

        let mediaStart = lines[startLineIndex].start
        if lines.indices.contains(endLineIndex + 1) {
            return max(mediaStart + minimumDuration, lines[endLineIndex + 1].start)
        }
        return max(mediaStart + minimumDuration, lines[endLineIndex].end)
    }

    static func playbackEndTime(
        forSentencesFrom startSentenceIndex: Int,
        through endSentenceIndex: Int,
        in sentences: [SentenceSpan],
        minimumDuration: Double
    ) -> Double {
        guard sentences.indices.contains(startSentenceIndex),
              sentences.indices.contains(endSentenceIndex) else { return 0 }

        let mediaStart = sentences[startSentenceIndex].start
        if sentences.indices.contains(endSentenceIndex + 1) {
            return max(mediaStart + minimumDuration, sentences[endSentenceIndex + 1].start)
        }
        return max(mediaStart + minimumDuration, sentences[endSentenceIndex].end)
    }
}

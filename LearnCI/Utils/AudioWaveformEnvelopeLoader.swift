import AVFoundation
import Foundation

enum AudioWaveformEnvelopeLoader {
    private static var cache: [String: [Float]] = [:]
    private static let cacheLock = NSLock()

    static func load(
        url: URL,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval,
        binCount: Int = 220
    ) async -> [Float] {
        let safeStart = max(0, startSeconds)
        let safeEnd = max(safeStart + 1, endSeconds)
        let key = "\(url.absoluteString)|\(Int(safeStart))|\(Int(safeEnd))|\(binCount)"

        cacheLock.lock()
        if let cached = cache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let envelope = await sampleEnvelope(
            url: url,
            startSeconds: safeStart,
            endSeconds: safeEnd,
            binCount: binCount
        )

        cacheLock.lock()
        cache[key] = envelope
        cacheLock.unlock()

        return envelope
    }

    private static func sampleEnvelope(
        url: URL,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval,
        binCount: Int
    ) async -> [Float] {
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            return placeholderEnvelope(binCount: binCount)
        }

        guard let track = tracks.first else {
            return placeholderEnvelope(binCount: binCount)
        }

        guard let reader = try? AVAssetReader(asset: asset) else {
            return placeholderEnvelope(binCount: binCount)
        }

        let timeRange = CMTimeRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            end: CMTime(seconds: endSeconds, preferredTimescale: 600)
        )
        reader.timeRange = timeRange

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            return placeholderEnvelope(binCount: binCount)
        }
        reader.add(output)
        guard reader.startReading() else {
            return placeholderEnvelope(binCount: binCount)
        }

        let windowDuration = endSeconds - startSeconds
        var peaks = Array(repeating: Float(0), count: binCount)
        var sampleCount = 0

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer(),
                  let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }

            let length = CMBlockBufferGetDataLength(blockBuffer)
            guard length >= 2 else { continue }

            var data = Data(count: length)
            let copyStatus = data.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return kCMBlockBufferUnallocatedBlockErr }
                return CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength: length,
                    destination: baseAddress
                )
            }
            guard copyStatus == kCMBlockBufferNoErr else { continue }

            let presentation = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let relativeSeconds = CMTimeGetSeconds(presentation) - startSeconds
            let binIndex = Int((relativeSeconds / windowDuration) * Double(binCount))
            guard binIndex >= 0, binIndex < binCount else { continue }

            var peak: Float = 0
            data.withUnsafeBytes { rawBuffer in
                let samples = rawBuffer.bindMemory(to: Int16.self)
                let stride = max(1, samples.count / 512)
                var index = 0
                while index < samples.count {
                    let normalized = Float(abs(samples[index])) / Float(Int16.max)
                    peak = max(peak, normalized)
                    index += stride
                }
            }

            peaks[binIndex] = max(peaks[binIndex], peak)
            sampleCount += 1

            if sampleCount.isMultiple(of: 64) {
                await Task.yield()
            }
        }

        if peaks.allSatisfy({ $0 <= 0.001 }) {
            return placeholderEnvelope(binCount: binCount)
        }

        if let maxPeak = peaks.max(), maxPeak > 0 {
            peaks = peaks.map { min(1, $0 / maxPeak) }
        }

        return peaks
    }

    private static func placeholderEnvelope(binCount: Int) -> [Float] {
        (0..<binCount).map { index in
            let phase = Float(index) / Float(max(1, binCount - 1))
            return 0.15 + 0.1 * sin(phase * .pi * 6)
        }
    }
}

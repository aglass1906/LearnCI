import SwiftUI

struct PodcastStudyTranscriptPanel: View {
    let blocks: [StudyBlock]
    let activeBlockIndex: Int?
    var expanded: Bool = false
    let onSeek: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !expanded {
                Label("Transcript", systemImage: "list.bullet.rectangle")
                    .font(.subheadline.weight(.semibold))
            }

            if blocks.isEmpty {
                Text("No transcript blocks yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(blocks) { block in
                            transcriptRow(block)
                        }
                    }
                }
                .frame(maxHeight: expanded ? .infinity : 220)
            }
        }
    }

    private func transcriptRow(_ block: StudyBlock) -> some View {
        let isActive = block.index == activeBlockIndex

        return Button {
            onSeek(block.mediaStart)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(formatTimestamp(block.mediaStart))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isActive {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }

                Text(block.targetText)
                    .font(.subheadline)
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .multilineTextAlignment(.leading)

                if let native = block.nativeText, !native.isEmpty {
                    Text(native)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? Color.blue.opacity(0.12) : Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let minutes = total / 60
        let remainder = total % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}

/// A few transcript lines around the playhead to help audio/script alignment.
struct PodcastTimingTranscriptSnippet: View {
    let blocks: [StudyBlock]
    let playbackTime: TimeInterval
    let onSeek: (Double) -> Void

    private var anchorIndex: Int {
        guard !blocks.isEmpty else { return 0 }
        if let containing = blocks.firstIndex(where: { $0.contains(time: playbackTime) }) {
            return containing
        }
        return blocks.enumerated().min(by: {
            abs($0.element.mediaStart - playbackTime) < abs($1.element.mediaStart - playbackTime)
        })?.offset ?? 0
    }

    private var visibleBlocks: [StudyBlock] {
        guard !blocks.isEmpty else { return [] }
        let lower = max(0, anchorIndex - 1)
        let upper = min(blocks.count - 1, anchorIndex + 2)
        return Array(blocks[lower...upper])
    }

    private var activeBlockID: String? {
        blocks.first(where: { $0.contains(time: playbackTime) })?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Lines at playhead", systemImage: "text.quote")
                .font(.caption.weight(.semibold))

            Text("Play until you recognize a line, then align the teal blocks to that moment on the waveform.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if visibleBlocks.isEmpty {
                Text("No transcript lines in this range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleBlocks) { block in
                        snippetRow(block, isActive: block.id == activeBlockID)
                    }
                }
            }
        }
    }

    private func snippetRow(_ block: StudyBlock, isActive: Bool) -> some View {
        Button {
            onSeek(block.mediaStart)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(PodcastStudyContentStart.formattedTimestamp(block.mediaStart))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(isActive ? Color.red : .secondary)
                    Spacer()
                    if isActive {
                        Label("Now playing", systemImage: "speaker.wave.2.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                }

                Text(block.targetText)
                    .font(.subheadline)
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isActive
                    ? Color.red.opacity(0.1)
                    : Color(UIColor.tertiarySystemGroupedBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isActive ? Color.red.opacity(0.35) : Color.clear, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

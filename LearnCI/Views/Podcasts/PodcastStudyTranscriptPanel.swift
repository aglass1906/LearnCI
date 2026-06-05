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

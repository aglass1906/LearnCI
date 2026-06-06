import SwiftUI

struct StudyTransportBar: View {
    let canGoPrevious: Bool
    let canGoNext: Bool
    let isLooping: Bool
    let isBlockPlaying: Bool
    let isBlockPlaybackLocked: Bool
    let onPrevious: () -> Void
    let onPlayStop: () -> Void
    let onToggleLoop: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                transportButton("Prev", systemImage: "chevron.left", disabled: !canGoPrevious, action: onPrevious)
                transportButton(
                    isBlockPlaying ? "Stop" : "Play",
                    systemImage: isBlockPlaying ? "stop.fill" : "play.fill",
                    prominent: true,
                    action: onPlayStop
                )
                transportButton(
                    "Loop",
                    systemImage: isLooping ? "repeat.1.circle.fill" : "repeat.1.circle",
                    selected: isLooping,
                    action: onToggleLoop
                )
                transportButton("Next", systemImage: "chevron.right", disabled: !canGoNext, action: onNext)
            }

            if isBlockPlaybackLocked {
                Label("Native speed locked during block playback", systemImage: "1.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func transportButton(
        _ title: String,
        systemImage: String,
        disabled: Bool = false,
        prominent: Bool = false,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(prominent ? .blue : (selected ? .blue : .primary))
        .disabled(disabled)
    }
}

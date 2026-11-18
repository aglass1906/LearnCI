import SwiftUI

/// Study-block transport (previous block · play/stop block · loop · next block).
/// Styled to match the shared player controls but kept separate: it steps through
/// transcript blocks, not the whole episode.
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
            HStack(spacing: 0) {
                sideButton("backward.end.fill", label: "Previous block", enabled: canGoPrevious, action: onPrevious)
                playStopButton
                sideButton(
                    isLooping ? "repeat.1.circle.fill" : "repeat.1.circle",
                    label: isLooping ? "Stop looping block" : "Loop block",
                    enabled: true,
                    highlighted: isLooping,
                    action: onToggleLoop
                )
                sideButton("forward.end.fill", label: "Next block", enabled: canGoNext, action: onNext)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: isBlockPlaying)

            if isBlockPlaybackLocked {
                Label("Native speed locked during block playback", systemImage: "1.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var playStopButton: some View {
        Button(action: onPlayStop) {
            Image(systemName: isBlockPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 60, height: 60)
                .background(PlayerTheme.accent, in: Circle())
                .shadow(color: PlayerTheme.accent.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(PlayerPressStyle())
        .frame(maxWidth: .infinity)
        .accessibilityLabel(isBlockPlaying ? "Stop block" : "Play block")
    }

    private func sideButton(
        _ symbol: String,
        label: String,
        enabled: Bool,
        highlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(highlighted ? PlayerTheme.accent : Color.primary)
                .frame(minWidth: PlayerTheme.minTapTarget, minHeight: PlayerTheme.minTapTarget)
        }
        .buttonStyle(PlayerPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(label)
    }
}

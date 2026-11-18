import SwiftUI

/// Previous track · back 15 · play/pause · forward 15 · next track.
/// Identical on every player surface; unavailable buttons are dimmed, never removed.
struct PlayerTransportControls: View {
    let isPlaying: Bool
    var isBuffering: Bool = false
    var canGoPrevious: Bool = true
    var canGoNext: Bool = true
    var canPlayPause: Bool = true
    var skipInterval: Int = 15

    let onPrevious: () -> Void
    let onSkipBackward: () -> Void
    let onPlayPause: () -> Void
    let onSkipForward: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            sideButton("backward.end.fill", label: "Previous chapter", enabled: canGoPrevious, action: onPrevious)
            sideButton("gobackward.\(skipInterval)", label: "Back \(skipInterval) seconds", enabled: true, large: true, action: onSkipBackward)
            playButton
            sideButton("goforward.\(skipInterval)", label: "Forward \(skipInterval) seconds", enabled: true, large: true, action: onSkipForward)
            sideButton("forward.end.fill", label: "Next chapter", enabled: canGoNext, action: onNext)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isPlaying)
    }

    private var playButton: some View {
        Button(action: onPlayPause) {
            ZStack {
                Circle()
                    .fill(PlayerTheme.accent)
                    .shadow(color: PlayerTheme.accent.opacity(0.45), radius: 14, y: 6)
                if isBuffering {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .offset(x: isPlaying ? 0 : 2)
                }
            }
            .frame(width: PlayerTheme.playButtonDiameter, height: PlayerTheme.playButtonDiameter)
        }
        .buttonStyle(PlayerPressStyle())
        .disabled(!canPlayPause)
        .opacity(canPlayPause ? 1 : 0.45)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }

    private func sideButton(
        _ symbol: String,
        label: String,
        enabled: Bool,
        large: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: large ? PlayerTheme.skipIconSize : 24, weight: .semibold))
                .foregroundStyle(PlayerTheme.iconTint)
                .frame(minWidth: PlayerTheme.minTapTarget, minHeight: PlayerTheme.minTapTarget)
        }
        .buttonStyle(PlayerPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(label)
    }
}

struct PlayerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

import SwiftUI
import AVKit

/// Utility icons in a fixed order: speed, sleep timer, AirPlay, CarPlay, chapters, transcript, more.
/// Pass nil for any action that doesn't apply; the rest keep their relative order.
struct PlayerSecondaryRow: View {
    @Binding var rate: Float
    var rates: [Float] = [0.75, 1.0, 1.25, 1.5]
    var showsSpeed: Bool = true
    var sleepTimerActive: Bool = false
    var onSleepTimer: (() -> Void)? = nil
    var showsAirPlay: Bool = true
    var onCarPlay: (() -> Void)? = nil
    var onChapters: (() -> Void)? = nil
    var onTranscript: (() -> Void)? = nil
    var onMore: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            if showsSpeed {
                Menu {
                    ForEach(rates, id: \.self) { value in
                        Button(PlayerTimeFormat.rateLabel(value)) { rate = value }
                    }
                } label: {
                    Text(PlayerTimeFormat.rateLabel(rate))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(PlayerTheme.iconTint)
                        .frame(minWidth: PlayerTheme.minTapTarget, minHeight: PlayerTheme.minTapTarget)
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Playback speed \(PlayerTimeFormat.rateLabel(rate))")
            }
            if let onSleepTimer {
                iconButton("moon.zzz.fill", label: "Sleep timer", highlighted: sleepTimerActive, action: onSleepTimer)
            }
            if showsAirPlay {
                PlayerAirPlayButton()
                    .frame(width: PlayerTheme.minTapTarget, height: PlayerTheme.minTapTarget)
                    .frame(maxWidth: .infinity)
            }
            if let onCarPlay {
                iconButton("car.fill", label: "CarPlay", action: onCarPlay)
            }
            if let onChapters {
                iconButton("list.bullet", label: "Chapters", action: onChapters)
            }
            if let onTranscript {
                iconButton("text.quote", label: "Transcript", action: onTranscript)
            }
            if let onMore {
                iconButton("ellipsis", label: "More", action: onMore)
            }
        }
    }

    private func iconButton(_ symbol: String, label: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(highlighted ? PlayerTheme.accent : PlayerTheme.iconTint)
                .frame(minWidth: PlayerTheme.minTapTarget, minHeight: PlayerTheme.minTapTarget)
        }
        .buttonStyle(PlayerPressStyle())
        .frame(maxWidth: .infinity)
        .accessibilityLabel(label)
    }
}

struct PlayerAirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor(PlayerTheme.accent)
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

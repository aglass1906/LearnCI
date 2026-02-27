import SwiftUI
import AVKit

// MARK: - VideoGeneratorSheet
// Presented from StorySessionView when the user taps "Generate Scene Video".
// Two states:
//   1. No Google API key  → explanation + link to AI Settings
//   2. Key exists         → style picker + cost warning + confirm button

struct VideoGeneratorSheet: View {
    let story: Story
    var onGenerate: (VideoStyle) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedStyle: VideoStyle = .photorealistic
    @State private var hasKey: Bool = false

    private let veoService = VeoService()

    var body: some View {
        NavigationStack {
            Group {
                if hasKey {
                    generatorForm
                } else {
                    noKeyView
                }
            }
            .navigationTitle("Scene Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .task {
            hasKey = await veoService.hasKey()
        }
    }

    // MARK: - Style Picker + Cost Confirmation

    private var generatorForm: some View {
        Form {
            Section {
                ForEach(VideoStyle.allCases) { style in
                    Button {
                        selectedStyle = style
                    } label: {
                        HStack {
                            Image(systemName: style.icon)
                                .frame(width: 28)
                                .foregroundStyle(.tint)
                            Text(style.rawValue)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedStyle == style {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } header: {
                Text("Visual Style")
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Estimated Cost: \(VideoStyle.estimatedCostRange)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Charged at \(VideoStyle.ratePerSecond) to your Google Cloud account. Generation takes 2–6 minutes. Keep the app open.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Cost Notice")
            }

            Section {
                Button {
                    dismiss()
                    onGenerate(selectedStyle)
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "video.badge.plus")
                        Text("Generate Video")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .tint(.blue)
            }
        }
    }

    // MARK: - No Key Explanation

    private var noKeyView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "key.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Google API Key Required")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Video generation uses Google's Veo 3 model, which always requires a Google API key — even if you use OpenAI for the prompt step.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 10) {
                Label("Approx. \(VideoStyle.estimatedCostRange) per 8-second clip", systemImage: "dollarsign.circle")
                Label("Charged to your Google Cloud account", systemImage: "cloud")
                Label("Key is stored on-device only", systemImage: "lock.shield")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("To add your key:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Profile → AI Settings → Google API Key")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Button {
                dismiss()
            } label: {
                Text("Got it")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
            }

            Spacer()
        }
    }
}

// MARK: - VideoPlayerView
// Wraps AVPlayer for looping, muted, ambient video playback in the hero area.

struct LoopingVideoPlayerView: View {
    let url: URL

    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayerLayer(player: player)
            .onAppear { setupPlayer() }
            .onDisappear { player?.pause() }
    }

    private func setupPlayer() {
        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.isMuted = true
        avPlayer.actionAtItemEnd = .none

        // Loop indefinitely
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in avPlayer.seek(to: .zero); avPlayer.play() }

        avPlayer.play()
        self.player = avPlayer
    }
}

// UIViewRepresentable wrapper for AVPlayerLayer
private struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerUIView { PlayerUIView() }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.setPlayer(player)
    }
}

private class PlayerUIView: UIView {
    private var playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    func setPlayer(_ player: AVPlayer?) {
        playerLayer.player = player
    }
}

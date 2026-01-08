import SwiftUI
import AVKit

struct CardVideoPlayer: View {
    let url: URL
    let audioManager: AudioManager
    var shouldPause: Bool = false
    
    @State private var player: AVPlayer?
    
    var body: some View {
        VideoPlayerController(player: player, audioManager: audioManager)
            .onAppear {
                setupPlayer()
            }
            .onDisappear {
                player?.pause()
            }
            .onChange(of: url) { _, newUrl in
                replacePlayerItem(with: newUrl)
            }
            .onChange(of: shouldPause) { _, shouldPause in
                if shouldPause {
                    player?.pause()
                }
            }
    }
    
    private func setupPlayer() {
        // Stop any competing audio (TTS, background music)
        audioManager.stopAudio()
        
        // The audio session configuration is handled by VideoPlayerController
        
        if player == nil {
            // Async creation to allow view hierarchy to settle
            DispatchQueue.main.async {
                let newPlayer = AVPlayer(url: self.url)
                newPlayer.isMuted = false
                newPlayer.volume = 1.0
                
                // CRITICAL: Differentiate audio algorithm for Simulator vs Device
                #if targetEnvironment(simulator)
                // Simulator has known audio engine issues with pitch algorithms.
                // .timeDomain is often the most robust for basic playback here.
                newPlayer.currentItem?.audioTimePitchAlgorithm = .timeDomain
                #else
                // Device: Use varispeed for high-quality 1.0x playback
                newPlayer.currentItem?.audioTimePitchAlgorithm = .varispeed
                #endif
                
                // CRITICAL: Force rate to normal
                newPlayer.rate = 1.0
                
                self.player = newPlayer
            }
        } else {
            // If player exists but might have wrong item (unlikely due to keying, but safe)
            replacePlayerItem(with: url)
        }
    }
    
    private func replacePlayerItem(with newUrl: URL) {
        let item = AVPlayerItem(url: newUrl)
        // Differentiate audio algorithm for Simulator vs Device
        #if targetEnvironment(simulator)
        item.audioTimePitchAlgorithm = .timeDomain
        #else
        item.audioTimePitchAlgorithm = .varispeed
        #endif
        
        player?.replaceCurrentItem(with: item)
        // Re-enforce unmute when item changes
        player?.isMuted = false
        player?.volume = 1.0
    }
}

struct VideoPlayerController: UIViewControllerRepresentable {
    var player: AVPlayer?
    var audioManager: AudioManager

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        // Critical: Configure session BEFORE controller setup
        audioManager.configureAudioSession()
        
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        // Ensure video gravity fits nicely
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

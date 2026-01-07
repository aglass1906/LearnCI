import AudioToolbox
import AVFoundation
import UIKit

class SoundManager: NSObject {
    static let shared = SoundManager()
    
    enum SoundType: String {
        case flip = "sfx_flip"
        case match = "sfx_match"
        case mismatch = "sfx_mismatch"
        case win = "sfx_win"
        case click = "sfx_click"
    }
    
    private var players: [SoundType: AVAudioPlayer] = [:]
    
    private override init() {
        super.init()
    }
    
    func play(_ type: SoundType) {
        // 1. Try to play custom sound file first
        if playCustomSound(for: type) {
            return
        }
        
        // 2. Fallback to System Sounds if file not found
        playSystemFallback(for: type)
    }
    
    private func playCustomSound(for type: SoundType) -> Bool {
        // Reuse player if exists
        if let player = players[type] {
            if player.isPlaying {
                player.stop()
                player.currentTime = 0
            }
            player.play()
            return true
        }
        
        // Search for file (try common extensions and subdirectories)
        let extensions = ["wav", "mp3", "m4a", "caf"]
        let subdirectories = [nil, "Audio", "Sounds", "SFX", "Resources/Audio", "Resources/Sounds"]
        
        var soundURL: URL?
        
        outerLoop: for ext in extensions {
            for sub in subdirectories {
                if let url = Bundle.main.url(forResource: type.rawValue, withExtension: ext, subdirectory: sub) {
                    soundURL = url
                    break outerLoop
                }
            }
        }
        
        guard let url = soundURL else { return false }
        
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            players[type] = player
            return true
        } catch {
            print("SoundManager: Failed to play custom sound \(type.rawValue): \(error)")
            return false
        }
    }
    
    private func playSystemFallback(for type: SoundType) {
        var soundID: SystemSoundID = 0
        
        switch type {
        case .flip:
            // "Tock" / Key click sound (1104 is good, 1105 is louder)
            soundID = 1104
        case .match:
            // "Tink" / Success chime
            soundID = 1001 
        case .mismatch:
            // "Vibrate" / Error buzz
            soundID = 1073
        case .win:
            // "Fanfare" / Mail Sent
            soundID = 1001
        case .click:
            soundID = 1306
        }
        
        AudioServicesPlaySystemSound(soundID)
    }
}

import Foundation
import AVFoundation

@Observable
class AudioManager {
    var player: AVAudioPlayer?
    
    func playAudio(named filename: String) {
        // Look for the file in the bundle (Resources folder)
        // We accept filename with extension e.g. "hola.mp3"
        
        // 1. Try Bundle Resource (if flattened)
        if let url = Bundle.main.url(forResource: filename, withExtension: nil) {
            play(url: url)
            return
        }
        
        // 2. Try looking in the specific Resources/Audio path if we are running in simulator references
        // We'll search recursively or just check the Audio folder relative to Bundle
        if let url = Bundle.main.url(forResource: "Audio/\(filename)", withExtension: nil) {
             play(url: url)
             return
        }
        
        // 3. Fallback for untracked local development files (simulated path)
        let localPath = "/Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Resources/Audio/\(filename)"
        if FileManager.default.fileExists(atPath: localPath) {
             play(url: URL(fileURLWithPath: localPath))
             return
        }
        
        print("Audio file not found: \(filename)")
    }
    
    private func play(url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            print("Failed to play audio: \(error)")
        }
    }
}

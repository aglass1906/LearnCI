import Foundation
import AVFoundation

@Observable
class AudioManager: NSObject, AVAudioPlayerDelegate {
    var player: AVAudioPlayer?
    private var onCompletion: (() -> Void)?
    
    func playAudio(named filename: String, folderName: String? = nil, completion: (() -> Void)? = nil) {
        self.onCompletion = completion
        
        // 1. Try Bundle Resource in specific subdirectory if folderName provided
        if let folder = folderName {
            if let url = Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: "Data/\(folder)") {
                play(url: url)
                return
            }
        }
        
        // 2. Try Bundle Resource (flattened or fallback)
        if let url = Bundle.main.url(forResource: filename, withExtension: nil) {
            play(url: url)
            return
        }
        
        // 3. Try looking in the specific Resources/Audio path (Legacy)
        if let url = Bundle.main.url(forResource: "Audio/\(filename)", withExtension: nil) {
             play(url: url)
             return
        }
        
        // 4. Fallback for local development files in the new structure
        if let folder = folderName {
            let localPath = "/Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Resources/Data/\(folder)/\(filename)"
            if FileManager.default.fileExists(atPath: localPath) {
                 play(url: URL(fileURLWithPath: localPath))
                 return
            }
        }
        
        // 5. Legacy Fallback
        let localLegacyPath = "/Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Resources/Audio/\(filename)"
        if FileManager.default.fileExists(atPath: localLegacyPath) {
             play(url: URL(fileURLWithPath: localLegacyPath))
             return
        }
        
        print("Audio file not found: \(filename) in folder: \(folderName ?? "nil")")
        onCompletion?()
    }
    
    func playSequence(filenames: [String], folderName: String? = nil) {
        guard !filenames.isEmpty else { return }
        var remaining = filenames
        let first = remaining.removeFirst()
        
        playAudio(named: first, folderName: folderName) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.playSequence(filenames: remaining, folderName: folderName)
            }
        }
    }
    
    private func play(url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.play()
        } catch {
            print("Failed to play audio: \(error)")
            onCompletion?()
        }
    }
    
    func stopAudio() {
        player?.stop()
        onCompletion = nil
    }
    
    // MARK: - AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onCompletion?()
        onCompletion = nil
    }
}

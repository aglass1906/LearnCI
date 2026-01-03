import Foundation
import AVFoundation

@Observable
class AudioManager: NSObject, AVAudioPlayerDelegate {
    var player: AVAudioPlayer?
    private var onCompletion: (() -> Void)?
    
    func playAudio(named filename: String, folderName: String? = nil, completion: (() -> Void)? = nil) {
        self.onCompletion = completion
        
        if let url = resolveAudioURL(filename: filename, folderName: folderName) {
            play(url: url)
        } else {
            print("Audio file not found: \(filename) (folder: \(folderName ?? "nil"))")
            onCompletion?()
        }
    }

    private func resolveAudioURL(filename: String, folderName: String?) -> URL? {
        let fm = FileManager.default
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension.isEmpty ? nil : (filename as NSString).pathExtension
        
        // 1. Try local dev paths (Simulator/Mac only)
        if let folder = folderName {
            let localPath = "/Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Resources/Data/\(folder)/\(filename)"
            if fm.fileExists(atPath: localPath) {
                return URL(fileURLWithPath: localPath)
            }
        }
        let localLegacyPath = "/Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Resources/Audio/\(filename)"
        if fm.fileExists(atPath: localLegacyPath) {
            return URL(fileURLWithPath: localLegacyPath)
        }

        // 2. Try Bundle with subdirectories
        if let folder = folderName {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Data/\(folder)") ??
                        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Data/\(folder)") {
                return url
            }
        }
        
        // 3. Try Bundle standard locations
        if let url = Bundle.main.url(forResource: name, withExtension: ext) ??
                    Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Audio") ??
                    Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Audio") {
            return url
        }

        // 4. Robust recursive search in bundle (fallback for complex deployment)
        let bundleURL = Bundle.main.bundleURL
        if let enumerator = fm.enumerator(at: bundleURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == filename {
                    return fileURL
                }
            }
        }
        
        return nil
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

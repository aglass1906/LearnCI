import Foundation
import AVFoundation

@Observable
class AudioManager: NSObject, AVAudioPlayerDelegate {
    var player: AVAudioPlayer?
    private var onCompletion: (() -> Void)?
    private var sequenceWorkItem: DispatchWorkItem?
    
    // Tracking current sequence to avoid redundant starts
    private var currentSequence: [String] = []
    
    // Caching resolved URLs to avoid repeated recursive searches
    private var audioURLCache: [String: URL] = [:]
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            // Keep it active as long as the app is in the game context
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    func playAudio(named filename: String, folderName: String? = nil, completion: (() -> Void)? = nil) {
        // Avoid restarting if this specific file is already playing
        if let player = player, player.isPlaying, currentSequence == [filename] {
            return
        }
        
        self.stopAudio()
        self.currentSequence = [filename]
        self.onCompletion = completion
        
        if let url = resolveAudioURL(filename: filename, folderName: folderName) {
            play(url: url)
        } else {
            print("Audio file not found: \(filename) (folder: \(folderName ?? "nil"))")
            onCompletion?()
        }
    }

    private func resolveAudioURL(filename: String, folderName: String?) -> URL? {
        let cacheKey = "\(folderName ?? "root")/\(filename)"
        if let cached = audioURLCache[cacheKey] {
            return cached
        }
        
        let fm = FileManager.default
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension.isEmpty ? nil : (filename as NSString).pathExtension
        
        // 1. Try local dev paths (Simulator/Mac only)
        if let folder = folderName {
            let localPath = "/Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Resources/Data/\(folder)/\(filename)"
            if fm.fileExists(atPath: localPath) {
                let url = URL(fileURLWithPath: localPath)
                audioURLCache[cacheKey] = url
                return url
            }
        }
        let localLegacyPath = "/Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI/Resources/Audio/\(filename)"
        if fm.fileExists(atPath: localLegacyPath) {
            let url = URL(fileURLWithPath: localLegacyPath)
            audioURLCache[cacheKey] = url
            return url
        }

        // 2. Try Bundle with subdirectories
        if let folder = folderName {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Data/\(folder)") ??
                        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Data/\(folder)") {
                audioURLCache[cacheKey] = url
                return url
            }
        }
        
        // 3. Try Bundle standard locations
        if let url = Bundle.main.url(forResource: name, withExtension: ext) ??
                    Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Audio") ??
                    Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Audio") {
            audioURLCache[cacheKey] = url
            return url
        }

        // 4. Robust recursive search in bundle (fallback)
        let bundleURL = Bundle.main.bundleURL
        if let enumerator = fm.enumerator(at: bundleURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == filename {
                    audioURLCache[cacheKey] = fileURL
                    return fileURL
                }
            }
        }
        
        return nil
    }
    
    func playSequence(filenames: [String], folderName: String? = nil) {
        // Avoid restarting if the same sequence is already playing/scheduled
        guard filenames != currentSequence else { return }
        
        stopAudio() // Ensure clean state before new sequence
        
        guard !filenames.isEmpty else { 
            currentSequence = []
            return 
        }
        
        currentSequence = filenames
        var remaining = filenames
        let first = remaining.removeFirst()
        
        playAudio(named: first, folderName: folderName) { [weak self] in
            let workItem = DispatchWorkItem {
                self?.playSequence(filenames: remaining, folderName: folderName)
            }
            self?.sequenceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
        }
    }
    
    private func play(url: URL) {
        do {
            // Re-activating session only if necessary (usually once is enough)
            if !AVAudioSession.sharedInstance().isOtherAudioPlaying {
                try? AVAudioSession.sharedInstance().setActive(true)
            }
            
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()
        } catch {
            print("Failed to play audio: \(error)")
            onCompletion?()
        }
    }
    
    func stopAudio() {
        sequenceWorkItem?.cancel()
        sequenceWorkItem = nil
        player?.stop()
        onCompletion = nil
        currentSequence = []
    }
    
    // MARK: - AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onCompletion?()
        onCompletion = nil
    }
}

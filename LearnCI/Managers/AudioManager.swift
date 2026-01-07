import Foundation
import AVFoundation

@Observable
class AudioManager: NSObject, AVAudioPlayerDelegate {
    var player: AVAudioPlayer?
    private var onCompletion: (() -> Void)?
    private var sequenceWorkItem: DispatchWorkItem?
    
    // Caching resolved URLs to avoid repeated recursive searches
    private var audioURLCache: [String: URL] = [:]
    
    // TTS Synthesizer
    private let synthesizer = AVSpeechSynthesizer()
    
    override init() {
        super.init()
        configureAudioSession()
    }
    
    func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Standard playback config.
            // Reverting to .default mode as .moviePlayback can sometimes conflict with TTS on certain devices/simulators.
            // Using standard options (interrupting others) to ensure clean playback pipeline.
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            print("DEBUG: AVAudioSession active. Category: Playback, Mode: Default")
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    func audioExists(named filename: String, folderName: String? = nil) -> Bool {
        return resolveAudioURL(filename: filename, folderName: folderName) != nil
    }

    private func resolveAudioURL(filename: String, folderName: String?) -> URL? {
        let cacheKey = "\(folderName ?? "root")/\(filename)"
        if let cached = audioURLCache[cacheKey] {
            return cached
        }
        
        let fm = FileManager.default
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension.isEmpty ? nil : (filename as NSString).pathExtension
        
        // 1. Try local dev paths (Simulator only)
        #if targetEnvironment(simulator)
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
        #endif

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
        // Physical devices are case-sensitive. We do a case-insensitive match here for resilience.
        let bundleURL = Bundle.main.bundleURL
        if let enumerator = fm.enumerator(at: bundleURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent.lowercased() == filename.lowercased() {
                    audioURLCache[cacheKey] = fileURL
                    return fileURL
                }
            }
        }
        
        return nil
    }
    
    private func playInternal(filename: String, folderName: String?, text: String? = nil, language: Language? = nil, useFallback: Bool = false, ttsRate: Float = 0.5, completion: (() -> Void)? = nil) {
        self.onCompletion = completion
        
        if let url = resolveAudioURL(filename: filename, folderName: folderName) {
            play(url: url)
        } else {
            print("Audio file not found: \(filename) (folder: \(folderName ?? "nil"))")
            
            // Try one more time with exact filename in root bundle if folder was provided
            if folderName != nil, let fallbackUrl = resolveAudioURL(filename: filename, folderName: nil) {
                play(url: fallbackUrl)
            } else if useFallback, let text = text, let language = language {
                // FALLBACK: Use TTS
                speak(text: text, language: language, rate: ttsRate)
            } else {
                onCompletion?()
            }
        }
    }
    
    func playAudio(named filename: String, folderName: String? = nil, text: String? = nil, language: Language? = nil, useFallback: Bool = false, ttsRate: Float = 0.5, completion: (() -> Void)? = nil) {
        // Avoid restarting if this specific file is already playing as a single intent
        if let player = player, player.isPlaying, currentSequence == [AudioItem(filename: filename, text: text, language: language)] {
            return
        }
        
        // If speaking, checking synthesizer state might be needed, but usually we just stop and restart
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        stopAudio()
        self.currentSequence = [AudioItem(filename: filename, text: text, language: language)]
        
        playInternal(filename: filename, folderName: folderName, text: text, language: language, useFallback: useFallback, ttsRate: ttsRate, completion: completion)
    }
    
    // MARK: - Sequence Playback
    
    struct AudioItem: Equatable {
        let filename: String
        let text: String?
        let language: Language?
    }
    
    // Tracking current sequence
    private var currentSequence: [AudioItem] = []
    
    func playSequence(items: [AudioItem], folderName: String? = nil, useFallback: Bool = false) {
        // Avoid restarting if the same sequence is already playing
        guard items != currentSequence else { return }
        
        stopAudio()
        
        guard !items.isEmpty else {
            currentSequence = []
            return
        }
        
        currentSequence = items
        playNextInSequence(items: items, folderName: folderName, useFallback: useFallback)
    }
    
    private func playNextInSequence(items: [AudioItem], folderName: String?, useFallback: Bool) {
        var remaining = items
        guard !remaining.isEmpty else { return }
        let first = remaining.removeFirst()
        
        playInternal(
            filename: first.filename,
            folderName: folderName,
            text: first.text,
            language: first.language,
            useFallback: useFallback
        ) { [weak self] in
            let workItem = DispatchWorkItem {
                self?.playNextInSequence(items: remaining, folderName: folderName, useFallback: useFallback)
            }
            self?.sequenceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
        }
    }
    
    // Deprecated string-only override for compatibility if needed, but we should migrate
    func playSequence(filenames: [String], folderName: String? = nil) {
        let items = filenames.map { AudioItem(filename: $0, text: nil, language: nil) }
        playSequence(items: items, folderName: folderName, useFallback: false)
    }

    private func play(url: URL) {
        do {
            configureAudioSession()
            
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()
        } catch {
            print("Failed to play audio: \(error)")
            onCompletion?()
        }
    }
    
    private func speak(text: String, language: Language, rate: Float) {
        let utterance = AVSpeechUtterance(string: text)
        
        let voiceCode: String
        switch language {
        case .spanish: voiceCode = "es-MX"
        case .japanese: voiceCode = "ja-JP"
        case .korean: voiceCode = "ko-KR"
        }
        
        utterance.voice = AVSpeechSynthesisVoice(language: voiceCode)
        utterance.rate = rate
        
        // Ensure session is correct
        configureAudioSession()
        
        synthesizer.delegate = self
        synthesizer.speak(utterance)
    }
    
    func stopAudio() {
        sequenceWorkItem?.cancel()
        sequenceWorkItem = nil
        player?.stop()
        synthesizer.stopSpeaking(at: .immediate)
        onCompletion = nil
        currentSequence = []
    }
    
    // MARK: - AVAudioPlayerDelegate & AVSpeechSynthesizerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onCompletion?()
        onCompletion = nil
    }
    
}

extension AudioManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onCompletion?()
        onCompletion = nil
    }
}

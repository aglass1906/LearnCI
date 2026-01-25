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
        // Explicitly tell synthesizer to use the existing audio session we configure
        synthesizer.usesApplicationAudioSession = true
        configureAudioSession()
    }
    
    func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Standard playback config.
            // Reverting to .default mode as .moviePlayback can sometimes conflict with TTS on certain devices/simulators.
            // Using standard options (interrupting others) to ensure clean playback pipeline.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            print("DEBUG: AVAudioSession active. Category: Playback, Mode: Default, Options: MixWithOthers")
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
    
    private func playInternal(filename: String, folderName: String?, text: String? = nil, language: Language? = nil, voiceGender: String? = nil, useFallback: Bool = false, ttsRate: Float = 0.5, completion: (() -> Void)? = nil) {
        self.onCompletion = completion
        
        // Define fallback action
        let performFallback = {
            if useFallback, let text = text, let language = language {
                print("DEBUG: Using TTS Fallback (\(voiceGender ?? "default")) for: \(text)")
                self.speak(text: text, language: language, gender: voiceGender, rate: ttsRate)
            } else {
                self.onCompletion?()
            }
        }
        
        // Attempt 1: Specific Folder
        if let url = resolveAudioURL(filename: filename, folderName: folderName) {
            do {
                try play(url: url)
                return // Success
            } catch {
                print("DEBUG: Primary audio file found but failed to play: \(error).")
            }
        } else {
            print("Audio file not found: \(filename) (folder: \(folderName ?? "nil"))")
        }
        
        // Attempt 2: Root Bundle (only if we looked in a folder first)
        if folderName != nil, let url = resolveAudioURL(filename: filename, folderName: nil) {
             do {
                try play(url: url)
                return // Success
            } catch {
                print("DEBUG: Root fallback audio file found but failed to play: \(error).")
            }
        }
        
        // Final Fallback: TTS
        performFallback()
    }
    
    func playAudio(named filename: String, folderName: String? = nil, text: String? = nil, language: Language? = nil, voiceGender: String? = nil, useFallback: Bool = false, ttsRate: Float = 0.5, completion: (() -> Void)? = nil) {
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
        
        playInternal(filename: filename, folderName: folderName, text: text, language: language, voiceGender: voiceGender, useFallback: useFallback, ttsRate: ttsRate, completion: completion)
    }
    
    // MARK: - Sequence Playback
    
    struct AudioItem: Equatable {
        let filename: String
        let text: String?
        let language: Language?
        let voiceGender: String?
        
        init(filename: String, text: String? = nil, language: Language? = nil, voiceGender: String? = nil) {
            self.filename = filename
            self.text = text
            self.language = language
            self.voiceGender = voiceGender
        }
    }
    
    // Tracking current sequence
    private var currentSequence: [AudioItem] = []
    
    func playSequence(items: [AudioItem], folderName: String? = nil, useFallback: Bool = false, ttsRate: Float = 0.5) {
        // Avoid restarting if the same sequence is already playing
        guard items != currentSequence else { return }
        
        stopAudio()
        
        guard !items.isEmpty else {
            currentSequence = []
            return
        }
        
        currentSequence = items
        playNextInSequence(items: items, folderName: folderName, useFallback: useFallback, ttsRate: ttsRate)
    }
    
    private func playNextInSequence(items: [AudioItem], folderName: String?, useFallback: Bool, ttsRate: Float) {
        var remaining = items
        guard !remaining.isEmpty else { return }
        let first = remaining.removeFirst()
        
        playInternal(
            filename: first.filename,
            folderName: folderName,
            text: first.text,
            language: first.language,
            voiceGender: first.voiceGender,
            useFallback: useFallback,
            ttsRate: ttsRate
        ) { [weak self] in
            let workItem = DispatchWorkItem {
                self?.playNextInSequence(items: remaining, folderName: folderName, useFallback: useFallback, ttsRate: ttsRate)
            }
            self?.sequenceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
        }
    }
    
    // Deprecated string-only override for compatibility if needed, but we should migrate
    func playSequence(filenames: [String], folderName: String? = nil) {
        let items = filenames.map { AudioItem(filename: $0, text: nil, language: nil) }
        playSequence(items: items, folderName: folderName, useFallback: false, ttsRate: 0.5)
    }

    private func play(url: URL) throws {
        configureAudioSession()
        player = try AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.prepareToPlay()
        player?.play()
    }
    
    private func speak(text: String, language: Language, gender: String?, rate: Float) {
        let utterance = AVSpeechUtterance(string: text)
        
        let voiceCode: String
        switch language {
        case .spanish: voiceCode = "es-MX"
        case .japanese: voiceCode = "ja-JP"
        case .korean: voiceCode = "ko-KR"
        case .french: voiceCode = "fr-FR"
        }
        
        // Find voice by language and optionally gender
        if let genderFilter = gender {
            let preferredGender: AVSpeechSynthesisVoiceGender = genderFilter.lowercased() == "male" ? .male : .female
            let allVoices = AVSpeechSynthesisVoice.speechVoices()
            
            // Helper to determine effective gender (handling "Unspecified" novelty voices)
            func isVoice(_ voice: AVSpeechSynthesisVoice, matchGender target: AVSpeechSynthesisVoiceGender) -> Bool {
                if voice.gender == target { return true }
                if voice.gender == .unspecified {
                    let maleNames = ["Jorge", "Juan", "Diego", "Carlos", "Grandpa", "Rocko", "Reed", "Eddy", "Rishi", "Daniel"]
                    let femaleNames = ["Monica", "Paulina", "Soledad", "Angelica", "Grandma", "Sandy", "Shelley", "Flo", "Lola", "Samantha"]
                    
                    if target == .male {
                        return maleNames.contains(where: { voice.name.contains($0) })
                    } else {
                        return femaleNames.contains(where: { voice.name.contains($0) })
                    }
                }
                return false
            }
            
            // 1. Exact Match: Voice Code + Effective Gender (e.g., es-MX Male/Eddy)
            if let voice = allVoices.first(where: {
                $0.language == voiceCode && isVoice($0, matchGender: preferredGender)
            }) {
                print("DEBUG: Selected exact match: \(voice.name) (\(voice.language))")
                utterance.voice = voice
            }
            // 2. Dialect Fallback: Language Prefix + Effective Gender (e.g., es-ES Male/Rocko)
            else if let voice = allVoices.first(where: {
                $0.language.starts(with: language.code) && isVoice($0, matchGender: preferredGender)
            }) {
                print("DEBUG: Selected dialect fallback: \(voice.name) (\(voice.language)) for \(preferredGender)")
                utterance.voice = voice
            }
            // 3. Language Fallback: Default for Code
            else if let voice = AVSpeechSynthesisVoice(language: voiceCode) {
                 print("DEBUG: Preferred gender \(genderFilter) not found for \(voiceCode) or dialects. Falling back to default: \(voice.name)")
                 utterance.voice = voice
            } else {
                 print("DEBUG: No voice found for \(voiceCode). System default will be used.")
            }
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: voiceCode)
        }
        
        utterance.rate = rate
        utterance.volume = 1.0 // Ensure maximum volume relative to system level
        
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

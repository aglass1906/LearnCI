import Foundation
import AVFoundation
import MediaPlayer

@Observable
class AudioManager: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioManager()
    
    var player: AVAudioPlayer?
    private var onCompletion: (() -> Void)?
    private var sequenceWorkItem: DispatchWorkItem?

    /// Indicates whether audio is currently playing (file or TTS)
    var isPlaying: Bool = false
    
    var currentTime: Double? {
        player?.currentTime
    }

    // MARK: - Ambient Audio
    private var ambientPlayer: AVAudioPlayer?
    var ambientVolume: Float = 0.15 {
        didSet { ambientPlayer?.volume = ambientVolume }
    }
    var isAmbientPlaying: Bool = false

    // MARK: - AVPlayer Streaming
    var streamPlayer: AVPlayer?
    var isStreaming: Bool = false
    var streamDuration: Double = 0
    var streamCurrentTime: Double = 0
    var streamFinished: Bool = false
    var streamPlaybackRate: Float = 1.0
    var streamLoadError: String?
    var streamIsBuffering: Bool = false
    var onStreamFinished: (() -> Void)?
    private var streamTimeObserver: Any?
    private var streamItemObservations: [NSKeyValueObservation] = []
    private var isAudioSessionConfigured = false
    private var wasPlayingBeforeInterruption = false
    private var wasStreamingBeforeInterruption = false
    
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
        guard !isAudioSessionConfigured else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            // .playback category is required for background audio.
            // .default mode is standard.
            // Removing .mixWithOthers to ensure we capture remote command events (Lock Screen controls).
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            isAudioSessionConfigured = true
            print("DEBUG: AVAudioSession active. Category: Playback")
        } catch {
            print("Failed to setup audio session: \(error)")
            return
        }

        setupRemoteTransportControls()
        setupInterruptionObserver()
    }

    func activatePlaybackSession() {
        configureAudioSession()
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to activate audio session: \(error)")
        }
    }

    private func setupInterruptionObserver() {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            // Phone call, Siri, alarm, etc. — pause but keep the player alive
            wasStreamingBeforeInterruption = isStreaming
            wasPlayingBeforeInterruption = player?.isPlaying == true

            if isStreaming {
                streamPlayer?.pause()
                isStreaming = false
            }
            if player?.isPlaying == true {
                player?.pause()
                isPlaying = false
            }

        case .ended:
            guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

            guard options.contains(.shouldResume) else {
                wasPlayingBeforeInterruption = false
                wasStreamingBeforeInterruption = false
                return
            }

            try? AVAudioSession.sharedInstance().setActive(true)

            if wasStreamingBeforeInterruption, streamPlayer != nil {
                streamPlayer?.play()
                if streamPlaybackRate != 1.0 { streamPlayer?.rate = streamPlaybackRate }
                isStreaming = true
                updateStreamNowPlayingInfo()
            } else if wasPlayingBeforeInterruption, let player {
                player.play()
                isPlaying = true
                updateNowPlayingInfo()
            }

            wasPlayingBeforeInterruption = false
            wasStreamingBeforeInterruption = false

        @unknown default:
            break
        }
    }
    
    // MARK: - Remote Command Center (Lock Screen)
    
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if let sp = self.streamPlayer {
                sp.play()
                self.isStreaming = true
                self.updateStreamNowPlayingInfo()
                return .success
            }
            guard let player = self.player else { return .commandFailed }
            if !player.isPlaying {
                player.play()
                self.isPlaying = true
                self.updateNowPlayingInfo()
                return .success
            }
            return .commandFailed
        }

        // Pause
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if let sp = self.streamPlayer {
                sp.pause()
                self.isStreaming = false
                self.updateStreamNowPlayingInfo()
                return .success
            }
            guard let player = self.player else { return .commandFailed }
            if player.isPlaying {
                player.pause()
                self.isPlaying = false
                self.updateNowPlayingInfo()
                return .success
            }
            return .commandFailed
        }

        // Skip Forward (10s)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [10]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.streamPlayer != nil {
                let newTime = min(self.streamDuration, self.streamCurrentTime + 10)
                self.seekStream(to: newTime)
                self.updateStreamNowPlayingInfo()
                return .success
            }
            guard let player = self.player else { return .commandFailed }
            let newTime = player.currentTime + 10
            player.currentTime = min(player.duration, newTime)
            self.updateNowPlayingInfo()
            return .success
        }

        // Skip Backward (10s)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [10]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.streamPlayer != nil {
                let newTime = max(0, self.streamCurrentTime - 10)
                self.seekStream(to: newTime)
                self.updateStreamNowPlayingInfo()
                return .success
            }
            guard let player = self.player else { return .commandFailed }
            let newTime = player.currentTime - 10
            player.currentTime = max(0, newTime)
            self.updateNowPlayingInfo()
            return .success
        }

        // Scrubbing (Seek)
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            if self.streamPlayer != nil {
                self.seekStream(to: event.positionTime)
                self.updateStreamNowPlayingInfo()
                return .success
            }
            guard let player = self.player else { return .commandFailed }
            player.currentTime = event.positionTime
            self.updateNowPlayingInfo()
            return .success
        }
    }
    
    func updateNowPlayingInfo(title: String? = nil, artist: String? = nil, artworkImage: UIImage? = nil) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
        
        if let title = title { info[MPMediaItemPropertyTitle] = title }
        if let artist = artist { info[MPMediaItemPropertyArtist] = artist }
        if let image = artworkImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        
        if let player = player {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime
            info[MPMediaItemPropertyPlaybackDuration] = player.duration
            info[MPNowPlayingInfoPropertyPlaybackRate] = player.isPlaying ? player.rate : 0.0
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    // Clear info when stopped
    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
        guard !remaining.isEmpty else {
            // Sequence complete - clear and set isPlaying to false
            currentSequence = []
            isPlaying = false
            return
        }
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

    func playAudio(url: URL) throws {
        stopAudio()
        configureAudioSession()
        player = try AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.prepareToPlay()
        // Do not auto-play, let UI control it
        isPlaying = false
    }

    func play(url: URL) throws {
        configureAudioSession()
        player = try AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.prepareToPlay()
        player?.play()
        isPlaying = true
    }

    func playOneShot(url: URL, rate: Float = 1.0) throws {
        stopAudio()
        configureAudioSession()

        player = try AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.enableRate = true
        player?.rate = rate
        player?.prepareToPlay()
        player?.play()
        isPlaying = true
    }

    func setOneShotRate(_ rate: Float) {
        player?.enableRate = true
        player?.rate = rate
    }
    
    func seek(to time: Double) {
        player?.currentTime = time
    }
    
    func speak(text: String, language: Language, gender: String?, rate: Float) {
        let utterance = AVSpeechUtterance(string: text)
        
        let voiceCode: String
        switch language {
        case .spanish: voiceCode = "es-MX"
        case .japanese: voiceCode = "ja-JP"
        case .korean: voiceCode = "ko-KR"
        case .french: voiceCode = "fr-FR"
        case .vietnamese: voiceCode = "vi-VN"
        case .english: voiceCode = "en-US"
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
        isPlaying = true
    }
    
    // MARK: - Streaming Playback (AVPlayer)

    func streamAudio(url: URL, startAt: Double = 0) {
        activatePlaybackSession()
        streamFinished = false
        streamLoadError = nil

        if let player = streamPlayer {
            replaceStreamItem(url: url, startAt: startAt, player: player)
            return
        }

        stopNonStreamAudio()
        let playerItem = makeStreamPlayerItem(url: url)
        streamPlayer = AVPlayer(playerItem: playerItem)
        configureStreamPlayback(player: streamPlayer!, item: playerItem, startAt: startAt)
    }

    private func stopNonStreamAudio() {
        sequenceWorkItem?.cancel()
        sequenceWorkItem = nil
        player?.stop()
        synthesizer.stopSpeaking(at: .immediate)
        onCompletion = nil
        currentSequence = []
        isPlaying = false
    }

    private func makeStreamPlayerItem(url: URL) -> AVPlayerItem {
        let headers = ["User-Agent": "LearnCI/1.0 (iOS; Podcast Player)"]
        let asset = AVURLAsset(
            url: url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
        )
        return AVPlayerItem(asset: asset)
    }

    private func replaceStreamItem(url: URL, startAt: Double, player: AVPlayer) {
        if let oldItem = player.currentItem {
            NotificationCenter.default.removeObserver(
                self,
                name: AVPlayerItem.didPlayToEndTimeNotification,
                object: oldItem
            )
        }
        if let observer = streamTimeObserver {
            player.removeTimeObserver(observer)
            streamTimeObserver = nil
        }
        clearStreamObservations()

        streamDuration = 0
        streamCurrentTime = 0
        isStreaming = false
        streamIsBuffering = true

        let playerItem = makeStreamPlayerItem(url: url)
        player.replaceCurrentItem(with: playerItem)
        configureStreamPlayback(player: player, item: playerItem, startAt: startAt)
    }

    private func configureStreamPlayback(player: AVPlayer, item: AVPlayerItem, startAt: Double) {
        attachStreamObservations(player: player, item: item)

        Task {
            do {
                let duration = try await item.asset.load(.duration)
                await MainActor.run {
                    if duration.isNumeric {
                        self.streamDuration = CMTimeGetSeconds(duration)
                    }
                }
            } catch {
                print("Failed to load duration: \(error)")
            }
        }

        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        streamTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.streamCurrentTime = CMTimeGetSeconds(time)

            if self.streamDuration == 0, let item = self.streamPlayer?.currentItem {
                let dur = item.duration
                if dur.isNumeric {
                    self.streamDuration = CMTimeGetSeconds(dur)
                }
            }

            if self.isStreaming {
                self.updateStreamNowPlayingInfo()
            }
        }

        if startAt > 0 {
            let seekTime = CMTime(seconds: startAt, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            player.seek(to: seekTime)
            streamCurrentTime = startAt
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(streamDidFinish),
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: item
        )
    }

    func playStream() {
        guard streamPlayer != nil else {
            streamLoadError = streamLoadError ?? "Audio is not ready to play yet."
            isStreaming = false
            return
        }

        activatePlaybackSession()
        streamPlayer?.play()
        // Apply custom rate if set (no-op if 1.0)
        if streamPlaybackRate != 1.0 {
            streamPlayer?.rate = streamPlaybackRate
        }
        isStreaming = true
        updateStreamBufferingState()
    }

    func pauseStream() {
        streamPlayer?.pause()
        isStreaming = false
        streamIsBuffering = false
        updateStreamNowPlayingInfo()
    }

    func seekStream(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        streamPlayer?.seek(to: time)
        streamCurrentTime = seconds
        if isStreaming {
            streamIsBuffering = true
            updateStreamBufferingState()
        }
    }

    func setStreamRate(_ rate: Float) {
        guard let player = streamPlayer else { return }
        if isStreaming {
            // Setting rate on AVPlayer while playing: use rate directly
            // (setting rate to non-zero both resumes and sets speed)
            player.rate = rate
        } else {
            // Store rate; it will apply when playStream() is called
            player.rate = 0 // keep paused
        }
        streamPlaybackRate = rate
    }

    func stopStream() {
        if let observer = streamTimeObserver {
            streamPlayer?.removeTimeObserver(observer)
            streamTimeObserver = nil
        }
        clearStreamObservations()
        NotificationCenter.default.removeObserver(self, name: AVPlayerItem.didPlayToEndTimeNotification, object: streamPlayer?.currentItem)
        streamPlayer?.pause()
        streamPlayer = nil
        isStreaming = false
        streamFinished = false
        onStreamFinished = nil
        streamDuration = 0
        streamCurrentTime = 0
        streamPlaybackRate = 1.0
        streamLoadError = nil
        streamIsBuffering = false
        clearNowPlayingInfo()
    }

    private func clearStreamObservations() {
        streamItemObservations.forEach { $0.invalidate() }
        streamItemObservations.removeAll()
    }

    private func attachStreamObservations(player: AVPlayer, item: AVPlayerItem) {
        clearStreamObservations()
        streamIsBuffering = true

        streamItemObservations.append(
            item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor in
                    self?.handleStreamItemStatus(item)
                    self?.updateStreamBufferingState()
                }
            }
        )

        streamItemObservations.append(
            item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.updateStreamBufferingState()
                }
            }
        )

        streamItemObservations.append(
            item.observe(\.isPlaybackBufferEmpty, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.updateStreamBufferingState()
                }
            }
        )

        streamItemObservations.append(
            player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.updateStreamBufferingState()
                }
            }
        )
    }

    private func updateStreamBufferingState() {
        guard let player = streamPlayer, let item = player.currentItem else {
            streamIsBuffering = false
            return
        }

        if item.status == .failed {
            streamIsBuffering = false
            return
        }

        if item.status == .unknown {
            streamIsBuffering = true
            return
        }

        if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            streamIsBuffering = true
            return
        }

        if isStreaming, item.isPlaybackBufferEmpty, !item.isPlaybackLikelyToKeepUp {
            streamIsBuffering = true
            return
        }

        streamIsBuffering = false
    }

    private func handleStreamItemStatus(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            streamLoadError = nil
            let duration = item.duration
            if duration.isNumeric {
                streamDuration = CMTimeGetSeconds(duration)
            }
        case .failed:
            streamLoadError = item.error?.localizedDescription ?? "Could not load episode audio."
            isStreaming = false
            streamIsBuffering = false
            print("[AudioManager] Stream failed: \(item.error?.localizedDescription ?? "unknown")")
        case .unknown:
            streamIsBuffering = true
        @unknown default:
            break
        }
    }

    func updateStreamNowPlayingInfo(title: String? = nil, artist: String? = nil, artworkImage: UIImage? = nil) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()

        if let title = title { info[MPMediaItemPropertyTitle] = title }
        if let artist = artist { info[MPMediaItemPropertyArtist] = artist }
        if let image = artworkImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = streamCurrentTime
        info[MPMediaItemPropertyPlaybackDuration] = streamDuration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isStreaming ? (streamPlayer?.rate ?? 1.0) : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    @objc private func streamDidFinish() {
        isStreaming = false
        streamFinished = true
        onStreamFinished?()
    }

    // MARK: - Ambient Playback

    func playAmbient(url: URL, volume: Float = 0.3) {
        stopAmbient()
        do {
            // Allow ambient to mix with the main story player within this app.
            // The .playback category already allows multiple AVAudioPlayers in the same session.
            ambientPlayer = try AVAudioPlayer(contentsOf: url)
            ambientPlayer?.numberOfLoops = -1 // infinite loop
            ambientPlayer?.volume = volume
            ambientVolume = volume
            ambientPlayer?.prepareToPlay()
            ambientPlayer?.play()
            isAmbientPlaying = true
        } catch {
            print("[AudioManager] Failed to start ambient audio: \(error)")
        }
    }

    func pauseAmbient() {
        ambientPlayer?.pause()
        isAmbientPlaying = false
    }

    func resumeAmbient() {
        ambientPlayer?.play()
        isAmbientPlaying = ambientPlayer != nil
    }

    func stopAmbient() {
        ambientPlayer?.stop()
        ambientPlayer = nil
        isAmbientPlaying = false
    }

    func setAmbientVolume(_ volume: Float) {
        ambientVolume = volume
        ambientPlayer?.volume = volume
    }

    func stopAudio() {
        sequenceWorkItem?.cancel()
        sequenceWorkItem = nil
        player?.stop()
        synthesizer.stopSpeaking(at: .immediate)
        onCompletion = nil
        currentSequence = []
        isPlaying = false
        stopStream()
    }
    
    // MARK: - AVAudioPlayerDelegate & AVSpeechSynthesizerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Only set isPlaying=false if not in a sequence (sequence handles its own completion)
        if currentSequence.isEmpty {
            isPlaying = false
        }
        onCompletion?()
        onCompletion = nil
    }
    
}

extension AudioManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Only set isPlaying=false if not in a sequence (sequence handles its own completion)
        if currentSequence.isEmpty {
            isPlaying = false
        }
        onCompletion?()
        onCompletion = nil
    }
}

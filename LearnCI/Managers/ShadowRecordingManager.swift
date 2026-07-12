import Foundation
import AVFoundation

enum ShadowMicPermission {
    case granted
    case denied
    case undetermined
}

@Observable
@MainActor
final class ShadowRecordingManager: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    var isRecording: Bool = false
    var isPlayingUserRecording: Bool = false
    var currentLineID: String?
    var lastRecordingURL: URL?
    var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var playbackPlayer: AVAudioPlayer?
    private var storyID: String = ""

    override init() {
        super.init()
    }

    // MARK: - Session

    private func activateRecordSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            errorMessage = "Could not activate recording session: \(error.localizedDescription)"
        }
    }

    /// Restore the shared `.playback` category so ongoing story audio elsewhere
    /// in the app continues to behave normally after the shadow session ends.
    func restorePlaybackSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            errorMessage = "Could not restore playback session: \(error.localizedDescription)"
        }
    }

    // MARK: - Permissions

    var micPermission: ShadowMicPermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        case .undetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }

    func requestMicPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    // MARK: - Recording

    /// Begin a fresh recording for `lineID` under this story's folder. Returns
    /// the destination URL that will hold the WAV/M4A on stop.
    @discardableResult
    func startRecording(storyID: String, lineID: String) -> URL? {
        stopPlayback()
        self.storyID = storyID
        self.currentLineID = lineID
        errorMessage = nil

        activateRecordSession()

        let url = recordingURL(storyID: storyID, lineID: lineID)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else {
                errorMessage = "Recorder refused to start."
                return nil
            }
            self.recorder = recorder
            self.isRecording = true
            return url
        } catch {
            errorMessage = "Could not start recording: \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func stopRecording() -> URL? {
        guard let recorder else { return nil }
        recorder.stop()
        let url = recorder.url
        self.recorder = nil
        self.isRecording = false
        self.lastRecordingURL = url
        restorePlaybackSession()
        return url
    }

    func discardRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        if lastRecordingURL == url { lastRecordingURL = nil }
    }

    // MARK: - Playback of user recording

    func playRecording(at url: URL) {
        stopPlayback()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            playbackPlayer = player
            isPlayingUserRecording = true
        } catch {
            errorMessage = "Could not play back your recording: \(error.localizedDescription)"
        }
    }

    func stopPlayback() {
        playbackPlayer?.stop()
        playbackPlayer = nil
        isPlayingUserRecording = false
    }

    // MARK: - Filesystem helpers

    func recordingURL(storyID: String, lineID: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs
            .appendingPathComponent("StoryShadowing", isDirectory: true)
            .appendingPathComponent(storyID, isDirectory: true)
            .appendingPathComponent("\(lineID).m4a")
    }

    func existingRecordingURL(storyID: String, lineID: String) -> URL? {
        let url = recordingURL(storyID: storyID, lineID: lineID)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Delegates

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlayingUserRecording = false
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            self.isRecording = false
        }
    }
}

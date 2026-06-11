import SwiftUI
import AVFoundation
import Combine
import Supabase

/// Chapter intro content shown before chapter body playback.
/// Play/pause is driven by the shared story footer via [isPlaying].
struct ChapterInfoCardView: View {
    let chapter: StoryChapter
    let heroImage: UIImage?
    let languageCode: String
    @Binding var selectedLanguage: StorySessionView.DisplayLanguage
    @Binding var isPlaying: Bool
    let onIntroFinished: () -> Void

    @Environment(AuthManager.self) private var authManager

    @State private var synthesizer = AVSpeechSynthesizer()
    @State private var introPlayer: AVPlayer?
    @State private var introCurrentTime: Double = 0
    @State private var isLoadingAudio: Bool = false
    @State private var introEndObserver: NSObjectProtocol?
    @State private var didCompleteIntro = false

    let introTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .bottom) {
                    if let img = heroImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 220)
                            .clipped()
                    } else {
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(height: 220)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(chapterNumberLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())

                Text(displayTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                introTextView

                Text("Characters: NARRATOR")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)

                Color.clear.frame(height: 180)
            }
            .padding()
        }
        .onAppear {
            didCompleteIntro = false
        }
        .onDisappear {
            didCompleteIntro = true
            stopIntroAudio()
        }
        .onChange(of: isPlaying) { _, playing in
            syncPlayback(with: playing)
        }
        .onReceive(introTimer) { _ in
            guard let player = introPlayer else { return }
            introCurrentTime = CMTimeGetSeconds(player.currentTime())
        }
    }

    private var hasIntroAudio: Bool {
        guard let path = chapter.chapterIntroAudioUrl else { return false }
        return !path.isEmpty
    }

    private var hasIntroText: Bool {
        !(chapter.chapterIntroText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var hasIntroContent: Bool {
        hasIntroAudio || hasIntroText
    }

    private var chapterNumberLabel: String {
        if chapter.isPrologue { return "Prologue" }
        if chapter.isEpilogue { return "Epilogue" }
        return "Chapter \(chapter.chapterNumber)"
    }

    private var displayTitle: String {
        switch selectedLanguage {
        case .target:
            return chapter.titleTargetLanguage
        case .native:
            let english = chapter.titleEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
            return english.isEmpty ? chapter.titleTargetLanguage : english
        }
    }

    private var displayIntroText: String? {
        let text: String?
        switch selectedLanguage {
        case .target:
            text = chapter.chapterIntroText
        case .native:
            text = chapter.chapterIntroTextEnglish ?? chapter.chapterIntroText
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    @ViewBuilder
    private var introTextView: some View {
        if let intro = displayIntroText {
            if selectedLanguage == .target,
               let timings = chapter.chapterIntroWordTimings, !timings.isEmpty,
               chapter.chapterIntroAudioUrl != nil {
                TimedTextView(
                    segment: StorySegmentTiming(
                        speaker: "",
                        text: intro,
                        startTime: 0,
                        endTime: .greatestFiniteMagnitude,
                        timings: timings
                    ),
                    currentTime: introCurrentTime
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let parts = intro.components(separatedBy: "\n\n")
                if let quote = parts.first {
                    Text(quote)
                        .font(.title3)
                        .italic()
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                        .overlay(
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: 4),
                            alignment: .leading
                        )
                }
                if parts.count > 1 {
                    Text(parts.dropFirst().joined(separator: "\n\n"))
                        .font(.body)
                        .foregroundStyle(selectedLanguage == .native ? .secondary : .primary)
                        .padding(.top, 8)
                }
            }
        }
    }

    private func syncPlayback(with playing: Bool) {
        if playing {
            startIntroPlaybackIfNeeded()
        } else {
            pauseIntroAudio()
        }
    }

    private func startIntroPlaybackIfNeeded() {
        if introPlayer != nil {
            introPlayer?.play()
            return
        }
        if synthesizer.isSpeaking || synthesizer.isPaused {
            if synthesizer.isPaused {
                synthesizer.continueSpeaking()
            }
            return
        }
        if hasIntroAudio {
            startIntroPlayer()
        } else if hasIntroText {
            startTTS()
        } else {
            finishIntro()
        }
    }

    private func startIntroPlayer() {
        guard let path = chapter.chapterIntroAudioUrl, !path.isEmpty else {
            finishIntro()
            return
        }

        isLoadingAudio = true
        Task {
            do {
                let data = try await authManager.supabase.storage
                    .from("audio-stories")
                    .download(path: path)

                let ext = path.hasSuffix(".mp3") ? "mp3" : "m4a"
                let tmpURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("chapter_intro_\(UUID().uuidString).\(ext)")
                try data.write(to: tmpURL)

                await MainActor.run {
                    activateIntroPlayer(url: tmpURL)
                }
                return
            } catch {
                print("[ChapterInfoCard] download() failed: \(error) — trying signed URL")
            }

            do {
                let signedURL = try await authManager.supabase.storage
                    .from("audio-stories")
                    .createSignedURL(path: path, expiresIn: 3600)

                await MainActor.run {
                    activateIntroPlayer(url: signedURL)
                }
                return
            } catch {
                print("[ChapterInfoCard] createSignedURL() failed: \(error) — falling back to TTS")
            }

            await MainActor.run {
                isLoadingAudio = false
                if hasIntroText {
                    startTTS()
                } else {
                    finishIntro()
                }
            }
        }
    }

    private func activateIntroPlayer(url: URL) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let player = AVPlayer(url: url)
        introPlayer = player
        isLoadingAudio = false
        registerIntroEndObserver(for: player)
        player.play()
    }

    private func registerIntroEndObserver(for player: AVPlayer) {
        if let introEndObserver {
            NotificationCenter.default.removeObserver(introEndObserver)
        }
        introEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            finishIntro()
        }
    }

    private func pauseIntroAudio() {
        introPlayer?.pause()
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
        }
    }

    private func stopIntroAudio() {
        if let introEndObserver {
            NotificationCenter.default.removeObserver(introEndObserver)
            self.introEndObserver = nil
        }
        introPlayer?.pause()
        introPlayer = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func finishIntro() {
        guard !didCompleteIntro else { return }
        didCompleteIntro = true
        stopIntroAudio()
        isPlaying = false
        onIntroFinished()
    }

    private func bcp47Code(for code: String) -> String {
        switch code {
        case "es": return "es-MX"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "fr": return "fr-FR"
        case "vi": return "vi-VN"
        case "en": return "en-US"
        default:   return code
        }
    }

    private func startTTS() {
        var utteranceText = chapter.titleTargetLanguage
        if let intro = chapter.chapterIntroText, !intro.isEmpty {
            utteranceText += ". " + intro
        }

        let utterance = AVSpeechUtterance(string: utteranceText)
        utterance.voice = AVSpeechSynthesisVoice(language: bcp47Code(for: languageCode))
        utterance.rate = 0.5

        synthesizer.speak(utterance)
        DispatchQueue.main.asyncAfter(deadline: .now() + estimatedSpeechDuration(for: utteranceText)) {
            guard isPlaying else { return }
            finishIntro()
        }
    }

    private func estimatedSpeechDuration(for text: String) -> TimeInterval {
        max(2.0, Double(text.count) * 0.06)
    }
}

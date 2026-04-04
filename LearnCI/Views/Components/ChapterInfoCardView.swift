import SwiftUI
import AVFoundation
import Combine
import Supabase

/// Displays chapter information before playback starts.
/// When `chapter.chapterIntroAudioUrl` is present the intro audio streams and
/// words highlight in sync using `chapterIntroWordTimings`. Otherwise the card
/// falls back to AVSpeechSynthesizer TTS.
struct ChapterInfoCardView: View {
    let chapter: StoryChapter
    let heroImage: UIImage?
    let languageCode: String
    let onContinue: () -> Void

    @Environment(AuthManager.self) private var authManager

    // TTS fallback
    @State private var synthesizer = AVSpeechSynthesizer()

    // Intro audio playback
    @State private var introPlayer: AVPlayer?
    @State private var introCurrentTime: Double = 0
    @State private var isIntroPlaying: Bool = false
    @State private var isLoadingAudio: Bool = false

    // 20 Hz timer — only meaningful when intro audio is active
    let introTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Hero image or gradient placeholder with play/pause button overlay
            ZStack(alignment: .bottom) {
                if let img = heroImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 250)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [.accentColor, .accentColor.opacity(0.6)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(height: 250)
                }

                // Play / Pause / Loading button
                if hasIntroAudio {
                    Button(action: toggleIntroAudio) {
                        if isLoadingAudio {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(2)
                                .frame(width: 64, height: 64)
                        } else {
                            Image(systemName: isIntroPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.white, .white.opacity(0.3))
                                .shadow(radius: 8)
                        }
                    }
                    .disabled(isLoadingAudio)
                    .padding(.bottom, 24)
                }
            }
            .frame(height: 250)

            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Chapter Title
                        Text(chapter.titleTargetLanguage)
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top, 24)

                        // Intro content — highlighted if audio+timings available, styled text otherwise
                        introTextView

                        // Characters involved
                        Text("Characters: NARRATOR")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .padding(.bottom, 16)
                    }
                }

                Button(action: {
                    stopIntroAudio()
                    onContinue()
                }) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }
                .padding(.bottom, 32)
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .background(Color(.systemBackground))
        }
        .onDisappear {
            stopIntroAudio()
        }
        .onReceive(introTimer) { _ in
            guard let player = introPlayer else { return }
            introCurrentTime = CMTimeGetSeconds(player.currentTime())
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Helpers

    private var hasIntroAudio: Bool {
        guard let path = chapter.chapterIntroAudioUrl else { return false }
        return !path.isEmpty
    }

    // MARK: - Intro Text View

    @ViewBuilder
    private var introTextView: some View {
        if let intro = chapter.chapterIntroText, !intro.isEmpty {
            if let timings = chapter.chapterIntroWordTimings, !timings.isEmpty,
               chapter.chapterIntroAudioUrl != nil {
                // Synchronized word-highlight view
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
                // Styled fallback: quote + orientation text
                let parts = intro.components(separatedBy: "\n\n")
                if let quote = parts.first {
                    Text(quote)
                        .font(.title3)
                        .italic()
                        .foregroundColor(.secondary)
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
                        .padding(.top, 8)
                }
            }
        }
    }

    // MARK: - Audio

    private func toggleIntroAudio() {
        if isIntroPlaying {
            // Pause
            introPlayer?.pause()
            if synthesizer.isSpeaking { synthesizer.pauseSpeaking(at: .word) }
            isIntroPlaying = false
        } else {
            // Play or resume
            if introPlayer != nil {
                // Already loaded — just resume
                introPlayer?.play()
                isIntroPlaying = true
            } else if hasIntroAudio {
                startIntroPlayer()
            } else {
                startTTS()
            }
        }
    }

    private func startIntroPlayer() {
        guard let path = chapter.chapterIntroAudioUrl, !path.isEmpty else { return }

        isLoadingAudio = true
        print("[ChapterInfoCard] Preparing intro audio path: \(path)")

        Task {
            // Strategy 1: authenticated .download() → temp file → AVPlayer
            do {
                let data = try await authManager.supabase.storage
                    .from("audio-stories")
                    .download(path: path)

                let ext = path.hasSuffix(".mp3") ? "mp3" : "m4a"
                let tmpURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("chapter_intro_\(UUID().uuidString).\(ext)")
                try data.write(to: tmpURL)
                print("[ChapterInfoCard] Downloaded \(data.count / 1024)KB → playing from temp file")

                await MainActor.run {
                    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                    try? AVAudioSession.sharedInstance().setActive(true)
                    introPlayer = AVPlayer(url: tmpURL)
                    introPlayer?.play()
                    isIntroPlaying = true
                    isLoadingAudio = false
                }
                return
            } catch {
                print("[ChapterInfoCard] download() failed: \(error) — trying signed URL")
            }

            // Strategy 2: createSignedURL → stream via AVPlayer (no download needed)
            do {
                let signedURL = try await authManager.supabase.storage
                    .from("audio-stories")
                    .createSignedURL(path: path, expiresIn: 3600)

                print("[ChapterInfoCard] Signed URL obtained — streaming")
                await MainActor.run {
                    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                    try? AVAudioSession.sharedInstance().setActive(true)
                    introPlayer = AVPlayer(url: signedURL)
                    introPlayer?.play()
                    isIntroPlaying = true
                    isLoadingAudio = false
                }
                return
            } catch {
                print("[ChapterInfoCard] createSignedURL() failed: \(error) — falling back to TTS")
            }

            // Strategy 3: TTS fallback
            await MainActor.run {
                isLoadingAudio = false
                startTTS()
            }
        }
    }

    private func stopIntroAudio() {
        introPlayer?.pause()
        introPlayer = nil
        isIntroPlaying = false
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    // MARK: - TTS Fallback

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
        isIntroPlaying = true
    }
}

import SwiftUI
import AVFoundation

/// Stage 4 — Shadow the scene in paragraph-sized chunks. The scene image sits
/// at the top; below it, one card per chunk with its own Play / Record / Mine
/// controls, so the learner can hear a chunk, pause, say it aloud, record and
/// compare — without scrolling away from the text they're speaking.
struct StoryShadowingStageView: View {
    @Bindable var vm: StoryPathSessionViewModel

    @Environment(AudioManager.self) private var audioManager
    @State private var recorder = ShadowRecordingManager()

    @State private var permissionSheet: PermissionState = .idle
    @State private var chunkStates: [String: ChunkState] = [:]
    @State private var chunks: [ShadowChunk] = []
    @State private var sceneAudioURL: URL?
    @State private var sceneImageURL: URL?
    @State private var playingChunkID: String?
    @State private var segmentTimer: Timer?
    @State private var showMicExplainer: Bool = false
    @State private var pendingChunkID: String?

    private enum PermissionState: Equatable {
        case idle, prompting, denied
    }

    private struct ChunkState {
        var didRecord: Bool = false
        var recordingURL: URL? = nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    heroImage
                    intro
                    ForEach(chunks) { chunk in
                        chunkCard(chunk)
                    }
                    if chunks.isEmpty {
                        ContentUnavailableView(
                            "No audio yet",
                            systemImage: "waveform.slash",
                            description: Text("This scene doesn't have audio available for shadowing.")
                        )
                        .padding(.top, 32)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            StoryPathBottomBar(
                primaryTitle: "Finish Scene",
                primaryEnabled: true,
                primaryAction: onContinue,
                caption: bottomCaption,
                confirmMessage: "You'll finish this scene. You can come back with the ← button."
            )
        }
        .onAppear { bootstrap() }
        .onDisappear { teardownAudio() }
        .sheet(isPresented: $showMicExplainer) {
            MicExplainerSheet(
                onContinue: {
                    showMicExplainer = false
                    beginRecordingAfterExplainer()
                },
                onCancel: {
                    showMicExplainer = false
                    pendingChunkID = nil
                }
            )
            .presentationDetents([.height(340)])
        }
        .alert("Microphone access needed", isPresented: Binding(get: { permissionSheet == .denied }, set: { _ in permissionSheet = .idle })) {
            Button("OK", role: .cancel) {}
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Enable microphone access in Settings to shadow. You can also skip this stage.")
        }
    }

    private var recordedCount: Int {
        chunks.filter { chunkStates[$0.id]?.didRecord == true }.count
    }

    private var bottomCaption: String {
        if chunks.isEmpty { return "No audio for this scene — skip ahead." }
        if recordedCount == 0 { return "Play a chunk, pause, say it out loud. Record to compare — or skip." }
        return "Recorded \(recordedCount) of \(chunks.count) chunk\(chunks.count == 1 ? "" : "s")."
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var header: some View {
        HStack {
            Label("Shadow in \(chunks.count) chunk\(chunks.count == 1 ? "" : "s")", systemImage: "mic.fill")
                .font(.subheadline.weight(.medium))
            Spacer()
            Text("\(recordedCount) of \(chunks.count) done")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    @ViewBuilder
    private var heroImage: some View {
        if let url = sceneImageURL {
            CachedAsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .overlay(ProgressView())
            }
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Say it out loud")
                .font(.title3.weight(.semibold))
            Text("Each card is one chunk of the scene. Play it, then repeat aloud. Record yourself and compare.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func chunkCard(_ chunk: ShadowChunk) -> some View {
        let state = chunkStates[chunk.id] ?? ChunkState()
        let isRecordingThis = recorder.isRecording && recorder.currentLineID == chunk.id
        let isPlayingThis = playingChunkID == chunk.id && audioManager.isStreaming

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Chunk \(chunk.index + 1) of \(chunks.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if state.didRecord {
                    Label("Recorded", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Text(chunk.text)
                .font(.system(size: 19, design: .serif))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 24) {
                ChunkIconButton(
                    systemImage: isPlayingThis ? "pause.fill" : "play.fill",
                    tint: .accentColor,
                    isProminent: false,
                    accessibility: isPlayingThis ? "Pause" : "Play chunk"
                ) {
                    togglePlay(chunk)
                }

                ChunkIconButton(
                    systemImage: isRecordingThis ? "stop.fill" : "mic.fill",
                    tint: isRecordingThis ? .red : .accentColor,
                    isProminent: true,
                    accessibility: isRecordingThis ? "Stop recording" : "Record yourself"
                ) {
                    toggleRecord(chunk)
                }

                ChunkIconButton(
                    systemImage: "waveform",
                    tint: .accentColor,
                    isProminent: false,
                    accessibility: "Play my recording"
                ) {
                    playMine(chunk)
                }
                .disabled(state.recordingURL == nil)
                .opacity(state.recordingURL == nil ? 0.35 : 1)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isPlayingThis || isRecordingThis ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
        )
    }

    // MARK: - Playback

    /// Play this chunk's segment of the scene audio (word-timing time range),
    /// or pause if it's currently playing.
    private func togglePlay(_ chunk: ShadowChunk) {
        recorder.stopPlayback()

        if playingChunkID == chunk.id, audioManager.isStreaming {
            audioManager.pauseStream()
            stopSegmentTimer()
            playingChunkID = nil
            return
        }

        guard let url = sceneAudioURL else { return }
        stopSegmentTimer()
        audioManager.onStreamFinished = {
            playingChunkID = nil
            stopSegmentTimer()
        }
        audioManager.streamAudio(url: url, startAt: chunk.startTime ?? 0)
        audioManager.playStream()
        playingChunkID = chunk.id
        if let end = chunk.endTime {
            startSegmentTimer(end: end)
        }
    }

    /// Poll the stream clock and pause at the chunk's end time.
    private func startSegmentTimer(end: Double) {
        segmentTimer?.invalidate()
        segmentTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                if audioManager.streamCurrentTime >= end - 0.05 {
                    audioManager.pauseStream()
                    playingChunkID = nil
                    stopSegmentTimer()
                }
            }
        }
    }

    private func stopSegmentTimer() {
        segmentTimer?.invalidate()
        segmentTimer = nil
    }

    private func stopScenePlayback() {
        stopSegmentTimer()
        audioManager.stopStream()
        playingChunkID = nil
    }

    // MARK: - Recording

    private func toggleRecord(_ chunk: ShadowChunk) {
        if recorder.isRecording {
            if let url = recorder.stopRecording() {
                var state = chunkStates[chunk.id] ?? ChunkState()
                state.didRecord = true
                state.recordingURL = url
                chunkStates[chunk.id] = state
                vm.recordShadowLineDone(chunk.id)
            }
            return
        }

        switch recorder.micPermission {
        case .granted:
            stopScenePlayback()
            _ = recorder.startRecording(storyID: vm.story.id.uuidString, lineID: chunk.id)
        case .undetermined:
            pendingChunkID = chunk.id
            showMicExplainer = true
        case .denied:
            permissionSheet = .denied
        }
    }

    private func beginRecordingAfterExplainer() {
        guard let chunkID = pendingChunkID else { return }
        Task {
            let granted = await recorder.requestMicPermission()
            await MainActor.run {
                pendingChunkID = nil
                if granted {
                    stopScenePlayback()
                    _ = recorder.startRecording(storyID: vm.story.id.uuidString, lineID: chunkID)
                } else {
                    permissionSheet = .denied
                }
            }
        }
    }

    private func playMine(_ chunk: ShadowChunk) {
        guard let url = chunkStates[chunk.id]?.recordingURL else { return }
        stopScenePlayback()
        recorder.playRecording(at: url)
    }

    private func onContinue() {
        recorder.stopPlayback()
        recorder.restorePlaybackSession()
        stopScenePlayback()
        vm.advanceToNextStage()
    }

    private func teardownAudio() {
        recorder.stopPlayback()
        stopScenePlayback()
    }

    // MARK: - Chunk building

    private func bootstrap() {
        let adapter = StoryReaderDataAdapter(story: vm.story)
        guard let clip = adapter
            .audioClips(forChapter: vm.chunkChapterArrayIndex)
            .first(where: { $0.sceneIndex == vm.chunkSceneIndex })
        else {
            chunks = []
            return
        }

        sceneImageURL = clip.imageURL
        sceneAudioURL = StoryReaderDataAdapter.cachedAudioURL(
            storyID: vm.story.id,
            clip: clip,
            storyUpdatedAt: vm.story.updatedAt
        ) ?? StoryReaderDataAdapter.remoteAudioURL(for: clip.urlString)

        let text = clip.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, sceneAudioURL != nil else {
            chunks = []
            return
        }

        chunks = Self.buildChunks(
            sceneText: text,
            timings: vm.chunkWordTimings,
            idPrefix: "\(vm.currentChunk?.chapterNumber ?? 0)-\(clip.sceneIndex)"
        )

        // Restore any existing recordings for these chunks.
        for chunk in chunks {
            let existing = recorder.existingRecordingURL(storyID: vm.story.id.uuidString, lineID: chunk.id)
            var state = ChunkState()
            if let existing {
                state.didRecord = true
                state.recordingURL = existing
                vm.recordShadowLineDone(chunk.id)
            }
            chunkStates[chunk.id] = state
        }
    }

    /// Split the scene text into paragraph-sized chunks and map each to a time
    /// range in the scene audio using word timings (same \p{L}+ word order as
    /// `TimedTextView`). Chunks without timing coverage get nil times and play
    /// the whole scene audio from their best-known start.
    static func buildChunks(sceneText: String, timings: [WordTiming], idPrefix: String) -> [ShadowChunk] {
        let paragraphs = splitIntoParagraphs(sceneText)
        var result: [ShadowChunk] = []
        var wordCursor = 0

        for (index, para) in paragraphs.enumerated() {
            let count = wordCount(in: para)
            let startIdx = wordCursor
            let endIdx = wordCursor + count - 1
            wordCursor += count

            var start: Double? = nil
            var end: Double? = nil
            if count > 0, startIdx < timings.count {
                start = timings[startIdx].start
                if endIdx < timings.count {
                    end = timings[endIdx].end
                }
            }

            result.append(
                ShadowChunk(
                    id: "\(idPrefix)-p\(index)",
                    index: index,
                    text: para,
                    startTime: start,
                    endTime: end
                )
            )
        }
        return result
    }

    private static func splitIntoParagraphs(_ text: String) -> [String] {
        var parts = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Single-block scenes: group sentences into pairs so chunks stay short
        // enough to say in one breath or two.
        if parts.count <= 1 {
            let sentences = splitSentences(text)
            if sentences.count > 2 {
                parts = stride(from: 0, to: sentences.count, by: 2).map { start in
                    sentences[start..<min(start + 2, sentences.count)].joined(separator: " ")
                }
            }
        }
        return parts.isEmpty ? [text] : parts
    }

    private static func splitSentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ".!?。！？".contains(ch) {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { result.append(trimmed) }
                current = ""
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { result.append(trimmed) }
        return result
    }

    /// Counts words with the same \p{L}+ pattern `TimedTextView` uses, so word
    /// indices line up with `WordTiming` order.
    private static func wordCount(in text: String) -> Int {
        let regex = try? NSRegularExpression(pattern: "\\p{L}+")
        let ns = text as NSString
        return regex?.numberOfMatches(in: text, range: NSRange(location: 0, length: ns.length)) ?? 0
    }
}

/// Compact circular icon button for the chunk cards (play / record / listen).
private struct ChunkIconButton: View {
    let systemImage: String
    let tint: Color
    let isProminent: Bool
    let accessibility: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isProminent ? Color.white : tint)
                .frame(width: 44, height: 44)
                .background(isProminent ? tint : tint.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }
}

struct ShadowChunk: Identifiable, Equatable {
    let id: String
    let index: Int
    let text: String
    /// Segment bounds within the scene audio (seconds); nil when word timings
    /// don't cover this chunk — playback then runs from startTime (or 0) to the
    /// end of the scene audio.
    let startTime: Double?
    let endTime: Double?
}

/// One-time friendly explainer shown before the OS microphone prompt.
private struct MicExplainerSheet: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 28)

            Text("Record your speaking")
                .font(.title3.weight(.semibold))

            Text("Shadowing means saying a chunk out loud and comparing it to the original. LearnCI needs microphone access to record you. Recordings stay on your device — they're never uploaded.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 10) {
                Button(action: onContinue) {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onCancel) {
                    Text("Not now").frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}

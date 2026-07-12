import SwiftUI
import AVFoundation

/// Stage 4 — Shadow a couple of passages. Picks two scene-length passages (a
/// paragraph / few sentences) from the current chapter that have audio, and
/// walks the learner through Play → Pause → say it out loud → Record → compare.
struct StoryShadowingStageView: View {
    @Bindable var vm: StoryPathSessionViewModel

    @Environment(AudioManager.self) private var audioManager
    @State private var recorder = ShadowRecordingManager()

    @State private var permissionSheet: PermissionState = .idle
    @State private var lineStates: [String: LineState] = [:]
    @State private var lines: [ShadowLine] = []
    @State private var playingLineID: String?
    @State private var showMicExplainer: Bool = false
    @State private var pendingLineID: String?

    private enum PermissionState: Equatable {
        case idle, prompting, denied
    }

    private struct LineState {
        var didRecord: Bool = false
        var recordingURL: URL? = nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 20) {
                    intro
                    ForEach(Array(lines.enumerated()), id: \.element.id) { pair in
                        lineCard(index: pair.offset, line: pair.element)
                    }
                    if lines.isEmpty {
                        ContentUnavailableView(
                            "No audio yet",
                            systemImage: "waveform.slash",
                            description: Text("This chapter doesn't have scene audio available for shadowing.")
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
                caption: vm.shadowRecordedLineIDs.isEmpty
                    ? "Play the passage, pause, and say it out loud. Record to compare — or skip."
                    : "Recorded this passage. Nice speaking practice!",
                confirmMessage: "You'll finish this scene. You can come back with the ← button."
            )
        }
        .onAppear { bootstrap() }
        .onDisappear {
            recorder.stopPlayback()
            audioManager.stopStream()
        }
        .sheet(isPresented: $showMicExplainer) {
            MicExplainerSheet(
                onContinue: {
                    showMicExplainer = false
                    beginRecordingAfterExplainer()
                },
                onCancel: {
                    showMicExplainer = false
                    pendingLineID = nil
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
            Text("Enable microphone access in Settings to shadow passages. You can also skip this stage.")
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var header: some View {
        HStack {
            Label("Shadow \(lines.count) passage\(lines.count == 1 ? "" : "s")", systemImage: "mic.fill")
                .font(.subheadline.weight(.medium))
            Spacer()
            Text("\(vm.shadowRecordedLineIDs.count) of \(lines.count) done")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    @ViewBuilder
    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Say it out loud")
                .font(.title3.weight(.semibold))
            Text("Press play to hear a passage, pause it, then repeat it aloud. Record yourself and compare — retake as many times as you like.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lineCard(index: Int, line: ShadowLine) -> some View {
        let state = lineStates[line.id] ?? LineState()
        let isRecordingThisLine = recorder.isRecording && recorder.currentLineID == line.id
        let isPlayingThis = playingLineID == line.id && audioManager.isStreaming

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Passage \(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if state.didRecord {
                    Label("Recorded", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            if let imageURL = line.imageURL {
                CachedAsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color(uiColor: .tertiarySystemFill))
                }
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Text(line.text)
                .font(.system(size: 19, design: .serif))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    togglePlayOriginal(line)
                } label: {
                    Label(isPlayingThis ? "Pause" : "Play", systemImage: isPlayingThis ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    toggleRecord(line)
                } label: {
                    Label(isRecordingThisLine ? "Stop" : "Record", systemImage: isRecordingThisLine ? "stop.fill" : "record.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isRecordingThisLine ? .red : .accentColor)
                .controlSize(.regular)

                Button {
                    playMine(line)
                } label: {
                    Label("Mine", systemImage: "waveform").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(state.recordingURL == nil)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    // MARK: - Actions

    private func bootstrap() {
        lines = chooseLines()
        for line in lines {
            let existing = recorder.existingRecordingURL(storyID: vm.story.id.uuidString, lineID: line.id)
            var state = LineState()
            if let existing {
                state.didRecord = true
                state.recordingURL = existing
                vm.recordShadowLineDone(line.id)
            }
            lineStates[line.id] = state
        }
    }

    /// Play, pause, or resume the original narration for a passage so the
    /// learner can listen, stop, and repeat aloud.
    private func togglePlayOriginal(_ line: ShadowLine) {
        recorder.stopPlayback()

        // Same passage currently playing → pause.
        if playingLineID == line.id, audioManager.isStreaming {
            audioManager.pauseStream()
            return
        }
        // Same passage, loaded but paused → resume.
        if playingLineID == line.id, audioManager.streamPlayer != nil {
            audioManager.playStream()
            return
        }
        // Different (or first) passage → load and play.
        guard let url = line.audioURL else { return }
        audioManager.onStreamFinished = {
            playingLineID = nil
        }
        audioManager.streamAudio(url: url)
        audioManager.playStream()
        playingLineID = line.id
    }

    private func toggleRecord(_ line: ShadowLine) {
        if recorder.isRecording {
            if let url = recorder.stopRecording() {
                var state = lineStates[line.id] ?? LineState()
                state.didRecord = true
                state.recordingURL = url
                lineStates[line.id] = state
                vm.recordShadowLineDone(line.id)
            }
            return
        }

        // Permission gate
        switch recorder.micPermission {
        case .granted:
            stopOriginalPlayback()
            _ = recorder.startRecording(storyID: vm.story.id.uuidString, lineID: line.id)
        case .undetermined:
            // Friendly explainer before the system permission prompt.
            pendingLineID = line.id
            showMicExplainer = true
        case .denied:
            permissionSheet = .denied
        }
    }

    private func beginRecordingAfterExplainer() {
        guard let lineID = pendingLineID else { return }
        Task {
            let granted = await recorder.requestMicPermission()
            await MainActor.run {
                pendingLineID = nil
                if granted {
                    stopOriginalPlayback()
                    _ = recorder.startRecording(storyID: vm.story.id.uuidString, lineID: lineID)
                } else {
                    permissionSheet = .denied
                }
            }
        }
    }

    private func playMine(_ line: ShadowLine) {
        guard let url = lineStates[line.id]?.recordingURL else { return }
        stopOriginalPlayback()
        recorder.playRecording(at: url)
    }

    private func stopOriginalPlayback() {
        audioManager.stopStream()
        playingLineID = nil
    }

    private func onContinue() {
        recorder.stopPlayback()
        recorder.restorePlaybackSession()
        audioManager.stopStream()
        vm.advanceToNextStage()
    }

    // MARK: - Passage selection

    /// The passage to shadow is the current Study Mode chunk (this scene). If
    /// the scene has no audio clip, returns empty.
    private func chooseLines() -> [ShadowLine] {
        let adapter = StoryReaderDataAdapter(story: vm.story)
        guard let clip = adapter
            .audioClips(forChapter: vm.chunkChapterArrayIndex)
            .first(where: { $0.sceneIndex == vm.chunkSceneIndex })
        else {
            return []
        }

        let text = clip.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        let url = StoryReaderDataAdapter.cachedAudioURL(
            storyID: vm.story.id,
            clip: clip,
            storyUpdatedAt: vm.story.updatedAt
        ) ?? StoryReaderDataAdapter.remoteAudioURL(for: clip.urlString)
        guard let url else { return [] }

        return [
            ShadowLine(
                id: "\(vm.currentChunk?.chapterNumber ?? 0)-\(clip.sceneIndex)",
                text: text,
                audioURL: url,
                imageURL: clip.imageURL,
                wordCount: text.split(whereSeparator: { $0.isWhitespace }).count
            )
        ]
    }
}

private struct ShadowLine: Identifiable, Hashable {
    let id: String
    let text: String
    let audioURL: URL?
    let imageURL: URL?
    let wordCount: Int
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

            Text("Shadowing means saying a passage out loud and comparing it to the original. LearnCI needs microphone access to record you. Recordings stay on your device — they're never uploaded.")
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

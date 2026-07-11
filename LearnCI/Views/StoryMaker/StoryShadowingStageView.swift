import SwiftUI
import AVFoundation

/// Stage 4 — Shadow two lines. Auto-picks two short scenes from the current
/// chapter that have generated audio, and walks the user through Play →
/// Record → Play Mine → Retake for each.
struct StoryShadowingStageView: View {
    @Bindable var vm: StoryPathSessionViewModel

    @Environment(AudioManager.self) private var audioManager
    @State private var recorder = ShadowRecordingManager()

    @State private var permissionSheet: PermissionState = .idle
    @State private var lineStates: [String: LineState] = [:]
    @State private var lines: [ShadowLine] = []
    @State private var currentIndex: Int = 0

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
                primaryTitle: canAdvance ? "Continue to Plan" : "Continue",
                primaryEnabled: true,
                primaryAction: onContinue,
                secondaryTitle: nil,
                secondaryAction: nil,
                caption: canAdvance
                    ? "Great — you've recorded \(vm.shadowRecordedLineIDs.count) of \(lines.count)."
                    : "Record each line, then compare. Skip anytime."
            )
        }
        .onAppear { bootstrap() }
        .onDisappear {
            recorder.stopPlayback()
            audioManager.stopStream()
        }
        .alert("Microphone access needed", isPresented: Binding(get: { permissionSheet == .denied }, set: { _ in permissionSheet = .idle })) {
            Button("OK", role: .cancel) {}
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Enable microphone access in Settings to shadow lines. You can also skip this stage.")
        }
    }

    private var canAdvance: Bool { true }

    // MARK: - Sub-views

    @ViewBuilder
    private var header: some View {
        HStack {
            Label("Shadow \(lines.count) line\(lines.count == 1 ? "" : "s")", systemImage: "mic.fill")
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
            Text("Listen, then repeat as closely as you can. Record yourself, compare, retake if you want.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lineCard(index: Int, line: ShadowLine) -> some View {
        let state = lineStates[line.id] ?? LineState()
        let isCurrent = currentIndex == index
        let isRecordingThisLine = recorder.isRecording && recorder.currentLineID == line.id

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Line \(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if state.didRecord {
                    Label("Recorded", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Text(line.text)
                .font(.system(size: 20, design: .serif))
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                Button {
                    playOriginal(line)
                } label: {
                    Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
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
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isCurrent ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 2)
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

    private func playOriginal(_ line: ShadowLine) {
        recorder.stopPlayback()
        if let url = line.audioURL {
            audioManager.streamRepeatCount = 1
            audioManager.streamAudio(url: url)
            audioManager.playStream()
        }
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
            audioManager.stopStream()
            _ = recorder.startRecording(storyID: vm.story.id.uuidString, lineID: line.id)
        case .undetermined:
            permissionSheet = .prompting
            Task {
                let granted = await recorder.requestMicPermission()
                await MainActor.run {
                    if granted {
                        permissionSheet = .idle
                        audioManager.stopStream()
                        _ = recorder.startRecording(storyID: vm.story.id.uuidString, lineID: line.id)
                    } else {
                        permissionSheet = .denied
                    }
                }
            }
        case .denied:
            permissionSheet = .denied
        }
    }

    private func playMine(_ line: ShadowLine) {
        guard let url = lineStates[line.id]?.recordingURL else { return }
        audioManager.stopStream()
        recorder.playRecording(at: url)
    }

    private func onContinue() {
        recorder.stopPlayback()
        recorder.restorePlaybackSession()
        audioManager.stopStream()
        vm.advanceToNextStage()
    }

    // MARK: - Line selection

    private func chooseLines() -> [ShadowLine] {
        guard let chapter = vm.chapter else { return [] }
        let langCode = vm.story.targetLanguageCode
        let candidates = chapter.scenes
            .sorted { $0.sceneIndex < $1.sceneIndex }
            .compactMap { scene -> ShadowLine? in
                let text = scene.captionFor(langCode).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
                guard wordCount >= 4 else { return nil }
                guard let audioUrlString = scene.audioUrlForLanguage(langCode),
                      let url = URL(string: audioUrlString) else { return nil }
                return ShadowLine(
                    id: "\(chapter.chapterNumber)-\(scene.sceneIndex)",
                    text: text,
                    audioURL: url,
                    wordCount: wordCount
                )
            }
        // Pick shortest 2 for the least intimidating first attempt.
        let picked = candidates.sorted { $0.wordCount < $1.wordCount }.prefix(vm.shadowLineCount)
        return picked.sorted { $0.id < $1.id }
    }
}

private struct ShadowLine: Identifiable, Hashable {
    let id: String
    let text: String
    let audioURL: URL?
    let wordCount: Int
}

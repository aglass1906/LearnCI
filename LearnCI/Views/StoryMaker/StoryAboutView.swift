import SwiftUI
import SwiftData

struct StoryAboutView: View {
    let story: Story

    @Environment(\.modelContext) private var modelContext
    @Environment(AmbientSoundManager.self) private var ambientSoundManager

    // Hero image state
    @State private var heroImage: UIImage? = nil

    // Story / audio regeneration
    @State private var storyManager = StoryManager()

    // Video generation
    @State private var isGeneratingVideo: Bool = false
    @State private var videoGenerationError: String? = nil
    @State private var videoStatusMessage: String? = nil
    private let veoService = VeoService()
    private let openAIService = OpenAIService()

    // Sheet presentation
    @State private var showStoryInfo = false
    @State private var showPromptDetails = false
    @State private var showVideoGenerator = false
    @State private var showAmbientPicker = false

    // Quiz navigation (from menu shortcut)
    @State private var navigateToQuiz = false

    var body: some View {
        GeometryReader { fullGeo in
            scrollContent(heroHeight: fullGeo.size.height * 0.42)
        }
    }

    @ViewBuilder
    private func scrollContent(heroHeight: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── Hero Media ────────────────────────────────────────────
                HeroMediaView(
                    story: story,
                    image: $heroImage,
                    isGeneratingVideo: isGeneratingVideo,
                    videoStatus: videoStatusMessage,
                    videoError: videoGenerationError,
                    onGenerateVideo: { showVideoGenerator = true },
                    showGenerateButton: false
                )
                .frame(height: heroHeight)
                .clipped()

                // ── Regeneration Status Banner ────────────────────────────
                if storyManager.isGenerating, let status = storyManager.statusMessage {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text(status)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                }

                // ── Story Details ─────────────────────────────────────────
                VStack(alignment: .leading, spacing: 20) {

                    // Title
                    Text(story.title)
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .padding(.top, 24)

                    // Metadata badges
                    HStack(spacing: 8) {
                        Label(story.language.displayName, systemImage: "globe")
                            .badgeStyle()
                        Label(LevelManager.shared.description(for: story.level), systemImage: "chart.bar")
                            .badgeStyle()
                        if let wordCount = storyWordCount {
                            Label(wordCount, systemImage: "doc.text")
                                .badgeStyle()
                        }
                    }

                    Divider()

                    // Story teaser (first ~200 chars of target text)
                    if !storyTeaser.isEmpty {
                        Text(storyTeaser)
                            .font(.system(size: 17, weight: .regular, design: .serif))
                            .foregroundColor(.secondary)
                            .lineSpacing(6)
                    }

                    Divider()

                    // ── Ambient Sound ─────────────────────────────────────
                    AmbientSoundRow(story: story, onChangeTap: { showAmbientPicker = true })

                    Divider()

                    // ── Call to action buttons ────────────────────────────
                    VStack(spacing: 12) {
                        // Start Listening
                        NavigationLink(destination: StorySessionView(story: story)) {
                            HStack {
                                Image(systemName: "headphones")
                                    .font(.title3)
                                Text("Start Listening")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                        }

                        // Take Quiz
                        NavigationLink(destination: StoryQuizView(story: story)) {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                    .font(.title3)
                                Text("Take Quiz")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .foregroundColor(.primary)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.bottom, 40)
                }
                .padding(.horizontal)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        // Hide tab bar for the entire immersive story flow
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showStoryInfo = true } label: {
                        Label("Story Info", systemImage: "info.circle")
                    }
                    Button { showPromptDetails = true } label: {
                        Label("View Prompts", systemImage: "text.viewfinder")
                    }

                    Divider()

                    if !storyManager.isGenerating {
                        Button {
                            Task { await storyManager.regenerateStory(for: story, context: modelContext) }
                        } label: {
                            Label("Regenerate Story", systemImage: "arrow.clockwise.circle.fill")
                        }
                        Button {
                            Task { await storyManager.regenerateAudio(for: story, context: modelContext) }
                        } label: {
                            Label("Regenerate Audio", systemImage: "waveform.badge.plus")
                        }
                    } else {
                        Label(storyManager.statusMessage ?? "Working…", systemImage: "ellipsis")
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    NavigationLink(destination: StoryQuizView(story: story)) {
                        Label("Comprehension Quiz", systemImage: "checkmark.circle")
                    }
                    if story.comprehensionQuestionsJSON != nil {
                        Button {
                            story.comprehensionQuestionsJSON = nil
                            try? modelContext.save()
                        } label: {
                            Label("Regenerate Quiz", systemImage: "arrow.clockwise")
                        }
                    }

                    Divider()

                    if !isGeneratingVideo {
                        Button { showVideoGenerator = true } label: {
                            Label(
                                story.remoteVideoPath == nil ? "Generate Scene Video" : "Regenerate Scene Video",
                                systemImage: story.remoteVideoPath == nil ? "video.badge.plus" : "arrow.clockwise.circle"
                            )
                        }
                    }

                    Divider()

                    Button {
                        UIPasteboard.general.string = story.targetLanguageText
                    } label: {
                        Label("Copy Story (\(story.language.displayName))", systemImage: "doc.on.doc")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showStoryInfo) {
            StoryInfoSheet(story: story)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showPromptDetails) {
            StoryPromptsSheet(story: story)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showVideoGenerator) {
            VideoGeneratorSheet(story: story) { style in
                Task { await generateSceneVideo(style: style) }
            }
        }
        .sheet(isPresented: $showAmbientPicker) {
            AmbientSoundPickerSheet(story: story)
                .presentationDetents([.medium, .large])
        }
        .alert("Regeneration Failed", isPresented: Binding(
            get: { storyManager.errorMessage != nil },
            set: { if !$0 { storyManager.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { storyManager.errorMessage = nil }
        } message: {
            Text(storyManager.errorMessage ?? "")
        }
    }

    // MARK: - Helpers

    private var storyTeaser: String {
        let text = story.targetLanguageText
        guard text.count > 200 else { return text }
        let index = text.index(text.startIndex, offsetBy: 200)
        return String(text[..<index]) + "…"
    }

    private var storyWordCount: String? {
        let words = story.targetLanguageText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let count = words.count
        guard count > 0 else { return nil }
        return "\(count) words"
    }

    // MARK: - Scene Video Generation

    @MainActor
    private func generateSceneVideo(style: VideoStyle) async {
        isGeneratingVideo = true
        videoGenerationError = nil
        videoStatusMessage = "Writing cinematic prompt…"

        do {
            // 1. Generate cinematic Veo prompt
            let veoPrompt: String
            if VideoPromptModel.saved == .gemini {
                veoPrompt = try await veoService.generateVeoPrompt(
                    storyText: story.targetLanguageText,
                    style: style.promptStyle
                )
            } else {
                veoPrompt = try await openAIService.generateVeoPrompt(
                    storyText: story.targetLanguageText,
                    style: style.promptStyle
                )
            }

            // 2. Save prompt + style immediately
            story.videoStyle = style.rawValue
            story.videoGenPrompt = veoPrompt
            try? modelContext.save()

            // 3. Call Veo API — polls until done (up to 6 mins)
            let videoData = try await veoService.generateVideo(prompt: veoPrompt) { status in
                Task { @MainActor in self.videoStatusMessage = status }
            }

            // 4. Save video file locally — SyncManager uploads on next sync cycle
            videoStatusMessage = "Saving video…"
            let filename = "video_\(story.id.uuidString).mp4"
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let localURL = docs.appendingPathComponent(filename)
            try videoData.write(to: localURL)
            try? modelContext.save()

        } catch {
            videoGenerationError = error.localizedDescription
        }

        videoStatusMessage = nil
        isGeneratingVideo = false
    }
}

// MARK: - Badge Modifier

private extension View {
    func badgeStyle() -> some View {
        self
            .font(.caption.bold())
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
    }
}

// MARK: - Ambient Sound Row

private struct AmbientSoundRow: View {
    let story: Story
    let onChangeTap: () -> Void

    private var currentSound: AmbientSound {
        AmbientSound.catalog.first { $0.id == story.ambientSoundId } ?? .none
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Label("Ambient Sound", systemImage: "waveform.and.music.mic")
                    .font(.subheadline.bold())
                Text(currentSound.isNone ? "None" : currentSound.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Change", action: onChangeTap)
                .font(.caption.bold())
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Ambient Sound Picker Sheet

private struct AmbientSoundPickerSheet: View {
    let story: Story
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AmbientSoundManager.self) private var ambientSoundManager

    var body: some View {
        NavigationStack {
            List {
                Section("Volume Mix") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "speaker.fill")
                                .foregroundStyle(.secondary)
                            Slider(value: Binding(
                                get: { Double(story.ambientVolume) },
                                set: { story.ambientVolume = Float($0); saveContext() }
                            ), in: 0...1)
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundStyle(.secondary)
                        }
                        Text("Ambient volume: \(Int(story.ambientVolume * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Select Sound") {
                    ForEach(AmbientSound.catalog) { sound in
                        AmbientSoundPickerRow(sound: sound, isSelected: story.ambientSoundId == sound.id) {
                            story.ambientSoundId = sound.id
                            saveContext()
                            if !sound.isNone {
                                Task { try? await ambientSoundManager.ensureDownloaded(sound) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ambient Sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func saveContext() { try? modelContext.save() }
}

private struct AmbientSoundPickerRow: View {
    let sound: AmbientSound
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sound.displayName)
                        .foregroundStyle(.primary)
                    if !sound.isNone && !sound.genreIds.isEmpty {
                        Text(sound.genreIds.prefix(3).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

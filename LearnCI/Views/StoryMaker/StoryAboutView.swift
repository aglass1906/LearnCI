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
    @State private var showRegenerateOptions = false

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
                    
                    // Compact Header Layout
                    HStack(alignment: .top, spacing: 20) {
                        // thumbnail on the left
                        HeroMediaView(
                            story: story,
                            image: $heroImage,
                            isGeneratingVideo: isGeneratingVideo,
                            videoStatus: videoStatusMessage,
                            videoError: videoGenerationError,
                            onGenerateVideo: { showVideoGenerator = true },
                            showGenerateButton: false
                        )
                        .frame(width: 120, height: 160)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            // Title
                            Text(story.title)
                                .font(.system(size: 24, weight: .bold, design: .serif))
                                .fixedSize(horizontal: false, vertical: true)
                            
                            // Character/Setting info if available
                            if !story.preferences.protagonistName.isEmpty {
                                Text("Starring \(story.preferences.protagonistName)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            // Metadata badges
                            FlowLayout(spacing: 8) {
                                Label(story.preferences.genre.rawValue, systemImage: "theatermasks")
                                    .badgeStyle()
                                Label(story.language.displayName, systemImage: "globe")
                                    .badgeStyle()
                                Label(LevelManager.shared.description(for: story.level), systemImage: "chart.bar")
                                    .badgeStyle()
                            }
                        }
                    }
                    .padding(.top, 24)

                    Divider()

                    // Additional Metadata
                    FlowLayout(spacing: 8) {
                        if !story.chapters.isEmpty {
                            Label("\(story.chapters.count) chapters", systemImage: "book.pages")
                                .badgeStyle()
                        }
                        if story.isDramatized {
                            Label("Dramatized", systemImage: "person.2.fill")
                                .badgeStyle()
                        }
                        if let wordCount = storyWordCount {
                            Label(wordCount, systemImage: "doc.text")
                                .badgeStyle()
                        }
                        if story.preferences.interactiveAudio {
                            Label("Interactive", systemImage: "sparkles")
                                .badgeStyle()
                                .foregroundStyle(.purple)
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

                    // ── Chapters ──────────────────────────────────────────
                    if !story.chapters.isEmpty {
                        chapterListSection
                        Divider()
                    }

                    // ── Ambient Sound ─────────────────────────────────────
                    AmbientSoundRow(story: story, onChangeTap: { showAmbientPicker = true })

                    Divider()

                    // ── Call to action buttons ────────────────────────────
                    VStack(spacing: 12) {
                        // Start Listening
                        if story.preferences.interactiveAudio || (story.chapters.count > 1) {
                            NavigationLink(destination: InteractiveStorySessionView(story: story)) {
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text("Start Interactive Session")
                                }
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.purple)
                                .cornerRadius(12)
                            }
                        } else {
                            NavigationLink(destination: StorySessionView(story: story)) {
                                HStack {
                                    Image(systemName: "headphones")
                                    Text("Start Listening")
                                }
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.accentColor)
                                .cornerRadius(12)
                            }
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
                            showRegenerateOptions = true
                        } label: {
                            Label("Regenerate…", systemImage: "arrow.clockwise.circle")
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

                    if !isGeneratingVideo && !storyManager.isGenerating {
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
        .sheet(isPresented: $showRegenerateOptions) {
            RegenerateOptionsSheet(story: story, storyManager: storyManager) { options in
                Task { await storyManager.regenerateSelected(options, for: story, context: modelContext) }
            }
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

    private var chapterListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chapters")
                .font(.headline)
            ForEach(Array(story.chapters.enumerated()), id: \.offset) { index, chapter in
                HStack(alignment: .top, spacing: 12) {
                    let label = chapter.isPrologue ? "P" : chapter.isEpilogue ? "E" : "\(index + 1)"
                    let color = chapter.isPrologue ? Color.orange : (chapter.isEpilogue ? Color.purple : Color.accentColor)
                    
                    Text(label)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(color)
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(chapter.titleTargetLanguage)
                                .font(.subheadline.bold())
                            if chapter.isPrologue {
                                Text("Prologue")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(4)
                            } else if chapter.isEpilogue {
                                Text("Epilogue")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.purple)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                        if let intro = chapter.chapterIntroText ?? chapter.chapterIntroTextEnglish {
                            Text(intro)
                                .font(.caption.italic())
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 2)
                        }
                        if let summary = chapter.plotSummaryEnglish ?? chapter.plotSummaryTarget {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private var storyTeaser: String {
        let text = story.chapters.first?.textTargetLanguage ?? ""
        guard text.count > 200 else { return text }
        let index = text.index(text.startIndex, offsetBy: 200)
        return String(text[..<index]) + "…"
    }

    private var storyWordCount: String? {
        let combined = story.chapters.map { $0.textTargetLanguage }.joined(separator: " ")
        let count = combined.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
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

// MARK: - Regenerate Options Sheet

private struct RegenerateOptionsSheet: View {
    let story: Story
    let storyManager: StoryManager
    var onRegenerate: (RegenerateOptions) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var options = RegenerateOptions()

    var body: some View {
        NavigationStack {
            Form {
                // ── Story Text ────────────────────────────────────────────
                Section {
                    optionRow(
                        icon: "doc.text.fill", color: .blue,
                        title: "Target Language Text",
                        subtitle: "Rewrites the full \(story.language.displayName) story",
                        isOn: $options.targetText
                    )
                    .onChange(of: options.targetText) { _, isOn in
                        if isOn {
                            // Translation and audio must follow new text
                            options.translation = true
                            options.audio = true
                        }
                    }

                    optionRow(
                        icon: "globe", color: .green,
                        title: "English Translation",
                        subtitle: options.targetText
                            ? "Updated automatically with new text"
                            : "Re-translates the existing \(story.language.displayName) text",
                        isOn: $options.translation
                    )
                    .disabled(options.targetText)
                } header: {
                    Text("Story Text")
                } footer: {
                    if options.targetText {
                        Label(
                            "Translation and audio are required when regenerating story text.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                // ── Visuals ───────────────────────────────────────────────
                Section("Visuals") {
                    optionRow(
                        icon: "photo.fill", color: .orange,
                        title: "Cover Art",
                        subtitle: "Generates a new AI illustration",
                        isOn: $options.coverArt
                    )
                }

                // ── Audio ─────────────────────────────────────────────────
                Section {
                    optionRow(
                        icon: "waveform", color: .purple,
                        title: "Story Audio",
                        subtitle: options.targetText
                            ? "Updated automatically with new text"
                            : "Re-voices the story with new audio",
                        isOn: $options.audio
                    )
                    .disabled(options.targetText)
                } header: {
                    Text("Audio")
                }

                // ── Action ────────────────────────────────────────────────
                Section {
                    Button {
                        dismiss()
                        onRegenerate(options)
                    } label: {
                        HStack {
                            Spacer()
                            Label("Regenerate Selected", systemImage: "arrow.clockwise")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!options.hasSelection)
                }
                .listRowBackground(options.hasSelection ? Color.blue : Color.blue.opacity(0.35))
                .foregroundStyle(.white)
            }
            .navigationTitle("Regenerate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func optionRow(
        icon: String, color: Color,
        title: String, subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
        }
    }
}

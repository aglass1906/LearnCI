import SwiftUI
import SwiftData

struct StoryAboutView: View {
    let story: Story

    @Environment(\.modelContext) private var modelContext
    @Environment(AmbientSoundManager.self) private var ambientSoundManager
    @Environment(SyncManager.self) private var syncManager

    // Pipeline pushing
    @State private var isPushingToPipeline = false
    @State private var pipelineStatusMessage: String? = nil
    @State private var showPipelineSuccessAlert = false

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
    @State private var showChapterJSON = false
    @State private var showBookSpine = false

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

                            StoryWorkspaceMetaChips(story: story)

                            if story.preferences.audioStyle == .dramatized {
                                Label("Dramatized", systemImage: "person.2.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.teal.opacity(0.12))
                                    .foregroundStyle(.teal)
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .padding(.top, 24)

                    Divider()

                    // ── Play Options ──────────────────────────────────────
                    VStack(spacing: 12) {
                        // Read & Listen
                        NavigationLink(destination: StoryReaderFactoryView(story: story)) {
                            HStack {
                                Image(systemName: story.preferences.storyType.icon)
                                Text(primaryReaderTitle)
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accentColor)
                            .cornerRadius(12)
                        }

                        if story.preferences.storyType == .dialogStory {
                            // Dialog Mode
                            NavigationLink(destination: DialogSessionView(story: story)) {
                                HStack {
                                    Image(systemName: "mic.fill")
                                    Text("Dialog Playback Mode")
                                }
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.orange)
                                .cornerRadius(12)
                            }

                        }

                        // Take Quiz
                        NavigationLink(destination: StoryQuizView(story: story)) {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                    .font(.title3)
                                Text("Take the Quiz")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemBackground))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }

                    Divider()

                    // Additional Metadata
                    FlowLayout(spacing: 8) {
                        if let wordCount = storyWordCount {
                            Label(wordCount, systemImage: "doc.text")
                                .badgeStyle()
                        }
                        if story.preferences.interactiveAudio {
                            Label("Dialog Audio", systemImage: "waveform.and.mic")
                                .badgeStyle()
                                .foregroundStyle(.orange)
                        }
                    }

                    Divider()

                    if let overview = story.storyOverviewText {
                        previewSection(
                            title: "Story Overview",
                            systemImage: "text.book.closed",
                            body: overview
                        )
                        Divider()
                    }

                    if let profile = story.ciProfile {
                        learningProfileSection(profile)
                        Divider()
                    }

                    // ── Chapters ──────────────────────────────────────────
                    if !story.chapters.isEmpty {
                        chapterListSection
                        Divider()
                    }

                    // ── Ambient Sound ─────────────────────────────────────
                    AmbientSoundRow(story: story, onChangeTap: { showAmbientPicker = true })

                    Divider()

                    // ── Administrative Actions ────────────────────────────
                    VStack(spacing: 12) {
                        
                        // Push to Pipeline
                        Button(action: pushStoryToPipeline) {
                            HStack {
                                if isPushingToPipeline {
                                    ProgressView().tint(.white)
                                        .padding(.trailing, 4)
                                    Text("Saving...")
                                } else {
                                    Image(systemName: "icloud.and.arrow.up")
                                    Text("Save to Pipeline")
                                }
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        .disabled(isPushingToPipeline)
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
                    Button { showChapterJSON = true } label: {
                        Label("View Chapter JSON", systemImage: "curlybraces")
                    }
                    Button { showBookSpine = true } label: {
                        Label("Show Book Spine", systemImage: "list.number")
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

                    Menu {
                        ForEach(StoryPreferences.StoryType.allCases) { type in
                            Button {
                                var prefs = story.preferences
                                prefs.storyType = type
                                if let data = try? JSONEncoder().encode(prefs),
                                   let json = String(data: data, encoding: .utf8) {
                                    story.preferencesJSON = json
                                    try? modelContext.save()
                                }
                            } label: {
                                Label(type.displayName, systemImage: type.icon)
                            }
                        }
                    } label: {
                        Label("Set Story Type", systemImage: "tag")
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
        .sheet(isPresented: $showChapterJSON) {
            ChapterJSONSheet(chaptersJSON: story.chaptersJSON)
        }
        .sheet(isPresented: $showBookSpine) {
            BookSpineSheet(story: story)
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
        .alert("Pipeline", isPresented: $showPipelineSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(pipelineStatusMessage ?? "")
        }
    }

    private var primaryReaderTitle: String {
        switch story.preferences.storyType {
        case .comicBook:
            return "Read Comic Book"
        case .pictureBook:
            return "Read Picture Book"
        case .dialogStory:
            return "Read Dialog Story"
        case .audioStory:
            return "Listen to Audio Story"
        case .storyBook:
            return "Read & Listen to the story"
        case .standard:
            return "Read & Listen to the story"
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

                    if let urlString = chapter.coverUrl,
                       let url = AppConfig.chapterCoverURL(urlString) {
                        Spacer()
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Color(.secondarySystemBackground)
                        }
                        .frame(width: 60, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func previewSection(title: String, systemImage: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func learningProfileSection(_ profile: CiProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Learning Profile", systemImage: "graduationcap")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Label(profile.learningStrategy.displayName, systemImage: profile.learningStrategy.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(profile.learningStrategy.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let summary = profile.summaryText {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var storyWordCount: String? {
        let combined = story.chapters.map { $0.bodyTextTargetForReading }.joined(separator: " ")
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

    // MARK: - Pipeline Push Action
    
    @MainActor
    private func pushStoryToPipeline() {
        isPushingToPipeline = true
        Task {
            do {
                try await syncManager.pushToPipeline(story: story, context: modelContext)
                pipelineStatusMessage = "Successfully saved story to pipeline."
            } catch {
                pipelineStatusMessage = "Failed to save: \(error.localizedDescription)"
            }
            isPushingToPipeline = false
            showPipelineSuccessAlert = true
        }
    }
}

// MARK: - Chapter JSON Sheet

private struct ChapterJSONSheet: View {
    let chaptersJSON: String?
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    /// Full raw JSON for copying
    private var fullJSON: String {
        chaptersJSON ?? "(no chaptersJSON stored)"
    }

    /// Pretty-printed JSON with word_timings stripped for readable display
    private var displayJSON: String {
        guard let raw = chaptersJSON, let data = raw.data(using: .utf8) else {
            return "(no chaptersJSON stored)"
        }
        guard var arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return raw
        }
        let stripKeys = ["word_timings", "chapter_intro_word_timings", "chapterIntroWordTimings"]
        arr = arr.map { chapter in
            var c = chapter
            stripKeys.forEach { c.removeValue(forKey: $0) }
            return c
        }
        guard let pretty = try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else { return raw }
        return str
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(displayJSON)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Chapter JSON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(copied ? "Copied!" : "Copy Full JSON") {
                        UIPasteboard.general.string = fullJSON
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    }
                    .foregroundStyle(copied ? .green : .blue)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Book Spine Sheet

private struct BookSpineSheet: View {
    let story: Story

    @Environment(\.dismiss) private var dismiss
    @State private var selectedMode: SpineModeOption

    private var adapter: StoryReaderDataAdapter {
        StoryReaderDataAdapter(story: story)
    }

    init(story: Story) {
        self.story = story
        _selectedMode = State(initialValue: SpineModeOption.defaultMode(for: story))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Reader", selection: $selectedMode) {
                        ForEach(SpineModeOption.allCases) { option in
                            Label(option.title, systemImage: option.icon).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    let items = adapter.items(for: selectedMode.spineMode)
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        spineRow(index: index, item: item)
                    }
                } header: {
                    Text("\(selectedMode.title) Order")
                } footer: {
                    Text("This is the exact StoryReadingSpine order consumed by the selected reader mode.")
                }
            }
            .navigationTitle("Book Spine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func spineRow(index: Int, item: StoryReadingSpineItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color(for: item))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Label(title(for: item), systemImage: icon(for: item))
                    .font(.subheadline.weight(.semibold))
                if let detail = detail(for: item) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(item.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }

    private func title(for item: StoryReadingSpineItem) -> String {
        switch item {
        case .cover:
            return "Cover"
        case .readingMatterPage:
            return "Reading Matter"
        case .chapter(let index):
            guard let chapter = adapter.chapter(for: .chapter(index: index)) else {
                return "Chapter \(index + 1)"
            }
            return chapter.titleTargetLanguage.isEmpty ? "Chapter \(index + 1)" : chapter.titleTargetLanguage
        case .scene(_, let sceneIndex):
            return "Scene \(sceneIndex + 1)"
        }
    }

    private func detail(for item: StoryReadingSpineItem) -> String? {
        switch item {
        case .cover:
            return story.title
        case .readingMatterPage:
            guard let page = adapter.readingMatterPage(for: item) else { return nil }
            let title = page.titleTarget?.nilIfEmptySpineSheet ?? page.titleNative?.nilIfEmptySpineSheet ?? page.id
            let placement = page.placement?.nilIfEmptySpineSheet ?? "placement unset"
            return "\(title) · \(placement)"
        case .chapter(let index):
            guard let chapter = adapter.chapter(for: .chapter(index: index)) else { return nil }
            let type = chapter.isPrologue ? "Prologue" : chapter.isEpilogue ? "Epilogue" : "Chapter"
            return "\(type) \(index + 1) · \(chapter.scenes.count) scenes"
        case .scene(let chapterIndex, _):
            guard let scene = adapter.scene(for: item) else { return nil }
            let lines = scene.dialogues.count
            let hasImage = adapter.sceneImageURL(scene: scene, chapterIndex: chapterIndex) != nil
            let hasAudio = scene.audioUrl?.nilIfEmptySpineSheet != nil
            return "Chapter \(chapterIndex + 1) · \(lines) dialog lines · image \(hasImage ? "yes" : "no") · audio \(hasAudio ? "yes" : "no")"
        }
    }

    private func icon(for item: StoryReadingSpineItem) -> String {
        switch item {
        case .cover:
            return "book.closed"
        case .readingMatterPage:
            return "doc.text"
        case .chapter:
            return "book.pages"
        case .scene:
            return "photo.on.rectangle"
        }
    }

    private func color(for item: StoryReadingSpineItem) -> Color {
        switch item {
        case .cover:
            return .accentColor
        case .readingMatterPage:
            return .indigo
        case .chapter:
            return .blue
        case .scene:
            return .orange
        }
    }
}

private struct SpineModeOption: Identifiable, Hashable, CaseIterable {
    let id: String
    let title: String
    let icon: String
    let spineMode: StoryReadingSpineMode

    static let storyBook = SpineModeOption(id: "storyBook", title: "Story Book", icon: "book", spineMode: .storyBook)
    static let audioBook = SpineModeOption(id: "audioBook", title: "Audio Book", icon: "headphones", spineMode: .audioBook)
    static let dialogStory = SpineModeOption(id: "dialogStory", title: "Dialog", icon: "text.bubble", spineMode: .dialogStory)
    static let pictureBook = SpineModeOption(id: "pictureBook", title: "Picture Book", icon: "photo", spineMode: .pictureBook)
    static let comicBook = SpineModeOption(id: "comicBook", title: "Comic Book", icon: "rectangle.grid.2x2", spineMode: .comicBook)

    static let allCases: [SpineModeOption] = [.storyBook, .audioBook, .dialogStory, .pictureBook, .comicBook]

    static func defaultMode(for story: Story) -> SpineModeOption {
        switch story.preferences.storyType {
        case .storyBook, .standard:
            return .storyBook
        case .audioStory:
            return .audioBook
        case .dialogStory:
            return .dialogStory
        case .comicBook:
            return .comicBook
        case .pictureBook:
            return .pictureBook
        }
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

private extension String {
    var nilIfEmptySpineSheet: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

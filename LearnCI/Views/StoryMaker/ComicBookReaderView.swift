import SwiftUI

struct ComicBookReaderView: View {
    let story: Story
    private let initialPageIndex: Int
    private let onProgressChange: ((StoryReaderProgressUpdate) -> Void)?

    @State private var currentPageIndex = 0
    @State private var selectedPanel: ComicPanelModel?

    init(
        story: Story,
        initialPageIndex: Int = 0,
        onProgressChange: ((StoryReaderProgressUpdate) -> Void)? = nil
    ) {
        self.story = story
        self.initialPageIndex = initialPageIndex
        self.onProgressChange = onProgressChange
        _currentPageIndex = State(initialValue: max(0, initialPageIndex))
    }

    private var adapter: StoryReaderDataAdapter {
        StoryReaderDataAdapter(story: story)
    }

    private var segments: [ComicBookSegment] {
        ComicBookRenderer.makeSegments(story: story, adapter: adapter)
    }

    var body: some View {
        Group {
            if let issue = adapter.requirementIssue(for: .comicBook) {
                StoryReaderUnavailableView(title: issue.title, message: issue.message)
            } else if segments.isEmpty {
                StoryReaderUnavailableView(title: "Comic Layout Missing", message: "This comic book has no visible spine-backed panels.")
            } else {
                comicPager
            }
        }
        .navigationTitle(story.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedPanel) { panel in
            ComicPanelDetailView(panel: panel)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            reconcileInitialPage()
            saveReadingProgress()
        }
        .onChange(of: currentPageIndex) { _, _ in
            saveReadingProgress()
        }
    }

    private var comicPager: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground).ignoresSafeArea()

            TabView(selection: $currentPageIndex) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    ComicBookSegmentView(story: story, adapter: adapter, segment: segment) { panel in
                        selectedPanel = panel
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            ComicPageControls(
                currentPage: currentPageIndex + 1,
                pageCount: segments.count,
                canGoBack: currentPageIndex > 0,
                canGoForward: currentPageIndex < segments.count - 1,
                onBack: { currentPageIndex = max(0, currentPageIndex - 1) },
                onForward: { currentPageIndex = min(segments.count - 1, currentPageIndex + 1) }
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
    }

    private func reconcileInitialPage() {
        let count = segments.count
        guard count > 0 else { return }
        currentPageIndex = min(max(0, currentPageIndex), count - 1)
    }

    private func saveReadingProgress() {
        guard segments.indices.contains(currentPageIndex) else { return }
        let segment = segments[currentPageIndex]
        onProgressChange?(StoryReaderProgressUpdate(
            index: currentPageIndex,
            total: segments.count,
            chapterIndex: segment.chapterIndex,
            sceneIndex: segment.sceneIndex
        ))
    }
}

enum ComicBookSegment: Identifiable, Equatable {
    case cover
    case readingMatter(index: Int)
    case chapterIntro(chapterIndex: Int)
    case chapterPage(ComicBookPageModel)
    case chapterQuiz(chapterIndex: Int)
    case chapterVocabulary(chapterIndex: Int)

    var id: String {
        switch self {
        case .cover:
            return "cover"
        case .readingMatter(let index):
            return "matter-\(index)"
        case .chapterIntro(let chapterIndex):
            return "intro-\(chapterIndex)"
        case .chapterPage(let page):
            return page.id
        case .chapterQuiz(let chapterIndex):
            return "quiz-\(chapterIndex)"
        case .chapterVocabulary(let chapterIndex):
            return "vocab-\(chapterIndex)"
        }
    }

    var chapterIndex: Int? {
        switch self {
        case .cover, .readingMatter:
            return nil
        case .chapterIntro(let chapterIndex),
             .chapterQuiz(let chapterIndex),
             .chapterVocabulary(let chapterIndex):
            return chapterIndex
        case .chapterPage(let page):
            return page.chapterIndex
        }
    }

    var sceneIndex: Int? {
        if case .chapterPage(let page) = self {
            return page.sceneIndex
        }
        return nil
    }
}

struct ComicBookRenderer {
    static func makeSegments(story: Story, adapter: StoryReaderDataAdapter) -> [ComicBookSegment] {
        let items = adapter.items(for: .comicBook)
        let panelPages = makePages(story: story, adapter: adapter)
        var panelPageByChapter: [Int: ComicBookPageModel] = [:]
        for page in panelPages {
            if let chapterIndex = page.chapterIndex {
                panelPageByChapter[chapterIndex] = page
            }
        }

        var segments: [ComicBookSegment] = []
        var emittedChapterPages = Set<Int>()

        for item in items {
            switch item {
            case .cover:
                segments.append(.cover)
            case .readingMatterPage(let index, _):
                segments.append(.readingMatter(index: index))
            case .chapter(let chapterIndex):
                segments.append(.chapterIntro(chapterIndex: chapterIndex))
            case .scene(let chapterIndex, _):
                if emittedChapterPages.insert(chapterIndex).inserted,
                   let page = panelPageByChapter[chapterIndex] {
                    segments.append(.chapterPage(page))
                }
            case .chapterQuiz(let chapterIndex):
                segments.append(.chapterQuiz(chapterIndex: chapterIndex))
            case .chapterVocabulary(let chapterIndex):
                segments.append(.chapterVocabulary(chapterIndex: chapterIndex))
            }
        }

        let hasPanelSegments = segments.contains {
            if case .chapterPage = $0 { return true }
            return false
        }
        if hasPanelSegments {
            return segments
        }
        return panelPages.map { .chapterPage($0) }
    }

    static func makePages(story: Story, adapter: StoryReaderDataAdapter) -> [ComicBookPageModel] {
        guard let layout = story.storyLayout, !layout.pages.isEmpty else { return [] }
        let spineSceneIDs = Set(adapter.spine(for: .comicBook).sceneItems.map(\.id))

        return layout.pages.enumerated().map { pageIndex, page in
            let panels = page.canvases
                .flatMap(\.panels)
                .compactMap { panel -> ComicPanelModel? in
                    let spineItem = StoryReadingSpineItem.scene(chapterIndex: panel.chapterIndex, sceneIndex: panel.sceneIndex)
                    guard spineSceneIDs.contains(spineItem.id),
                          let scene = adapter.scene(for: spineItem) else {
                        return nil
                    }
                    return ComicPanelModel(
                        panel: panel,
                        scene: scene,
                        chapter: story.chapters[safe: panel.chapterIndex],
                        imageURL: adapter.sceneImageURL(scene: scene, chapterIndex: panel.chapterIndex)
                    )
                }

            return ComicBookPageModel(
                pageNumber: pageIndex + 1,
                chapterIndex: page.chapterIndex,
                sceneIndex: page.sceneIndex,
                panels: panels
            )
        }
        .filter { !$0.panels.isEmpty }
    }

    static func storyCoverImageURL(for story: Story) -> URL? {
        if let path = story.remoteCoverPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty,
           let url = AppConfig.chapterCoverURL(path) {
            return url
        }
        if let path = story.coverArt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty,
           let url = AppConfig.chapterCoverURL(path) {
            return url
        }
        return nil
    }
}

struct ComicBookPageModel: Identifiable, Equatable {
    let pageNumber: Int
    let chapterIndex: Int?
    let sceneIndex: Int?
    let panels: [ComicPanelModel]

    var id: String { "page-\(pageNumber)" }
}

struct ComicPanelModel: Identifiable, Equatable {
    let id = UUID()
    let panel: PanelLayout
    let scene: StoryScene
    let chapter: StoryChapter?
    let imageURL: URL?

    var title: String {
        chapter?.titleTargetLanguage ?? "Scene \(scene.sceneIndex + 1)"
    }

    var caption: String {
        scene.captionTarget?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? scene.scriptTargetLanguage?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? ""
    }
}

private struct ComicBookSegmentView: View {
    let story: Story
    let adapter: StoryReaderDataAdapter
    let segment: ComicBookSegment
    let onPanelTap: (ComicPanelModel) -> Void

    var body: some View {
        switch segment {
        case .cover:
            ScrollView {
                VStack(spacing: 16) {
                    if let url = ComicBookRenderer.storyCoverImageURL(for: story) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFit()
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground))
                                    .frame(height: 220)
                            }
                        }
                    }
                    Text(story.title)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        case .readingMatter(let index):
            if let page = story.readingMatterPages[safe: index] {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(page.titleTarget ?? page.titleNative ?? "Reading Matter")
                            .font(.title3.weight(.semibold))
                        if let body = page.bodyTarget ?? page.bodyNative {
                            TappableStoryText(text: body, font: .body)
                        }
                    }
                    .padding()
                }
            }
        case .chapterIntro(let chapterIndex):
            if let chapter = story.chapters[safe: chapterIndex] {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(StoryReadingSpineTitles.chapterTitle(for: chapter, index: chapterIndex))
                            .font(.title3.weight(.semibold))
                        if let intro = chapter.chapterIntroText {
                            TappableStoryText(text: intro, font: .body)
                        }
                    }
                    .padding()
                }
            }
        case .chapterPage(let page):
            ComicBookPageView(page: page, onPanelTap: onPanelTap)
        case .chapterQuiz(let chapterIndex):
            if let chapter = story.chapters[safe: chapterIndex] {
                let resolved = ChapterComprehensionQuizResolver.questions(for: chapter, in: story)
                let title = resolved.isStoryWideFallback ? "Story Comprehension Quiz" : "Chapter Comprehension"
                ScrollView {
                    InlineChapterQuizView(questions: resolved.questions, title: title)
                        .padding()
                }
            }
        case .chapterVocabulary(let chapterIndex):
            if let chapter = story.chapters[safe: chapterIndex] {
                ScrollView {
                    InlineChapterVocabularyView(
                        vocabularyNote: chapter.vocabularyNote ?? "",
                        title: "Chapter Word Focus"
                    )
                    .padding()
                }
            }
        }
    }
}

private struct ComicBookPageView: View {
    let page: ComicBookPageModel
    let onPanelTap: (ComicPanelModel) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.secondarySystemBackground))

                ForEach(page.panels) { panel in
                    ComicPanelView(panel: panel)
                        .frame(
                            width: geometry.size.width * normalized(panel.panel.width),
                            height: geometry.size.height * normalized(panel.panel.height)
                        )
                        .position(
                            x: geometry.size.width * (normalized(panel.panel.x) + normalized(panel.panel.width) / 2),
                            y: geometry.size.height * (normalized(panel.panel.y) + normalized(panel.panel.height) / 2)
                        )
                        .onTapGesture { onPanelTap(panel) }
                }
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
    }

    private func normalized(_ value: Double) -> Double {
        if value > 1 {
            return min(max(value / 100.0, 0), 1)
        }
        return min(max(value, 0), 1)
    }
}

private struct ComicPanelView: View {
    let panel: ComicPanelModel

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ComicPanelImage(url: panel.imageURL, cropRegion: panel.panel.cropRegion)

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                if !panel.caption.isEmpty {
                    TappableStoryText(
                        text: panel.caption,
                        font: .caption.weight(.semibold),
                        lineSpacing: 2,
                        foregroundColor: .white
                    )
                        .lineLimit(4)
                }

                ForEach(panel.scene.dialogues.prefix(2)) { dialogue in
                    TappableStoryText(
                        text: "\(dialogue.character): \(dialogue.text)",
                        font: .caption2,
                        lineSpacing: 1,
                        foregroundColor: .white.opacity(0.9)
                    )
                        .lineLimit(2)
                }
            }
            .foregroundStyle(.white)
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(.white.opacity(0.85), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
    }
}

private struct ComicPanelImage: View {
    let url: URL?
    let cropRegion: CropRegion

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cropRegion.alignment)
            case .failure:
                placeholder
            case .empty:
                placeholder.overlay { ProgressView().tint(.white) }
            @unknown default:
                placeholder
            }
        }
        .clipped()
        .background(Color(.tertiarySystemBackground))
    }

    private var placeholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.indigo.opacity(0.55), Color.teal.opacity(0.45), Color.orange.opacity(0.38)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

private struct ComicPanelDetailView: View {
    let panel: ComicPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ComicPanelImage(url: panel.imageURL, cropRegion: panel.panel.cropRegion)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    Text(panel.title)
                        .font(.headline)
                    Text("Scene \(panel.scene.sceneIndex + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !panel.caption.isEmpty {
                    TappableStoryText(text: panel.caption, font: .body)
                }

                if !panel.scene.dialogues.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(panel.scene.dialogues) { dialogue in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dialogue.character)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                TappableStoryText(text: dialogue.text, font: .body)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding()
        }
    }
}

private struct ComicPageControls: View {
    let currentPage: Int
    let pageCount: Int
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 38, height: 38)
            }
            .disabled(!canGoBack)

            Spacer()

            Text("\(currentPage) / \(pageCount)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial)
                .clipShape(Capsule())

            Spacer()

            Button(action: onForward) {
                Image(systemName: "chevron.right")
                    .frame(width: 38, height: 38)
            }
            .disabled(!canGoForward)
        }
        .buttonStyle(.borderedProminent)
    }
}

private extension CropRegion {
    var alignment: Alignment {
        switch self {
        case .topLeft:
            return .topLeading
        case .topRight:
            return .topTrailing
        case .bottomLeft:
            return .bottomLeading
        case .bottomRight:
            return .bottomTrailing
        case .topHalf:
            return .top
        case .bottomHalf:
            return .bottom
        case .center, .centre, .full:
            return .center
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

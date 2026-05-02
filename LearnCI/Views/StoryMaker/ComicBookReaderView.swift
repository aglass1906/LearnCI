import SwiftUI

struct ComicBookReaderView: View {
    let story: Story

    @State private var currentPageIndex = 0
    @State private var selectedPanel: ComicPanelModel?

    private var pages: [ComicBookPageModel] {
        ComicBookRenderer.makePages(story: story)
    }

    var body: some View {
        Group {
            if pages.isEmpty {
                StoryReaderUnavailableView(
                    title: "Comic Layout Missing",
                    message: "This comic book needs layout pages and scene data before it can be rendered."
                )
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
    }

    private var comicPager: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground).ignoresSafeArea()

            TabView(selection: $currentPageIndex) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    ComicBookPageView(page: page) { panel in
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
                pageCount: pages.count,
                canGoBack: currentPageIndex > 0,
                canGoForward: currentPageIndex < pages.count - 1,
                onBack: { currentPageIndex = max(0, currentPageIndex - 1) },
                onForward: { currentPageIndex = min(pages.count - 1, currentPageIndex + 1) }
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
    }
}

struct ComicBookRenderer {
    static func makePages(story: Story) -> [ComicBookPageModel] {
        guard let layout = story.storyLayout, !layout.pages.isEmpty else { return [] }

        return layout.pages.enumerated().map { pageIndex, page in
            let panels = page.canvases
                .flatMap(\.panels)
                .compactMap { panel -> ComicPanelModel? in
                    guard let scene = story.scene(atChapter: panel.chapterIndex, scene: panel.sceneIndex) else {
                        return nil
                    }
                    return ComicPanelModel(
                        panel: panel,
                        scene: scene,
                        chapter: story.chapters[safe: panel.chapterIndex],
                        imageURL: story.imageURL(for: scene, chapterIndex: panel.chapterIndex)
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
}

struct ComicBookPageModel: Identifiable, Equatable {
    let id = UUID()
    let pageNumber: Int
    let chapterIndex: Int?
    let sceneIndex: Int?
    let panels: [ComicPanelModel]
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
                    Text(panel.caption)
                        .font(.caption.weight(.semibold))
                        .lineLimit(4)
                }

                ForEach(panel.scene.dialogues.prefix(2)) { dialogue in
                    Text("\(dialogue.character): \(dialogue.text)")
                        .font(.caption2)
                        .lineLimit(2)
                        .foregroundStyle(.white.opacity(0.9))
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
                    Text(panel.caption)
                        .font(.body)
                }

                if !panel.scene.dialogues.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(panel.scene.dialogues) { dialogue in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dialogue.character)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Text(dialogue.text)
                                    .font(.body)
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

private extension Story {
    func scene(atChapter chapterIndex: Int, scene sceneIndex: Int) -> StoryScene? {
        chapters[safe: chapterIndex]?.scenes.first { $0.sceneIndex == sceneIndex }
    }

    func imageURL(for scene: StoryScene, chapterIndex: Int) -> URL? {
        if let imageUrl = scene.imageUrl?.nilIfEmpty {
            return AppConfig.chapterCoverURL(imageUrl)
        }
        if let coverUrl = chapters[safe: chapterIndex]?.coverUrl?.nilIfEmpty {
            return AppConfig.chapterCoverURL(coverUrl)
        }
        if let remoteCoverPath = remoteCoverPath?.nilIfEmpty {
            return AppConfig.chapterCoverURL(remoteCoverPath)
        }
        if let coverArt = coverArt?.nilIfEmpty {
            return AppConfig.chapterCoverURL(coverArt)
        }
        return nil
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

import SwiftUI

struct PictureBookReaderView: View {
    let story: Story

    private var spreads: [PictureBookSpreadModel] {
        PictureBookRenderer.makeSpreads(story: story)
    }

    var body: some View {
        Group {
            if spreads.isEmpty {
                StoryReaderUnavailableView(
                    title: "Picture Layout Missing",
                    message: "This picture book needs layout pages and scene data before it can be rendered."
                )
            } else {
                TabView {
                    ForEach(spreads) { spread in
                        PictureBookSpreadView(spread: spread)
                    }
                }
                .tabViewStyle(.page)
                .ignoresSafeArea(edges: .top)
            }
        }
        .navigationTitle(story.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PictureBookRenderer {
    static func makeSpreads(story: Story) -> [PictureBookSpreadModel] {
        guard let layout = story.storyLayout else { return [] }

        let panels = layout.flatSequence.isEmpty
            ? layout.pages.flatMap { $0.canvases.flatMap(\.panels) }
            : layout.flatSequence

        return panels.compactMap { panel in
            guard let scene = story.sceneForPictureBook(chapterIndex: panel.chapterIndex, sceneIndex: panel.sceneIndex) else {
                return nil
            }

            return PictureBookSpreadModel(
                chapterTitle: story.chapters[safeForPictureBook: panel.chapterIndex]?.titleTargetLanguage,
                scene: scene,
                imageURL: story.imageURLForPictureBook(scene: scene, chapterIndex: panel.chapterIndex)
            )
        }
    }
}

struct PictureBookSpreadModel: Identifiable {
    let id = UUID()
    let chapterTitle: String?
    let scene: StoryScene
    let imageURL: URL?
}

private struct PictureBookSpreadView: View {
    let spread: PictureBookSpreadModel

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: spread.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Color(.secondarySystemBackground)
                case .empty:
                    Color(.secondarySystemBackground).overlay { ProgressView() }
                @unknown default:
                    Color(.secondarySystemBackground)
                }
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                if let chapterTitle = spread.chapterTitle {
                    Text(chapterTitle)
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.76))
                }

                if let caption = spread.scene.captionTarget?.nilIfEmptyForPictureBook {
                    Text(caption)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }

                ForEach(spread.scene.dialogues.prefix(3)) { dialogue in
                    Text("\(dialogue.character): \(dialogue.text)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .padding(22)
        }
    }
}

private extension Story {
    func sceneForPictureBook(chapterIndex: Int, sceneIndex: Int) -> StoryScene? {
        chapters[safeForPictureBook: chapterIndex]?.scenes.first { $0.sceneIndex == sceneIndex }
    }

    func imageURLForPictureBook(scene: StoryScene, chapterIndex: Int) -> URL? {
        if let imageUrl = scene.imageUrl?.nilIfEmptyForPictureBook {
            return AppConfig.chapterCoverURL(imageUrl)
        }
        if let coverUrl = chapters[safeForPictureBook: chapterIndex]?.coverUrl?.nilIfEmptyForPictureBook {
            return AppConfig.chapterCoverURL(coverUrl)
        }
        if let remoteCoverPath = remoteCoverPath?.nilIfEmptyForPictureBook {
            return AppConfig.chapterCoverURL(remoteCoverPath)
        }
        if let coverArt = coverArt?.nilIfEmptyForPictureBook {
            return AppConfig.chapterCoverURL(coverArt)
        }
        return nil
    }
}

private extension Collection {
    subscript(safeForPictureBook index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var nilIfEmptyForPictureBook: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

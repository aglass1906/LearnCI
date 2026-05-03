import SwiftUI

struct PictureBookReaderView: View {
    let story: Story

    private var adapter: StoryReaderDataAdapter {
        StoryReaderDataAdapter(story: story)
    }

    private var spreads: [PictureBookSpreadModel] {
        PictureBookRenderer.makeSpreads(story: story, adapter: adapter)
    }

    var body: some View {
        Group {
            if let issue = adapter.requirementIssue(for: .pictureBook) {
                StoryReaderUnavailableView(title: issue.title, message: issue.message)
            } else if spreads.isEmpty {
                StoryReaderUnavailableView(title: "Reader Data Missing", message: "This picture book has no visible spine items.")
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
    static func makeSpreads(story: Story, adapter: StoryReaderDataAdapter) -> [PictureBookSpreadModel] {
        adapter.items(for: .pictureBook).compactMap { item in
            switch item {
            case .cover:
                return PictureBookSpreadModel(
                    id: item.id,
                    title: story.title,
                    subtitle: "\(story.language.displayName) · Level \(story.level)",
                    body: nil,
                    scene: nil,
                    imageURL: coverURL(for: story)
                )
            case .readingMatterPage:
                guard let page = adapter.readingMatterPage(for: item) else { return nil }
                return PictureBookSpreadModel(
                    id: item.id,
                    title: page.titleTarget?.nilIfEmptyForPictureBook,
                    subtitle: nil,
                    body: page.bodyTarget?.nilIfEmptyForPictureBook,
                    scene: nil,
                    imageURL: coverURL(for: story)
                )
            case .chapter:
                return nil
            case .scene(let chapterIndex, _):
                guard let scene = adapter.scene(for: item) else { return nil }
                return PictureBookSpreadModel(
                    id: item.id,
                    title: story.chapters[safeForPictureBook: chapterIndex]?.titleTargetLanguage.nilIfEmptyForPictureBook,
                    subtitle: nil,
                    body: scene.captionTarget?.nilIfEmptyForPictureBook,
                    scene: scene,
                    imageURL: adapter.sceneImageURL(scene: scene, chapterIndex: chapterIndex)
                )
            }
        }
    }

    private static func coverURL(for story: Story) -> URL? {
        if let remoteCoverPath = story.remoteCoverPath?.nilIfEmptyForPictureBook {
            return AppConfig.chapterCoverURL(remoteCoverPath)
        }
        if let coverArt = story.coverArt?.nilIfEmptyForPictureBook {
            return AppConfig.chapterCoverURL(coverArt)
        }
        return nil
    }
}

struct PictureBookSpreadModel: Identifiable {
    let id: String
    let title: String?
    let subtitle: String?
    let body: String?
    let scene: StoryScene?
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
                if let title = spread.title {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }

                if let subtitle = spread.subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.76))
                }

                if let body = spread.body {
                    Text(body)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }

                if let scene = spread.scene {
                    ForEach(scene.dialogues.prefix(3)) { dialogue in
                        Text("\(dialogue.character): \(dialogue.text)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }
            }
            .padding(22)
        }
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

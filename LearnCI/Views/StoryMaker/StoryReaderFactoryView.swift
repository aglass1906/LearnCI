import SwiftUI

struct StoryReaderFactoryView: View {
    let story: Story

    var body: some View {
        switch story.preferences.storyType {
        case .storyBook:
            StorySessionView(story: story)
        case .audioStory:
            AudioBookReaderView(story: story)
        case .interactiveStory:
            KaraokeSessionView(story: story)
        case .comicBook:
            ComicBookReaderView(story: story)
        case .pictureBook:
            PictureBookReaderView(story: story)
        case .standard, .vocabularyBuilder:
            StoryReaderUnavailableView(
                title: "Unsupported Story Type",
                message: "This story type is not routed through the story reader."
            )
        }
    }
}

struct StoryReaderUnavailableView: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
        .navigationTitle("Story Reader")
    }
}

import SwiftUI

struct StoryReaderFactoryView: View {
    let story: Story

    var body: some View {
        switch story.preferences.storyType {
        case .storyBook, .standard:
            StorySessionView(story: story)
        case .audioStory:
            AudioBookReaderView(story: story)
        case .dialogStory:
            DialogStoryFlowView(story: story)
        case .comicBook:
            ComicBookReaderView(story: story)
        case .pictureBook:
            PictureBookReaderView(story: story)
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

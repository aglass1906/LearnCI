import SwiftUI

/// Audio-only story listening for lock screen and CarPlay. Plays scene narration in order,
/// skips chapter quiz and Word Focus, and starts playback automatically.
struct StoryAudioPlaybackView: View {
    let story: Story

    @State private var resumeChoice: StoryAudioResumeChoice?
    @State private var showResumePrompt = false

    private var adapter: StoryReaderDataAdapter {
        StoryReaderDataAdapter(story: story)
    }

    private var savedProgress: StoryReaderProgress? {
        StoryReaderProgressStore.progress(for: story.id, readerKind: .audioPlayback)
    }

    private var initialNavIndex: Int {
        switch resumeChoice {
        case .resume(let progress):
            return progress.index
        case .startOver, .none:
            return 0
        }
    }

    private var initialPlaybackPosition: Double? {
        if case .resume(let progress) = resumeChoice {
            return progress.position
        }
        return nil
    }

    var body: some View {
        Group {
            if let issue = adapter.requirementIssue(for: .audioBook) {
                StoryReaderUnavailableView(title: issue.title, message: issue.message)
            } else if resumeChoice == nil, savedProgress?.isResumable == true {
                ProgressView("Loading audio…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AudioBookReaderView(
                    story: story,
                    initialNavIndex: initialNavIndex,
                    initialPlaybackPosition: initialPlaybackPosition,
                    playbackMode: .continuousAudio,
                    onProgressChange: saveProgress
                )
            }
        }
        .navigationTitle("Listen")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard resumeChoice == nil else { return }
            if savedProgress?.isResumable == true {
                showResumePrompt = true
            } else {
                resumeChoice = .startOver
            }
        }
        .confirmationDialog(
            "Continue listening?",
            isPresented: $showResumePrompt,
            titleVisibility: .visible
        ) {
            if let savedProgress {
                Button("Pick Up Where I Left Off") {
                    resumeChoice = .resume(savedProgress)
                }
            }
            Button("Start From Beginning") {
                StoryReaderProgressStore.save(
                    .init(index: 0, total: nil),
                    for: story.id,
                    readerKind: .audioPlayback
                )
                resumeChoice = .startOver
            }
        } message: {
            Text("Resume your listening session or start the story over.")
        }
    }

    private func saveProgress(_ update: StoryReaderProgressUpdate) {
        StoryReaderProgressStore.save(update, for: story.id, readerKind: .audioPlayback)
    }
}

private enum StoryAudioResumeChoice: Equatable {
    case startOver
    case resume(StoryReaderProgress)
}

import SwiftUI

/// Audio-only story listening for lock screen and CarPlay. Plays scene narration in order,
/// skips chapter quiz and Word Focus, and starts playback automatically.
struct StoryAudioPlaybackView: View {
    let story: Story

    @State private var resumeChoice: StoryAudioResumeChoice?
    @State private var showResumePrompt = false
    @State private var isDownloading = false
    @State private var downloadFailure: String?

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await downloadStoryAudio() }
                } label: {
                    if isDownloading {
                        ProgressView()
                    } else {
                        Image(systemName: allAudioIsCached ? "checkmark.circle.fill" : "arrow.down.circle")
                    }
                }
                .disabled(isDownloading || allAudioIsCached)
                .accessibilityLabel(allAudioIsCached ? "Downloaded" : "Download story audio")
            }
        }
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
        .alert("Download Failed", isPresented: Binding(
            get: { downloadFailure != nil },
            set: { if !$0 { downloadFailure = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloadFailure ?? "The story audio could not be downloaded.")
        }
    }

    private func saveProgress(_ update: StoryReaderProgressUpdate) {
        StoryReaderProgressStore.save(update, for: story.id, readerKind: .audioPlayback)
    }

    private var storyClips: [StorySceneAudioClip] {
        adapter.audioBookPlaybackClips()
    }

    private var allAudioIsCached: Bool {
        let clips = storyClips
        return !clips.isEmpty && clips.allSatisfy {
            StoryReaderDataAdapter.cachedAudioURL(storyID: story.id, clip: $0, storyUpdatedAt: story.updatedAt) != nil
        }
    }

    private func downloadStoryAudio() async {
        isDownloading = true
        defer { isDownloading = false }
        let clips = storyClips
        guard !clips.isEmpty else {
            downloadFailure = "This story does not have downloadable audio."
            return
        }
        for clip in clips {
            guard await StoryReaderDataAdapter.downloadAndCacheAudioIfNeeded(
                storyID: story.id,
                clip: clip,
                storyUpdatedAt: story.updatedAt
            ) != nil else {
                downloadFailure = "One or more story audio tracks could not be downloaded."
                return
            }
        }
    }
}

private enum StoryAudioResumeChoice: Equatable {
    case startOver
    case resume(StoryReaderProgress)
}

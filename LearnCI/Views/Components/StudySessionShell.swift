import SwiftUI
import SwiftData

/// Shared study workspace: block focus, transport, and optional transcript.
struct StudySessionShell<Transcript: View>: View {
    @Bindable var session: StudySessionViewModel
    @Binding var focusWindowSize: StudyFocusWindowSize
    let userID: String?
    let translationState: YouTubeStudyLoadState
    var showsTranscript: Bool = true
    var fillsAvailableHeight: Bool = false
    let transcript: () -> Transcript
    let onWordTap: (String) -> Void
    let onDefineSession: () -> Void
    let onNotes: () -> Void
    let onFocusWindowSizeChange: (StudyFocusWindowSize) -> Void

    @Query private var allNotes: [StudyNote]

    init(
        session: StudySessionViewModel,
        userID: String?,
        focusWindowSize: Binding<StudyFocusWindowSize>,
        translationState: YouTubeStudyLoadState,
        showsTranscript: Bool = true,
        fillsAvailableHeight: Bool = false,
        @ViewBuilder transcript: @escaping () -> Transcript,
        onWordTap: @escaping (String) -> Void,
        onDefineSession: @escaping () -> Void,
        onNotes: @escaping () -> Void,
        onFocusWindowSizeChange: @escaping (StudyFocusWindowSize) -> Void
    ) {
        self._session = Bindable(wrappedValue: session)
        self.userID = userID
        self._focusWindowSize = focusWindowSize
        self.translationState = translationState
        self.showsTranscript = showsTranscript
        self.fillsAvailableHeight = fillsAvailableHeight
        self.transcript = transcript
        self.onWordTap = onWordTap
        self.onDefineSession = onDefineSession
        self.onNotes = onNotes
        self.onFocusWindowSizeChange = onFocusWindowSizeChange
        _allNotes = Query(sort: \StudyNote.updatedAt, order: .reverse)
    }

    private var currentBlockNoteCount: Int {
        guard let userID, let block = session.currentBlock else { return 0 }
        return allNotes.filter {
            $0.userID == userID &&
            $0.resourceId == session.resource.resourceId &&
            $0.blockIndex == block.index
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: fillsAvailableHeight ? 10 : 16) {
            if let block = session.currentBlock {
                HStack {
                    Label("Study Block", systemImage: "text.book.closed")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    focusWindowSizePicker
                }

                StudyBlockFocusView(
                    block: block,
                    positionLabel: session.blockPositionLabel,
                    noteCount: currentBlockNoteCount,
                    expandsVertically: fillsAvailableHeight,
                    onWordTap: onWordTap
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: fillsAvailableHeight ? .infinity : nil,
                    alignment: .topLeading
                )

                StudyTransportBar(
                    canGoPrevious: session.canGoPrevious,
                    canGoNext: session.canGoNext,
                    isLooping: session.isLooping,
                    isBlockPlaying: session.isBlockPlaying,
                    isBlockPlaybackLocked: session.playbackController.isBlockPlaybackActive,
                    onPrevious: { session.goToPreviousBlock() },
                    onPlayStop: { session.togglePlayStop() },
                    onToggleLoop: { session.toggleLoopCurrentBlock() },
                    onNext: { session.goToNextBlock() }
                )

                HStack(spacing: 12) {
                    Button(action: onDefineSession) {
                        Label("Define session", systemImage: "clock.badge.checkmark")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)

                    Button(action: onNotes) {
                        Label(
                            currentBlockNoteCount > 0 ? "Notes (\(currentBlockNoteCount))" : "Notes",
                            systemImage: "note.text"
                        )
                        .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }

            if case .loading = translationState {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading translations…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showsTranscript {
                transcript()
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: fillsAvailableHeight ? .infinity : nil,
            alignment: .topLeading
        )
    }

    private var focusWindowSizePicker: some View {
        HStack(spacing: 6) {
            ForEach(StudyFocusWindowSize.allCases) { size in
                Button {
                    focusWindowSize = size
                    onFocusWindowSizeChange(size)
                } label: {
                    Text(size.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(focusWindowSize == size ? .white : .primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(focusWindowSize == size ? Color.blue : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(Capsule())
    }
}

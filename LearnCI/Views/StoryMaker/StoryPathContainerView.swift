import SwiftUI
import SwiftData

/// Outer shell for the 5-stage Story Guided Learning Path. Owns the
/// `StoryPathSessionViewModel`, hides the tab bar for the immersive flow, and
/// switches between the stage views based on `vm.currentStage`.
struct StoryPathContainerView: View {
    let story: Story
    let startAtChapter: Int?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Environment(StoryPathProgressStore.self) private var progressStore

    @State private var vm: StoryPathSessionViewModel?
    @State private var showExitConfirmation = false

    init(story: Story, startAtChapter: Int? = nil) {
        self.story = story
        self.startAtChapter = startAtChapter
    }

    var body: some View {
        Group {
            if let vm {
                content(vm: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { bootstrap() }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .storyWordLookupHost(story: story)
    }

    @ViewBuilder
    private func content(vm: StoryPathSessionViewModel) -> some View {
        VStack(spacing: 0) {
            header(vm: vm)
            Divider()
            stageBody(vm: vm)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .confirmationDialog(
            "Exit guided path?",
            isPresented: $showExitConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save & Exit") {
                vm.persist()
                dismiss()
            }
            Button("Keep Learning", role: .cancel) {}
        } message: {
            Text("Your progress is saved automatically. You can pick up on this stage from the Learn tab.")
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(vm: StoryPathSessionViewModel) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    showExitConfirmation = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(uiColor: .secondarySystemBackground), in: Circle())
                }
                .accessibilityLabel("Exit guided path")

                if vm.canGoBack {
                    Button {
                        vm.goToPreviousStage()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 36, height: 36)
                            .background(Color.accentColor.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel("Back to previous stage")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(story.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(vm.chapterTitleDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("Stage \(vm.currentStage.rawValue) of 5")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            stageRail(vm: vm)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func stageRail(vm: StoryPathSessionViewModel) -> some View {
        HStack(spacing: 6) {
            ForEach(StoryPathSessionViewModel.Stage.allCases, id: \.rawValue) { stage in
                let done = vm.stageCompletion[stage.rawValue - 1]
                let isCurrent = vm.currentStage == stage
                Capsule()
                    .fill(done ? Color.green : (isCurrent ? Color.accentColor : Color(uiColor: .tertiarySystemFill)))
                    .frame(height: 4)
                    .overlay(
                        Group {
                            if isCurrent {
                                Capsule()
                                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 2)
                            }
                        }
                    )
                    .accessibilityLabel(stage.label)
            }
        }
    }

    // MARK: - Stage body dispatch

    @ViewBuilder
    private func stageBody(vm: StoryPathSessionViewModel) -> some View {
        switch vm.currentStage {
        case .read:
            StoryPathReadStageView(vm: vm)
        case .loopListen:
            StoryPathLoopListenStageView(vm: vm)
        case .lookup:
            StoryPathLookupStageView(vm: vm)
        case .shadow:
            StoryShadowingStageView(vm: vm)
        case .planNext:
            StoryPathPlanNextStageView(vm: vm)
        }
    }

    // MARK: - Bootstrap

    private func bootstrap() {
        let effectiveChapter = startAtChapter
            ?? story.chapters.first?.chapterNumber
            ?? 1
        vm = StoryPathSessionViewModel(
            story: story,
            chapterNumber: effectiveChapter,
            userID: authManager.currentUser,
            context: modelContext,
            progressStore: progressStore
        )
    }
}

/// Shared bottom bar used across the stage views.
struct StoryPathBottomBar: View {
    let primaryTitle: String
    let primaryEnabled: Bool
    let primaryAction: () -> Void
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    var caption: String? = nil
    /// When set, tapping the primary button asks for confirmation first (guards
    /// against an accidental Continue advancing a stage).
    var confirmMessage: String? = nil

    @State private var showConfirm = false

    private func onPrimaryTap() {
        if confirmMessage != nil {
            showConfirm = true
        } else {
            primaryAction()
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                Button(action: onPrimaryTap) {
                    HStack(spacing: 6) {
                        Text(primaryTitle)
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!primaryEnabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.thinMaterial)
        .confirmationDialog(
            "Move on to the next stage?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button(primaryTitle) { primaryAction() }
            Button("Not yet", role: .cancel) {}
        } message: {
            if let confirmMessage {
                Text(confirmMessage)
            }
        }
    }
}

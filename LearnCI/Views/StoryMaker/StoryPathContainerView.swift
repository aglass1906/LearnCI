import SwiftUI
import SwiftData

/// Outer shell for Study Mode's guided flow. Owns the
/// `StoryPathSessionViewModel`, hides the tab bar, and renders by phase:
/// per-chunk stages → chunk-complete decision → session wrap-up → finished.
struct StoryPathContainerView: View {
    let story: Story

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Environment(StoryPathProgressStore.self) private var progressStore

    @State private var vm: StoryPathSessionViewModel?
    @State private var showExitConfirmation = false
    @State private var showScenePicker = false

    init(story: Story) {
        self.story = story
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
            phaseBody(vm: vm)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .confirmationDialog(
            "Exit study session?",
            isPresented: $showExitConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save & Exit") {
                vm.persist()
                dismiss()
            }
            Button("Keep Studying", role: .cancel) {}
        } message: {
            Text("Your progress is saved. This story stays in Study Mode — pick up from the Learn tab or the story page.")
        }
        .sheet(isPresented: $showScenePicker) {
            StoryScenePickerSheet(vm: vm)
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
                .accessibilityLabel("Exit study session")

                if vm.phase == .studying, vm.canGoBack {
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
                    Text(vm.chunkTitleDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if vm.phase == .studying || vm.phase == .chunkComplete {
                    Button {
                        showScenePicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(vm.chunkPositionLabel)
                                .font(.caption.weight(.semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Choose a scene to study")
                } else {
                    Text(vm.chunkPositionLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if vm.phase == .studying {
                stageRail(vm: vm)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func stageRail(vm: StoryPathSessionViewModel) -> some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(StoryPathSessionViewModel.Stage.allCases, id: \.rawValue) { stage in
                let done = vm.stageCompletion[stage.rawValue - 1]
                let isCurrent = vm.currentStage == stage
                VStack(spacing: 4) {
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
                    HStack(spacing: 3) {
                        Image(systemName: stage.systemImage)
                            .font(.system(size: 9, weight: isCurrent ? .bold : .regular))
                        Text(stage.label)
                            .font(.caption2.weight(isCurrent ? .bold : .regular))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(isCurrent ? Color.accentColor : (done ? Color.green : Color.secondary))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(stage.label)\(isCurrent ? ", current stage" : (done ? ", completed" : ""))")
            }
        }
    }

    // MARK: - Phase dispatch

    @ViewBuilder
    private func phaseBody(vm: StoryPathSessionViewModel) -> some View {
        switch vm.phase {
        case .studying:
            stageBody(vm: vm)
        case .chunkComplete:
            StoryChunkCompleteView(vm: vm)
        case .wrapUp:
            StorySessionWrapUpView(vm: vm, onExit: { dismiss() })
        case .finished:
            StoryStudyFinishedView(story: story, onDone: { dismiss() })
        }
    }

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
        }
    }

    // MARK: - Bootstrap

    private func bootstrap() {
        vm = StoryPathSessionViewModel(
            story: story,
            userID: authManager.currentUser,
            context: modelContext,
            store: progressStore
        )
    }
}

// MARK: - Chunk complete decision

private struct StoryChunkCompleteView: View {
    @Bindable var vm: StoryPathSessionViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.green)
            Text("Scene complete")
                .font(.title2.weight(.semibold))
            Text(vm.chunkPositionLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if vm.isLastChunk {
                Text("That's the last scene of this story — nice work.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()

            VStack(spacing: 10) {
                if vm.isLastChunk {
                    Button {
                        vm.beginWrapUp()
                    } label: {
                        Text("Wrap Up & Finish Story").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        vm.studyNextChunk()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Study Next Scene")
                            Image(systemName: "arrow.right")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        vm.beginWrapUp()
                    } label: {
                        Text("Finish for Today").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Session wrap-up (plan / reminder)

private struct StorySessionWrapUpView: View {
    @Bindable var vm: StoryPathSessionViewModel
    let onExit: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(NextSessionPlanManager.self) private var planManager

    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 24)
                    Text(vm.isLastChunk ? "Story finished!" : "Great session")
                        .font(.title2.weight(.semibold))
                    Text(vm.isLastChunk
                         ? "You've studied every scene in this story."
                         : "Come back tomorrow to keep your streak going.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    VStack(spacing: 12) {
                        Toggle("Remind me tomorrow", isOn: $vm.remindTomorrow)
                        if vm.remindTomorrow {
                            DatePicker("Time", selection: $vm.reminderTime, displayedComponents: [.hourAndMinute])
                        }
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            StoryPathBottomBar(
                primaryTitle: isSaving ? "Saving…" : (vm.isLastChunk ? "Finish" : "Done for Today"),
                primaryEnabled: !isSaving,
                primaryAction: finish
            )
        }
    }

    private func finish() {
        isSaving = true
        Task {
            if vm.remindTomorrow {
                await scheduleReminder()
            }
            await MainActor.run {
                isSaving = false
                if vm.isLastChunk {
                    vm.finishStory()      // → phase .finished (container shows finished view)
                } else {
                    vm.finishForToday()
                    onExit()
                }
            }
        }
    }

    private func scheduleReminder() async {
        let calendar = Calendar.current
        let scheduledFor = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date().addingTimeInterval(86_400)
        let comps = calendar.dateComponents([.hour, .minute], from: vm.reminderTime)
        let notifTime = calendar.date(bySettingHour: comps.hour ?? 8, minute: comps.minute ?? 0, second: 0, of: scheduledFor)

        _ = await planManager.upsertPlan(
            userID: authManager.currentUser,
            scheduledFor: scheduledFor,
            sourceType: .story,
            sourceID: vm.story.id.uuidString,
            sourceTitle: vm.story.title,
            chapterNumber: vm.currentChunk?.chapterNumber,
            sceneIndex: vm.currentChunk?.sceneIndex,
            targetMinutes: 10,
            wordReviewCount: 5,
            focusNote: nil,
            notificationTime: notifTime,
            in: modelContext
        )
    }
}

// MARK: - Finished

private struct StoryStudyFinishedView: View {
    let story: Story
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "trophy.fill")
                .font(.system(size: 72))
                .foregroundStyle(.yellow)
            Text("Story complete")
                .font(.title.weight(.bold))
            Text("You finished studying \(story.title). It's no longer in Study Mode.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                onDone()
            } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Scene picker

/// Sheet listing every scene of the story; tapping one jumps the guided
/// study session to it. Completed scenes show a green check, the current
/// scene is highlighted.
private struct StoryScenePickerSheet: View {
    let vm: StoryPathSessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let completed = vm.completedChunkOrdinals()
                ForEach(Array(vm.chunks.enumerated()), id: \.element.id) { index, chunk in
                    let isCurrent = index == vm.chunkOrdinal
                    Button {
                        vm.jumpToChunk(at: index)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: completed.contains(index)
                                  ? "checkmark.circle.fill"
                                  : (isCurrent ? "book.pages.fill" : "circle"))
                                .foregroundStyle(completed.contains(index)
                                                 ? Color.green
                                                 : (isCurrent ? Color.accentColor : Color.secondary))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vm.titleForChunk(chunk))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if isCurrent {
                                    Text("Currently studying")
                                        .font(.caption2)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Scenes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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

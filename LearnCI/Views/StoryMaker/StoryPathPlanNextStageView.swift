import SwiftUI
import SwiftData

/// Stage 5 — Plan the next day's session. Writes a `NextSessionPlan` via
/// `NextSessionPlanManager` and (optionally) schedules a local notification.
struct StoryPathPlanNextStageView: View {
    @Bindable var vm: StoryPathSessionViewModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Environment(NextSessionPlanManager.self) private var planManager

    @State private var isSaving: Bool = false
    @State private var didSave: Bool = false
    @State private var errorMessage: String?
    @State private var focusNote: String = ""

    // Hoisted out of `body` with explicit types to keep the SwiftUI body
    // type-checker fast (nil/closure ternaries are the usual offenders).
    private var planPrimaryTitle: String {
        if didSave { return "Done" }
        return isSaving ? "Saving..." : "Save Plan"
    }
    private var planPrimaryAction: () -> Void {
        if didSave { return { finish() } }
        return { save() }
    }
    private var planSecondaryTitle: String? {
        didSave ? nil : "Skip"
    }
    private var planSecondaryAction: (() -> Void)? {
        guard !didSave else { return nil }
        return { finish() }
    }
    private var planCaption: String {
        didSave
            ? "Your plan is queued. See you tomorrow."
            : "This shows up as \"Today's Plan\" on your Dashboard tomorrow."
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                if didSave {
                    savedConfirmation
                        .padding(20)
                } else {
                    Form {
                        Section("Which chapter tomorrow?") {
                            Picker("Chapter", selection: $vm.planNextChapter) {
                                ForEach(vm.nextChapterOptions, id: \.chapterNumber) { chap in
                                    Text(chap.titleFor(vm.story.targetLanguageCode))
                                        .tag(chap.chapterNumber)
                                }
                            }
                        }

                        Section("Target") {
                            Stepper(value: $vm.planTargetMinutes, in: 5...60, step: 5) {
                                HStack {
                                    Text("Read time")
                                    Spacer()
                                    Text("\(vm.planTargetMinutes) min").foregroundStyle(.secondary)
                                }
                            }
                            Stepper(value: $vm.planWordCount, in: 0...30, step: 1) {
                                HStack {
                                    Text("Words to review")
                                    Spacer()
                                    Text("\(vm.planWordCount)").foregroundStyle(.secondary)
                                }
                            }
                        }

                        Section("Focus (optional)") {
                            TextField("e.g. Nail past-tense verbs", text: $focusNote, axis: .vertical)
                                .lineLimit(1...3)
                        }

                        Section("Reminder") {
                            Toggle("Send a reminder", isOn: $vm.planNotificationEnabled)
                            if vm.planNotificationEnabled {
                                DatePicker(
                                    "Time",
                                    selection: $vm.planNotificationTime,
                                    displayedComponents: [.hourAndMinute]
                                )
                            }
                        }

                        if let errorMessage {
                            Section {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            StoryPathBottomBar(
                primaryTitle: planPrimaryTitle,
                primaryEnabled: !isSaving,
                primaryAction: planPrimaryAction,
                secondaryTitle: planSecondaryTitle,
                secondaryAction: planSecondaryAction,
                caption: planCaption
            )
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var header: some View {
        HStack {
            Label("Plan next session", systemImage: "calendar")
                .font(.subheadline.weight(.medium))
            Spacer()
            Text("Almost done")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    @ViewBuilder
    private var savedConfirmation: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.green)
            Text("Plan saved")
                .font(.title2.weight(.semibold))
            let chapterTitle = vm.nextChapterOptions.first(where: { $0.chapterNumber == vm.planNextChapter })?
                .titleFor(vm.story.targetLanguageCode) ?? "Chapter \(vm.planNextChapter)"
            Text("Tomorrow: \(chapterTitle) · \(vm.planTargetMinutes) min · \(vm.planWordCount) word\(vm.planWordCount == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if vm.planNotificationEnabled {
                Label("Reminder set for \(formatted(vm.planNotificationTime))", systemImage: "bell.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    // MARK: - Actions

    private func save() {
        isSaving = true
        errorMessage = nil
        let userID = authManager.currentUser
        let scheduledFor = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date().addingTimeInterval(86_400)

        // If the user asked for a reminder, combine tomorrow's date + the
        // hour/minute from the picker.
        var notificationTime: Date? = nil
        if vm.planNotificationEnabled {
            let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: vm.planNotificationTime)
            notificationTime = Calendar.current.date(
                bySettingHour: timeComponents.hour ?? 8,
                minute: timeComponents.minute ?? 0,
                second: 0,
                of: scheduledFor
            )
        }

        Task {
            _ = await planManager.upsertPlan(
                userID: userID,
                scheduledFor: scheduledFor,
                sourceType: .story,
                sourceID: vm.story.id.uuidString,
                sourceTitle: vm.story.title,
                chapterNumber: vm.planNextChapter,
                sceneIndex: nil,
                targetMinutes: vm.planTargetMinutes,
                wordReviewCount: vm.planWordCount,
                focusNote: focusNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : focusNote,
                notificationTime: notificationTime,
                in: modelContext
            )
            await MainActor.run {
                isSaving = false
                didSave = true
            }
        }
    }

    private func finish() {
        vm.complete()
        dismiss()
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

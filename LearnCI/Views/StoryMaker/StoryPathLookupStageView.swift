import SwiftUI
import SwiftData

/// Stage 3 — Look Up & Mark. The chapter body is shown with tappable words
/// (the container view's `.storyWordLookupHost(story:)` handles the sheet +
/// SavedStudyWord persistence). At the end, we surface a mini flashcard
/// review of everything saved during this stage.
struct StoryPathLookupStageView: View {
    @Bindable var vm: StoryPathSessionViewModel

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager

    @State private var sessionStart: Date = Date()
    @State private var savedWords: [SavedStudyWord] = []
    @State private var showMiniReview: Bool = false
    @State private var refreshTimer: Timer?

    private var chapter: StoryChapter? { vm.chapter }
    private var languageCode: String { vm.story.targetLanguageCode }
    private var bodyText: String {
        chapter?.bodyTextForLanguage(languageCode) ?? vm.story.targetLanguageText
    }
    private var wordTimings: [WordTiming] {
        chapter?.bodyWordTimingsForLanguage(languageCode) ?? vm.story.wordTimings
    }

    // Hoisted out of `body` with explicit types to keep the SwiftUI body
    // type-checker fast (nil/closure ternaries are the usual offenders).
    private var lookupPrimaryTitle: String {
        savedWords.isEmpty ? "Continue" : "Review \(savedWords.count) Word\(savedWords.count == 1 ? "" : "s")"
    }
    private var lookupSecondaryTitle: String? {
        savedWords.isEmpty ? nil : "Skip Review"
    }
    private var lookupSecondaryAction: (() -> Void)? {
        savedWords.isEmpty ? nil : { onContinue() }
    }
    private var lookupCaption: String {
        savedWords.isEmpty
            ? "Tap words to save them, or continue when you're ready."
            : "Ready for a quick self-check on the words you marked?"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tap any word you don't know. Interesting phrases? Long-press a word, then tap the last word to select a range.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                    TappableStoryText(
                        text: bodyText,
                        font: .system(size: 20, design: .serif),
                        lineSpacing: 8,
                        timings: wordTimings,
                        currentTime: nil,
                        activeColor: .accentColor
                    )
                    .padding(.horizontal, 20)

                    if !savedWords.isEmpty {
                        savedWordsCard
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }
                }
                .padding(.vertical, 16)
            }
            StoryPathBottomBar(
                primaryTitle: lookupPrimaryTitle,
                primaryEnabled: true,
                primaryAction: primaryTapped,
                secondaryTitle: lookupSecondaryTitle,
                secondaryAction: lookupSecondaryAction,
                caption: lookupCaption
            )
        }
        .sheet(isPresented: $showMiniReview) {
            StoryPathMiniReviewSheet(
                story: vm.story,
                words: savedWords,
                onFinish: {
                    showMiniReview = false
                    onContinue()
                }
            )
        }
        .onAppear {
            sessionStart = Date().addingTimeInterval(-1)
            refreshSaved()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
                Task { @MainActor in refreshSaved() }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
            vm.persist()
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Label("\(savedWords.count) saved", systemImage: "star.text.square")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(savedWords.isEmpty ? .secondary : Color.orange)
            Spacer()
            Text("Chapter body")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    @ViewBuilder
    private var savedWordsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Words you marked")
                .font(.subheadline.weight(.semibold))
            FlowChipRow(words: savedWords)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func primaryTapped() {
        if savedWords.isEmpty {
            onContinue()
        } else {
            showMiniReview = true
        }
    }

    private func onContinue() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        vm.advanceToNextStage()
    }

    private func refreshSaved() {
        guard let userID = authManager.currentUser else { return }
        let storyID = vm.story.id.uuidString
        let sourceTypeRaw = SavedStudyWordSourceType.story.rawValue
        let sessionStartValue = sessionStart
        let descriptor = FetchDescriptor<SavedStudyWord>(
            predicate: #Predicate {
                $0.userID == userID &&
                $0.sourceTypeRaw == sourceTypeRaw &&
                $0.sourceId == storyID &&
                $0.createdAt >= sessionStartValue
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        savedWords = fetched
        for word in fetched {
            vm.recordWordMarked(word.id)
        }
    }
}

private struct FlowChipRow: View {
    let words: [SavedStudyWord]

    var body: some View {
        // Simple wrapping layout using LazyVGrid with adaptive columns.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(words) { word in
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.caption2)
                    Text(word.word).font(.footnote.weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.15), in: Capsule())
                .foregroundStyle(Color.orange)
            }
        }
    }
}

/// Minimal review sheet — walks through the words the user just saved,
/// showing target-language form → reveal translation → next.
private struct StoryPathMiniReviewSheet: View {
    let story: Story
    let words: [SavedStudyWord]
    let onFinish: () -> Void

    @State private var index: Int = 0
    @State private var revealed: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if words.isEmpty {
                    ContentUnavailableView("No words yet", systemImage: "star", description: Text("Tap some words on the chapter and come back."))
                } else {
                    ProgressView(value: Double(index + 1), total: Double(words.count))
                        .padding(.horizontal)

                    Spacer()

                    VStack(spacing: 16) {
                        Text(words[index].word)
                            .font(.system(size: 44, weight: .semibold, design: .serif))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        if let pos = words[index].partOfSpeech, !pos.isEmpty {
                            Text(pos)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if revealed {
                            VStack(spacing: 8) {
                                if let translation = words[index].translation, !translation.isEmpty {
                                    Text(translation)
                                        .font(.title3.weight(.medium))
                                        .foregroundStyle(Color.accentColor)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)
                                } else {
                                    Text("(translation pending)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                if let sentence = words[index].sentenceTarget, !sentence.isEmpty {
                                    Text(sentence)
                                        .font(.footnote)
                                        .italic()
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)
                                }
                            }
                        }
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        if !revealed {
                            Button {
                                withAnimation { revealed = true }
                            } label: {
                                Text("Show Translation").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        } else if index < words.count - 1 {
                            Button {
                                withAnimation {
                                    index += 1
                                    revealed = false
                                }
                            } label: {
                                Text("Next").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        } else {
                            Button {
                                onFinish()
                            } label: {
                                Text("Finish Review").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Quick Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { onFinish() }
                }
            }
        }
    }
}

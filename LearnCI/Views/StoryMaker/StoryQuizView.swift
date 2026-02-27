import SwiftUI
import SwiftData

/// Full-screen quiz destination. Can receive pre-generated questions (from StorySessionView)
/// or generate them on demand (when navigated directly from StoryAboutView).
struct StoryQuizView: View {
    let story: Story
    /// Optionally pass pre-generated questions (e.g. from StorySessionView background generation).
    var preloadedQuestions: [ComprehensionQuestion]? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var questions: [ComprehensionQuestion] = []
    @State private var isLoading: Bool = false

    // Quiz state
    @State private var currentIndex: Int = 0
    @State private var selectedAnswer: Int? = nil
    @State private var score: Int = 0
    @State private var isComplete: Bool = false

    var body: some View {
        Group {
            if isLoading && questions.isEmpty {
                loadingView
            } else if isComplete {
                resultsView
            } else if !questions.isEmpty {
                questionView
            } else {
                errorView
            }
        }
        .navigationTitle("Comprehension Quiz")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isComplete) // hide back on results so we use custom button
        .onAppear { loadQuestions() }
    }

    // MARK: - Loading
    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
            Text("Generating questions…")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error
    private var errorView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("Couldn't load questions")
                .font(.headline)
            Text("Check your connection and try again.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                questions = []
                story.comprehensionQuestionsJSON = nil
                loadQuestions()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Question View
    private var questionView: some View {
        let question = questions[currentIndex]
        return VStack(alignment: .leading, spacing: 0) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: geo.size.width * CGFloat(currentIndex + 1) / CGFloat(questions.count))
                        .animation(.easeInOut, value: currentIndex)
                }
            }
            .frame(height: 4)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 12)

            Text("Question \(currentIndex + 1) of \(questions.count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(question.question)
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .lineSpacing(6)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    VStack(spacing: 10) {
                        ForEach(question.choices.indices, id: \.self) { idx in
                            Button {
                                guard selectedAnswer == nil else { return }
                                selectedAnswer = idx
                                if idx == question.correctIndex { score += 1 }
                            } label: {
                                HStack {
                                    Text(["A", "B", "C", "D"][idx])
                                        .font(.caption.bold())
                                        .frame(width: 24, height: 24)
                                        .background(choiceBadgeColor(idx: idx, correctIndex: question.correctIndex))
                                        .clipShape(Circle())
                                        .foregroundColor(.white)
                                    Text(question.choices[idx])
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                }
                                .padding()
                                .background(choiceBackground(idx: idx, correctIndex: question.correctIndex))
                                .cornerRadius(12)
                            }
                            .disabled(selectedAnswer != nil)
                        }
                    }
                    .padding(.horizontal)

                    if selectedAnswer != nil {
                        Button {
                            if currentIndex + 1 < questions.count {
                                currentIndex += 1
                                selectedAnswer = nil
                            } else {
                                isComplete = true
                            }
                        } label: {
                            Text(currentIndex + 1 < questions.count ? "Next →" : "See Results")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedAnswer)
                .padding(.bottom, 30)
            }
        }
    }

    // MARK: - Results View
    private var resultsView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Score ring
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 12)
                    .frame(width: 130, height: 130)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / CGFloat(questions.count))
                    .stroke(score >= (questions.count * 3 / 4) ? Color.green : Color.orange,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 130, height: 130)
                    .animation(.easeOut(duration: 0.8), value: score)
                VStack(spacing: 2) {
                    Text("\(score)")
                        .font(.system(size: 44, weight: .bold))
                    Text("of \(questions.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            VStack(spacing: 8) {
                Text(score >= (questions.count * 3 / 4) ? "Great job! 🎉" : "Keep practicing!")
                    .font(.title2.bold())
                Text(score >= (questions.count * 3 / 4)
                    ? "You understood the story well."
                    : "Try re-reading the story and come back.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            // Back to Stories — pops to root (the story list)
            Button {
                dismiss()
            } label: {
                Text("Back to Stories")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Choice Styling

    private func choiceBackground(idx: Int, correctIndex: Int) -> Color {
        guard let selected = selectedAnswer else { return Color(.secondarySystemBackground) }
        if idx == correctIndex { return Color.green.opacity(0.15) }
        if idx == selected { return Color.red.opacity(0.15) }
        return Color(.secondarySystemBackground)
    }

    private func choiceBadgeColor(idx: Int, correctIndex: Int) -> Color {
        guard let selected = selectedAnswer else { return Color.secondary.opacity(0.4) }
        if idx == correctIndex { return Color.green }
        if idx == selected { return Color.red }
        return Color.secondary.opacity(0.3)
    }

    // MARK: - Question Loading

    private func loadQuestions() {
        // 1. Use preloaded questions from StorySessionView if provided
        if let preloaded = preloadedQuestions, !preloaded.isEmpty {
            questions = preloaded
            return
        }
        // 2. Use cached questions from the story model
        if !story.comprehensionQuestions.isEmpty {
            questions = story.comprehensionQuestions
            return
        }
        // 3. Generate fresh questions
        isLoading = true
        Task {
            let level = LevelManager.shared.description(for: story.level)
            let generated = try? await OpenAIService().generateComprehensionQuestions(
                storyText: story.targetLanguageText,
                language: story.language.displayName,
                level: level
            )
            await MainActor.run {
                if let qs = generated, let data = try? JSONEncoder().encode(qs) {
                    story.comprehensionQuestionsJSON = String(data: data, encoding: .utf8)
                    try? modelContext.save()
                    questions = qs
                }
                isLoading = false
            }
        }
    }
}

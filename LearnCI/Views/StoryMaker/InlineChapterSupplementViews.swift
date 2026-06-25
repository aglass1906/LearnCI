import SwiftUI

struct InlineChapterQuizView: View {
    let questions: [ComprehensionQuestion]
    let title: String

    @State private var questionIndex = 0
    @State private var selectedAnswer: Int?
    @State private var answered = false

    var body: some View {
        Group {
            if questions.isEmpty {
                emptyState
            } else {
                questionContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No comprehension questions yet for this chapter.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(title)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
    }

    private var questionContent: some View {
        let question = questions[questionIndex]

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title.uppercased())
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.accentColor)
                    .tracking(0.8)

                Text("\(questionIndex + 1) / \(questions.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(question.question)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                    Button {
                        submit(index)
                    } label: {
                        Text(choice)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .background(choiceFill(index: index, question: question))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(choiceBorder(index: index, question: question), lineWidth: 1.8)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(answered)
                }

                Button(questionIndex < questions.count - 1 ? "Next Question" : "Done") {
                    advance()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!answered)
            }
            .padding(20)
        }
    }

    private func submit(_ index: Int) {
        guard !answered else { return }
        selectedAnswer = index
        answered = true
    }

    private func advance() {
        guard answered else { return }
        if questionIndex < questions.count - 1 {
            questionIndex += 1
            selectedAnswer = nil
            answered = false
            return
        }
    }

    private func choiceBorder(index: Int, question: ComprehensionQuestion) -> Color {
        guard answered, let selectedAnswer else {
            return Color.secondary.opacity(0.25)
        }
        if index == question.correctIndex { return .green }
        if index == selectedAnswer { return .red }
        return Color.secondary.opacity(0.15)
    }

    private func choiceFill(index: Int, question: ComprehensionQuestion) -> Color {
        guard answered, let selectedAnswer else {
            return Color.secondary.opacity(0.08)
        }
        if index == question.correctIndex { return Color.green.opacity(0.12) }
        if index == selectedAnswer { return Color.red.opacity(0.1) }
        return Color.secondary.opacity(0.05)
    }
}

struct InlineChapterVocabularyView: View {
    let vocabularyNote: String
    let title: String

    var body: some View {
        let note = vocabularyNote.trimmingCharacters(in: .whitespacesAndNewlines)

        Group {
            if note.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No chapter vocabulary yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(title.uppercased(), systemImage: "text.book.closed")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Color.accentColor)
                            .tracking(0.8)

                        Text(note)
                            .font(.body)
                            .lineSpacing(6)
                            .foregroundStyle(.primary)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

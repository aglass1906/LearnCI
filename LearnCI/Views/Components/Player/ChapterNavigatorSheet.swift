import SwiftUI

/// Chapter list for stories and podcasts. Tap a row to jump to that chapter.
struct ChapterNavigatorSheet: View {
    let chapters: [PlaybackChapter]
    let currentIndex: Int?
    var currentProgress: Double = 0
    var isPlaying: Bool = false
    let onSelect: (PlaybackChapter) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                        row(index: index, chapter: chapter)
                            .id(chapter.id)
                            .listRowBackground(
                                index == currentIndex ? Color.white.opacity(0.10) : Color.clear
                            )
                            .listRowSeparatorTint(Color.white.opacity(0.12))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onAppear {
                    if let currentIndex, chapters.indices.contains(currentIndex) {
                        proxy.scrollTo(chapters[currentIndex].id, anchor: .center)
                    }
                }
            }
            .background(PlayerBackground())
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func row(index: Int, chapter: PlaybackChapter) -> some View {
        let isCurrent = index == currentIndex
        let isDone = chapter.isCompleted || (currentIndex.map { index < $0 } ?? false)
        return Button {
            onSelect(chapter)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                leading(index: index, isCurrent: isCurrent, isDone: isDone)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    Text(chapter.title)
                        .font(.system(.body, design: .rounded).weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? PlayerTheme.primaryText : PlayerTheme.primaryText.opacity(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if isCurrent {
                        ProgressView(value: currentProgress)
                            .tint(PlayerTheme.accent)
                    }
                }

                Spacer(minLength: 8)

                if let duration = chapter.duration {
                    Text(PlayerTimeFormat.clock(duration))
                        .font(PlayerTheme.timeFont)
                        .foregroundStyle(PlayerTheme.secondaryText)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(index + 1). \(chapter.title)")
        .accessibilityValue(isCurrent ? "Now playing" : (isDone ? "Completed" : ""))
    }

    @ViewBuilder
    private func leading(index: Int, isCurrent: Bool, isDone: Bool) -> some View {
        if isCurrent {
            Image(systemName: "waveform")
                .foregroundStyle(PlayerTheme.accent)
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
        } else if isDone {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(PlayerTheme.secondaryText)
        } else {
            Text("\(index + 1)")
                .font(PlayerTheme.timeFont)
                .foregroundStyle(PlayerTheme.secondaryText)
        }
    }
}

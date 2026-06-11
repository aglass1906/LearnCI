import SwiftUI

/// Library / pipeline meta chips — mirrors Flutter `WorkspaceStoryHeaderChips`.
struct StoryWorkspaceMetaChips: View {
    let story: Story

    private static let cefrLevels = ["A0", "A1", "A2", "B1", "B2", "C1", "C2"]

    var body: some View {
        FlowLayout(spacing: 6) {
            metaChip(
                systemImage: "books.vertical",
                label: story.preferences.storyType.displayName,
                color: .orange,
                tooltip: "Story type"
            )
            metaChip(
                systemImage: "tag",
                label: story.preferences.genre.rawValue,
                color: .orange,
                tooltip: "Genre"
            )
            metaChip(
                systemImage: "books.vertical.fill",
                label: chapterLine,
                color: .blue,
                tooltip: chapterLine
            )
            metaChip(
                systemImage: "globe",
                label: story.language.displayName,
                color: .orange,
                tooltip: "Target language"
            )
            metaChip(
                systemImage: "brain.head.profile",
                label: cefrCode,
                color: .cyan,
                tooltip: "Pedagogical level (CEFR)"
            )
            if let profile = story.ciProfile {
                metaChip(
                    systemImage: profile.learningStrategy.systemImage,
                    label: profile.learningStrategy.shortLabel,
                    color: .green,
                    tooltip:
                        "Learning Strategy: \(profile.learningStrategy.displayName)\n\(profile.learningStrategy.description)"
                )
            }
        }
    }

    private var chapterLine: String {
        let count = story.chapters.count
        return count == 1 ? "1 chapter" : "\(count) chapters"
    }

    private var cefrCode: String {
        let index = min(max(story.level, 0), Self.cefrLevels.count - 1)
        return Self.cefrLevels[index]
    }

    private func metaChip(
        systemImage: String,
        label: String,
        color: Color,
        tooltip: String
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.32), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(tooltip)
    }
}

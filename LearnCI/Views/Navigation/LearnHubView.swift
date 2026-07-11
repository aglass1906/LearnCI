import SwiftUI
import SwiftData

struct LearnHubView: View {
    let columns = [
        GridItem(.flexible(), spacing: 16)
    ]

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(StoryPathProgressStore.self) private var pathProgressStore

    @Query private var stories: [Story]

    private var activePaths: [StoryPathProgress] {
        pathProgressStore.activeInProgress(
            for: authManager.currentUser,
            in: modelContext
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !activePaths.isEmpty {
                        continueYourStorySection
                    }

                    LazyVGrid(columns: columns, spacing: 16) {
                        NavigationLink(destination: AboutCIView()) {
                            HubPanelHero(
                                title: "Comprehensive Learning",
                                subtitle: "Study the method behind input-first language learning",
                                icon: "book.closed.fill",
                                gradient: Gradient(colors: [.blue, .teal])
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: SavedStudyWordsView()) {
                            HubPanelHero(
                                title: "Saved Study Words",
                                subtitle: "Review words saved from flashcards, stories, YouTube, and podcasts",
                                icon: "star.text.square.fill",
                                gradient: Gradient(colors: [.yellow, .orange])
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Learn")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    @ViewBuilder
    private var continueYourStorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Continue Your Story")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(activePaths.count) in progress")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                ForEach(activePaths, id: \.id) { progress in
                    if let story = story(withID: progress.storyID) {
                        NavigationLink {
                            StoryPathContainerView(story: story, startAtChapter: progress.chapterNumber)
                        } label: {
                            ContinueYourStoryRow(progress: progress, story: story)
                        }
                        .buttonStyle(.plain)
                    } else {
                        ContinueYourStoryRow(progress: progress, story: nil)
                            .opacity(0.6)
                    }
                }
            }
        }
    }

    private func story(withID storyID: String) -> Story? {
        guard let uuid = UUID(uuidString: storyID) else { return nil }
        return stories.first(where: { $0.id == uuid })
    }
}

private struct ContinueYourStoryRow: View {
    let progress: StoryPathProgress
    let story: Story?

    private var stageLabel: String {
        let stage = StoryPathSessionViewModel.Stage(rawValue: progress.currentStage) ?? .read
        return stage.label
    }

    private var lastTouchedText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: progress.updatedAt, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [.accentColor.opacity(0.75), .accentColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 52, height: 68)
                .overlay(
                    Image(systemName: "book.pages.fill")
                        .foregroundStyle(.white)
                        .font(.title2)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(progress.storyTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text("Chapter \(progress.chapterNumber) · \(stageLabel) · Stage \(progress.currentStage) of 5")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("Last opened \(lastTouchedText)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "arrow.right.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    LearnHubView()
}

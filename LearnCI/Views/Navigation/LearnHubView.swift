import SwiftUI
import SwiftData

struct LearnHubView: View {
    let columns = [
        GridItem(.flexible(), spacing: 16)
    ]

    @Environment(AuthManager.self) private var authManager

    @Query(sort: \StoryStudyState.updatedAt, order: .reverse) private var allStudyStates: [StoryStudyState]

    private var studyStates: [StoryStudyState] {
        allStudyStates.filter { $0.isActive && $0.userID == authManager.currentUser }
    }

    private var studyingSubtitle: String {
        studyStates.isEmpty
            ? "Stories you're studying scene by scene"
            : "\(studyStates.count) in progress — resume where you left off"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        NavigationLink(destination: StudyingStoriesView()) {
                            HubPanelHero(
                                title: "Studying",
                                subtitle: studyingSubtitle,
                                icon: "book.pages.fill",
                                gradient: Gradient(colors: [.purple, .indigo])
                            )
                        }
                        .buttonStyle(.plain)

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

}

/// Dedicated screen listing every story currently in Study Mode.
struct StudyingStoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(StoryPathProgressStore.self) private var pathProgressStore

    @Query private var stories: [Story]
    @Query(sort: \StoryStudyState.updatedAt, order: .reverse) private var allStudyStates: [StoryStudyState]

    private var studyStates: [StoryStudyState] {
        allStudyStates.filter { $0.isActive && $0.userID == authManager.currentUser }
    }

    var body: some View {
        Group {
            if studyStates.isEmpty {
                ContentUnavailableView {
                    Label("No stories in Study Mode", systemImage: "book.pages")
                } description: {
                    Text("Open a story and tap \u{201C}Study This Story\u{201D} to begin a guided, scene-by-scene study session.")
                }
            } else {
                List {
                    ForEach(studyStates, id: \.id) { state in
                        rowView(for: state)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pathProgressStore.unstudy(state, in: modelContext)
                                } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Studying")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func rowView(for state: StoryStudyState) -> some View {
        if let story = story(withID: state.storyID) {
            NavigationLink {
                StoryPathContainerView(story: story)
            } label: {
                StudyingRow(state: state)
            }
            .buttonStyle(.plain)
        } else {
            StudyingRow(state: state).opacity(0.6)
        }
    }

    private func story(withID storyID: String) -> Story? {
        guard let uuid = UUID(uuidString: storyID) else { return nil }
        return stories.first(where: { $0.id == uuid })
    }
}

private struct StudyingRow: View {
    let state: StoryStudyState

    private var lastTouchedText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: state.updatedAt, relativeTo: Date())
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

            VStack(alignment: .leading, spacing: 6) {
                Text(state.storyTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text("Scene \(state.currentOrdinal + 1) of \(max(1, state.totalChunks))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: state.progressFraction)
                    .tint(.accentColor)
                Text("Last studied \(lastTouchedText)")
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
        .modelContainer(for: [Story.self, StoryPathProgress.self, StoryStudyState.self], inMemory: true)
        .environment(AuthManager())
        .environment(StoryPathProgressStore())
}

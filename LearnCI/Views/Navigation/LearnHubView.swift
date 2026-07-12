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
    @Query(sort: \StoryStudyState.updatedAt, order: .reverse) private var allStudyStates: [StoryStudyState]

    private var studyStates: [StoryStudyState] {
        allStudyStates.filter { $0.isActive && $0.userID == authManager.currentUser }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !studyStates.isEmpty {
                        studyingSection
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
    private var studyingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Studying")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(studyStates.count) stor\(studyStates.count == 1 ? "y" : "ies")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                ForEach(studyStates, id: \.id) { state in
                    if let story = story(withID: state.storyID) {
                        NavigationLink {
                            StoryPathContainerView(story: story)
                        } label: {
                            StudyingRow(state: state)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                pathProgressStore.unstudy(state, in: modelContext)
                            } label: {
                                Label("Remove from Study Mode", systemImage: "minus.circle")
                            }
                        }
                    } else {
                        StudyingRow(state: state).opacity(0.6)
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

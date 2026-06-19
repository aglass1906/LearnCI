import SwiftUI

struct LearnHubView: View {
    let columns = [
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
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
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Learn")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    LearnHubView()
}

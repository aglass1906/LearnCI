import SwiftUI

struct InputHubView: View {
    @State private var showGames = false

    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                NavigationLink(destination: VideoView()) {
                    HubPanel(
                        title: "YouTube",
                        subtitle: "Subs, playlists & videos",
                        icon: "play.rectangle.fill",
                        gradient: Gradient(colors: [Color(red: 0.9, green: 0, blue: 0), .red])
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                NavigationLink(destination: PodcastListView()) {
                    HubPanel(
                        title: "Podcasts",
                        subtitle: "Audio shows & episodes",
                        icon: "headphones",
                        gradient: Gradient(colors: [.purple, .indigo])
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                NavigationLink(destination: StoryListView()) {
                    HubPanel(
                        title: "Stories",
                        subtitle: "Interactive reading",
                        icon: "sparkles.rectangle.stack.fill",
                        gradient: Gradient(colors: [.blue, .cyan])
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                NavigationLink(destination: ResourceLibraryView()) {
                    HubPanel(
                        title: "The Library",
                        subtitle: "Books & resources",
                        icon: "books.vertical.fill",
                        gradient: Gradient(colors: [.green, .mint])
                    )
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink(destination: FlashcardDeckBrowserView()) {
                    HubPanel(
                        title: "Flashcards",
                        subtitle: "Browse decks & study cards",
                        icon: "rectangle.stack.fill",
                        gradient: Gradient(colors: [.blue, .indigo])
                    )
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    showGames = true
                } label: {
                    HubPanel(
                        title: "Games",
                        subtitle: "Focused practice modes",
                        icon: "gamecontroller.fill",
                        gradient: Gradient(colors: [.orange, .pink])
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
        .sheet(isPresented: $showGames) {
            GameView(
                availableGameTypes: GameConfiguration.GameType.allCases.filter { $0 != .flashcards }
            )
        }
    }
}

#Preview {
    NavigationStack {
        InputHubView()
    }
}

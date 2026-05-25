import SwiftUI

struct InputHubView: View {
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
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}

#Preview {
    NavigationStack {
        InputHubView()
    }
}

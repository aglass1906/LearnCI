import SwiftUI

struct InputHubView: View {
    @Environment(AuthManager.self) private var authManager
    
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero Panel: Favorites
                NavigationLink(destination: FavoritesView()) {
                    HubPanelHero(
                        title: "Favorites",
                        subtitle: "Your most used channels & links",
                        icon: "heart.fill",
                        gradient: Gradient(colors: [.pink, .red])
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                // Grid for other inputs
                LazyVGrid(columns: columns, spacing: 16) {
                    NavigationLink(destination: VideoView()) {
                        HubPanel(
                            title: "YouTube",
                            subtitle: "Channels & videos",
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
                    
                    NavigationLink(destination: StoryListView(userID: authManager.currentUser)) {
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
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}

struct HubPanelHero: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: Gradient
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(gradient: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

struct HubPanel: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: Gradient
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.white)
            
            VStack(spacing: 2) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(gradient: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    NavigationStack {
        InputHubView()
            .environment(AuthManager())
    }
}

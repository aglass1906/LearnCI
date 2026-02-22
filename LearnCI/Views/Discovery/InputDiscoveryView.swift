import SwiftUI

enum DiscoveryTab: String, CaseIterable, Identifiable {
    case favorites = "Favorites"
    case videos = "Videos"
    case podcasts = "Podcasts"
    case library = "Library"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .favorites: return "heart.fill"
        case .videos: return "play.rectangle.fill"
        case .podcasts: return "headphones"
        case .library: return "books.vertical.fill"
        }
    }
}

struct InputDiscoveryView: View {
    @State private var selectedTab: DiscoveryTab = .favorites
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Tab Picker
                Picker("Discovery Mode", selection: $selectedTab) {
                    ForEach(DiscoveryTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                Group {
                    switch selectedTab {
                    case .favorites:
                        FavoritesView()
                    case .videos:
                        VideoView()
                    case .podcasts:
                        PodcastListView()
                    case .library:
                        ResourceLibraryView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Input Discovery")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    InputDiscoveryView()
}

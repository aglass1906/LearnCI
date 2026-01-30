import SwiftUI

struct VideoGridView: View {
    let videos: [YouTubeVideo]
    let isLoading: Bool
    let onLoadMore: (() -> Void)?
    @Binding var selectedVideo: YouTubeVideo?
    // We need a way to check if watched, usually via a closure or environment
    let isVideoWatched: (String) -> Bool
    
    // Initializer with reasonable defaults
    init(videos: [YouTubeVideo], isLoading: Bool = false, onLoadMore: (() -> Void)? = nil, selectedVideo: Binding<YouTubeVideo?>, isVideoWatched: @escaping (String) -> Bool) {
        self.videos = videos
        self.isLoading = isLoading
        self.onLoadMore = onLoadMore
        self._selectedVideo = selectedVideo
        self.isVideoWatched = isVideoWatched
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(videos) { video in
                    VideoCard(
                        video: video,
                        isWatched: isVideoWatched(video.id)
                    )
                    .onTapGesture {
                        selectedVideo = video
                    }
                    .onAppear {
                        if let onLoadMore = onLoadMore, video.id == videos.last?.id {
                            onLoadMore()
                        }
                    }
                }
                
                if onLoadMore != nil && isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.trailing, 4)
                        Text("Loading more...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .gridCellColumns(2)
                    .padding(.vertical, 20)
                }
            }
            .padding()
        }
    }
}

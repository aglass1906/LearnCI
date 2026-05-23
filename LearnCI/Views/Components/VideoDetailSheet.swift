import SwiftUI

struct VideoDetailSheet: View {
    let video: YouTubeVideo
    let onWatch: () -> Void
    let onLogTime: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    
    private var favoriteVideoUrl: String {
        "https://www.youtube.com/watch?v=\(video.id)"
    }
    
    @State private var watchDuration: TimeInterval = 0
    @State private var hasLoggedTime = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Embedded Player with Tracking
                    YouTubePlayerView(
                        videoID: video.id,
                        videoURL: video.videoStreamURL,
                        watchDuration: $watchDuration
                    )
                        .frame(height: 220)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                    
                    favoriteVideoBar
                    
                    Text(video.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack {
                        Text(video.channelTitle)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Duration: \(video.durationInMinutes) min")
                            .foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                    
                    // Live Watch Stats
                    if watchDuration > 0 {
                        HStack {
                            Image(systemName: "timer")
                            Text("Watching: \(Int(watchDuration))s")
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    
                    Text(video.description)
                        .font(.body)
                    
                    VStack(spacing: 12) {
                        // Manual Log Button
                        Button(action: {
                            onLogTime(Int(max(1, watchDuration / 60)))
                            hasLoggedTime = true
                        }) {
                            Label("Log Watch Time Now", systemImage: "clock.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                        
                        // User can still open external app if needed
                        Button(action: onWatch) {
                            Label("Open in YouTube App", systemImage: "arrow.up.right.video.fill")
                            .font(.headline)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.top)
                }
                .padding()
            }
            .navigationTitle("Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    FavoriteButton(
                        consumptionUrl: favoriteVideoUrl,
                        type: .youtube,
                        title: video.title,
                        author: video.channelTitle,
                        subtitle: video.durationInMinutes > 0 ? "\(video.durationInMinutes) min" : nil,
                        imageUrl: video.thumbnailURL
                    )
                    .font(.title3)
                }
            }
            .onDisappear {
                // Auto-Log if significant time watched and not manually logged
                if !hasLoggedTime && watchDuration > 10 {
                    let minutes = Int(max(1, watchDuration / 60))
                    onLogTime(minutes)
                }
            }
        }
    }
    
    private var favoriteVideoBar: some View {
        HStack(spacing: 12) {
            FavoriteButton(
                consumptionUrl: favoriteVideoUrl,
                type: .youtube,
                title: video.title,
                author: video.channelTitle,
                subtitle: video.durationInMinutes > 0 ? "\(video.durationInMinutes) min" : nil,
                imageUrl: video.thumbnailURL
            )
            .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Favorite this video")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Find it under Input → YouTube → Favorites → Saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

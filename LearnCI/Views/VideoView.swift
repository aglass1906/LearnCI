import SwiftUI
import SwiftData

struct VideoView: View {
    @Environment(YouTubeManager.self) private var youtubeManager
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    
    @State private var selectedVideo: YouTubeVideo?
    @State private var showWatchTimePrompt = false
    @State private var watchMinutes: Double = 10
    
    var userProfile: UserProfile? {
        profiles.first
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if !youtubeManager.isAuthenticated {
                    notConnectedView
                } else if youtubeManager.isLoading {
                    ProgressView("Loading videos...")
                } else if youtubeManager.videos.isEmpty {
                    ContentUnavailableView(
                        "No Videos",
                        systemImage: "play.rectangle",
                        description: Text("Connect your YouTube account to see videos")
                    )
                } else {
                    videoListView
                }
            }
            .navigationTitle("Videos")
            .toolbar {
                if youtubeManager.isAuthenticated {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { youtubeManager.loadVideos() }) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .sheet(item: $selectedVideo) { video in
                VideoDetailSheet(
                    video: video,
                    onWatch: {
                        openInYouTube(video)
                        selectedVideo = nil
                        showWatchTimePrompt = true
                    },
                    onLogTime: {
                        selectedVideo = video
                        showWatchTimePrompt = true
                    }
                )
            }
            .sheet(isPresented: $showWatchTimePrompt) {
                LogWatchTimeSheet(
                    minutes: $watchMinutes,
                    onSave: {
                        logWatchTime(Int(watchMinutes))
                        showWatchTimePrompt = false
                        watchMinutes = 10
                    }
                )
            }
        }
    }
    
    var notConnectedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)
            
            Text("Connect YouTube")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Go to Profile to connect your YouTube account")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            NavigationLink(destination: ProfileView()) {
                Label("Go to Profile", systemImage: "person.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: 300)
                    .background(Color.red)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
    
    var videoListView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(youtubeManager.videos) { video in
                    VideoCard(video: video)
                        .onTapGesture {
                            selectedVideo = video
                        }
                }
            }
            .padding()
        }
    }
    
    func openInYouTube(_ video: YouTubeVideo) {
        if let url = URL(string: "youtube://\(video.id)") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else if let webURL = URL(string: "https://www.youtube.com/watch?v=\(video.id)") {
                UIApplication.shared.open(webURL)
            }
        }
    }
    
    func logWatchTime(_ minutes: Int) {
        guard minutes > 0 else { return }
        
        let language = userProfile?.currentLanguage ?? .spanish
        let activity = UserActivity(
            date: Date(),
            minutes: minutes,
            activityType: .watchingVideos,
            language: language
        )
        modelContext.insert(activity)
    }
}

struct VideoCard: View {
    let video: YouTubeVideo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            AsyncImage(url: URL(string: video.thumbnailURL)) { image in
                image
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(16/9, contentMode: .fill)
                    .overlay {
                        ProgressView()
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Title
            Text(video.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
            
            // Channel & Duration
            HStack {
                Text(video.channelTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                Text("\(video.durationInMinutes)m")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct VideoDetailSheet: View {
    let video: YouTubeVideo
    let onWatch: () -> Void
    let onLogTime: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AsyncImage(url: URL(string: video.thumbnailURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .aspectRatio(16/9, contentMode: .fill)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
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
                    
                    Text(video.description)
                        .font(.body)
                    
                    VStack(spacing: 12) {
                        Button(action: onWatch) {
                            Label("Watch on YouTube", systemImage: "play.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .cornerRadius(10)
                        }
                        
                        Button(action: onLogTime) {
                            Label("Log Watch Time", systemImage: "clock.fill")
                                .font(.headline)
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(10)
                        }
                    }
                    .padding(.top)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct LogWatchTimeSheet: View {
    @Binding var minutes: Double
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Watch Duration")) {
                    VStack(alignment: .leading) {
                        Text("Minutes: \(Int(minutes))")
                            .foregroundStyle(.secondary)
                        Slider(value: $minutes, in: 1...120, step: 1)
                    }
                }
            }
            .navigationTitle("Log Watch Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    VideoView()
        .environment(YouTubeManager())
}

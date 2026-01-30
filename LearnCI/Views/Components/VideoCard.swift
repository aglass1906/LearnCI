import SwiftUI

struct VideoCard: View {
    let video: YouTubeVideo
    let isWatched: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Thumbnail with Overlays
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: video.thumbnailURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .aspectRatio(16/9, contentMode: .fill)
                            .overlay { ProgressView().scaleEffect(0.8) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    
                    Text("\(video.durationInMinutes)m")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.75))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .padding(6)
                }
                
                if isWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .background(Circle().fill(.white))
                        .font(.title3)
                        .padding(4)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(video.title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                // Channel info & Date
                HStack {
                    Text(video.channelTitle)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(video.publishedAt, style: .relative)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if let level = video.level {
                        Text(level.rawValue)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                    }
                }
                .font(.caption)
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

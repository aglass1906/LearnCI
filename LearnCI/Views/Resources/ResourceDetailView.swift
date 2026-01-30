import SwiftUI
import SwiftData

extension URL: Identifiable {
    public var id: String { absoluteString }
}

struct ResourceDetailView: View {
    let resource: LearningResource
    
    var body: some View {
        content
    }
    
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(DataManager.self) private var dataManager
    
    // @State private var showBrowser = false // Removed in favor of item-based sheet
    @State private var startTime: Date?
    @State private var readingDuration: TimeInterval = 0
    @State private var showTimeLogSheet = false
    @State private var logMinutes: Double = 5
    @State private var logComment: String = ""
    
    @State private var browserUrl: URL?
    
    func openUrl(_ url: URL) {
        browserUrl = url
        startTime = Date()
        // showBrowser = true // No longer needed with sheet(item:)
    }
    
    func getLinkIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "youtube": return "play.rectangle.fill"
        case "spotify", "podcast", "apple_podcasts": return "headphones"
        case "pdf": return "doc.text.fill"
        case "website": return "globe"
        default: return "link"
        }
    }
    
    func handleBrowserDismiss() {
        browserUrl = nil
        if let start = startTime {
            let end = Date()
            readingDuration = end.timeIntervalSince(start)
            
            // If read for more than 1 minute, prompt to log
            if readingDuration > 60 {
                logMinutes = max(1, round(readingDuration / 60))
                logComment = "Read: \(resource.title)"
                showTimeLogSheet = true
            }
        }
    }
    
    func saveActivity() {
        let minutes = Int(logMinutes)
        guard minutes > 0 else { return }
        
        let activity = UserActivity(
            date: Date(),
            minutes: minutes,
            activityType: mapResourceTypeToActivity(resource.type),
            language: Language(rawValue: resource.language) ?? .spanish,
            userID: authManager.currentUser,
            comment: logComment
        )
        
        modelContext.insert(activity)
        // SwiftData autosaves, try? modelContext.save() is optional but good practice
    }
    
    func mapResourceTypeToActivity(_ type: ResourceType) -> ActivityType {
        switch type {
        case .book, .website: return .reading
        case .youtube: return .watchingVideos
        case .podcast: return .podcasts
        }
    }
    
    // Helper to determine the correct favorite type and ID (Channel ID vs URL)
    func resolveFavoriteTypeAndId(_ resource: LearningResource) -> (FavoriteType, String) {
        // Default to website/url
        var type: FavoriteType = .website
        var id: String = resource.mainUrl
        
        switch resource.type {
        case .youtube:
            // Use Central Helper
            if let resolvedId = FavoritesManager.resolveChannelId(from: resource.mainUrl) {
                type = .channel
                id = resolvedId
            } else {
                 type = .website
            }
            
        case .podcast:
            type = .podcast
        default:
            type = .website
        }
        
        return (type, id)
    }
}

extension ResourceDetailView {
    // ... existing view ...
}

// Add sheets to main body
extension ResourceDetailView {
    // This wrapper is needed because `body` is computed
    // We will inject the sheet modifiers into the main details view below
}

// Re-structure struct for cleaner modifiers
extension ResourceDetailView {
    
    @ViewBuilder
    var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hero Image
                ZStack {
                    Color(UIColor.secondarySystemBackground) // Clean neutral background
                    
                    AsyncImage(url: URL(string: resource.coverImageUrl ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(20) // Extra padding for the large detail view
                            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                    } placeholder: {
                        Image(systemName: resource.type.icon)
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.3))
                    }
                }
                .frame(height: 250)
                .clipped()
                
                VStack(alignment: .leading, spacing: 16) {
                    // Title Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(resource.type.displayName.uppercased())
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                        
                        Text(resource.title)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        
                        Text(resource.author)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Metadata Badges
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Badge(text: resource.difficulty, color: .blue)
                            Badge(text: resource.language.uppercased(), color: .orange)
                            
                            ForEach(resource.tags, id: \.self) { tag in
                                Badge(text: tag, color: .gray)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About")
                            .font(.headline)
                        
                        Text(resource.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    
                    // Curator Notes
                    if let notes = resource.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Curator's Note", systemImage: "quote.opening")
                                .font(.headline)
                                .foregroundStyle(.indigo)
                            
                            Text(notes)
                                .font(.body)
                                .italic()
                                .foregroundStyle(.primary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.indigo.opacity(0.05))
                                .cornerRadius(12)
                        }
                    }
                    
                    Spacer(minLength: 20)
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        // Main URL Button
                        if let url = URL(string: resource.mainUrl), !resource.mainUrl.isEmpty {
                            HStack {
                                Button(action: {
                                    openUrl(url)
                                }) {
                                    HStack {
                                        Image(systemName: "safari")
                                        Text("Open Resource")
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption)
                                    }
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(16)
                                }
                                
                                // Favorite Main Resource Link
                                let (favType, favId) = resolveFavoriteTypeAndId(resource)
                                
                                FavoriteButton(
                                    consumptionUrl: favId,
                                    type: favType,
                                    title: resource.title,
                                    author: resource.author,
                                    imageUrl: resource.coverImageUrl,
                                    sourceResourceId: resource.id.uuidString
                                )
                                .font(.title2)
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(16)
                            }
                        }
                        
                        // Additional Resource Links
                        if let links = resource.resourceLinks {
                            ForEach(links.filter { $0.isActive ?? true }.sorted { ($0.order ?? 0) < ($1.order ?? 0) }) { link in
                                if let url = URL(string: link.url) {
                                    HStack {
                                        Button(action: {
                                            openUrl(url)
                                        }) {
                                            HStack {
                                                Image(systemName: getLinkIcon(link.type))
                                                Text(link.label.isEmpty ? "Open Link" : link.label)
                                                Spacer()
                                                Image(systemName: "arrow.up.right")
                                                    .font(.caption)
                                            }
                                            .font(.subheadline)
                                            .foregroundStyle(Color.primary)
                                            .padding()
                                            .background(Color(UIColor.secondarySystemBackground))
                                            .cornerRadius(16)
                                        }
                                        
                                        // Favorite Link
                                        FavoriteButton(
                                            consumptionUrl: link.url,
                                            type: .other, // TODO: Map link type to FavoriteType more granularly if needed
                                            title: link.label.isEmpty ? resource.title : link.label,
                                            author: resource.author,
                                            subtitle: resource.title,
                                            imageUrl: resource.coverImageUrl,
                                            sourceResourceId: resource.id.uuidString
                                        )
                                        .padding()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $browserUrl) { url in
            InAppBrowserView(url: url, onDismiss: handleBrowserDismiss)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showTimeLogSheet) {
            LogActivitySheet(
                minutes: $logMinutes,
                comment: $logComment,
                onSave: saveActivity
            )
        }
    }
}

struct Badge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

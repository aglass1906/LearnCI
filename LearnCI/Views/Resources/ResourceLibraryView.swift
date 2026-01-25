import SwiftUI
import SwiftData

struct ResourceLibraryView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Query private var allProfiles: [UserProfile]
    
    var userProfile: UserProfile? {
        allProfiles.first { $0.userID == authManager.currentUser }
    }
    
    @State private var resourceManager = ResourceManager()
    @State private var selectedFilter: ResourceType? = nil // nil = All
    
    // Convert to strict types for the Picker
    enum FilterOption: String, CaseIterable, Identifiable {
        case all = "All"
        case listen = "Listen"
        case read = "Read"
        case watch = "Watch"
        
        var id: String { rawValue }
    }
    
    enum ViewMode {
        case grid, list
    }
    
    @State private var viewMode: ViewMode = .grid
    @State private var uiFilter: FilterOption = .all
    @State private var showAddResourceSheet = false
    
    var filteredResources: [LearningResource] {
        switch uiFilter {
        case .all:
            return resourceManager.resources
        case .listen:
            return resourceManager.resources(of: .podcast)
        case .read:
            return resourceManager.resources.filter { $0.type == .book || $0.type == .website }
        case .watch:
            return resourceManager.resources(of: .youtube)
        }
    }
    
    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter Bar
                Picker("Filter", selection: $uiFilter) {
                    ForEach(FilterOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                if resourceManager.isLoading {
                    ProgressView("Loading Library...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredResources.isEmpty {
                    ContentUnavailableView(
                        "No Resources Found",
                        systemImage: "books.vertical",
                        description: Text("Try changing the filter.")
                    )
                } else {
                    ScrollView {
                        if viewMode == .grid {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(filteredResources) { resource in
                                    NavigationLink(destination: ResourceDetailView(resource: resource)) {
                                        ResourceCard(resource: resource)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding()
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredResources) { resource in
                                    NavigationLink(destination: ResourceDetailView(resource: resource)) {
                                        ResourceRow(resource: resource)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                        .padding(.leading, 80)
                                }
                            }
                            .padding()
                        }
                    }
                    .refreshable {
                         await resourceManager.loadRemoteResources(
                            client: authManager.supabase,
                            language: userProfile?.currentLanguage.code
                         )
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                Button(action: { 
                    Task { 
                        await resourceManager.loadRemoteResources(
                            client: authManager.supabase,
                            language: userProfile?.currentLanguage.code
                        ) 
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                
                Button(action: {
                    withAnimation {
                        viewMode = (viewMode == .grid) ? .list : .grid
                    }
                }) {
                    Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                }
                
                Button(action: { showAddResourceSheet = true }) {
                    Image(systemName: "plus")
                }
            }
            .onChange(of: userProfile?.currentLanguage) { _, newValue in
                if let newLang = newValue {
                    Task {
                        await resourceManager.loadRemoteResources(
                            client: authManager.supabase,
                            language: newLang.code
                        )
                    }
                }
            }
            .task {
                await resourceManager.loadRemoteResources(
                    client: authManager.supabase,
                    language: userProfile?.currentLanguage.code
                )
            }
            .sheet(isPresented: $showAddResourceSheet) {
                AddResourceSheet(
                    resourceManager: resourceManager,
                    currentLanguage: userProfile?.currentLanguage.code
                )
            }
        }
    }
    
    func openResource(_ resource: LearningResource) {
        if let url = URL(string: resource.mainUrl) {
            UIApplication.shared.open(url)
        }
    }
}

private func getLinkIcon(_ type: String) -> String {
    switch type.lowercased() {
    case "youtube": return "play.rectangle.fill"
    case "spotify", "podcast", "apple_podcasts": return "headphones"
    case "pdf": return "doc.text.fill"
    case "website": return "globe"
    default: return "link"
    }
}

struct ResourceRow: View {
    let resource: LearningResource
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail Image - Fit logic to prevent cropping logos
            ZStack {
                Color.gray.opacity(0.1)
                
                AsyncImage(url: URL(string: resource.coverImageUrl ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(4) // Slight padding so logos don't touch edges
                } placeholder: {
                    Image(systemName: resource.type.icon)
                        .font(.title2)
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 60, height: 60)
            .cornerRadius(8)
            .clipped()
            
            VStack(alignment: .leading, spacing: 4) {
                Text(resource.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(resource.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Image(systemName: resource.type.icon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text(resource.difficulty)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .cornerRadius(4)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle()) // Make full row tapable
    }
}

struct ResourceCard: View {
    let resource: LearningResource
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover Image - Clean Fit (No Blur)
            ZStack {
                Color.gray.opacity(0.05) // Subtle background base
                
                AsyncImage(url: URL(string: resource.coverImageUrl ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(12) // Generous padding for logos
                } placeholder: {
                    Image(systemName: resource.type.icon)
                        .font(.largeTitle)
                        .foregroundColor(.gray.opacity(0.3)) // Softer placeholder
                }
            }
            .frame(height: 160)
            .clipped()
            .cornerRadius(12)
            .overlay(
                // Type Badge
                Image(systemName: resource.type.icon)
                    .font(.caption)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .padding(6)
                , alignment: .topTrailing
            )
            
            // Text Content
            VStack(alignment: .leading, spacing: 4) {
                Text(resource.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Text(resource.author)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack {
                    Text(resource.difficulty)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                    
                    Spacer()
                    
                    // Link Icons
                    HStack(spacing: 6) {
                        if !resource.mainUrl.isEmpty {
                             Image(systemName: "safari")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if let links = resource.resourceLinks {
                            ForEach(Array(links.filter { $0.isActive ?? true }.sorted { ($0.order ?? 0) < ($1.order ?? 0) }.prefix(4)), id: \.id) { link in
                                Image(systemName: getLinkIcon(link.type))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            if links.filter({ $0.isActive ?? true }).count > 4 {
                                Text("+\(links.filter({ $0.isActive ?? true }).count - 4)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    ResourceLibraryView()
}

import SwiftUI

struct ResourceDetailView: View {
    let resource: LearningResource
    
    var body: some View {
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
                    
                    // Action Button
                    Button(action: openResource) {
                        HStack {
                            Image(systemName: "safari")
                            Text("Open Resource")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(16)
                    }
                }
                .padding()
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
    
    func openResource() {
        if let url = URL(string: resource.mainUrl) {
            UIApplication.shared.open(url)
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

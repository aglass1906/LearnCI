import SwiftUI
import SwiftData

struct FavoriteButton: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    
    // We can inject the manager or just use local logic, 
    // but using the manager keeps logic centralized.
    let manager = FavoritesManager()
    
    let consumptionUrl: String
    let type: FavoriteType
    let title: String
    let author: String?
    let subtitle: String?
    let imageUrl: String?
    let sourceResourceId: String?
    
    @Query private var favorites: [Favorite]
    
    init(
        consumptionUrl: String,
        type: FavoriteType,
        title: String,
        author: String? = nil,
        subtitle: String? = nil,
        imageUrl: String? = nil,
        sourceResourceId: String? = nil
    ) {
        self.consumptionUrl = consumptionUrl
        self.type = type
        self.title = title
        self.author = author
        self.subtitle = subtitle
        self.imageUrl = imageUrl
        self.sourceResourceId = sourceResourceId
        
        // Setup query to watch specific item
        let userID = UserDefaults.standard.string(forKey: "userID") ?? "" // Fallback or need auth injection
        _favorites = Query(filter: #Predicate<Favorite> {
            $0.consumptionUrl == consumptionUrl // && $0.userID == userID (predicate limitation, handled in logic)
        })
    }
    
    // Computed property to check if *this* user has favored it
    var isFavorited: Bool {
        guard let currentUser = authManager.currentUser else { return false }
        return favorites.contains { $0.userID == currentUser }
    }
    
    var body: some View {
        Button(action: {
            print("DEBUG: FavoriteButton tapped. Current User: \(String(describing: authManager.currentUser))")
            guard let currentUser = authManager.currentUser else {
                 print("DEBUG: No user logged in, cannot favorite.")
                 return 
            }
            
            manager.toggleFavorite(
                context: modelContext,
                userID: currentUser,
                consumptionUrl: consumptionUrl,
                type: type,
                title: title,
                author: author,
                subtitle: subtitle,
                imageUrl: imageUrl,
                sourceResourceId: sourceResourceId
            )
        }) {
            // Debug overlay
            ZStack {
                Image(systemName: isFavorited ? "heart.fill" : "heart")
                    .foregroundColor(isFavorited ? .red : .primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .onChange(of: favorites) { oldValue, newValue in
                print("DEBUG: FavoriteButton query updated. Count: \(newValue.count)")
            }
        }
    }
}

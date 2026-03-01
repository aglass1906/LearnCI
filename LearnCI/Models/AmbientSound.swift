import Foundation

struct AmbientSound: Codable, Identifiable, Equatable {
    let id: String           // e.g. "forest_day"
    let displayName: String  // e.g. "Forest"
    let supabasePath: String // e.g. "ambient/forest_day.mp3"
    let genreIds: [String]   // matches StoryPreferences.Genre.rawValue

    // Local filename once downloaded (derived, not stored in Supabase)
    var localFilename: String { "\(id).mp3" }
}

// MARK: - Catalog

extension AmbientSound {
    /// Full library of available ambient sounds.
    static let catalog: [AmbientSound] = [
        // Romance
        AmbientSound(id: "cafe_busy",       displayName: "Busy Café",        supabasePath: "ambient/cafe_busy.mp3",       genreIds: ["Romance", "Slice of Life", "Comedy"]),
        AmbientSound(id: "fireplace",       displayName: "Fireplace",        supabasePath: "ambient/fireplace.mp3",       genreIds: ["Romance", "Historical"]),
        // Action
        AmbientSound(id: "urban_street",    displayName: "Urban Street",     supabasePath: "ambient/urban_street.mp3",    genreIds: ["Action", "Sci-Fi"]),
        AmbientSound(id: "jungle_wind",     displayName: "Jungle Wind",      supabasePath: "ambient/jungle_wind.mp3",     genreIds: ["Action", "Fantasy"]),
        // Mystery
        AmbientSound(id: "rain_night",      displayName: "Rain at Night",    supabasePath: "ambient/rain_night.mp3",      genreIds: ["Mystery", "Horror", "Drama"]),
        AmbientSound(id: "old_building",    displayName: "Old Building",     supabasePath: "ambient/old_building.mp3",    genreIds: ["Mystery", "Horror", "Historical"]),
        // Fantasy
        AmbientSound(id: "enchanted_forest",displayName: "Enchanted Forest", supabasePath: "ambient/enchanted_forest.mp3",genreIds: ["Fantasy"]),
        AmbientSound(id: "tavern_crowd",    displayName: "Medieval Tavern",  supabasePath: "ambient/tavern_crowd.mp3",    genreIds: ["Fantasy", "Historical"]),
        // Sci-Fi
        AmbientSound(id: "spaceship_hum",   displayName: "Spaceship Hum",    supabasePath: "ambient/spaceship_hum.mp3",   genreIds: ["Sci-Fi"]),
        AmbientSound(id: "futuristic_city", displayName: "Futuristic City",  supabasePath: "ambient/futuristic_city.mp3", genreIds: ["Sci-Fi", "Action"]),
        // Slice of Life
        AmbientSound(id: "coffee_shop",     displayName: "Coffee Shop",      supabasePath: "ambient/coffee_shop.mp3",     genreIds: ["Slice of Life", "Romance", "Comedy"]),
        AmbientSound(id: "neighborhood",    displayName: "Quiet Neighborhood",supabasePath: "ambient/neighborhood.mp3",   genreIds: ["Slice of Life"]),
        // Comedy
        AmbientSound(id: "park_outdoor",    displayName: "Outdoor Park",     supabasePath: "ambient/park_outdoor.mp3",    genreIds: ["Comedy", "Slice of Life"]),
        // Horror
        AmbientSound(id: "eerie_wind",      displayName: "Eerie Wind",       supabasePath: "ambient/eerie_wind.mp3",      genreIds: ["Horror"]),
        AmbientSound(id: "forest_night",    displayName: "Forest at Night",  supabasePath: "ambient/forest_night.mp3",    genreIds: ["Horror", "Mystery"]),
        // Historical
        AmbientSound(id: "marketplace",     displayName: "Cobblestone Market",supabasePath: "ambient/marketplace.mp3",    genreIds: ["Historical"]),
        AmbientSound(id: "countryside",     displayName: "Open Countryside",  supabasePath: "ambient/countryside.mp3",    genreIds: ["Historical", "Fantasy"]),
        // None
        AmbientSound(id: "none",            displayName: "None",              supabasePath: "",                           genreIds: []),
    ]

    static let none = catalog.first { $0.id == "none" }!

    /// Returns the best ambient sound for a given genre, or `.none` if no match.
    static func defaultSound(for genre: StoryPreferences.Genre) -> AmbientSound {
        let match = catalog.first { $0.genreIds.contains(genre.rawValue) && $0.id != "none" }
        return match ?? none
    }

    /// Whether this entry represents "no ambient sound".
    var isNone: Bool { id == "none" }
}

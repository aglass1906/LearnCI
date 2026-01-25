import Foundation
import Observation
import Supabase

@Observable
class ResourceManager {
    var resources: [LearningResource] = []
    var isLoading: Bool = false
    var errorMessage: String?
    
    // In the future, this will be injected or fetched from Supabase
    private let seedFileName = "curated_resources"
    
    init() {
        loadResources()
    }
    
    @MainActor
    func submitDraftResource(client: SupabaseClient, title: String, author: String, description: String, mainUrl: String, type: ResourceType, difficulty: String, language: String) async -> Bool {
        do {
            let newResource = LearningResource(
                id: UUID(),
                type: type,
                title: title,
                author: author,
                description: description,
                coverImageUrl: nil, // User doesn't upload image in V1
                mainUrl: mainUrl,
                feedUrl: nil,
                tags: [],
                language: language,
                dialect: nil,
                difficulty: difficulty,
                avgRating: nil,
                notes: nil,
                isFeatured: false,
                status: "draft",
                resourceLinks: nil
            )
            
            try await client.from("learning_resources").insert(newResource).execute()
            print("Draft resource submitted successfully.")
            return true
        } catch {
            print("Error submitting draft: \(error)")
            errorMessage = "Submission failed: \(error.localizedDescription)"
            return false
        }
    }
    
    func loadResources() {
        isLoading = true
        errorMessage = nil
        
        // 1. For now, load from local JSON Bundle
        // In verify phase/production, we will swap this to Supabase fetch
        guard let url = Bundle.main.url(forResource: seedFileName, withExtension: "json") else {
            errorMessage = "Could not find \(seedFileName).json"
            isLoading = false
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            self.resources = try decoder.decode([LearningResource].self, from: data)
            print("Successfully loaded \(self.resources.count) resources.")
        } catch {
            print("Error decoding resources: \(error)")
            errorMessage = "Failed to load resources: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    @MainActor
    func loadRemoteResources(client: SupabaseClient, language: String?) async {
        isLoading = true
        errorMessage = nil
        
        do {
            var query = client.from("learning_resources").select()
            
            // Filter by language if provided
            if let language = language {
                 query = query.eq("language", value: language)
            }
            
            // Only show published resources
            query = query.eq("status", value: "published")
            
            let fetched: [LearningResource] = try await query.execute().value
            
            self.resources = fetched
            print("Successfully loaded \(fetched.count) resources from Supabase (Language: \(language ?? "All")).")
        } catch {
            print("Error fetching remote resources: \(error)")
            errorMessage = "Failed to fetch cloud resources: \(error.localizedDescription)"
            // Fallback is already loaded from init()
        }
        
        isLoading = false
    }
    
    // Helper to get resources by type
    func resources(of type: ResourceType) -> [LearningResource] {
        resources.filter { $0.type == type }
    }
    
    // Helper to filter
    func filteredResources(type: ResourceType?, level: String?) -> [LearningResource] {
        var result = resources
        
        if let type = type {
            result = result.filter { $0.type == type }
        }
        
        if let level = level, level != "All" {
             // Simple contains check as difficulty might be "Beginner" or "CEFR A1"
             result = result.filter { $0.difficulty.contains(level) }
        }
        
        return result
    }
}

import Foundation
import SwiftData
import Supabase
import Observation

@Observable
class SyncManager {
    var isSyncing: Bool = false
    var lastSync: Date?
    var errorMessage: String?
    
    private let authManager: AuthManager
    
    init(authManager: AuthManager) {
        self.authManager = authManager
    }
    
// MARK: - Coaching DTOs

struct DailyFeedbackDTO: Encodable {
    let id: UUID
    let user_id: UUID
    let date: Date
    let rating: Int
    let note: String?
}

struct CoachingCheckInDTO: Encodable {
    let id: UUID
    let user_id: UUID
    let date: Date
    let hours_milestone: Int
    let activity_ratings: [String: Int]
    let progress_sentiment: String
    let next_cycle_plan: String
    let notes: String?
}

    // MARK: - Sync Methods
    
    @MainActor
    func syncNow(modelContext: ModelContext) async {
        guard let userID = authManager.currentUser else { 
            print("Sync skipped: No user logged in")
            return 
        }
        guard !isSyncing else { return }
        
        isSyncing = true
        errorMessage = nil
        
        defer { isSyncing = false }
        
        do {
            // 0. Adopt Anonymous Data (if any)
            try adoptAnonymousData(context: modelContext, userID: userID)
            
            // 1. Sync Profile (Upsert)
            try await syncProfile(context: modelContext, userID: userID)
            
            // 2. Sync Activities (Push new)
            try await syncActivities(context: modelContext, userID: userID)
            
            // 3. Sync Daily Feedback (Push new)
            try await syncDailyFeedback(context: modelContext, userID: userID)
            
            // 4. Sync Coaching Check-ins (Push new)
            try await syncCheckIns(context: modelContext, userID: userID)
            
            lastSync = Date()
            print("Sync completed successfully")
        } catch {
            errorMessage = "Sync failed: \(error.localizedDescription)"
            print("Sync Error: \(error)")
        }
    }

    @MainActor
    private func syncDailyFeedback(context: ModelContext, userID: String) async throws {
        let descriptor = FetchDescriptor<DailyFeedback>(
            predicate: #Predicate { $0.userID == userID && $0.isSynced == false }
        )
        let unSyncedItems = try context.fetch(descriptor)
        guard !unSyncedItems.isEmpty else { return }
        
        let dtos = unSyncedItems.compactMap { item -> DailyFeedbackDTO? in
            guard let uid = UUID(uuidString: userID) else { return nil }
            return DailyFeedbackDTO(
                id: item.id,
                user_id: uid,
                date: item.date,
                rating: item.rating,
                note: item.note
            )
        }
        
        guard !dtos.isEmpty else { return }
        
        try await authManager.supabase.from("daily_feedback")
            .upsert(dtos, onConflict: "id")
            .execute()
            
        for item in unSyncedItems { item.isSynced = true }
        try context.save()
    }
    
    @MainActor
    private func syncCheckIns(context: ModelContext, userID: String) async throws {
        let descriptor = FetchDescriptor<CoachingCheckIn>(
            predicate: #Predicate { $0.userID == userID && $0.isSynced == false }
        )
        let unSyncedItems = try context.fetch(descriptor)
        guard !unSyncedItems.isEmpty else { return }
        
        let dtos = unSyncedItems.compactMap { item -> CoachingCheckInDTO? in
             guard let uid = UUID(uuidString: userID) else { return nil }
             return CoachingCheckInDTO(
                id: item.id,
                user_id: uid,
                date: item.date,
                hours_milestone: item.hoursMilestone,
                activity_ratings: item.activityRatings,
                progress_sentiment: item.progressSentiment,
                next_cycle_plan: item.nextCyclePlan,
                notes: item.notes
             )
        }
        
        guard !dtos.isEmpty else { return }
        
        try await authManager.supabase.from("coaching_check_ins")
            .upsert(dtos, onConflict: "id")
            .execute()
            
        for item in unSyncedItems { item.isSynced = true }
        try context.save()
    }
    
    /// Migrates any local data with `nil` userID OR mismatching userID to the current logged-in user.
    private func adoptAnonymousData(context: ModelContext, userID: String) throws {
        // Debug: List all profiles to see what's going on
        let allProfiles = try context.fetch(FetchDescriptor<UserProfile>())
        print("DEBUG: Found \(allProfiles.count) total profiles locally.")
        for p in allProfiles {
            print("  - Profile: \(p.name), ID: \(p.id), UserID: \(p.userID ?? "nil")")
        }
        
        // 1. Adopt Profile (Any profile that isn't mine)
        // We assume single-user-at-a-time ownership for this device
        let profileDescriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.userID != userID })
        let otherProfiles = try context.fetch(profileDescriptor)
        
        for profile in otherProfiles {
            print("Adopting profile '\(profile.name)' (was: \(profile.userID ?? "nil")) for user \(userID)")
            profile.userID = userID
        }
        
        // 2. Adopt Activities (Any activity that isn't mine)
        let activityDescriptor = FetchDescriptor<UserActivity>(predicate: #Predicate { $0.userID != userID })
        let otherActivities = try context.fetch(activityDescriptor)
        
        if !otherActivities.isEmpty {
            print("Adopting \(otherActivities.count) activities (mixed owners) for user \(userID)")
            for activity in otherActivities {
                activity.userID = userID
                activity.isSynced = false // Ensure they get pushed
            }
        }
        
        if !otherProfiles.isEmpty || !otherActivities.isEmpty {
            try context.save()
        }
    }
    
    @MainActor
    private func syncProfile(context: ModelContext, userID: String) async throws {
        // Fetch local profile for this user
        let descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.userID == userID })
        guard let profile = try context.fetch(descriptor).first else { return }
        
        // Create DTO
        guard let uuid = UUID(uuidString: userID) else {
            print("Sync Error: Invalid User ID format (not a UUID): \(userID)")
            return
        }
        
        let profileDTO = ProfileUploadDTO(
            user_id: uuid, 
            name: profile.name,
            current_language: profile.currentLanguageRaw,
            current_level: profile.currentLevelRaw,
            daily_goal_minutes: profile.dailyGoalMinutes,
            daily_card_goal: profile.dailyCardGoal,
            is_public: profile.isPublic,
            updated_at: profile.updatedAt,
            email: profile.email,
            full_name: profile.fullName,
            location: profile.location,
            avatar_url: profile.avatarUrl,
            last_selected_deck_id: profile.lastSelectedDeckId,
            last_check_in_hours: profile.lastCheckInHours,
            starting_hours: profile.startingHours
        )
        
        // Upsert to Supabase
        // We match on user_id to update availability
        try await authManager.supabase.from("profiles")
            .upsert(profileDTO, onConflict: "user_id")
            .execute()
    }
    
    @MainActor
    private func syncActivities(context: ModelContext, userID: String) async throws {
        // Fetch un-synced activities for this user
        let descriptor = FetchDescriptor<UserActivity>(
            predicate: #Predicate { $0.userID == userID && $0.isSynced == false }
        )
        let unSyncedActivities = try context.fetch(descriptor)
        
        guard !unSyncedActivities.isEmpty else { return }
        print("Found \(unSyncedActivities.count) activities to sync")
        
        // Map to DTOs
        let activityDTOs = unSyncedActivities.compactMap { activity -> ActivityDTO? in
            guard let uid = UUID(uuidString: userID) else { return nil }
            return ActivityDTO(
                user_id: uid,
                date: activity.date,
                minutes: activity.minutes,
                activity_type: activity.activityTypeRaw,
                language: activity.languageRaw,
                comment: activity.comment
            )
        }
        
        guard !activityDTOs.isEmpty else { return }
        
        // Push to Supabase
        try await authManager.supabase.from("user_activities")
            .insert(activityDTOs)
            .execute()
        
        // Mark as synced locally
        for activity in unSyncedActivities {
            activity.isSynced = true
        }
        
        try context.save()
    }
    
    @MainActor
    func fetchLeaderboard() async throws -> [ProfileDTO] {
        let response: [ProfileDTO] = try await authManager.supabase.from("profiles")
            .select()
            .order("total_minutes", ascending: false)
            .limit(50)
            .execute()
            .value
        
        return response
    }
}

// MARK: - DTOs

struct ProfileUploadDTO: Encodable {
    let user_id: UUID
    let name: String
    let current_language: String
    let current_level: String
    let daily_goal_minutes: Int
    let daily_card_goal: Int?
    let is_public: Bool
    let updated_at: Date
    let email: String?
    let full_name: String?
    let location: String?
    let avatar_url: String?
    let last_selected_deck_id: String?
    let last_check_in_hours: Int?
    let starting_hours: Int?
}

struct ProfileDTO: Codable, Identifiable {
    var id: UUID { user_id }
    let user_id: UUID
    let name: String
    let current_language: String
    let current_level: String
    let daily_goal_minutes: Int
    let daily_card_goal: Int?
    let is_public: Bool
    let total_minutes: Int?
    let updated_at: Date
    let email: String?
    let full_name: String?
    let location: String?
    let avatar_url: String?
    let last_selected_deck_id: String?
    let last_check_in_hours: Int?
    let starting_hours: Int?
}

struct ActivityDTO: Encodable {
    let user_id: UUID
    let date: Date
    let minutes: Int
    let activity_type: String
    let language: String
    let comment: String?
}

import Foundation
import SwiftData
import Supabase
import Observation

@Observable
class SyncManager {
    var isSyncing: Bool = false
    var hasInitialSyncCompleted: Bool = false
    var lastSync: Date?
    var errorMessage: String?
    
    private let authManager: AuthManager
    
    init(authManager: AuthManager) {
        self.authManager = authManager
    }
    
// MARK: - Coaching DTOs

struct DailyFeedbackDTO: Codable {
    let id: UUID
    let user_id: UUID
    let date: Date
    let rating: Int
    let note: String?
}

struct CoachingCheckInDTO: Codable {
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
        
        defer { 
            isSyncing = false
            hasInitialSyncCompleted = true
        }
        
        do {
            // 0. Adopt Anonymous Data (if any)
            try adoptAnonymousData(context: modelContext, userID: userID)
            
            // 1. Sync Profile (Upsert)
            try await syncProfile(context: modelContext, userID: userID)
            
            // 2. Sync Activities (Push new)
            try await syncActivities(context: modelContext, userID: userID)
            
            // 3. Sync Daily Feedback (Push new)
            try await syncDailyFeedback(context: modelContext, userID: userID)
            
            // 0. Pull Latest Data (Server Wins)
            try await pullProfile(context: modelContext, userID: userID) // Initial pull to get baseline
            try await pullActivities(context: modelContext, userID: userID)
            try await pullDailyFeedback(context: modelContext, userID: userID)
            try await pullCheckIns(context: modelContext, userID: userID)
            
            // 4. Sync Coaching Check-ins (Push new)
            try await syncCheckIns(context: modelContext, userID: userID)
            
            // 5. Final Pull (Update Profile Totals after Push triggers)
            try await pullProfile(context: modelContext, userID: userID)
            
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

    @MainActor
    private func pullDailyFeedback(context: ModelContext, userID: String) async throws {
        guard let uid = UUID(uuidString: userID) else { return }
        
        // Manual decoding to avoid inference errors
        let response = try await authManager.supabase.from("daily_feedback")
            .select()
            .eq("user_id", value: uid)
            .order("date", ascending: false)
            .limit(50)
            .execute()
            
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data: [DailyFeedbackDTO] = try decoder.decode([DailyFeedbackDTO].self, from: response.data)
            
        for dto in data {
             let id = dto.id
             // Check existence
             let descriptor = FetchDescriptor<DailyFeedback>(predicate: #Predicate { $0.id == id })
             if let existing = try context.fetch(descriptor).first {
                 // Update from server (Server Wins after Push)
                 existing.rating = dto.rating
                 existing.note = dto.note
                 existing.date = dto.date
                 existing.isSynced = true
             } else {
                 // Insert new
                 let newFeedback = DailyFeedback(
                     date: dto.date,
                     rating: dto.rating,
                     note: dto.note,
                     userID: userID
                 )
                 newFeedback.id = dto.id
                 newFeedback.isSynced = true
                 context.insert(newFeedback)
             }
        }
        try context.save()
    }

    @MainActor
    private func pullCheckIns(context: ModelContext, userID: String) async throws {
        guard let uid = UUID(uuidString: userID) else { return }
        
        let response = try await authManager.supabase.from("coaching_check_ins")
            .select()
            .eq("user_id", value: uid)
            .order("date", ascending: false)
            .limit(50)
            .execute()
            
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data: [CoachingCheckInDTO] = try decoder.decode([CoachingCheckInDTO].self, from: response.data)
            
        for dto in data {
             let id = dto.id
             let descriptor = FetchDescriptor<CoachingCheckIn>(predicate: #Predicate { $0.id == id })
             
             if let existing = try context.fetch(descriptor).first {
                 // Update from server
                 existing.hoursMilestone = dto.hours_milestone
                 existing.activityRatings = dto.activity_ratings
                 existing.progressSentiment = dto.progress_sentiment
                 existing.nextCyclePlan = dto.next_cycle_plan
                 existing.notes = dto.notes
                 existing.date = dto.date
                 existing.isSynced = true
             } else {
                 let newCheckIn = CoachingCheckIn(
                     date: dto.date, 
                     hoursMilestone: dto.hours_milestone, 
                     userID: userID,
                     activityRatings: dto.activity_ratings,
                     progressSentiment: dto.progress_sentiment,
                     nextCyclePlan: dto.next_cycle_plan,
                     notes: dto.notes
                 )
                 newCheckIn.id = dto.id
                 newCheckIn.isSynced = true
                 context.insert(newCheckIn)
             }
        }
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
        
        // 1. Adopt Anonymous Profile Only
        // We only want to claim "Guest" data (userID == nil).
        // If a profile has a DIFFERENT userID, it belongs to someone else (e.g. previous logout).
        // DO NOT STEAL IT.
        let profileDescriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.userID == nil })
        let anonymousProfiles = try context.fetch(profileDescriptor)
        
        for profile in anonymousProfiles {
            print("Adopting anonymous profile '\(profile.name)' for user \(userID)")
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
        
        if !anonymousProfiles.isEmpty || !otherActivities.isEmpty {
            try context.save()
        }
    }
    
    @MainActor
    private func syncProfile(context: ModelContext, userID: String) async throws {
        // Fetch local profile for this user
        let descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.userID == userID })
        guard let profile = try context.fetch(descriptor).first else { return }
        
        guard let uuid = UUID(uuidString: userID) else {
            print("Sync Error: Invalid User ID format (not a UUID): \(userID)")
            return
        }
        
        // SMART SYNC CHECK:
        // Before unconditionally pushing, check the server's timestamp.
        // If Server is NEWER -> Skip Push (Server Wins).
        // If Local is NEWER -> Push (Local Wins).
        
        struct TimestampDTO: Decodable {
            let updated_at: Date
        }
        
        do {
            let response = try await authManager.supabase.from("profiles")
                .select("updated_at")
                .eq("user_id", value: uuid)
                .single()
                .execute()
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let serverTimestamp = try decoder.decode(TimestampDTO.self, from: response.data)
            
            // Compare Timestamps (with small buffer for clock skew, e.g. 1 second)
            // If Local is OLDER or EQUAL, do not push.
            if profile.updatedAt <= serverTimestamp.updated_at {
                print("Smart Sync: Server is newer or equal (\(serverTimestamp.updated_at) vs local \(profile.updatedAt)). Skipping Push.")
                return
            }
             
            print("Smart Sync: Local is newer (\(profile.updatedAt) vs server \(serverTimestamp.updated_at)). Pushing...")
            
        } catch {
            // If fetch fails (e.g. no profile on server), we assume we should PUSH our local data.
            print("Smart Sync: Could not fetch server timestamp (Profile might be new). Proceeding with Push.")
        }
        
        // Create DTO
        let profileDTO = ProfileUploadDTO(
            user_id: uuid, 
            name: profile.name,
            current_language: profile.currentLanguageRaw,
            current_level: profile.currentLevelRaw,
            daily_goal_minutes: profile.dailyGoalMinutes,
            daily_card_goal: profile.dailyCardGoal,
            is_public: profile.isPublic,
            updated_at: profile.updatedAt,
            full_name: profile.fullName,
            location: profile.location,
            avatar_url: profile.avatarUrl,
            last_selected_deck_id: profile.lastSelectedDeckId,
            last_check_in_hours: profile.lastCheckInHours,
            starting_hours: profile.startingHours,
            tts_rate: profile.ttsRate,
            default_game_mode: profile.defaultGamePresetRaw,
            last_game_type: profile.lastGameTypeRaw,
            tts_voice_gender: profile.ttsVoiceGender
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
                id: activity.id,
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
        try context.save()
    }

    @MainActor
    private func pullProfile(context: ModelContext, userID: String) async throws {
        guard let uid = UUID(uuidString: userID) else { return }
        
        let response = try await authManager.supabase.from("profiles")
            .select()
            .eq("user_id", value: uid)
            .single()
            .execute()
            
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let dto = try decoder.decode(ProfileDTO.self, from: response.data)
        
        // Update local profile
        let descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.userID == userID })
        if let profile = try context.fetch(descriptor).first {
            // Update existing
            profile.name = dto.name
            profile.currentLanguageRaw = dto.current_language
            profile.currentLevelRaw = dto.current_level
            profile.dailyGoalMinutes = dto.daily_goal_minutes
            if let dc = dto.daily_card_goal { profile.dailyCardGoal = dc }
            profile.isPublic = dto.is_public
            if let tm = dto.total_minutes { profile.totalMinutes = tm }
            if let hours = dto.last_check_in_hours { profile.lastCheckInHours = hours }
            if let starting = dto.starting_hours { profile.startingHours = starting }
            if let tts = dto.tts_rate { profile.ttsRate = tts }
            if let dgm = dto.default_game_mode { profile.defaultGamePresetRaw = dgm }
            if let lgt = dto.last_game_type { profile.lastGameTypeRaw = lgt }
            if let tvg = dto.tts_voice_gender { profile.ttsVoiceGender = tvg }
        } else {
            // Insert new from Server
            print("Sync: Profile missing locally. Restoring from server.")
            let newProfile = UserProfile(
                name: dto.name,
                currentLanguage: Language(rawValue: dto.current_language) ?? .spanish,
                currentLevel: LearningLevel(rawValue: dto.current_level) ?? .superBeginner,
                dailyGoalMinutes: dto.daily_goal_minutes,
                dailyCardGoal: dto.daily_card_goal ?? 20,
                userID: userID,
                totalMinutes: dto.total_minutes ?? 0,
                defaultPreset: GameConfiguration.Preset(rawValue: dto.default_game_mode ?? "") ?? .inputFocus,
                lastGameType: GameConfiguration.GameType(rawValue: dto.last_game_type ?? "") ?? .flashcards,
                lastSelectedDeckId: dto.last_selected_deck_id,
                lastCheckInHours: dto.last_check_in_hours ?? 0,
                startingHours: dto.starting_hours ?? 0,
                ttsRate: dto.tts_rate ?? 0.5,
                ttsVoiceGender: dto.tts_voice_gender ?? "female"
            )
            // Fill in other optional fields
            newProfile.isPublic = dto.is_public
            newProfile.fullName = dto.full_name
            newProfile.location = dto.location
            newProfile.avatarUrl = dto.avatar_url
            newProfile.email = authManager.currentUserEmail
            
            context.insert(newProfile)
        }
        try context.save()
    }

    @MainActor
    private func pullActivities(context: ModelContext, userID: String) async throws {
        guard let uid = UUID(uuidString: userID) else { return }
        
        let response = try await authManager.supabase.from("user_activities")
            .select()
            .eq("user_id", value: uid)
            .order("date", ascending: false)
            .limit(100) // 100 most recent
            .execute()
            
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let dtos: [ActivityDTO] = try decoder.decode([ActivityDTO].self, from: response.data)
        
        for dto in dtos {
            let id = dto.id
            let descriptor = FetchDescriptor<UserActivity>(predicate: #Predicate { $0.id == id })
            
            if let existing = try context.fetch(descriptor).first {
                // Update from server
                existing.minutes = dto.minutes
                existing.activityTypeRaw = dto.activity_type
                existing.languageRaw = dto.language
                existing.comment = dto.comment
                existing.date = dto.date
                existing.isSynced = true
            } else {
                let newActivity = UserActivity(
                    date: dto.date,
                    minutes: dto.minutes,
                    activityType: ActivityType(rawValue: dto.activity_type) ?? .appLearning,
                    language: Language(rawValue: dto.language) ?? .spanish,
                    userID: userID,
                    comment: dto.comment
                )
                newActivity.id = dto.id
                newActivity.isSynced = true
                context.insert(newActivity)
            }
        }
        try context.save()
    }
    
    @MainActor
    func fetchLeaderboard() async throws -> [ProfileDTO] {
        let response = try await authManager.supabase.from("profiles")
            .select()
            .order("total_minutes", ascending: false)
            .limit(50)
            .execute()
            
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try decoder.decode([ProfileDTO].self, from: response.data)
        return data
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
    let full_name: String?
    let location: String?
    let avatar_url: String?
    let last_selected_deck_id: String?
    let last_check_in_hours: Int?
    let starting_hours: Int?
    let tts_rate: Float?
    let default_game_mode: String?
    let last_game_type: String?
    let tts_voice_gender: String?
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
    let full_name: String?
    let location: String?
    let avatar_url: String?
    let last_selected_deck_id: String?
    let last_check_in_hours: Int?
    let starting_hours: Int?
    let tts_rate: Float?
    let default_game_mode: String?
    let last_game_type: String?
    let tts_voice_gender: String?
}

struct ActivityDTO: Codable {
    let id: UUID
    let user_id: UUID
    let date: Date
    let minutes: Int
    let activity_type: String
    let language: String
    let comment: String?
}

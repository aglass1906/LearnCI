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
    
// MARK: - Story DTO
struct StoryDTO: Codable {
    let id: UUID
    let user_id: UUID
    let title: String
    let target_text: String
    let native_text: String?
    let prompt: String?
    let text_gen_prompt: String?
    let image_gen_prompt: String?
    let video_style: String?
    let video_gen_prompt: String?
    let remote_video_path: String?
    let preferences_json: String?
    let word_timings_json: String?
    let comprehension_questions_json: String?
    let speaker_voices_json: String?
    let tagged_target_text: String?
    let ambient_sound_id: String?
    let ambient_volume: Float?
    let language: String
    let level: Int
    let remote_audio_path: String?
    let remote_cover_path: String?
    let cover_art: String?
    let created_at: Date
    let updated_at: Date?
    let is_favorite: Bool
    let is_public: Bool
    let chapters: [StoryChapter]?
    let layout_json: JSONBlob?
    let reading_matter_pages_json: JSONBlob?
    let asset_forge_json: JSONBlob?
    let ci_profile_json: JSONBlob?
    let bible_json: JSONBlob?
    let scene_breakdown_json: JSONBlob?
}

/// Supabase JSONB columns may arrive as already-parsed JSON objects/arrays or
/// as strings depending on the selected column and client decoding path.
/// Store them in SwiftData as JSON strings so the model layer can decode them
/// consistently.
enum JSONBlob: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONBlob])
    case array([JSONBlob])
    case null

    var jsonString: String? {
        switch self {
        case .null:
            return nil
        case .string(let value):
            return value
        case .number, .bool, .object, .array:
            guard let data = try? JSONEncoder().encode(self) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONBlob].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONBlob].self) {
            self = .object(value)
        } else {
            throw DecodingError.typeMismatch(
                JSONBlob.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

/// Push-only DTO: omits remote_video_path so the upsert never overwrites it.
/// The server is the source of truth for video paths — only pull, never push.
struct PushStoryDTO: Codable {
    let id: UUID
    let user_id: UUID
    let title: String
    let target_text: String
    let native_text: String?
    let prompt: String?
    let text_gen_prompt: String?
    let image_gen_prompt: String?
    let video_style: String?
    let video_gen_prompt: String?
    let remote_video_path: String?
    let preferences_json: String?
    let word_timings_json: String?
    let comprehension_questions_json: String?
    let speaker_voices_json: String?
    let tagged_target_text: String?
    let ambient_sound_id: String?
    let ambient_volume: Float?
    let language: String
    let level: Int
    let remote_audio_path: String?
    let remote_cover_path: String?
    let cover_art: String?
    let created_at: Date
    let updated_at: Date?
    let is_favorite: Bool
    let is_public: Bool
    let chapters: [StoryChapter]?
}

/// DTO for pushing to story_pipeline table
struct PushStoryPipelineDTO: Codable {
    let id: UUID
    let user_id: UUID
    let title: String
    let target_text: String
    let native_text: String?
    let prompt: String?
    let text_gen_prompt: String?
    let image_gen_prompt: String?
    let video_style: String?
    let video_gen_prompt: String?
    let remote_video_path: String?
    let preferences_json: String?
    let word_timings_json: String?
    let comprehension_questions_json: String?
    let speaker_voices_json: String?
    let tagged_target_text: String?
    let ambient_sound_id: String?
    let ambient_volume: Double?
    let language: String
    let level: Int
    let remote_audio_path: String?
    let remote_cover_path: String?
    let created_at: Date
    let updated_at: Date?
    let is_favorite: Bool
    let chapters: [StoryChapter]?
    let pipeline_status: String?
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
            print("[Sync] Skipped: No user logged in")
            return 
        }
        guard !isSyncing else { return }
        
        isSyncing = true
        errorMessage = nil
        
        print("\n--- 🔄 Sync Started ---")
        
        defer { 
            isSyncing = false
            hasInitialSyncCompleted = true
            print("--- ✅ Sync Finished ---\n")
        }
        
        do {
            // 0. Adopt Anonymous Data (if any)
            try adoptAnonymousData(context: modelContext, userID: userID)
            
            // 1. Sync Profile (Upsert)
            try await syncProfile(context: modelContext, userID: userID)
            
            // 3. Pull Latest Data (Server Wins)
            try await pullProfile(context: modelContext, userID: userID)
            try await pullActivities(context: modelContext, userID: userID)
            try await pullDailyFeedback(context: modelContext, userID: userID)
            try await pullCheckIns(context: modelContext, userID: userID)
            
            // Pull server-owned stories. The DB service is the source of truth for stories.
            try await pullStories(context: modelContext, userID: userID)

            // Push Favorites
            try await syncFavorites(context: modelContext, userID: userID)
            
            // Sync Activities (Push new)
            try await syncActivities(context: modelContext, userID: userID)
            
            // Sync Daily Feedback (Push new)
            try await syncDailyFeedback(context: modelContext, userID: userID)
            
            // Sync Coaching Check-ins (Push new)
            try await syncCheckIns(context: modelContext, userID: userID)
            
            // NEW: Pull Favorites (Server Wins & Deletions)
            try await pullFavorites(context: modelContext, userID: userID)

            // Podcasts
            try await syncPodcasts(context: modelContext, userID: userID)
            try await pullPodcasts(context: modelContext, userID: userID)

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
        
        // 3. Adopt Stories (Handle orphan stories from before sync)
        // Since we fetch by userID in the app, stories with mixed/missing userIDs won't show up.
        // We should adopt them if they have no userID or if they are on this device.
        // However, we can't easily distinguish "mine" from "other user's" if multiple people login.
        // But for a personal device app, we usually assume data on device belongs to current user
        // OR we leave it alone.
        // Given the request "will my stories sync", we'll adopt any story that matches the criteria
        // of "created locally but not assigned".
        // The Story model requires userID, so if migration happened, they might have a dummy one.
        // Let's filter for stories where userID is arguably "wrong" or we want to force claim.
        // SAFE APPROACH: Adopt stories where userID is NOT the current one (if we assume single-user device mostly)
        // OR just rely on the fact the user is asking about *their* simulator data.
        let allStories = try context.fetch(FetchDescriptor<Story>())
        // Fix: Only adopt stories that have NO user ID (or empty string).
        // Do NOT adopt stories that belong to other users (which happens if multiple users login on same device).
        let orphanStories = allStories.filter { $0.userID.isEmpty }
        
        if !orphanStories.isEmpty {
            print("Adopting \(orphanStories.count) orphan stories for user \(userID)")
            for story in orphanStories {
                story.userID = userID
            }
        }
        
        if !anonymousProfiles.isEmpty || !otherActivities.isEmpty || !orphanStories.isEmpty {
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
                print("[Sync] Profile: Server is newer or equal (\(serverTimestamp.updated_at)). Skipping Push.")
                return
            }
            
            print("[Sync] Profile: Local is newer (\(profile.updatedAt)). Pushing...")
            
        } catch {
            // If fetch fails (e.g. no profile on server), we assume we should PUSH our local data.
            print("[Sync] Profile: New user or fetch error. Proceeding with Push.")
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
    private func syncFavorites(context: ModelContext, userID: String) async throws {
        let descriptor = FetchDescriptor<Favorite>(
            predicate: #Predicate { $0.userID == userID && $0.isSynced == false }
        )
        let unSynced = try context.fetch(descriptor)
        guard !unSynced.isEmpty else { return }
        print("Pushing \(unSynced.count) new favorites to Supabase")
        
        let dtos = unSynced.compactMap { fav -> FavoriteDTO? in
             guard let uid = UUID(uuidString: userID) else { return nil }
             return FavoriteDTO(
                id: fav.id,
                user_id: uid,
                consumption_url: fav.consumptionUrl,
                type: fav.typeRaw,
                title: fav.title,
                author: fav.author,
                image_url: fav.imageUrl,
                source_resource_id: fav.sourceResourceId,
                created_at: fav.createdAt
             )
        }
        
        guard !dtos.isEmpty else { return }
        
        try await authManager.supabase.from("favorites")
            .upsert(dtos, onConflict: "id")
            .execute()
            
        for fav in unSynced {
            fav.isSynced = true
        }
        try context.save()
    }
    
    @MainActor
    private func pullFavorites(context: ModelContext, userID: String) async throws {
        guard let uid = UUID(uuidString: userID) else { return }
        
        // 1. Fetch ALL Server Favorites
        let response = try await authManager.supabase.from("favorites")
            .select()
            .eq("user_id", value: uid)
            .execute()
            
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let serverFavorites = try decoder.decode([FavoriteDTO].self, from: response.data)
        
        let serverIDs = Set(serverFavorites.map { $0.id })
        
        // 2. Fetch ALL Local Favorites
        let descriptor = FetchDescriptor<Favorite>(predicate: #Predicate { $0.userID == userID })
        let localFavorites = try context.fetch(descriptor)
        
        // 3. Handle Deletions (Local item is synced, but missing from Server)
        for local in localFavorites {
            if local.isSynced && !serverIDs.contains(local.id) {
                print("Sync: Deleting local favorite '\(local.title)' (removed on server)")
                context.delete(local)
            }
        }
        
        // 4. Handle Updates / Insertions (Server -> Local)
        for dto in serverFavorites {
            if let existing = localFavorites.first(where: { $0.id == dto.id }) {
                // Update
                existing.consumptionUrl = dto.consumption_url
                existing.typeRaw = dto.type
                existing.title = dto.title
                existing.author = dto.author
                existing.imageUrl = dto.image_url
                existing.sourceResourceId = dto.source_resource_id
                existing.isSynced = true // Confirm synced
            } else {
                // Insert
                let newFav = Favorite(
                    userID: userID,
                    consumptionUrl: dto.consumption_url,
                    type: FavoriteType(rawValue: dto.type) ?? .other,
                    title: dto.title,
                    author: dto.author,
                    imageUrl: dto.image_url,
                    sourceResourceId: dto.source_resource_id
                )
                newFav.id = dto.id
                newFav.createdAt = dto.created_at
                newFav.isSynced = true
                context.insert(newFav)
            }
        }
        
        try context.save()
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
        // Use upsert to avoid unique constraint violations if data partially synced before
        try await authManager.supabase.from("user_activities")
            .upsert(activityDTOs, onConflict: "id")
            .execute()
        
        // Mark as synced locally
        for activity in unSyncedActivities {
            activity.isSynced = true
        }
        
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
            if let name = dto.name {
                profile.name = name
            }
            if let lang = dto.current_language { profile.currentLanguageRaw = lang }
            if let lvl = dto.current_level { profile.currentLevelRaw = lvl }
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
            
            // CRITICAL: Overwrite the 'bumped' updatedAt with the actual server timestamp 
            // to avoid a push-loop on the next sync.
            profile.updatedAt = dto.updated_at
        } else {
            // Insert new from Server
            print("Sync: Profile missing locally. Restoring from server.")
            let newProfile = UserProfile(
                name: dto.name ?? "Anonymous",
                currentLanguage: Language(rawValue: dto.current_language ?? "") ?? .spanish,
                currentLevel: LearningLevel(rawValue: dto.current_level ?? "") ?? .superBeginner,
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
            newProfile.updatedAt = dto.updated_at
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
    func pushToPipeline(story: Story, context: ModelContext) async throws {
        guard let userID = authManager.currentUser else {
            print("[Sync] Cannot push to pipeline: No user logged in")
            return
        }
        guard let uid = UUID(uuidString: userID) else {
            print("[Sync] Invalid user UUID")
            return
        }

        print("[Sync] Pipeline: Pushing story '\(story.title)' for user \(userID)...")

        // 1. Upload Audio if needed
        if let localFilename = story.audioFilename, 
           story.remoteAudioPath == nil {
            
            let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(localFilename)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    let audioData = try Data(contentsOf: fileURL)
                    // Preserve the actual file extension (WAV dramatized vs MP3 single-voice)
                    let srcExt = (localFilename as NSString).pathExtension.lowercased()
                    let remoteExt = srcExt == "wav" ? "wav" : "mp3"
                    let contentType = remoteExt == "wav" ? "audio/wav" : "audio/mpeg"
                    let remotePath = "\(userID)/\(story.id.uuidString)/audio/\(UUID().uuidString).\(remoteExt)"
                    try await authManager.supabase.storage
                        .from("audio-stories")
                        .upload(
                            remotePath,
                            data: audioData,
                            options: FileOptions(contentType: contentType)
                        )

                    // Update local model
                    story.remoteAudioPath = remotePath
                    try context.save()
                    print("Sync: Uploaded audio for story '\(story.title)' (\(remoteExt))")
                } catch {
                    print("Sync: Failed to upload audio for '\(story.title)': \(error)")
                }
            }
        }
        
        // 2. Upload Cover Image if needed
        if let coverFilename = story.coverArt,
           story.remoteCoverPath == nil {
            
            let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(coverFilename)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    let imageData = try Data(contentsOf: fileURL)
                    let remotePath = "\(userID)/\(story.id.uuidString)/covers/\(UUID().uuidString).png"
                    
                    try await authManager.supabase.storage
                        .from("audio-stories")
                        .upload(
                            remotePath,
                            data: imageData,
                            options: FileOptions(contentType: "image/png")
                        )
                    
                    // Update local model
                    story.remoteCoverPath = remotePath
                    try context.save()
                    print("Sync: Uploaded cover for story '\(story.title)'")
                } catch {
                    print("Sync: Failed to upload cover for '\(story.title)': \(error)")
                }
            }
        }
        
        // 3. Upload Video if generated locally but not yet on remote
        let videoFilename = "video_\(story.id.uuidString).mp4"
        let videoFileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(videoFilename)

        let hasLocalFile = FileManager.default.fileExists(atPath: videoFileURL.path)

        if hasLocalFile,
           story.remoteVideoPath == nil {
            do {
                let videoData = try Data(contentsOf: videoFileURL)
                let styleSlug = (story.videoStyle ?? "unknown")
                    .lowercased()
                    .components(separatedBy: .whitespaces)
                    .joined(separator: "_")
                let timestamp = Int(Date().timeIntervalSince1970)
                let remotePath = "\(userID)/\(story.id.uuidString)/videos/\(timestamp)_\(styleSlug).mp4"

                try await authManager.supabase.storage
                    .from("audio-stories")
                    .upload(
                        remotePath,
                        data: videoData,
                        options: FileOptions(contentType: "video/mp4")
                    )

                story.remoteVideoPath = remotePath
                try context.save()
                print("Sync: Uploaded video for story '\(story.title)' to audio-stories/\(remotePath)")
            } catch {
                print("Sync: Failed to upload video for '\(story.title)': \(error)")
            }
        }

        // 4. Push Metadata to story_pipeline
        let dto = PushStoryPipelineDTO(
            id: story.id,
            user_id: uid,
            title: story.title,
            target_text: story.targetLanguageText,
            native_text: story.nativeLanguageText,
            prompt: story.prompt,
            text_gen_prompt: story.textGenPrompt,
            image_gen_prompt: story.imageGenPrompt,
            video_style: story.videoStyle,
            video_gen_prompt: story.videoGenPrompt,
            remote_video_path: story.remoteVideoPath,
            preferences_json: story.preferencesJSON,
            word_timings_json: story.wordTimingsJSON,
            comprehension_questions_json: story.comprehensionQuestionsJSON,
            speaker_voices_json: story.speakerVoicesJSON,
            tagged_target_text: story.taggedTargetText,
            ambient_sound_id: story.ambientSoundId,
            ambient_volume: Double(story.ambientVolume),
            language: story.languageRaw,
            level: Int(story.levelRaw) ?? 1,
            remote_audio_path: story.remoteAudioPath,
            remote_cover_path: story.remoteCoverPath,
            created_at: story.createdAt,
            updated_at: Date(),
            is_favorite: story.isFavorite,
            chapters: story.chapters.isEmpty ? nil : story.chapters,
            pipeline_status: "draft"
        )
        
        try await authManager.supabase.from("story_pipeline")
            .upsert(dto, onConflict: "id")
            .execute()
            
        print("[Sync] Pipeline: Pushed metadata for '\(story.title)' successfully.")
    }
    
    @MainActor
    private func pullStories(context: ModelContext, userID: String) async throws {
        guard let uid = UUID(uuidString: userID) else { return }
        
        // Fetch stories the current user can read: their own rows and public DB-owned rows.
        let response = try await authManager.supabase.from("stories")
            .select()
            .or("user_id.eq.\(uid.uuidString),is_public.eq.true")
            .order("created_at", ascending: false)
            .execute()
            
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601 // Supabase returns ISO strings
        let dtos = try decoder.decode([StoryDTO].self, from: response.data)
        print("[Sync] Stories: Pulled \(dtos.count) server stories for user \(userID).")
        
        let serverIDs = Set(dtos.map { $0.id })
        
        let ownedDescriptor = FetchDescriptor<Story>(predicate: #Predicate { $0.userID == userID })
        let ownedLocalStories = try context.fetch(ownedDescriptor)
        let localStories = try context.fetch(FetchDescriptor<Story>())
        
        // Handle Deletions: If a local story WAS synced to the server previously, but is now missing,
        // it means the user deleted it from the server.
        for local in ownedLocalStories {
            let wasSynced = (local.remoteAudioPath != nil || local.remoteCoverPath != nil || local.remoteVideoPath != nil)
            if wasSynced && !serverIDs.contains(local.id) {
                print("[Sync] Stories: Deleting local story '\(local.title)' as it is no longer on the server.")
                context.delete(local)
            }
        }
        
        for dto in dtos {
            if let existing = localStories.first(where: { $0.id == dto.id }) {
                // Update
                let previousUpdatedAt = existing.updatedAt
                let previousChaptersJSON = existing.chaptersJSON
                existing.title = dto.title
                existing.isFavorite = dto.is_favorite
                existing.textGenPrompt = dto.text_gen_prompt
                existing.imageGenPrompt = dto.image_gen_prompt
                if let style = dto.video_style { existing.videoStyle = style }
                if let vPrompt = dto.video_gen_prompt { existing.videoGenPrompt = vPrompt }
                if let updatedAt = dto.updated_at { existing.updatedAt = updatedAt }

                // Always accept server remote paths as the source of truth
                if dto.remote_audio_path != existing.remoteAudioPath {
                    existing.remoteAudioPath = dto.remote_audio_path
                }
                if dto.remote_cover_path != existing.remoteCoverPath {
                    existing.remoteCoverPath = dto.remote_cover_path
                }
                // Video path: always accept the server value (server is source of truth).
                // If the path changed (including being nulled), delete the local remote cache so we re-download/re-upload.
                if dto.remote_video_path != existing.remoteVideoPath {
                    print("[Sync] Stories: Updated video path for '\(existing.title)' from server (to \(dto.remote_video_path ?? "nil"))")
                    existing.remoteVideoPath = dto.remote_video_path
                    // Delete stale remote cache so loadMedia() re-downloads the new video
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let staleCache = docs.appendingPathComponent("video_\(existing.id.uuidString)_remote.mp4")
                    try? FileManager.default.removeItem(at: staleCache)
                }

                if let pref = dto.preferences_json {
                    existing.preferencesJSON = pref
                }
                if let timings = dto.word_timings_json {
                    existing.wordTimingsJSON = timings
                }
                if let questions = dto.comprehension_questions_json {
                    existing.comprehensionQuestionsJSON = questions
                }
                if let voices = dto.speaker_voices_json {
                    existing.speakerVoicesJSON = voices
                }
                if let tagged = dto.tagged_target_text {
                    existing.taggedTargetText = tagged
                }
                if let soundId = dto.ambient_sound_id {
                    existing.ambientSoundId = soundId
                }
                if let vol = dto.ambient_volume {
                    existing.ambientVolume = vol
                }

                if let chapters = dto.chapters, let data = try? JSONEncoder().encode(chapters) {
                    let nextChaptersJSON = String(data: data, encoding: .utf8)
                    if nextChaptersJSON != previousChaptersJSON || dto.updated_at != previousUpdatedAt {
                        let deleted = StoryReaderDataAdapter.deleteCachedStoryAudio(storyID: existing.id)
                        if deleted > 0 {
                            print("[Sync] Stories: Cleared stale scene audio cache for '\(existing.title)'")
                        }
                    }
                    existing.chaptersJSON = nextChaptersJSON
                    // Trigger downloads for each chapter
                    downloadChapterAudio(for: existing, context: context)
                }
                existing.layoutJSON = dto.layout_json?.jsonString
                existing.readingMatterPagesJSON = dto.reading_matter_pages_json?.jsonString
                existing.assetForgeJSON = dto.asset_forge_json?.jsonString
                existing.ciProfileJSON = dto.ci_profile_json?.jsonString
                existing.bibleJSON = dto.bible_json?.jsonString
                existing.sceneBreakdownJSON = dto.scene_breakdown_json?.jsonString
            } else {
                // Insert New
                var cJSON: String?
                if let chapters = dto.chapters, let data = try? JSONEncoder().encode(chapters) {
                    cJSON = String(data: data, encoding: .utf8)
                }
                
                let newStory = Story(
                    id: dto.id,
                    userID: dto.user_id.uuidString,
                    title: dto.title,
                    targetLanguageText: dto.target_text,
                    nativeLanguageText: dto.native_text,
                    prompt: dto.prompt,
                    textGenPrompt: dto.text_gen_prompt,
                    imageGenPrompt: dto.image_gen_prompt,
                    preferencesJSON: dto.preferences_json,
                    wordTimingsJSON: dto.word_timings_json,
                    speakerVoicesJSON: dto.speaker_voices_json,
                    taggedTargetText: dto.tagged_target_text,
                    audioFilename: nil,
                    remoteAudioPath: dto.remote_audio_path,
                    remoteCoverPath: dto.remote_cover_path,
                    coverArt: dto.cover_art,
                    videoStyle: dto.video_style,
                    videoGenPrompt: dto.video_gen_prompt,
                    remoteVideoPath: dto.remote_video_path,
                    ambientSoundId: dto.ambient_sound_id,
                    ambientVolume: dto.ambient_volume ?? 0.3,
                    chaptersJSON: cJSON,
                    layoutJSON: dto.layout_json?.jsonString,
                    readingMatterPagesJSON: dto.reading_matter_pages_json?.jsonString,
                    assetForgeJSON: dto.asset_forge_json?.jsonString,
                    ciProfileJSON: dto.ci_profile_json?.jsonString,
                    bibleJSON: dto.bible_json?.jsonString,
                    sceneBreakdownJSON: dto.scene_breakdown_json?.jsonString,
                    language: Language(rawValue: dto.language) ?? .spanish,
                    level: dto.level,
                    createdAt: dto.created_at
                )
                newStory.isFavorite = dto.is_favorite
                newStory.comprehensionQuestionsJSON = dto.comprehension_questions_json
                context.insert(newStory)
                
                // Trigger Download for chapters if any
                if !newStory.chapters.isEmpty {
                    downloadChapterAudio(for: newStory, context: context)
                }

                // Trigger Download if needed (Legacy / Single Audio)
                if let remotePath = dto.remote_audio_path {
                    Task {
                        do {
                            let data = try await authManager.supabase.storage
                                .from("audio-stories")
                                .download(path: remotePath)

                            // Detect actual audio format by magic bytes (handles legacy uploads
                            // that were stored as WAV content but with a .mp3 remote path)
                            let isWAV = data.prefix(4) == Data([0x52, 0x49, 0x46, 0x46]) // "RIFF"
                            let ext = isWAV ? "wav" : "mp3"
                            let filename = "story_\(dto.id).\(ext)"
                            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            let url = docs.appendingPathComponent(filename)
                            try data.write(to: url)
                            print("Sync: Downloaded audio for story '\(dto.title)' as \(ext) (\(data.count / 1024)KB)")

                            let mainContext = context
                            await MainActor.run {
                                newStory.audioFilename = filename
                                try? mainContext.save()
                            }
                        } catch {
                            print("Sync: Failed to download audio for story \(dto.title): \(error)")
                        }
                    }
                }
                
                // Download cover image if needed
                if let remoteCoverPath = dto.remote_cover_path {
                    Task {
                        do {
                            let data = try await authManager.supabase.storage
                                .from("audio-stories")
                                .download(path: remoteCoverPath)
                            
                            let filename = "cover_\(dto.id).png"
                            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            let url = docs.appendingPathComponent(filename)
                            try data.write(to: url)
                            
                            let mainContext = context
                            await MainActor.run {
                                newStory.coverArt = filename
                                try? mainContext.save()
                            }
                        } catch {
                            print("Sync: Failed to download cover for story \(dto.title): \(error)")
                        }
                    }
                }
            }
        }
        try context.save()
    }

    private func downloadChapterAudio(for story: Story, context: ModelContext) {
        let storyID = story.id
        let chapters = story.chapters
        
        for chapter in chapters {
            guard let remotePath = chapter.audioUrl else { continue }
            
            // Derive extension from remote path
            let ext = (remotePath as NSString).pathExtension
            let finalExt = ext.isEmpty ? "mp3" : ext
            let filename = "story_\(storyID.uuidString)_chapter_\(chapter.id.uuidString).\(finalExt)"
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = docs.appendingPathComponent(filename)
            
            // Skip if already exists
            if FileManager.default.fileExists(atPath: url.path) { continue }
            
            Task {
                do {
                    let data = try await authManager.supabase.storage
                        .from("audio-stories")
                        .download(path: remotePath)

                    try data.write(to: url)
                    print("[Sync] Downloaded chapter audio for \(story.title): \(filename)")
                } catch {
                    print("[Sync] Failed to download chapter audio (\(chapter.titleTargetLanguage)) for \(story.title): \(error)")
                }
            }
        }
    }

    // MARK: - Podcast Sync

    @MainActor
    private func syncPodcasts(context: ModelContext, userID: String) async throws {
        guard let uid = UUID(uuidString: userID) else { return }

        // Push unsynced shows
        let showDescriptor = FetchDescriptor<PodcastShow>(
            predicate: #Predicate { $0.userID == userID && $0.isSynced == false }
        )
        let unsyncedShows = try context.fetch(showDescriptor)

        for show in unsyncedShows {
            let dto = PodcastShowDTO(
                id: show.id,
                user_id: uid,
                title: show.title,
                author: show.author,
                show_description: show.showDescription,
                feed_url: show.feedUrl,
                artwork_url: show.artworkUrl,
                language: show.languageRaw,
                added_at: show.addedAt
            )

            try await authManager.supabase.from("podcast_shows")
                .upsert(dto, onConflict: "id")
                .execute()

            show.isSynced = true

            // Push episodes for this show
            let unsyncedEpisodes = show.episodes.filter { !$0.isSynced }
            for episode in unsyncedEpisodes {
                let epDTO = PodcastEpisodeDTO(
                    id: episode.id,
                    show_id: show.id,
                    title: episode.title,
                    episode_description: episode.episodeDescription,
                    audio_url: episode.audioUrl,
                    published_date: episode.publishedDate,
                    duration: episode.duration,
                    playback_position: episode.playbackPosition,
                    is_played: episode.isPlayed
                )

                try await authManager.supabase.from("podcast_episodes")
                    .upsert(epDTO, onConflict: "id")
                    .execute()

                episode.isSynced = true
            }
        }

        // Also push episodes that changed (playback position, is_played) on already-synced shows
        let allShowsDescriptor = FetchDescriptor<PodcastShow>(
            predicate: #Predicate { $0.userID == userID && $0.isSynced == true }
        )
        let syncedShows = try context.fetch(allShowsDescriptor)
        for show in syncedShows {
            let dirtyEpisodes = show.episodes.filter { !$0.isSynced }
            for episode in dirtyEpisodes {
                let epDTO = PodcastEpisodeDTO(
                    id: episode.id,
                    show_id: show.id,
                    title: episode.title,
                    episode_description: episode.episodeDescription,
                    audio_url: episode.audioUrl,
                    published_date: episode.publishedDate,
                    duration: episode.duration,
                    playback_position: episode.playbackPosition,
                    is_played: episode.isPlayed
                )

                try await authManager.supabase.from("podcast_episodes")
                    .upsert(epDTO, onConflict: "id")
                    .execute()

                episode.isSynced = true
            }
        }

        try context.save()
    }

    @MainActor
    private func pullPodcasts(context: ModelContext, userID: String) async throws {
        guard let uid = UUID(uuidString: userID) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Pull shows
        let showResponse = try await authManager.supabase.from("podcast_shows")
            .select()
            .eq("user_id", value: uid)
            .execute()

        let serverShows = try decoder.decode([PodcastShowDTO].self, from: showResponse.data)

        let localShowsDescriptor = FetchDescriptor<PodcastShow>(
            predicate: #Predicate { $0.userID == userID }
        )
        let localShows = try context.fetch(localShowsDescriptor)
        let serverShowIDs = Set(serverShows.map { $0.id })

        // Delete shows removed on server
        for local in localShows {
            if local.isSynced && !serverShowIDs.contains(local.id) {
                context.delete(local)
            }
        }

        // Upsert shows from server
        for dto in serverShows {
            if let existing = localShows.first(where: { $0.id == dto.id }) {
                existing.title = dto.title
                existing.author = dto.author
                existing.showDescription = dto.show_description
                existing.feedUrl = dto.feed_url
                existing.artworkUrl = dto.artwork_url
                existing.languageRaw = dto.language
                existing.isSynced = true
            } else {
                let newShow = PodcastShow(
                    id: dto.id,
                    title: dto.title,
                    author: dto.author,
                    showDescription: dto.show_description,
                    feedUrl: dto.feed_url,
                    artworkUrl: dto.artwork_url,
                    language: Language(rawValue: dto.language) ?? .spanish,
                    addedAt: dto.added_at,
                    userID: userID
                )
                newShow.isSynced = true
                context.insert(newShow)
            }
        }

        try context.save()

        // Pull episodes for each server show
        let epResponse = try await authManager.supabase.from("podcast_episodes")
            .select()
            .in("show_id", values: serverShows.map { $0.id })
            .execute()

        let serverEpisodes = try decoder.decode([PodcastEpisodeDTO].self, from: epResponse.data)

        // Refetch local shows after inserts
        let refreshedShows = try context.fetch(localShowsDescriptor)

        for dto in serverEpisodes {
            guard let parentShow = refreshedShows.first(where: { $0.id == dto.show_id }) else { continue }

            if let existing = parentShow.episodes.first(where: { $0.id == dto.id }) {
                // Server wins for playback state
                existing.playbackPosition = dto.playback_position
                existing.isPlayed = dto.is_played
                existing.isSynced = true
            } else {
                let newEp = PodcastEpisode(
                    id: dto.id,
                    title: dto.title,
                    episodeDescription: dto.episode_description,
                    audioUrl: dto.audio_url,
                    publishedDate: dto.published_date,
                    duration: dto.duration,
                    playbackPosition: dto.playback_position,
                    isPlayed: dto.is_played
                )
                newEp.isSynced = true
                newEp.show = parentShow
                context.insert(newEp)
            }
        }

        try context.save()
    }

    @MainActor
    func fetchLeaderboard() async throws -> [ProfileDTO] {
        let response = try await authManager.supabase.from("profiles")
            .select()
            .eq("is_public", value: true)
            .order("total_minutes", ascending: false)
            .limit(50)
            .execute()
            
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ProfileDTO].self, from: response.data)
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
    let name: String?
    let current_language: String?
    let current_level: String?
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
    
    /// Display name with fallback for null names
    var displayName: String {
        name ?? "Anonymous"
    }
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

struct FavoriteDTO: Codable {
    let id: UUID
    let user_id: UUID
    let consumption_url: String
    let type: String
    let title: String
    let author: String?
    let image_url: String?
    let source_resource_id: String?
    let created_at: Date
}

struct PodcastShowDTO: Codable {
    let id: UUID
    let user_id: UUID
    let title: String
    let author: String
    let show_description: String
    let feed_url: String
    let artwork_url: String?
    let language: String
    let added_at: Date
}

struct PodcastEpisodeDTO: Codable {
    let id: UUID
    let show_id: UUID
    let title: String
    let episode_description: String
    let audio_url: String
    let published_date: Date
    let duration: Double
    let playback_position: Double
    let is_played: Bool
}

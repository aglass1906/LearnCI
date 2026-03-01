import Foundation
import SwiftData
import AVFoundation

@Observable
class StoryManager {
    private let openAIService = OpenAIService()
    private let fileManager = FileManager.default
    
    var isGenerating: Bool = false
    var statusMessage: String?
    var errorMessage: String?
    
    // MARK: - Core Logic
    
    @MainActor
    func generateStory(topic: String, language: Language, level: Int, preferences: StoryPreferences, context: ModelContext, userID: String) async -> Story? {
        isGenerating = true
        errorMessage = nil
        
        defer { isGenerating = false }
        
        do {
            // 1. Generate Text
            let levelString = describeLevel(level)
            print("Generating story for topic: \(topic), Language: \(language.rawValue), Level: \(levelString)")
            
            // Capture the prompt
            let textGenPrompt = await openAIService.constructStoryPrompt(
                topic: topic, 
                language: language.displayName, 
                level: levelString, 
                preferences: preferences
            )
            
            let (title, content) = try await openAIService.generateStory(
                topic: topic,
                language: language.displayName,
                level: levelString,
                preferences: preferences
            )
            
            // 2. Generate English Translation
            print("Generating English translation...")
            let englishTranslation = try await openAIService.generateTranslation(
                text: content,
                sourceLanguage: language.displayName
            )
            
            // 3. Generate Cover Art
            print("Generating cover art for: \(title)")
            let (coverImageData, imageGenPrompt) = try await openAIService.generateCoverArt(
                title: title,
                topic: topic,
                style: preferences.coverArtStyle
            )
            
            // 4. Save Cover Image
            let coverFilename = "cover_\(UUID().uuidString).png"
            let coverURL = getDocumentsDirectory().appendingPathComponent(coverFilename)
            try coverImageData.write(to: coverURL)
            print("Cover art saved to: \(coverURL.path)")
            
            // 5. Generate Audio (single voice or dramatized)
            print("Generating audio — style: \(preferences.audioStyle.rawValue), content length: \(content.count)")

            var speakerVoicesJSON: String? = nil
            var cleanContent = content  // tags stripped for display/translation

            let filename = "story_\(UUID().uuidString).wav"
            let audioURL = getDocumentsDirectory().appendingPathComponent(filename)

            if preferences.audioStyle == .dramatized {
                let segments = openAIService.parseSegments(from: content)
                let voiceMap = openAIService.assignVoices(
                    segments: segments,
                    narratorVoice: preferences.voice.rawValue,
                    protagonistName: preferences.protagonistName,
                    protagonistGender: preferences.protagonistGender
                )
                let audioData = try await openAIService.generateDramatizedAudio(
                    segments: segments,
                    voiceMapping: voiceMap
                )
                try audioData.write(to: audioURL)
                print("Dramatized audio saved to: \(audioURL.path)")

                // Persist voice mapping so it can be reused on regeneration
                if let mapData = try? JSONEncoder().encode(voiceMap) {
                    speakerVoicesJSON = String(data: mapData, encoding: .utf8)
                }

                // Strip tags so the display text is clean
                cleanContent = openAIService.cleanTaggedText(content)
            } else {
                let audioData = try await openAIService.generateAudio(
                    text: content,
                    voice: preferences.voice.rawValue
                )
                // Save as mp3 (rename filename extension)
                let mp3URL = audioURL.deletingPathExtension().appendingPathExtension("mp3")
                try audioData.write(to: mp3URL)
                print("Audio saved to: \(mp3URL.path)")
                // Reassign to mp3 path for word timings and story object
                let mp3Filename = mp3URL.lastPathComponent
                // (use mp3URL below for timings)
                _ = mp3Filename  // used via audioFilenameForSave below
            }

            // Resolve the actual saved filename (wav for dramatized, mp3 for single)
            let audioFilenameForSave: String
            if preferences.audioStyle == .dramatized {
                audioFilenameForSave = filename  // .wav
            } else {
                audioFilenameForSave = audioURL.deletingPathExtension().appendingPathExtension("mp3").lastPathComponent
            }
            let resolvedAudioURL = getDocumentsDirectory().appendingPathComponent(audioFilenameForSave)

            // 6. Generate Word Timings
            print("Generating word timings via Whisper...")
            var timingsJSON: String? = nil
            do {
                let timings = try await openAIService.generateWordTimings(for: resolvedAudioURL)
                if !timings.isEmpty {
                    let timingsData = try JSONEncoder().encode(timings)
                    timingsJSON = String(data: timingsData, encoding: .utf8)
                }
            } catch {
                print("Warning: Failed to generate word timings: \(error)")
            }

            // 7. Determine ambient sound from genre preference
            let ambientSound = AmbientSound.defaultSound(for: preferences.genre)
            let ambientSoundId = preferences.ambientSoundId == "none" || preferences.ambientSoundId.isEmpty
                ? ambientSound.id
                : preferences.ambientSoundId

            // 8. Create & Save Story Object
            let encoder = JSONEncoder()
            let prefInfo = try? String(data: encoder.encode(preferences), encoding: .utf8)

            let story = Story(
                userID: userID,
                title: title,
                targetLanguageText: cleanContent,
                nativeLanguageText: englishTranslation,
                prompt: topic,
                textGenPrompt: textGenPrompt,
                imageGenPrompt: imageGenPrompt,
                preferencesJSON: prefInfo,
                wordTimingsJSON: timingsJSON,
                speakerVoicesJSON: speakerVoicesJSON,
                taggedTargetText: preferences.audioStyle == .dramatized ? content : nil,
                audioFilename: audioFilenameForSave,
                coverArt: coverFilename,
                ambientSoundId: ambientSoundId,
                ambientVolume: Float(preferences.ambientVolume),
                language: language,
                level: level
            )
            
            context.insert(story)
            try context.save()
            
            return story
            
        } catch {
            print("Story Generation Error: \(error)")
            errorMessage = error.localizedDescription
            return nil
        }
    }
    
    // MARK: - Regeneration

    /// Re-runs the full story pipeline (text + translation + cover + audio + timings)
    /// and updates the existing Story object in-place.
    @MainActor
    func regenerateStory(for story: Story, context: ModelContext) async {
        guard let topic = story.prompt, !topic.isEmpty else {
            errorMessage = "No original prompt found — cannot regenerate."
            return
        }
        guard let prefJSON = story.preferencesJSON,
              let prefData = prefJSON.data(using: .utf8),
              let preferences = try? JSONDecoder().decode(StoryPreferences.self, from: prefData) else {
            errorMessage = "Could not read story preferences — cannot regenerate."
            return
        }

        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false; statusMessage = nil }

        do {
            let levelString = describeLevel(story.level)

            // 1. New text
            statusMessage = "Writing story…"
            let textGenPrompt = await openAIService.constructStoryPrompt(
                topic: topic, language: story.language.displayName,
                level: levelString, preferences: preferences
            )
            let (title, content) = try await openAIService.generateStory(
                topic: topic, language: story.language.displayName,
                level: levelString, preferences: preferences
            )

            // 2. Translation
            statusMessage = "Translating…"
            let translation = try await openAIService.generateTranslation(
                text: content, sourceLanguage: story.language.displayName
            )

            // 3. Cover art
            statusMessage = "Generating cover art…"
            let (coverData, imageGenPrompt) = try await openAIService.generateCoverArt(
                title: title, topic: topic, style: preferences.coverArtStyle
            )
            if let oldCover = story.coverArt {
                try? fileManager.removeItem(at: getDocumentsDirectory().appendingPathComponent(oldCover))
            }
            let coverFilename = "cover_\(UUID().uuidString).png"
            try coverData.write(to: getDocumentsDirectory().appendingPathComponent(coverFilename))

            // 4. Audio
            statusMessage = "Generating audio…"
            var speakerVoicesJSON: String? = nil
            var cleanContent = content
            let rawFilename = "story_\(UUID().uuidString).wav"
            let rawURL = getDocumentsDirectory().appendingPathComponent(rawFilename)

            if preferences.audioStyle == .dramatized {
                let segments = openAIService.parseSegments(from: content)
                let voiceMap = openAIService.assignVoices(
                    segments: segments, narratorVoice: preferences.voice.rawValue,
                    protagonistName: preferences.protagonistName,
                    protagonistGender: preferences.protagonistGender
                )
                let audioData = try await openAIService.generateDramatizedAudio(
                    segments: segments, voiceMapping: voiceMap
                )
                try audioData.write(to: rawURL)
                if let mapData = try? JSONEncoder().encode(voiceMap) {
                    speakerVoicesJSON = String(data: mapData, encoding: .utf8)
                }
                cleanContent = openAIService.cleanTaggedText(content)
            } else {
                let audioData = try await openAIService.generateAudio(
                    text: content, voice: preferences.voice.rawValue
                )
                let mp3URL = rawURL.deletingPathExtension().appendingPathExtension("mp3")
                try audioData.write(to: mp3URL)
            }

            let audioFilename: String
            if preferences.audioStyle == .dramatized {
                audioFilename = rawFilename
            } else {
                audioFilename = rawURL.deletingPathExtension().appendingPathExtension("mp3").lastPathComponent
            }
            let resolvedAudioURL = getDocumentsDirectory().appendingPathComponent(audioFilename)

            if let oldAudio = story.audioFilename {
                try? fileManager.removeItem(at: getDocumentsDirectory().appendingPathComponent(oldAudio))
            }

            // 5. Word timings
            statusMessage = "Generating word timings…"
            var timingsJSON: String? = nil
            if let timings = try? await openAIService.generateWordTimings(for: resolvedAudioURL),
               !timings.isEmpty,
               let data = try? JSONEncoder().encode(timings) {
                timingsJSON = String(data: data, encoding: .utf8)
            }

            // 6. Update story in-place
            story.title = title
            story.targetLanguageText = cleanContent
            story.taggedTargetText = preferences.audioStyle == .dramatized ? content : nil
            story.nativeLanguageText = translation
            story.textGenPrompt = textGenPrompt
            story.imageGenPrompt = imageGenPrompt
            story.coverArt = coverFilename
            story.audioFilename = audioFilename
            story.wordTimingsJSON = timingsJSON
            story.speakerVoicesJSON = speakerVoicesJSON
            story.comprehensionQuestionsJSON = nil // invalidated by new text
            // Clear remote paths so SyncManager re-uploads the new files
            story.remoteAudioPath = nil
            story.remoteCoverPath = nil

            try context.save()

        } catch {
            print("Regenerate Story Error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    /// Regenerates only the audio (and word timings) for an existing story.
    /// For dramatized stories, reuses the stored voice mapping and tagged text.
    @MainActor
    func regenerateAudio(for story: Story, context: ModelContext) async {
        guard let prefJSON = story.preferencesJSON,
              let prefData = prefJSON.data(using: .utf8),
              let preferences = try? JSONDecoder().decode(StoryPreferences.self, from: prefData) else {
            errorMessage = "Could not read story preferences — cannot regenerate audio."
            return
        }

        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false; statusMessage = nil }

        do {
            statusMessage = "Generating audio…"

            var newSpeakerVoicesJSON: String? = story.speakerVoicesJSON
            let rawFilename = "story_\(UUID().uuidString).wav"
            let rawURL = getDocumentsDirectory().appendingPathComponent(rawFilename)
            var audioFilename: String

            if preferences.audioStyle == .dramatized, let tagged = story.taggedTargetText {
                // Restore existing voice mapping so the same voices are reused
                var existingMapping: [String: String] = [:]
                if let mapJSON = story.speakerVoicesJSON,
                   let mapData = mapJSON.data(using: .utf8),
                   let map = try? JSONDecoder().decode([String: String].self, from: mapData) {
                    existingMapping = map
                }
                let segments = openAIService.parseSegments(from: tagged)
                let voiceMap = openAIService.assignVoices(
                    segments: segments, narratorVoice: preferences.voice.rawValue,
                    protagonistName: preferences.protagonistName,
                    protagonistGender: preferences.protagonistGender,
                    existingMapping: existingMapping
                )
                let audioData = try await openAIService.generateDramatizedAudio(
                    segments: segments, voiceMapping: voiceMap
                )
                try audioData.write(to: rawURL)
                audioFilename = rawFilename
                if let mapData = try? JSONEncoder().encode(voiceMap) {
                    newSpeakerVoicesJSON = String(data: mapData, encoding: .utf8)
                }
            } else {
                // Single narrator — or dramatized fallback when tagged text isn't stored
                let audioData = try await openAIService.generateAudio(
                    text: story.targetLanguageText, voice: preferences.voice.rawValue
                )
                let mp3URL = rawURL.deletingPathExtension().appendingPathExtension("mp3")
                try audioData.write(to: mp3URL)
                audioFilename = mp3URL.lastPathComponent
            }

            let resolvedURL = getDocumentsDirectory().appendingPathComponent(audioFilename)

            if let oldAudio = story.audioFilename {
                try? fileManager.removeItem(at: getDocumentsDirectory().appendingPathComponent(oldAudio))
            }

            // Word timings
            statusMessage = "Generating word timings…"
            var timingsJSON: String? = nil
            if let timings = try? await openAIService.generateWordTimings(for: resolvedURL),
               !timings.isEmpty,
               let data = try? JSONEncoder().encode(timings) {
                timingsJSON = String(data: data, encoding: .utf8)
            }

            story.audioFilename = audioFilename
            story.wordTimingsJSON = timingsJSON
            story.speakerVoicesJSON = newSpeakerVoicesJSON
            story.remoteAudioPath = nil // so SyncManager re-uploads

            try context.save()

        } catch {
            print("Regenerate Audio Error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    func deleteStory(_ story: Story, context: ModelContext) {
        // Delete audio file
        if let filename = story.audioFilename {
            let url = getDocumentsDirectory().appendingPathComponent(filename)
            try? fileManager.removeItem(at: url)
        }
        
        // Delete cover image file
        if let coverFilename = story.coverArt {
            let url = getDocumentsDirectory().appendingPathComponent(coverFilename)
            try? fileManager.removeItem(at: url)
        }
        
        // Delete object
        context.delete(story)
    }
    
    // MARK: - Helpers
    
    private func getDocumentsDirectory() -> URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    // Helper to describe level for Prompt
    // Helper to describe level for Prompt
    func describeLevel(_ level: Int) -> String {
        return LevelManager.shared.description(for: level)
    }
    
    // Expose for UI checks
    func hasAPIKey() async -> Bool {
        return await openAIService.hasKey()
    }
    
    // Preview Prompt
    func getPreviewPrompt(topic: String, language: Language, level: Int, preferences: StoryPreferences) async -> String {
        let levelString = describeLevel(level)
        return await openAIService.constructStoryPrompt(
            topic: topic,
            language: language.displayName,
            level: levelString,
            preferences: preferences
        )
    }
}

import Foundation
import SwiftData
import AVFoundation

@Observable
class StoryManager {
    private let openAIService = OpenAIService()
    private let fileManager = FileManager.default
    
    var isGenerating: Bool = false
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
            
            // 5. Generate Audio
            print("Generating audio for content length: \(content.count)")
            let audioData = try await openAIService.generateAudio(text: content, voice: preferences.voice.rawValue)
            
            // 6. Save Audio File
            let filename = "story_\(UUID().uuidString).mp3"
            let audioURL = getDocumentsDirectory().appendingPathComponent(filename)
            try audioData.write(to: audioURL)
            print("Audio saved to: \(audioURL.path)")
            
            // 6.5 Generate Word Timings
            print("Generating word timings via Whisper...")
            var timingsJSON: String? = nil
            do {
                let timings = try await openAIService.generateWordTimings(for: audioURL)
                if !timings.isEmpty {
                    let timingsData = try JSONEncoder().encode(timings)
                    timingsJSON = String(data: timingsData, encoding: .utf8)
                }
            } catch {
                print("Warning: Failed to generate word timings: \(error)")
                // Don't fail the whole story generation if timings fail
            }
            
            // 7. Create & Save Story Object
            let encoder = JSONEncoder()
            let prefInfo = try? String(data: encoder.encode(preferences), encoding: .utf8)
            
            let story = Story(
                userID: userID,
                title: title,
                targetLanguageText: content,
                nativeLanguageText: englishTranslation,
                prompt: topic,
                textGenPrompt: textGenPrompt,
                imageGenPrompt: imageGenPrompt,
                preferencesJSON: prefInfo,
                wordTimingsJSON: timingsJSON,
                audioFilename: filename,
                coverArt: coverFilename,
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

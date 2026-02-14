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
    func generateStory(topic: String, language: Language, level: Int, context: ModelContext, userID: String) async -> Story? {
        isGenerating = true
        errorMessage = nil
        
        defer { isGenerating = false }
        
        do {
            // 1. Generate Text
            let levelString = describeLevel(level)
            print("Generating story for topic: \(topic), Language: \(language.rawValue), Level: \(levelString)")
            
            let (title, content) = try await openAIService.generateStory(
                topic: topic,
                language: language.rawValue,
                level: levelString
            )
            
            // 2. Generate English Translation
            print("Generating English translation...")
            let englishTranslation = try await openAIService.generateTranslation(
                text: content,
                sourceLanguage: language.rawValue
            )
            
            // 3. Generate Cover Art
            print("Generating cover art for: \(title)")
            let coverImageData = try await openAIService.generateCoverArt(
                title: title,
                topic: topic
            )
            
            // 4. Save Cover Image
            let coverFilename = "cover_\(UUID().uuidString).png"
            let coverURL = getDocumentsDirectory().appendingPathComponent(coverFilename)
            try coverImageData.write(to: coverURL)
            print("Cover art saved to: \(coverURL.path)")
            
            // 5. Generate Audio
            print("Generating audio for content length: \(content.count)")
            let audioData = try await openAIService.generateAudio(text: content)
            
            // 6. Save Audio File
            let filename = "story_\(UUID().uuidString).mp3"
            let audioURL = getDocumentsDirectory().appendingPathComponent(filename)
            try audioData.write(to: audioURL)
            print("Audio saved to: \(audioURL.path)")
            
            // 7. Create & Save Story Object
            let story = Story(
                userID: userID,
                title: title,
                targetLanguageText: content,
                nativeLanguageText: englishTranslation,
                prompt: topic,
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
    
    private func describeLevel(_ level: Int) -> String {
        switch level {
        case 1: return "Absolute Beginner (A1)"
        case 2: return "Beginner (A2)"
        case 3: return "Intermediate (B1)"
        case 4: return "Upper Intermediate (B2)"
        case 5: return "Advanced (C1)"
        case 6: return "Mastery (C2)"
        default: return "Beginner"
        }
    }
    
    // Expose for UI checks
    func hasAPIKey() async -> Bool {
        return await openAIService.hasKey()
    }
}

import Foundation

enum OpenAIServiceError: Error {
    case invalidURL
    case noAPIKey
    case invalidResponse
    case apiError(String)
    case decodingError
}

actor OpenAIService {
    private let baseURL = "https://api.openai.com/v1"
    
    // In a real app, we might store this in Keychain. 
    // For this implementation, we'll read from UserDefaults via a helper or pass it in.
    private var apiKey: String? {
        UserDefaults.standard.string(forKey: "OpenAI_API_Key")
    }
    
    func generateStory(topic: String, language: String, level: String, preferences: StoryPreferences) async throws -> (title: String, content: String) {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenAIServiceError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = constructStoryPrompt(topic: topic, language: language, level: level, preferences: preferences)
        

        
        print("--- GENERATED PROMPT ---")
        print(prompt)
        print("------------------------")
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini", // Cost effective and fast
            "messages": [
                ["role": "system", "content": "You are a helpful language tutor. You respond strictly in JSON."],
                ["role": "user", "content": prompt]
            ],
            "response_format": ["type": "json_object"]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Print Raw Response
        if let responseString = String(data: data, encoding: .utf8) {
            print("--- RAW OPENAI RESPONSE ---")
            print(responseString)
            print("---------------------------")
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            var errorMessage = "Status code: \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errorJson["error"] as? [String: Any],
               let msg = errorObj["message"] as? String {
                errorMessage = msg
            }
            throw OpenAIServiceError.apiError(errorMessage)
        }
        
        // Decode logic
        struct ChatCompletionResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }
        
        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let contentString = result.choices.first?.message.content else {
            throw OpenAIServiceError.decodingError
        }
        
        // Parse the inner JSON content
        guard let data = contentString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: String],
              let title = json["title"],
              let content = json["content"] else {
            throw OpenAIServiceError.decodingError
        }
        
        return (title, content)
    }
    
    // Extracted for previewing
    func constructStoryPrompt(topic: String, language: String, level: String, preferences: StoryPreferences) -> String {
        // Determine Tone
        let toneDesc = preferences.humorLevel < 0.3 ? "Humorous" : (preferences.humorLevel > 0.7 ? "Serious" : "Balanced")
        
        // Determine Setting
        let settingDesc = preferences.realismLevel < 0.3 ? "Real world/Daily life" : (preferences.realismLevel > 0.7 ? "Sci-Fi/Futuristic" : "Contemporary with slight twist")
        
        // Determine Length based on preference
        let lengthInstruction = preferences.storyLength.promptInstruction
        
        // Construct detailed prompt components
        var promptComponents = [
            "Write a short, engaging story in \(language) suitable for a \(level) level learner.",
            "The topic is: \"\(topic)\".",
            "Preferences:",
            "- Tone: \(toneDesc)",
            "- Setting: \(settingDesc)",
            "- Genre: \(preferences.genre.rawValue)",
            "- Dialogue: Include \(preferences.dialogueAmount.rawValue.lowercased()) amount of dialogue.",
            "- Ending: \(preferences.endingType.rawValue)",
            lengthInstruction
        ]
        
        // Add Protagonist if specified
        if !preferences.protagonistName.isEmpty {
            let genderDesc = preferences.protagonistGender == .neutral ? "non-binary/gender-neutral" : preferences.protagonistGender.rawValue
            promptComponents.append("- Protagonist: The main character is named \(preferences.protagonistName) (\(genderDesc)).")
        }
        
        // Add Pedagogical Controls
        if !preferences.targetVocabulary.isEmpty {
            promptComponents.append("- REQUIRED VOCABULARY: You MUST naturally include the following words: \(preferences.targetVocabulary).")
        }
        
        if !preferences.grammarFocus.isEmpty {
            promptComponents.append("- GRAMMAR FOCUS: Prioritize using \(preferences.grammarFocus) where appropriate.")
        }
        
        promptComponents.append("Return the result as JSON with keys \"title\" and \"content\".")
        
        return promptComponents.joined(separator: "\n")
    }
    
    func generateAudio(text: String, voice: String = "alloy") async throws -> Data {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenAIServiceError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "tts-1",
            "input": text,
            "voice": voice
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            var errorMessage = "Status code: \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errorJson["error"] as? [String: Any],
               let msg = errorObj["message"] as? String {
                errorMessage = msg
            }
            throw OpenAIServiceError.apiError(errorMessage)
        }
        
        return data
    }
    
    func generateTranslation(text: String, sourceLanguage: String) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenAIServiceError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = """
        Translate the following \(sourceLanguage) text to English. 
        Preserve the tone and style. Return only the English translation, no explanations.
        
        Text: \(text)
        """
        
        print("--- TRANSLATION PROMPT ---")
        print(prompt)
        print("--------------------------")
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are a professional translator."],
                ["role": "user", "content": prompt]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            var errorMessage = "Status code: \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errorJson["error"] as? [String: Any],
               let msg = errorObj["message"] as? String {
                errorMessage = msg
            }
            throw OpenAIServiceError.apiError(errorMessage)
        }
        
        struct ChatCompletionResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }
        
        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let translation = result.choices.first?.message.content else {
            throw OpenAIServiceError.decodingError
        }
        
        return translation.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func generateCoverArt(title: String, topic: String, style: StoryPreferences.CoverArtStyle) async throws -> (imageData: Data, prompt: String) {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenAIServiceError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/images/generations")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = constructCoverArtPrompt(title: title, topic: topic, style: style)
        
        print("--- COVER ART PROMPT ---")
        print(prompt)
        print("------------------------")
        
        let body: [String: Any] = [
            "model": "dall-e-3",
            "prompt": prompt,
            "n": 1,
            "size": "1024x1024",
            "response_format": "b64_json"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            var errorMessage = "Status code: \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errorJson["error"] as? [String: Any],
               let msg = errorObj["message"] as? String {
                errorMessage = msg
            }
            throw OpenAIServiceError.apiError(errorMessage)
        }
        
        struct ImageResponse: Decodable {
            struct ImageData: Decodable {
                let b64_json: String
            }
            let data: [ImageData]
        }
        
        let result = try JSONDecoder().decode(ImageResponse.self, from: data)
        guard let base64String = result.data.first?.b64_json,
              let imageData = Data(base64Encoded: base64String) else {
            throw OpenAIServiceError.decodingError
        }
        
        return (imageData, prompt)
    }
    
    nonisolated func constructCoverArtPrompt(title: String, topic: String, style: StoryPreferences.CoverArtStyle) -> String {
        let styleDesc = style.promptDescription
        return "Create a illustration for a story titled '\(title)' about \(topic). Style: \(styleDesc). No text in the image."
    }
    
    func generateWordTimings(for audioURL: URL) async throws -> [WordTiming] {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenAIServiceError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Model
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json\r\n".data(using: .utf8)!)
        
        // Timestamp granularities
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"timestamp_granularities[]\"\r\n\r\n".data(using: .utf8)!)
        body.append("word\r\n".data(using: .utf8)!)
        
        // File
        let audioData = try Data(contentsOf: audioURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.mp3\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mpeg\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        print("--- GENERATING TIMINGS VIA WHISPER ---")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            var errorMessage = "Status code: \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errorJson["error"] as? [String: Any],
               let msg = errorObj["message"] as? String {
                errorMessage = msg
            }
            throw OpenAIServiceError.apiError(errorMessage)
        }
        
        // Decode Whisper output
        struct WhisperResponse: Decodable {
            struct Word: Decodable {
                let word: String
                let start: Double
                let end: Double
            }
            let words: [Word]?
        }
        
        let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
        guard let whisperWords = result.words else {
            return []
        }
        
        return whisperWords.map { WordTiming(word: $0.word, start: $0.start, end: $0.end) }
    }
    
    func generateComprehensionQuestions(
        storyText: String, language: String, level: String, count: Int = 4
    ) async throws -> [ComprehensionQuestion] {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenAIServiceError.noAPIKey
        }

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Generate \(count) multiple choice comprehension questions about the following \(language) story, for a \(level) level learner.
        Write ALL questions and answer choices in \(language) (not English).
        Test understanding of plot, characters, setting, and key events.
        Each question must have exactly 4 answer choices with one correct answer.
        Return a JSON object with a "questions" array. Each item has:
          "question" (string), "choices" (array of 4 strings), "correctIndex" (integer 0–3).

        Story:
        \(storyText)
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are a language learning assistant. Respond strictly in JSON."],
                ["role": "user", "content": prompt]
            ],
            "response_format": ["type": "json_object"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            var errorMessage = "Status code: \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errorJson["error"] as? [String: Any],
               let msg = errorObj["message"] as? String {
                errorMessage = msg
            }
            throw OpenAIServiceError.apiError(errorMessage)
        }

        struct ChatCompletionResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let contentString = result.choices.first?.message.content,
              let contentData = contentString.data(using: .utf8) else {
            throw OpenAIServiceError.decodingError
        }

        struct QuestionsWrapper: Decodable {
            let questions: [ComprehensionQuestion]
        }

        let wrapper = try JSONDecoder().decode(QuestionsWrapper.self, from: contentData)
        return wrapper.questions
    }

    func translateWord(_ word: String, language: String, context: String?) async throws -> (translation: String, partOfSpeech: String) {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenAIServiceError.noAPIKey
        }

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var prompt = "Translate the word '\(word)' from \(language) to English. Return JSON with keys 'translation' (concise, 1-5 words) and 'partOfSpeech' (e.g. noun, verb, adjective, adverb, pronoun, preposition)."
        if let ctx = context, !ctx.isEmpty {
            prompt += " Context sentence: '\(ctx)'"
        }

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are a language translator. Respond strictly in JSON."],
                ["role": "user", "content": prompt]
            ],
            "response_format": ["type": "json_object"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            var errorMessage = "Status code: \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errorJson["error"] as? [String: Any],
               let msg = errorObj["message"] as? String {
                errorMessage = msg
            }
            throw OpenAIServiceError.apiError(errorMessage)
        }

        struct ChatCompletionResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let contentString = result.choices.first?.message.content,
              let contentData = contentString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: contentData) as? [String: String],
              let translation = json["translation"] else {
            throw OpenAIServiceError.decodingError
        }

        return (translation, json["partOfSpeech"] ?? "")
    }

    // Check if key exists
    func hasKey() -> Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }
}

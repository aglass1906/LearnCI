import Foundation

struct WordTranslationResult: Equatable {
    let translation: String
    let partOfSpeech: String
    let lemma: String?
    let level: String?
    let verbTense: String?
    let grammarNotes: String?
    let usageNote: String?
    let exampleTarget: String?
    let exampleEnglish: String?
}

enum OpenAIServiceError: Error, LocalizedError {
    case invalidURL
    case noAPIKey
    case invalidResponse
    case apiError(String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The OpenAI request URL was invalid."
        case .noAPIKey:
            return "No OpenAI API key is saved. Add one in Profile → AI Settings."
        case .invalidResponse:
            return "OpenAI returned an unexpected response."
        case .apiError(let message):
            return message
        case .decodingError:
            return "Could not read the OpenAI response."
        }
    }
}

enum OpenAIAPIKeyStorage {
    private static let userDefaultsKey = "OpenAI_API_Key"

    static var apiKey: String? {
        UserDefaults.standard.string(forKey: userDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var isConfigured: Bool {
        guard let apiKey else { return false }
        return !apiKey.isEmpty
    }

    static func save(_ apiKey: String) {
        UserDefaults.standard.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: userDefaultsKey)
    }

    static func remove() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

actor OpenAIService {
    private let baseURL = "https://api.openai.com/v1"
    
    // In a real app, we might store this in Keychain. 
    // For this implementation, we'll read from UserDefaults via a helper or pass it in.
    private var apiKey: String? {
        OpenAIAPIKeyStorage.apiKey
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
        
        // Parse the inner JSON content — content may be a String or [String]
        guard let innerData = contentString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: innerData) as? [String: Any],
              let title = json["title"] as? String else {
            throw OpenAIServiceError.decodingError
        }

        let content: String
        if let str = json["content"] as? String {
            content = str
        } else if let arr = json["content"] as? [String] {
            content = arr.joined(separator: "\n")
        } else {
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
        
        // Dramatized mode: ask GPT to tag each line with a speaker label
        if preferences.audioStyle == .dramatized {
            promptComponents.append("""
            - SPEAKER TAGS: This story will be voiced by multiple speakers. \
            Prefix every line of the story with a speaker tag in the format [SPEAKER_NAME] where:
              • Narrator lines use [NARRATOR]
              • Each character's dialogue uses [CHARACTERNAME] (ALL UPPERCASE, no spaces, e.g. [ELENA], [BARISTA], [DRAGON])
              • Every single line must have a tag — do not leave any line untagged.
              • Tags must be EXACTLY in the format [NAME] — no colons, extra words, or punctuation inside the brackets.
              • Do NOT include stage directions or parenthetical notes anywhere (e.g. do NOT write "(whispering)", "(softly)", or "(points at door)").
            """)
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

    // MARK: - Dramatized Audio

    /// Represents one tagged segment of a dramatized story.
    struct StorySegment {
        let speaker: String  // e.g. "NARRATOR", "ELENA", "BARISTA"
        let text: String
    }

    /// Parses speaker-tagged story text into ordered segments.
    /// Expected format per line: "[SPEAKER] text" or "[SPEAKER:Name] text"
    /// Narrator lines without a tag are attributed to NARRATOR.
    nonisolated func parseSegments(from taggedText: String) -> [StorySegment] {
        var segments: [StorySegment] = []
        // Accumulate consecutive lines from the same speaker
        var currentSpeaker = "NARRATOR"
        var currentLines: [String] = []

        let lines = taggedText.components(separatedBy: "\n")
        let tagPattern = try? NSRegularExpression(pattern: #"^\[([A-Za-z][A-Za-z0-9_ ]*)\]\s*"#)

        func flush() {
            let text = currentLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                segments.append(StorySegment(speaker: currentSpeaker, text: text))
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if let match = tagPattern?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let tagRange = Range(match.range(at: 1), in: trimmed),
               let fullRange = Range(match.range, in: trimmed) {
                let speaker = String(trimmed[tagRange]).uppercased()
                let remainder = String(trimmed[fullRange.upperBound...]).trimmingCharacters(in: .whitespaces)

                if speaker != currentSpeaker {
                    flush()
                    currentSpeaker = speaker
                    currentLines = []
                }
                if !remainder.isEmpty { currentLines.append(remainder) }
            } else {
                // Untagged line — keep current speaker
                currentLines.append(trimmed)
            }
        }
        flush()
        return segments
    }

    /// Assigns an OpenAI voice to each unique speaker, preserving any existing mapping.
    /// - narrator: user's chosen voice
    /// - remaining speakers: assigned from the pool, respecting protagonist gender hint
    nonisolated func assignVoices(
        segments: [StorySegment],
        narratorVoice: String,
        protagonistName: String,
        protagonistGender: StoryPreferences.Gender,
        existingMapping: [String: String] = [:]
    ) -> [String: String] {
        var mapping = existingMapping
        let allVoices = StoryPreferences.Voice.allCases.map { $0.rawValue }
        let femaleVoices = ["nova", "shimmer"]
        let maleVoices   = ["echo", "onyx", "fable"]

        // Narrator is always the user's chosen voice
        mapping["NARRATOR"] = narratorVoice

        // Voices available for characters (exclude narrator's voice)
        var pool = allVoices.filter { $0 != narratorVoice }

        let speakers = Set(segments.map { $0.speaker }).subtracting(["NARRATOR"])
        for speaker in speakers.sorted() {
            guard mapping[speaker] == nil else { continue } // already assigned

            // Use protagonist gender hint for the protagonist
            let isProtagonist = !protagonistName.isEmpty &&
                speaker.uppercased() == protagonistName.uppercased()
            var preferred: String? = nil
            if isProtagonist {
                switch protagonistGender {
                case .female: preferred = pool.first { femaleVoices.contains($0) }
                case .male:   preferred = pool.first { maleVoices.contains($0) }
                case .neutral: break
                }
            }

            let chosen = preferred ?? pool.first ?? allVoices.first!
            mapping[speaker] = chosen
            pool.removeAll { $0 == chosen }
            if pool.isEmpty { pool = allVoices.filter { $0 != narratorVoice } } // cycle if exhausted
        }
        return mapping
    }

    /// Generates PCM audio for each segment using its assigned voice, concatenates the
    /// raw PCM bytes, wraps them in a WAV container, and returns the final Data.
    /// OpenAI TTS PCM format: 24000 Hz, 16-bit signed little-endian, mono.
    func generateDramatizedAudio(
        segments: [StorySegment],
        voiceMapping: [String: String]
    ) async throws -> Data {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenAIServiceError.noAPIKey
        }

        var allPCM = Data()

        for segment in segments {
            let voice = voiceMapping[segment.speaker] ?? voiceMapping["NARRATOR"] ?? "alloy"
            print("[Dramatized] Generating PCM for \(segment.speaker) (\(voice)): \(segment.text.prefix(50))…")

            let url = URL(string: "\(baseURL)/audio/speech")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "model": "tts-1",
                "input": segment.text,
                "voice": voice,
                "response_format": "pcm"  // raw 24kHz 16-bit mono signed LE
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                var msg = "PCM TTS failed for \(segment.speaker)"
                if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errObj = errJson["error"] as? [String: Any],
                   let m = errObj["message"] as? String { msg = m }
                throw OpenAIServiceError.apiError(msg)
            }
            allPCM.append(data)
        }

        return wrapPCMInWAV(pcmData: allPCM, sampleRate: 24000, channels: 1, bitsPerSample: 16)
    }

    /// Builds a valid WAV file from raw PCM bytes.
    private func wrapPCMInWAV(pcmData: Data, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) -> Data {
        var wav = Data()
        let dataSize   = UInt32(pcmData.count)
        let byteRate   = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let chunkSize  = 36 + dataSize  // 36 = rest of header after RIFF id + size field

        func append<T: FixedWidthInteger>(_ value: T) {
            var le = value.littleEndian
            wav.append(contentsOf: withUnsafeBytes(of: &le) { Array($0) })
        }

        // RIFF chunk
        wav.append(contentsOf: "RIFF".utf8)
        append(chunkSize)
        wav.append(contentsOf: "WAVE".utf8)

        // fmt sub-chunk
        wav.append(contentsOf: "fmt ".utf8)
        append(UInt32(16))        // sub-chunk size for PCM
        append(UInt16(1))         // PCM format
        append(channels)
        append(sampleRate)
        append(byteRate)
        append(blockAlign)
        append(bitsPerSample)

        // data sub-chunk
        wav.append(contentsOf: "data".utf8)
        append(dataSize)
        wav.append(pcmData)

        return wav
    }

    /// Strips speaker tags from tagged story text so the clean version can be stored/displayed.
    nonisolated func cleanTaggedText(_ taggedText: String) -> String {
        let tagPattern = try? NSRegularExpression(pattern: #"^\[[A-Za-z][A-Za-z0-9_ ]*\]\s*"#, options: .anchorsMatchLines)
        let range = NSRange(taggedText.startIndex..., in: taggedText)
        return tagPattern?.stringByReplacingMatches(in: taggedText, range: range, withTemplate: "") ?? taggedText
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

    func translateCaptionCueBatch(
        cues: [YouTubeCaptionCue],
        sourceLanguage: String,
        targetLanguage: String = "English"
    ) async throws -> [YouTubeTranslatedCue] {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenAIServiceError.noAPIKey
        }
        guard !cues.isEmpty else { return [] }

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let cuePayload = cues.map { ["cueIndex": $0.index, "text": $0.normalizedText] }
        let cueJSONData = try JSONSerialization.data(withJSONObject: cuePayload, options: [.sortedKeys])
        let cueJSONString = String(data: cueJSONData, encoding: .utf8) ?? "[]"

        let prompt = """
        Translate each caption cue from \(sourceLanguage) to \(targetLanguage).
        Return strict JSON with the shape {"translations":[{"cueIndex":0,"text":"..."}]}.
        Preserve meaning naturally, keep each translation concise, and do not omit any cue.

        Cues:
        \(cueJSONString)
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are a subtitle translator. Respond strictly in JSON."],
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

        struct TranslationWrapper: Decodable {
            struct Item: Decodable {
                let cueIndex: Int
                let text: String
            }
            let translations: [Item]
        }

        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let contentString = result.choices.first?.message.content,
              let contentData = contentString.data(using: .utf8) else {
            throw OpenAIServiceError.decodingError
        }

        let wrapper = try JSONDecoder().decode(TranslationWrapper.self, from: contentData)
        let cueIDs = Dictionary(uniqueKeysWithValues: cues.map { ($0.index, $0.id) })

        return wrapper.translations.map { item in
            YouTubeTranslatedCue(
                cueID: cueIDs[item.cueIndex],
                cueIndex: item.cueIndex,
                text: item.text
            )
        }
    }

    func translateStudyBlockBatch(
        blocks: [StudyBlock],
        sourceLanguage: String,
        targetLanguage: String = "English"
    ) async throws -> [Int: String] {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenAIServiceError.noAPIKey
        }
        guard !blocks.isEmpty else { return [:] }

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let blockPayload = blocks.map { ["blockIndex": $0.index, "text": $0.targetText] }
        let blockJSONData = try JSONSerialization.data(withJSONObject: blockPayload, options: [.sortedKeys])
        let blockJSONString = String(data: blockJSONData, encoding: .utf8) ?? "[]"

        let prompt = """
        Translate each study block from \(sourceLanguage) to \(targetLanguage).
        Return strict JSON with the shape {"translations":[{"blockIndex":0,"text":"..."}]}.
        Preserve meaning naturally, keep each translation concise, and do not omit any block.

        Blocks:
        \(blockJSONString)
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are a subtitle translator. Respond strictly in JSON."],
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

        struct TranslationWrapper: Decodable {
            struct Item: Decodable {
                let blockIndex: Int
                let text: String
            }
            let translations: [Item]
        }

        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let contentString = result.choices.first?.message.content,
              let contentData = contentString.data(using: .utf8) else {
            throw OpenAIServiceError.decodingError
        }

        let wrapper = try JSONDecoder().decode(TranslationWrapper.self, from: contentData)
        return Dictionary(uniqueKeysWithValues: wrapper.translations.map { ($0.blockIndex, $0.text) })
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
    
    func generateWordTimings(for audioURL: URL, languageCode: String? = nil) async throws -> [WordTiming] {
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

        if let languageCode, !languageCode.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(languageCode)\r\n".data(using: .utf8)!)
        }
        
        // File
        let audioData = try Data(contentsOf: audioURL)
        let fileMeta = Self.multipartFileMetadata(for: audioURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileMeta.filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(fileMeta.mimeType)\r\n\r\n".data(using: .utf8)!)
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
            } else if let responseString = String(data: data, encoding: .utf8), !responseString.isEmpty {
                errorMessage = responseString
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
        
        let result: WhisperResponse
        do {
            result = try JSONDecoder().decode(WhisperResponse.self, from: data)
        } catch {
            throw OpenAIServiceError.decodingError
        }

        guard let whisperWords = result.words, !whisperWords.isEmpty else {
            throw OpenAIServiceError.apiError("Whisper did not return any timed words for this audio.")
        }
        
        return whisperWords.map { WordTiming(word: $0.word, start: $0.start, end: $0.end) }
    }

    private static func multipartFileMetadata(for url: URL) -> (filename: String, mimeType: String) {
        switch url.pathExtension.lowercased() {
        case "m4a":
            return ("audio.m4a", "audio/mp4")
        case "mp4":
            return ("audio.mp4", "audio/mp4")
        case "wav":
            return ("audio.wav", "audio/wav")
        case "webm":
            return ("audio.webm", "audio/webm")
        case "mp3", "mpeg":
            return ("audio.mp3", "audio/mpeg")
        default:
            return ("audio.mp3", "audio/mpeg")
        }
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

    func translateWord(_ word: String, language: String, context: String?) async throws -> WordTranslationResult {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenAIServiceError.noAPIKey
        }

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let lookupText = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPhrase = lookupText.contains(where: { $0.isWhitespace || $0.isPunctuation })
        var prompt = if isPhrase {
            "Translate the phrase '\(lookupText)' from \(language) to English for a language learner."
        } else {
            "Translate the word '\(lookupText)' from \(language) to English for a language learner."
        }
        prompt += " Return JSON with string keys: translation, partOfSpeech, lemma, level, verbTense, grammarNotes, usageNote, exampleTarget, exampleEnglish. Keep translation concise. Use CEFR-style level when possible. Leave verbTense empty unless this is a conjugated verb form. Keep grammarNotes and usageNote under 18 words each."
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
              let json = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              let rawTranslation = json["translation"] else {
            throw OpenAIServiceError.decodingError
        }

        let translation: String
        if let value = rawTranslation as? String {
            translation = value
        } else if let values = rawTranslation as? [String] {
            translation = values.joined(separator: ", ")
        } else {
            translation = String(describing: rawTranslation)
        }

        func stringValue(_ keys: String...) -> String? {
            for key in keys {
                if let value = json[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                } else if let values = json[key] as? [String] {
                    let trimmed = values.joined(separator: ", ").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
            return nil
        }

        let partOfSpeech = stringValue("partOfSpeech", "part_of_speech") ?? ""

        let trimmedTranslation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranslation.isEmpty else {
            throw OpenAIServiceError.decodingError
        }

        return WordTranslationResult(
            translation: trimmedTranslation,
            partOfSpeech: partOfSpeech,
            lemma: stringValue("lemma"),
            level: stringValue("level"),
            verbTense: stringValue("verbTense", "verb_tense"),
            grammarNotes: stringValue("grammarNotes", "grammar_notes"),
            usageNote: stringValue("usageNote", "usage_note"),
            exampleTarget: stringValue("exampleTarget", "example_target"),
            exampleEnglish: stringValue("exampleEnglish", "example_english")
        )
    }

    func analyzeStudyWord(
        _ word: String,
        languageCode: String,
        context: String?,
        existingTranslation: String?,
        existingLevel: String?
    ) async throws -> StudyWordAnalysis {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenAIServiceError.noAPIKey
        }

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let lookupText = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let languageName = Language(rawValue: languageCode)?.displayName ?? languageCode
        var prompt = """
        Analyze the \(languageName) study word or phrase "\(lookupText)" for a language learner. Return JSON with string keys: translation, lemma, partOfSpeech, level, verbTense, grammarNotes. Use CEFR-style level labels when possible. Leave verbTense empty unless this is a conjugated verb form. Keep grammarNotes under 18 words.
        """
        if let existingTranslation, !existingTranslation.isEmpty {
            prompt += "\nKnown translation: \(existingTranslation)"
        }
        if let existingLevel, !existingLevel.isEmpty {
            prompt += "\nKnown level: \(existingLevel)"
        }
        if let context, !context.isEmpty {
            prompt += "\nContext sentence: \(context)"
        }

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are a concise language-learning grammar analyst. Respond strictly in JSON."],
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
              let json = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any] else {
            throw OpenAIServiceError.decodingError
        }

        func stringValue(_ keys: String...) -> String? {
            for key in keys {
                if let value = json[key] as? String {
                    return value
                }
            }
            return nil
        }

        return StudyWordAnalysis(
            translation: stringValue("translation"),
            lemma: stringValue("lemma"),
            partOfSpeech: stringValue("partOfSpeech", "part_of_speech"),
            level: stringValue("level"),
            verbTense: stringValue("verbTense", "verb_tense"),
            grammarNotes: stringValue("grammarNotes", "grammar_notes")
        )
    }

    // Check if key exists
    func hasKey() -> Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }

    // MARK: - Veo Prompt Generation

    /// Uses GPT-4o-mini to convert a story excerpt into a cinematic Veo prompt.
    func generateVeoPrompt(storyText: String, style: String) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenAIServiceError.noAPIKey
        }

        // Use the first ~500 characters of the story as the scene source
        let excerpt = String(storyText.prefix(500))

        let systemPrompt = "You are an expert film director and cinematographer. Your only job is to write short, vivid visual prompts for an AI video generator. Never include dialogue, character names, or abstract concepts. Focus purely on what the camera sees: setting, lighting, movement, atmosphere."

        let userPrompt = """
        Read this story excerpt and write a single cinematic scene prompt (1-2 sentences) for an AI video generator.
        The visual style must be: \(style).
        Describe: setting, lighting, camera angle/movement, atmosphere. No dialogue. No text on screen.

        Story excerpt:
        \(excerpt)
        """

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_tokens": 150
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OpenAIServiceError.invalidResponse
        }

        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let result = try JSONDecoder().decode(Response.self, from: data)
        guard let content = result.choices.first?.message.content else {
            throw OpenAIServiceError.decodingError
        }

        let prompt = content.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[OpenAI] Generated Veo prompt: \(prompt)")
        return prompt
    }
}

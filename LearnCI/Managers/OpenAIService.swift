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
    
    func generateStory(topic: String, language: String, level: String) async throws -> (title: String, content: String) {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenAIServiceError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Prompt Engineering
        let prompt = """
        Write a short, engaging story in \(language) suitable for a \(level) level learner. 
        The topic is: "\(topic)".
        Keep it under 200 words.
        Return the result as JSON with keys "title" and "content".
        """
        
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
    
    // Check if key exists
    func hasKey() -> Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }
}

import Foundation

// MARK: - Video Style

enum VideoStyle: String, CaseIterable, Identifiable, Codable {
    case photorealistic = "Photorealistic Cinematic"
    case pixar          = "Pixar 3D"
    case ghibli         = "Studio Ghibli 2D Anime"
    case timBurton      = "Tim Burton Stop-Motion"
    case watercolor     = "Watercolor Storybook"
    case claymation     = "Claymation"
    case cartoon1930s   = "Vintage 1930s Cartoon"
    case oilPainting    = "Living Oil Painting"
    case lineDrawing    = "Simple Line Drawing"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .photorealistic: return "camera.aperture"
        case .pixar:          return "sparkles"
        case .ghibli:         return "leaf"
        case .timBurton:      return "moon.stars"
        case .watercolor:     return "paintbrush"
        case .claymation:     return "cube"
        case .cartoon1930s:   return "film"
        case .oilPainting:    return "paintpalette"
        case .lineDrawing:    return "pencil"
        }
    }

    /// Injected into the cinematic prompt sent to Veo
    var promptStyle: String {
        switch self {
        case .photorealistic: return "hyper-detailed, photorealistic cinematic grade shot on a 35mm lens"
        case .pixar:          return "highly detailed, expressive, and colorful Pixar 3D animation aesthetic"
        case .ghibli:         return "highly atmospheric, hand-drawn 2D Studio Ghibli anime aesthetic"
        case .timBurton:      return "moody, atmospheric, stylized, highly detailed Tim Burton stop-motion aesthetic"
        case .watercolor:     return "soft, gentle, hand-painted watercolor illustration aesthetic, like a classic children's book brought to life"
        case .claymation:     return "highly tactile, physical claymation stop-motion aesthetic, with visible textures, fingerprints, and studio lighting"
        case .cartoon1930s:   return "classic 1930s rubber-hose cartoon animation aesthetic, expressive bouncy movements, vintage film grain"
        case .oilPainting:    return "living, breathing oil painting aesthetic, thick textured brushstrokes, vibrant colors, classical art style"
        case .lineDrawing:    return "minimalist hand-drawn aesthetic, caricature style with simple distinct black lines drawn on a piece of textured white paper, with simple child-like shapes in the background"
        }
    }

    /// Estimated cost range shown to the user before generation
    static let estimatedCostRange = "$1.75–$2.80"
    /// Per-second rate used for display
    static let ratePerSecond = "$0.35/sec"
}

// MARK: - Video Prompt Model Preference

enum VideoPromptModel: String, CaseIterable, Identifiable {
    case openAI  = "OpenAI GPT-4o-mini"
    case gemini  = "Google Gemini Flash"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .openAI:  return "brain"
        case .gemini:  return "sparkle"
        }
    }

    static let userDefaultsKey = "VideoPromptModel"

    /// Returns the saved preference, defaulting to OpenAI if unset.
    static var saved: VideoPromptModel {
        let raw = UserDefaults.standard.string(forKey: userDefaultsKey) ?? ""
        return VideoPromptModel(rawValue: raw) ?? .openAI
    }
}

// MARK: - Errors

enum VeoServiceError: Error, LocalizedError {
    case noAPIKey
    case invalidURL
    case apiError(String)
    case operationFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Google API key configured. Add your key in Profile → AI Settings."
        case .invalidURL:
            return "Invalid API URL."
        case .apiError(let msg):
            return "API error: \(msg)"
        case .operationFailed(let msg):
            return "Video generation failed: \(msg)"
        case .timeout:
            return "Video generation timed out after 6 minutes. Please try again."
        }
    }
}

// MARK: - Service

actor VeoService {

    static let userDefaultsKey = "Google_API_Key"

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    /// Cached after the first successful ListModels call so we don't hit it on every generation.
    private var cachedVeoModelName: String? = nil

    private var apiKey: String? {
        UserDefaults.standard.string(forKey: Self.userDefaultsKey)
    }

    func hasKey() -> Bool {
        guard let key = apiKey, !key.isEmpty else { return false }
        return true
    }

    // MARK: - Full Pipeline

    /// Submit to Veo, poll until done, return raw MP4 data.
    /// `onStatus` is called on the actor's executor — callers must hop to MainActor themselves.
    func generateVideo(prompt: String,
                       onStatus: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Data {
        guard let key = apiKey, !key.isEmpty else { throw VeoServiceError.noAPIKey }
        onStatus("Submitting to Veo…")
        let operationName = try await submitGeneration(prompt: prompt, apiKey: key)
        let videoURL = try await pollUntilDone(operationName: operationName, apiKey: key, onStatus: onStatus)
        onStatus("Downloading video…")

        // The URI from Veo requires the API key as a query parameter for authenticated download
        var downloadURL = videoURL
        if let host = videoURL.host, host.contains("generativelanguage.googleapis.com") {
            var components = URLComponents(url: videoURL, resolvingAgainstBaseURL: false)
            var items = components?.queryItems ?? []
            if !items.contains(where: { $0.name == "key" }) {
                items.append(URLQueryItem(name: "key", value: key))
            }
            components?.queryItems = items
            downloadURL = components?.url ?? videoURL
        }

        let (data, downloadResponse) = try await URLSession.shared.data(from: downloadURL)

        if let http = downloadResponse as? HTTPURLResponse {
            print("[VeoService] Download HTTP \(http.statusCode), size: \(data.count) bytes")
            guard http.statusCode == 200 else {
                let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw VeoServiceError.apiError("Video download failed: \(msg.prefix(200))")
            }
        }

        guard data.count > 10_000 else {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
            throw VeoServiceError.apiError("Downloaded data too small (\(data.count) bytes) — not a valid video. Response: \(preview)")
        }

        print("[VeoService] Video downloaded successfully: \(data.count) bytes")
        return data
    }

    // MARK: - Model Discovery

    /// Calls ListModels and returns the first Veo model that supports predictLongRunning.
    /// Results are cached for the lifetime of the actor instance.
    func discoverVeoModelName(apiKey: String) async throws -> String {
        if let cached = cachedVeoModelName { return cached }

        guard let url = URL(string: "\(baseURL)/models?key=\(apiKey)&pageSize=200") else {
            throw VeoServiceError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let raw = String(data: data, encoding: .utf8) ?? ""
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw VeoServiceError.apiError("Could not parse ListModels response: \(raw.prefix(300))")
        }

        // Log all veo-related models so we can see exactly what's available
        let veoModels = models.filter {
            ($0["name"] as? String ?? "").lowercased().contains("veo")
        }
        print("[VeoService] Available Veo models:")
        for m in veoModels {
            let name    = m["name"] as? String ?? "?"
            let methods = m["supportedGenerationMethods"] as? [String] ?? []
            print("  \(name) → \(methods)")
        }

        // Prefer the newest Veo model that supports predictLongRunning, sorted descending
        let candidates = veoModels
            .filter { ($0["supportedGenerationMethods"] as? [String] ?? []).contains("predictLongRunning") }
            .compactMap { $0["name"] as? String }
            .sorted(by: >)   // "models/veo-3..." sorts after "models/veo-2..."

        guard let best = candidates.first else {
            // Print the full list so it's visible in the console
            let allNames = models.compactMap { $0["name"] as? String }
            print("[VeoService] No Veo+predictLongRunning model found. All models: \(allNames)")
            throw VeoServiceError.apiError("No Veo model with predictLongRunning found. Check that your API key has Veo access enabled in Google AI Studio.")
        }

        // Strip the "models/" prefix — the endpoint URL already includes it
        let modelId = best.hasPrefix("models/") ? String(best.dropFirst("models/".count)) : best
        print("[VeoService] Using model: \(modelId)")
        cachedVeoModelName = modelId
        return modelId
    }

    // MARK: - Prompt Generation (Gemini Flash)

    /// Generates a cinematic Veo prompt from story text using Gemini Flash.
    /// Uses the same Google API key as video generation — no OpenAI tokens required.
    func generateVeoPrompt(storyText: String, style: String) async throws -> String {
        guard let key = apiKey, !key.isEmpty else { throw VeoServiceError.noAPIKey }

        let urlString = "\(baseURL)/models/gemini-2.0-flash:generateContent?key=\(key)"
        guard let url = URL(string: urlString) else { throw VeoServiceError.invalidURL }

        let systemInstruction = "You write short cinematic video prompts for AI video generation. Focus on setting, lighting, camera angle, and atmosphere. No dialogue, no text overlays, no abstract concepts. 1–2 sentences maximum."
        let userMessage = "Write a cinematic video prompt in this visual style: \(style). Based on this story excerpt:\n\n\(String(storyText.prefix(500)))"

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemInstruction]]],
            "contents": [["role": "user", "parts": [["text": userMessage]]]],
            "generationConfig": ["temperature": 0.7, "maxOutputTokens": 150]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw VeoServiceError.apiError("No HTTP response from Gemini")
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw VeoServiceError.apiError(msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw VeoServiceError.apiError("Unexpected Gemini response structure")
        }

        print("[VeoService] Gemini prompt: \(text.prefix(100))…")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Submit

    private func submitGeneration(prompt: String, apiKey: String) async throws -> String {
        let modelName = try await discoverVeoModelName(apiKey: apiKey)
        let urlString = "\(baseURL)/models/\(modelName):predictLongRunning?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw VeoServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // predictLongRunning uses Vertex AI-style "instances" + "parameters" (not "contents"/"generationConfig")
        let body: [String: Any] = [
            "instances": [
                ["prompt": prompt]
            ],
            "parameters": [
                "aspectRatio": "16:9",
                "durationSeconds": 8
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let rawBody = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"

        guard let http = response as? HTTPURLResponse else {
            throw VeoServiceError.apiError("No HTTP response")
        }
        guard http.statusCode == 200 else {
            print("[VeoService] submitGeneration HTTP \(http.statusCode): \(rawBody)")
            throw VeoServiceError.apiError("HTTP \(http.statusCode): \(rawBody)")
        }

        print("[VeoService] submitGeneration raw response: \(rawBody.prefix(300))")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String else {
            throw VeoServiceError.apiError("Missing operation name in response: \(rawBody)")
        }

        print("[VeoService] Operation started: \(name)")
        return name
    }

    // MARK: - Poll

    private func pollUntilDone(operationName: String, apiKey: String,
                               onStatus: @escaping @Sendable (String) -> Void) async throws -> URL {
        // operationName comes back as e.g. "projects/.../operations/vid-xxx"
        // Strip leading slash if present, then build the full poll URL
        let cleanName = operationName.hasPrefix("/") ? String(operationName.dropFirst()) : operationName

        // For predictLongRunning operations the status endpoint is under /v1beta/{name}
        let urlString = "https://generativelanguage.googleapis.com/v1beta/\(cleanName)?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw VeoServiceError.invalidURL }

        print("[VeoService] Polling URL: \(urlString.prefix(120))")

        // Poll every 10 seconds for up to 6 minutes (36 attempts)
        for attempt in 1...36 {
            try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            let elapsed = attempt * 10
            let mins = elapsed / 60
            let secs = elapsed % 60
            let timeStr = mins > 0 ? "\(mins)m \(secs)s elapsed" : "\(secs)s elapsed"
            onStatus("Generating video… \(timeStr)")
            print("[VeoService] Polling attempt \(attempt)/36…")

            let (data, _) = try await URLSession.shared.data(from: url)
            let rawBody = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            print("[VeoService] Poll response: \(rawBody.prefix(300))")

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let isDone = json["done"] as? Bool ?? false
            guard isDone else { continue }

            // Surface API-level errors
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw VeoServiceError.operationFailed(message)
            }

            // predictLongRunning response nests samples under response.generateVideoResponse
            if let response = json["response"] as? [String: Any],
               let videoResponse = response["generateVideoResponse"] as? [String: Any],
               let samples = videoResponse["generatedSamples"] as? [[String: Any]],
               let first = samples.first,
               let video = first["video"] as? [String: Any],
               let uriString = video["uri"] as? String,
               let videoURL = URL(string: uriString) {
                print("[VeoService] Video ready at: \(uriString)")
                return videoURL
            }

            throw VeoServiceError.operationFailed("Unexpected response structure: \(rawBody.prefix(200))")
        }

        throw VeoServiceError.timeout
    }
}

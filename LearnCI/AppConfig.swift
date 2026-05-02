import Foundation

/// Configuration settings for the app, handling different environments (Debug vs Release).
struct AppConfig {

    /// Supabase project URL
    static let supabaseProjectURL = "https://vuygqrbludhuywupcbma.supabase.co"

    /// Public base URL for the audio-stories storage bucket
    static let audioStoragePublicBase = "\(supabaseProjectURL)/storage/v1/object/public/audio-stories"

    /// Builds a full public URL from a chapter_cover_url storage path
    static func chapterCoverURL(_ path: String) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        return URL(string: "\(audioStoragePublicBase)/\(path)")
    }

    /// The base URL for the Web Portal.
    static var webPortalBaseURL: URL {
        #if DEBUG
        // Development / Debug URL
        return URL(string: "http://localhost:3000")!
        #else
        // Production / Release URL
        return URL(string: "https://learn-ci-web.vercel.app")!
        #endif
    }
}

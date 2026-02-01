import Foundation

/// Configuration settings for the app, handling different environments (Debug vs Release).
struct AppConfig {
    
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

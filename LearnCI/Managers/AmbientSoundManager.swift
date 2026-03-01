import Foundation
import Observation
import Supabase

/// Manages downloading and caching of ambient sound files from Supabase Storage.
/// Sounds are shared across all stories — downloaded once, reused forever.
@Observable
class AmbientSoundManager {
    private let authManager: AuthManager
    private let fileManager = FileManager.default

    /// Set of sound ids that are currently being downloaded.
    var downloading: Set<String> = []

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    // MARK: - Cache Directory

    private var cacheDirectory: URL {
        let docs = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("AmbientSounds", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func localURL(for sound: AmbientSound) -> URL {
        cacheDirectory.appendingPathComponent(sound.localFilename)
    }

    func isDownloaded(_ sound: AmbientSound) -> Bool {
        guard !sound.isNone else { return true }
        return fileManager.fileExists(atPath: localURL(for: sound).path)
    }

    // MARK: - Download

    /// Downloads the sound file from Supabase Storage if not already cached.
    /// Returns the local URL when ready. Throws if download fails.
    func ensureDownloaded(_ sound: AmbientSound) async throws -> URL {
        guard !sound.isNone else {
            throw AmbientSoundError.noSound
        }

        let url = localURL(for: sound)
        if fileManager.fileExists(atPath: url.path) {
            return url
        }

        guard !downloading.contains(sound.id) else {
            // Poll until another concurrent download finishes
            for _ in 0..<30 {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                if fileManager.fileExists(atPath: url.path) { return url }
            }
            throw AmbientSoundError.downloadTimeout
        }

        downloading.insert(sound.id)
        defer { downloading.remove(sound.id) }

        print("[AmbientSoundManager] Downloading: \(sound.supabasePath)")
        let data = try await authManager.supabase.storage
            .from("ambient-sounds")
            .download(path: sound.supabasePath)

        try data.write(to: url)
        print("[AmbientSoundManager] Saved: \(url.lastPathComponent)")
        return url
    }

    /// Downloads all catalog sounds that match a given genre (fire-and-forget pre-fetch).
    func prefetch(for genre: StoryPreferences.Genre) {
        let sounds = AmbientSound.catalog.filter {
            $0.genreIds.contains(genre.rawValue) && !$0.isNone
        }
        Task {
            for sound in sounds where !isDownloaded(sound) {
                try? await ensureDownloaded(sound)
            }
        }
    }
}

enum AmbientSoundError: Error, LocalizedError {
    case noSound
    case downloadTimeout

    var errorDescription: String? {
        switch self {
        case .noSound:          return "No ambient sound selected."
        case .downloadTimeout:  return "Ambient sound download timed out."
        }
    }
}

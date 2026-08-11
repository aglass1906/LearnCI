import Foundation

@Observable
@MainActor
final class MediaDownloadManager {
    static let shared = MediaDownloadManager()

    enum State: Equatable {
        case notDownloaded
        case downloading
        case downloaded
        case failed(String)
    }

    private(set) var activeDownloads: Set<String> = []
    private(set) var failures: [String: String] = [:]
    private var records: [String: String] = [:]

    private let recordsKey = "mediaDownloads.records.v1"
    private let fileManager = FileManager.default
    private let defaults: UserDefaults
    private let rootDirectory: URL?

    var downloadedCount: Int { records.count }

    var storageBytes: Int64 {
        records.values.reduce(0) { total, path in
            let size = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    init(defaults: UserDefaults = .standard, rootDirectory: URL? = nil) {
        self.defaults = defaults
        self.rootDirectory = rootDirectory
        records = defaults.dictionary(forKey: recordsKey) as? [String: String] ?? [:]
        removeInvalidRecords()
    }

    func state(for item: CarPlayMediaItem) -> State {
        if activeDownloads.contains(item.id) { return .downloading }
        if let message = failures[item.id] { return .failed(message) }
        return localURL(for: item) == nil ? .notDownloaded : .downloaded
    }

    func playableURL(for item: CarPlayMediaItem) -> URL {
        localURL(for: item) ?? item.url
    }

    func localURL(for item: CarPlayMediaItem) -> URL? {
        guard let path = records[item.id] else { return nil }
        let url = URL(fileURLWithPath: path)
        guard fileManager.fileExists(atPath: path),
              (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 0 else {
            return nil
        }
        return url
    }

    func download(_ item: CarPlayMediaItem) async {
        guard localURL(for: item) == nil, !activeDownloads.contains(item.id) else { return }
        activeDownloads.insert(item.id)
        failures[item.id] = nil
        defer { activeDownloads.remove(item.id) }

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: item.url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }

            let values = try temporaryURL.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) > 0 else { throw URLError(.zeroByteResource) }

            let directory = try downloadsDirectory()
            let ext = item.url.pathExtension.isEmpty ? "audio" : item.url.pathExtension
            let filename = item.id
                .replacingOccurrences(of: ":", with: "_")
                .replacingOccurrences(of: "/", with: "_")
            let destination = directory.appendingPathComponent(filename).appendingPathExtension(ext)

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporaryURL, to: destination)
            records[item.id] = destination.path
            persist()
        } catch {
            failures[item.id] = error.localizedDescription
        }
    }

    func delete(_ item: CarPlayMediaItem) {
        if let url = localURL(for: item) {
            try? fileManager.removeItem(at: url)
        }
        records[item.id] = nil
        failures[item.id] = nil
        persist()
    }

    func deleteAll() {
        for path in records.values {
            try? fileManager.removeItem(at: URL(fileURLWithPath: path))
        }
        records = [:]
        failures = [:]
        persist()
    }

    func cleanUpInvalidDownloads() {
        removeInvalidRecords()
    }

    private func downloadsDirectory() throws -> URL {
        let base = if let rootDirectory {
            rootDirectory
        } else {
            try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
        let directory = base.appendingPathComponent("LearnCIDownloads", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func removeInvalidRecords() {
        let validRecords = records.filter { fileManager.fileExists(atPath: $0.value) }
        guard validRecords.count != records.count else { return }
        records = validRecords
        persist()
    }

    private func persist() {
        defaults.set(records, forKey: recordsKey)
    }
}

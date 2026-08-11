import Foundation
import SwiftUI

@Observable
@MainActor
final class PlaybackQueueManager {
    static let shared = PlaybackQueueManager(audioManager: .shared)

    private(set) var items: [CarPlayMediaItem] = []
    private(set) var currentIndex: Int?

    var currentItem: CarPlayMediaItem? {
        guard let currentIndex, items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    var hasPrevious: Bool {
        guard let currentIndex else { return false }
        return items.indices.contains(currentIndex - 1)
    }

    var hasNext: Bool {
        guard let currentIndex else { return false }
        return items.indices.contains(currentIndex + 1)
    }

    private let audioManager: AudioManager
    private let downloads: MediaDownloadManager
    private let defaults: UserDefaults
    private let itemsKey = "playbackQueue.items.v1"
    private let indexKey = "playbackQueue.currentIndex.v1"
    private var controlledSessionID: UUID?
    private var controlledSelectionHandler: ((String) -> Bool)?
    private var controlledNextHandler: (() -> Bool)?
    private var controlledPreviousHandler: (() -> Bool)?

    init(
        audioManager: AudioManager,
        downloads: MediaDownloadManager = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.audioManager = audioManager
        self.downloads = downloads
        self.defaults = defaults
        restore()

        audioManager.onNextTrackCommand = { [weak self] in
            self?.playNext() ?? false
        }
        audioManager.onPreviousTrackCommand = { [weak self] in
            self?.playPrevious() ?? false
        }
        refreshCommandAvailability()
    }

    @discardableResult
    func replaceQueue(with newItems: [CarPlayMediaItem], startingAt item: CarPlayMediaItem) -> Bool {
        guard let index = newItems.firstIndex(where: { $0.id == item.id }) else { return false }
        clearControlledSession()
        items = newItems
        currentIndex = index
        persist()
        start(item)
        return true
    }

    @discardableResult
    func prepareQueue(with newItems: [CarPlayMediaItem], current item: CarPlayMediaItem) -> Bool {
        guard let index = newItems.firstIndex(where: { $0.id == item.id }) else { return false }
        clearControlledSession()
        items = newItems
        currentIndex = index
        audioManager.onStreamFinished = { [weak self] in
            _ = self?.playNext()
        }
        persist()
        refreshCommandAvailability()
        return true
    }

    func beginControlledSession(
        id: UUID,
        items newItems: [CarPlayMediaItem],
        current item: CarPlayMediaItem,
        onSelect: @escaping (String) -> Bool,
        onNext: @escaping () -> Bool,
        onPrevious: @escaping () -> Bool
    ) {
        guard let index = newItems.firstIndex(where: { $0.id == item.id }) else { return }
        controlledSessionID = id
        controlledSelectionHandler = onSelect
        controlledNextHandler = onNext
        controlledPreviousHandler = onPrevious
        items = newItems
        currentIndex = index
        persist()
        refreshCommandAvailability()
    }

    func synchronizeControlledSession(id: UUID, currentItemID: String) {
        guard controlledSessionID == id,
              let index = items.firstIndex(where: { $0.id == currentItemID }) else { return }
        currentIndex = index
        persist()
        refreshCommandAvailability()
    }

    func endControlledSession(id: UUID) {
        guard controlledSessionID == id else { return }
        clearControlledSession()
        refreshCommandAvailability()
    }

    func refreshPersistedItems(using resolvedItems: [CarPlayMediaItem]) {
        guard controlledSessionID == nil, !items.isEmpty else { return }
        let resolvedByID = Dictionary(uniqueKeysWithValues: resolvedItems.map { ($0.id, $0) })
        let oldCurrentID = currentItem?.id
        items = items.compactMap { resolvedByID[$0.id] }
        currentIndex = oldCurrentID.flatMap { id in items.firstIndex(where: { $0.id == id }) }
        if currentIndex == nil, !items.isEmpty { currentIndex = 0 }
        persist()
        refreshCommandAvailability()
    }

    @discardableResult
    func retryCurrent() -> Bool {
        guard let currentItem else { return false }
        start(currentItem)
        return true
    }

    func append(_ item: CarPlayMediaItem) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.append(item)
        persist()
        refreshCommandAvailability()
    }

    func remove(at offsets: IndexSet) {
        guard !offsets.isEmpty else { return }
        let oldCurrentID = currentItem?.id
        items.remove(atOffsets: offsets)
        currentIndex = oldCurrentID.flatMap { id in items.firstIndex(where: { $0.id == id }) }
        if currentIndex == nil, !items.isEmpty {
            currentIndex = min(offsets.first ?? 0, items.count - 1)
        }
        persist()
        refreshCommandAvailability()
    }

    func move(from offsets: IndexSet, to destination: Int) {
        let oldCurrentID = currentItem?.id
        items.move(fromOffsets: offsets, toOffset: destination)
        currentIndex = oldCurrentID.flatMap { id in items.firstIndex(where: { $0.id == id }) }
        persist()
        refreshCommandAvailability()
    }

    func clear() {
        items = []
        currentIndex = nil
        persist()
        refreshCommandAvailability()
    }

    @discardableResult
    func play(_ item: CarPlayMediaItem) -> Bool {
        if let controlledSelectionHandler {
            return controlledSelectionHandler(item.id)
        }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
        currentIndex = index
        persist()
        start(item)
        return true
    }

    @discardableResult
    func playNext() -> Bool {
        if let controlledNextHandler {
            return controlledNextHandler()
        }
        guard let currentIndex, items.indices.contains(currentIndex + 1) else { return false }
        self.currentIndex = currentIndex + 1
        persist()
        start(items[currentIndex + 1])
        return true
    }

    @discardableResult
    func playPrevious() -> Bool {
        if let controlledPreviousHandler {
            return controlledPreviousHandler()
        }
        guard let currentIndex, items.indices.contains(currentIndex - 1) else { return false }
        self.currentIndex = currentIndex - 1
        persist()
        start(items[currentIndex - 1])
        return true
    }

    private func start(_ item: CarPlayMediaItem) {
        audioManager.streamAudio(url: downloads.playableURL(for: item), startAt: item.resumePosition)
        audioManager.updateStreamNowPlayingInfo(title: item.title, artist: item.subtitle)
        audioManager.onStreamFinished = { [weak self] in
            _ = self?.playNext()
        }
        audioManager.playStream()
        refreshCommandAvailability()

        if let artworkURL = item.artworkURL {
            Task {
                guard let image = await NowPlayingArtworkLoader.shared.image(for: artworkURL),
                      currentItem?.id == item.id else { return }
                audioManager.updateStreamNowPlayingInfo(artworkImage: image)
            }
        }
    }

    private func refreshCommandAvailability() {
        audioManager.setTrackCommandAvailability(hasPrevious: hasPrevious, hasNext: hasNext)
    }

    private func clearControlledSession() {
        controlledSessionID = nil
        controlledSelectionHandler = nil
        controlledNextHandler = nil
        controlledPreviousHandler = nil
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: itemsKey)
        }
        if let currentIndex {
            defaults.set(currentIndex, forKey: indexKey)
        } else {
            defaults.removeObject(forKey: indexKey)
        }
    }

    private func restore() {
        if let data = defaults.data(forKey: itemsKey),
           let restoredItems = try? JSONDecoder().decode([CarPlayMediaItem].self, from: data) {
            items = restoredItems
        }
        if defaults.object(forKey: indexKey) != nil {
            let restoredIndex = defaults.integer(forKey: indexKey)
            currentIndex = items.indices.contains(restoredIndex) ? restoredIndex : nil
        }
    }
}

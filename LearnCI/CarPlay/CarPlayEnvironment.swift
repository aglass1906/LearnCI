import SwiftData

@MainActor
final class CarPlayEnvironment {
    static let shared = CarPlayEnvironment()

    private(set) var catalog: CarPlayCatalogProvider?
    let playback = PlaybackQueueManager.shared

    private init() {}

    func configure(modelContainer: ModelContainer) {
        guard catalog == nil else { return }
        let provider = CarPlayCatalogProvider(modelContainer: modelContainer)
        catalog = provider
        playback.refreshPersistedItems(using: provider.restorableQueueItems())
    }
}

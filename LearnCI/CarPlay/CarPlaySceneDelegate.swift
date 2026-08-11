import CarPlay
import UIKit

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        guard let catalog = CarPlayEnvironment.shared.catalog else {
            let unavailable = CPListTemplate(
                title: "LearnCI",
                sections: [CPListSection(items: [messageItem("Open LearnCI on your iPhone once, then reconnect CarPlay.")])]
            )
            interfaceController.setRootTemplate(unavailable, animated: false, completion: nil)
            return
        }

        let tabs = CPTabBarTemplate(templates: [
            makeTemplate(title: "Listen Now", systemImage: "play.circle.fill", items: catalog.listenNow()),
            makeTemplate(title: "Stories", systemImage: "book.fill", items: catalog.stories()),
            makeTemplate(title: "Podcasts", systemImage: "mic.fill", items: catalog.podcasts())
        ])
        interfaceController.setRootTemplate(tabs, animated: false, completion: nil)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    private func makeTemplate(
        title: String,
        systemImage: String,
        items: [CarPlayMediaItem]
    ) -> CPListTemplate {
        let rows: [CPListItem] = items.isEmpty
            ? [messageItem("No playable \(title.lowercased()) yet.")]
            : items.map { mediaItem in
                let row = CPListItem(text: mediaItem.title, detailText: mediaItem.subtitle)
                row.isExplicitContent = false
                if mediaItem.duration > 0 {
                    row.playbackProgress = min(1, mediaItem.resumePosition / mediaItem.duration)
                }
                row.handler = { [weak self] _, completion in
                    guard let self else {
                        completion()
                        return
                    }
                    let started = CarPlayEnvironment.shared.playback.replaceQueue(
                        with: items,
                        startingAt: mediaItem
                    )
                    completion()
                    if started {
                        self.interfaceController?.pushTemplate(
                            CPNowPlayingTemplate.shared,
                            animated: true,
                            completion: nil
                        )
                    }
                }
                return row
            }

        let template = CPListTemplate(title: title, sections: [CPListSection(items: rows)])
        template.tabTitle = title
        template.tabImage = UIImage(systemName: systemImage)
        return template
    }

    private func messageItem(_ text: String) -> CPListItem {
        let item = CPListItem(text: text, detailText: nil)
        item.isEnabled = false
        return item
    }
}

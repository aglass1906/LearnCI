import CarPlay
import UIKit

final class LearnCIAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        guard connectingSceneSession.role == .carTemplateApplication else {
            return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        }

        let configuration = UISceneConfiguration(
            name: "LearnCI CarPlay",
            sessionRole: connectingSceneSession.role
        )
        configuration.sceneClass = CPTemplateApplicationScene.self
        configuration.delegateClass = CarPlaySceneDelegate.self
        return configuration
    }
}

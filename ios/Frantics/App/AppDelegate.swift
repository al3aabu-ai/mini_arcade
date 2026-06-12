import UIKit

/// Frantics runs two kinds of scenes from one app:
///  - the normal phone scene (the player's controller)
///  - an external-display scene: when the host AirPlay-mirrors (or plugs in
///    HDMI), iOS hands the app the TV as a separate non-interactive screen
///    and we render the shared game board there instead of a mirror image.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            let config = UISceneConfiguration(name: "Board", sessionRole: connectingSceneSession.role)
            config.delegateClass = BoardSceneDelegate.self
            return config
        }
        let config = UISceneConfiguration(name: "Phone", sessionRole: connectingSceneSession.role)
        config.delegateClass = PhoneSceneDelegate.self
        return config
    }
}

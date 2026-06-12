import SwiftUI
import UIKit

/// Drives the TV. iOS creates this scene automatically when the host starts
/// AirPlay screen mirroring (or connects an HDMI adapter), because the app
/// opts into `UIWindowSceneSessionRoleExternalDisplayNonInteractive`.
final class BoardSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = .dark
        let root = BoardRootView().environmentObject(GameClient.shared)
        window.rootViewController = UIHostingController(rootView: root)
        window.isHidden = false
        self.window = window
        GameClient.shared.boardDisplayConnected = true
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window = nil
        GameClient.shared.boardDisplayConnected = false
    }
}

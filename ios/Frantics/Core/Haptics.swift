import UIKit

enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notify = UINotificationFeedbackGenerator()

    static func tick() { light.impactOccurred() }

    static func thump(intensity: CGFloat = 1.0) {
        heavy.impactOccurred(intensity: max(0.1, min(1, intensity)))
    }

    static func success() { notify.notificationOccurred(.success) }
    static func failure() { notify.notificationOccurred(.error) }
}

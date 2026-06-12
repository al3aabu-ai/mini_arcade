import CoreMotion
import Combine
import Foundation

/// Reads the gyroscope/accelerometer so the bomb can be passed by physically
/// tilting the phone toward a neighbor. Falls back gracefully (direction stays
/// nil) on devices/simulators without motion hardware — the UI then offers
/// tap-arrows instead.
@MainActor
final class TiltManager: ObservableObject {
    @Published var tilt: Double = 0 // -1 (hard left) ... +1 (hard right)
    @Published var direction: String? // "left" | "right" when past threshold

    private let manager = CMMotionManager()
    private let threshold = 0.32

    var available: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            // Portrait: gravity.x goes positive as the phone rolls to the right.
            let value = max(-1, min(1, gravity.x * 2.2))
            self.tilt = value
            if value <= -self.threshold {
                self.direction = "left"
            } else if value >= self.threshold {
                self.direction = "right"
            } else {
                self.direction = nil
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        tilt = 0
        direction = nil
    }
}

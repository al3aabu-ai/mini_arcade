import CoreMotion
import Foundation

/// Ice-bumper tilt input. Reads the GRAVITY vector (stable, low-noise vs. raw
/// accelerometer) and streams a normalized (pitch, roll) at a fixed tick. Hold
/// the phone flat like a tray; tilting in a direction pushes the bumper that way.
///
/// Gravity components are already a normalized tilt: each ≈ sin(angle on that
/// axis), so |(pitch, roll)| ≈ sin(total tilt from flat) — the server/board use
/// > 0.5 (sin 30°) as the over-tilt spin-out threshold.
@MainActor
final class BumperMotionController: ObservableObject {
    /// Live values for the on-screen bubble-level indicator.
    @Published var pitch: Double = 0
    @Published var roll: Double = 0
    @Published var available = true

    private let manager = CMMotionManager()
    private var calibration = (x: 0.0, y: 0.0)
    private var calibrated = false
    private let deadzone = 0.04
    /// Called every tick with the normalized vector → GameClient.updateMotionVector.
    var onSample: ((_ pitch: Double, _ roll: Double) -> Void)?

    /// Start streaming. 30Hz matches the joystick cadence and is gentle on
    /// battery/thermals; pass 60 for extra smoothness.
    func start(streamHz: Double = 30) {
        guard manager.isDeviceMotionAvailable else { available = false; return }
        guard !manager.isDeviceMotionActive else { return }
        calibrated = false
        manager.deviceMotionUpdateInterval = 1.0 / streamHz
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            // First good sample becomes "flat" so a comfortable hold reads as level.
            if !self.calibrated { self.calibration = (g.x, g.y); self.calibrated = true; return }

            var roll = g.x - self.calibration.x   // roll  → world X (left / right)
            var pitch = g.y - self.calibration.y  // pitch → world Z (forward / back)
            if (roll * roll + pitch * pitch) < self.deadzone * self.deadzone { roll = 0; pitch = 0 }
            roll = max(-1, min(1, roll))
            pitch = max(-1, min(1, pitch))

            self.roll = roll
            self.pitch = pitch
            self.onSample?(pitch, roll)
        }
    }

    /// Snapshot the current pose as the new "flat" reference (re-calibrate).
    func recalibrate() { calibrated = false }

    func stop() {
        manager.stopDeviceMotionUpdates()
        pitch = 0
        roll = 0
    }
}

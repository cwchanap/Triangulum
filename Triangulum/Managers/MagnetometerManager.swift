import Foundation
import CoreMotion
import os

class MagnetometerManager: ObservableObject {
    private let motionManager: CMMotionManager

    @Published var magneticFieldX: Double = 0.0
    @Published var magneticFieldY: Double = 0.0
    @Published var magneticFieldZ: Double = 0.0
    @Published var magnitude: Double = 0.0
    @Published var heading: Double = 0.0
    @Published var isAvailable: Bool = false
    @Published var errorMessage: String = ""

    init(motionManager: CMMotionManager = MotionService.shared) {
        self.motionManager = motionManager
        checkAvailability()
    }

    private func checkAvailability() {
        isAvailable = motionManager.isMagnetometerAvailable
    }

    func startMagnetometerUpdates() {
        guard isAvailable else {
            errorMessage = "Magnetometer not available on this device"
            return
        }

        guard motionManager.isMagnetometerAvailable else {
            errorMessage = "Motion sensors require privacy permissions. Please enable Motion & Fitness access in Settings."
            return
        }

        motionManager.magnetometerUpdateInterval = 0.1

        motionManager.startMagnetometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self else { return }

            if let error = error {
                let nsError = error as NSError
                if nsError.domain == CMErrorDomain && nsError.code == Int(CMErrorMotionActivityNotAuthorized.rawValue) {
                    self.errorMessage = "Motion sensor access denied. Please enable Motion & Fitness in Settings > Privacy & Security > Motion & Fitness"
                } else {
                    self.errorMessage = "Error reading magnetometer: \(error.localizedDescription)"
                }
                return
            }

            guard let data = data else {
                Logger.sensor.warning("MagnetometerManager: received nil data without error — reading frozen at last value")
                return
            }

            self.magneticFieldX = data.magneticField.x
            self.magneticFieldY = data.magneticField.y
            self.magneticFieldZ = data.magneticField.z
            self.magnitude = sqrt(pow(data.magneticField.x, 2) + pow(data.magneticField.y, 2) + pow(data.magneticField.z, 2))

            // Calculate heading (0-360 degrees)
            let radians = atan2(data.magneticField.y, data.magneticField.x)
            var degrees = radians * 180 / .pi
            if degrees < 0 {
                degrees += 360
            }
            self.heading = degrees

            self.errorMessage = ""
        }
    }

    func stopMagnetometerUpdates() {
        motionManager.stopMagnetometerUpdates()
    }
}

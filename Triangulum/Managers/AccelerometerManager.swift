import Foundation
import CoreMotion

class AccelerometerManager: ObservableObject {
    private let motionManager = CMMotionManager()

    @Published var accelerationX: Double = 0.0
    @Published var accelerationY: Double = 0.0
    @Published var accelerationZ: Double = 0.0
    @Published var magnitude: Double = 0.0
    @Published var isAvailable: Bool = false
    @Published var errorMessage: String = ""

    init() {
        checkAvailability()
    }

    private func checkAvailability() {
        isAvailable = motionManager.isAccelerometerAvailable
    }

    func startAccelerometerUpdates() {
        guard isAvailable else {
            errorMessage = "Accelerometer not available on this device"
            return
        }

        // Check if motion permissions are likely denied by testing availability
        guard motionManager.isAccelerometerAvailable else {
            errorMessage = "Motion sensors require privacy permissions. Please enable Motion & Fitness access in Settings."
            return
        }

        motionManager.accelerometerUpdateInterval = 0.1

        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self else { return }

            if let error = error {
                // Check for permission-related errors using NSError domain/code
                let nsError = error as NSError
                if nsError.domain == CMErrorDomain {
                    self.errorMessage = "Motion sensor access denied. Please enable Motion & Fitness in Settings > Privacy & Security > Motion & Fitness"
                } else {
                    self.errorMessage = "Error reading accelerometer: \(error.localizedDescription)"
                }
                return
            }

            guard let data = data else { return }

            self.accelerationX = data.acceleration.x
            self.accelerationY = data.acceleration.y
            self.accelerationZ = data.acceleration.z
            self.magnitude = sqrt(pow(data.acceleration.x, 2) + pow(data.acceleration.y, 2) + pow(data.acceleration.z, 2))
            self.errorMessage = ""
        }
    }

    func stopAccelerometerUpdates() {
        motionManager.stopAccelerometerUpdates()
    }
}

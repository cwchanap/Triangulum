import Foundation
import CoreMotion

class GyroscopeManager: ObservableObject {
    private let motionManager: CMMotionManager

    @Published var rotationX: Double = 0.0
    @Published var rotationY: Double = 0.0
    @Published var rotationZ: Double = 0.0
    @Published var magnitude: Double = 0.0
    @Published var isAvailable: Bool = false
    @Published var errorMessage: String = ""

    init(motionManager: CMMotionManager = MotionService.shared) {
        self.motionManager = motionManager
        checkAvailability()
    }

    private func checkAvailability() {
        isAvailable = motionManager.isGyroAvailable
    }

    func startGyroscopeUpdates() {
        guard isAvailable else {
            errorMessage = "Gyroscope not available on this device"
            return
        }

        motionManager.gyroUpdateInterval = 0.1

        motionManager.startGyroUpdates(to: .main) { [weak self] data, error in
            guard let self = self else { return }

            if let error = error {
                let nsError = error as NSError
                if nsError.domain == CMErrorDomain {
                    self.errorMessage = "Motion sensor access denied. Please enable Motion & Fitness in Settings > Privacy & Security > Motion & Fitness"
                } else {
                    self.errorMessage = "Error reading gyroscope: \(error.localizedDescription)"
                }
                return
            }

            guard let data = data else { return }

            self.rotationX = data.rotationRate.x
            self.rotationY = data.rotationRate.y
            self.rotationZ = data.rotationRate.z
            self.magnitude = sqrt(pow(data.rotationRate.x, 2) + pow(data.rotationRate.y, 2) + pow(data.rotationRate.z, 2))
            self.errorMessage = ""
        }
    }

    func stopGyroscopeUpdates() {
        motionManager.stopGyroUpdates()
    }
}

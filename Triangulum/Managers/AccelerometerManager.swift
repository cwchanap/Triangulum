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
        
        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self else { return }
            
            if let error = error {
                self.errorMessage = "Error reading accelerometer: \(error.localizedDescription)"
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
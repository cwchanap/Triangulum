import Foundation
import CoreMotion

class BarometerManager: ObservableObject {
    private let altimeter = CMAltimeter()
    private let motionManager = CMMotionManager()
    private let locationManager: LocationManager
    
    @Published var pressure: Double = 0.0
    @Published var attitude: CMAttitude?
    @Published var seaLevelPressure: Double = 0.0
    @Published var isAvailable: Bool = false
    @Published var isAttitudeAvailable: Bool = false
    @Published var errorMessage: String = ""
    
    init(locationManager: LocationManager) {
        self.locationManager = locationManager
        checkAvailability()
    }
    
    private func checkAvailability() {
        isAvailable = CMAltimeter.isRelativeAltitudeAvailable()
        isAttitudeAvailable = motionManager.isDeviceMotionAvailable
    }
    
    func startBarometerUpdates() {
        guard isAvailable else {
            errorMessage = "Barometer not available on this device"
            return
        }
        
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            guard let self = self else { return }
            
            if let error = error {
                self.errorMessage = "Error reading barometer: \(error.localizedDescription)"
                return
            }
            
            guard let data = data else { return }
            
            self.pressure = data.pressure.doubleValue
            self.seaLevelPressure = self.calculateSeaLevelPressure(
                currentPressure: data.pressure.doubleValue,
                altitude: self.locationManager.altitude
            )
            self.errorMessage = ""
        }
        
        startAttitudeUpdates()
    }
    
    func stopBarometerUpdates() {
        altimeter.stopRelativeAltitudeUpdates()
        motionManager.stopDeviceMotionUpdates()
    }
    
    private func startAttitudeUpdates() {
        guard isAttitudeAvailable else { return }
        
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            self.attitude = motion.attitude
        }
    }
    
    public func calculateSeaLevelPressure(currentPressure: Double, altitude: Double) -> Double {
        let temperatureK = 288.15
        let gasConstant = 287.053
        let gravity = 9.80665
        
        let exponent = (gravity * abs(altitude)) / (gasConstant * temperatureK)
        let pressureRatio = exp(exponent)
        
        return currentPressure * pressureRatio
    }
}
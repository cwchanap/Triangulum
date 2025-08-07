import Foundation
import CoreMotion

class BarometerManager: ObservableObject {
    private let altimeter = CMAltimeter()
    
    @Published var pressure: Double = 0.0
    @Published var relativeAltitude: Double = 0.0
    @Published var isAvailable: Bool = false
    @Published var errorMessage: String = ""
    
    init() {
        checkAvailability()
    }
    
    private func checkAvailability() {
        isAvailable = CMAltimeter.isRelativeAltitudeAvailable()
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
            self.relativeAltitude = data.relativeAltitude.doubleValue
            self.errorMessage = ""
        }
    }
    
    func stopBarometerUpdates() {
        altimeter.stopRelativeAltitudeUpdates()
    }
}
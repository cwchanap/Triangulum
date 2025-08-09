import Foundation
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    @Published var latitude: Double = 0.0
    @Published var longitude: Double = 0.0
    @Published var altitude: Double = 0.0
    @Published var accuracy: Double = 0.0
    @Published var isAvailable: Bool = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var errorMessage: String = ""
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        checkAvailability()
    }
    
    private func checkAvailability() {
        isAvailable = CLLocationManager.locationServicesEnabled()
        // Get authorization status without triggering main thread warning
        DispatchQueue.main.async { [weak self] in
            self?.authorizationStatus = self?.locationManager.authorizationStatus ?? .notDetermined
        }
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startLocationUpdates() {
        guard isAvailable else {
            errorMessage = "Location services not available"
            return
        }
        
        // Check authorization status properly
        let currentStatus = locationManager.authorizationStatus
        
        switch currentStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
            errorMessage = ""
        case .notDetermined:
            requestLocationPermission()
        case .denied, .restricted:
            errorMessage = "Location permission denied. Enable in Settings > Privacy & Security > Location Services"
        @unknown default:
            errorMessage = "Location permission status unknown"
        }
    }
    
    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        accuracy = location.horizontalAccuracy
        errorMessage = ""
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "Location error: \(error.localizedDescription)"
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        checkAvailability()
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            startLocationUpdates()
        case .denied, .restricted:
            errorMessage = "Location access denied"
        case .notDetermined:
            requestLocationPermission()
        @unknown default:
            break
        }
    }
}
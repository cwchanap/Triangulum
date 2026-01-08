import Foundation
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()

    @Published var latitude: Double = 0.0
    @Published var longitude: Double = 0.0
    @Published var altitude: Double = 0.0
    @Published var accuracy: Double = 0.0
    @Published var isAvailable: Bool = false
    @Published var heading: Double = 0.0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var errorMessage: String = ""

    /// Indicates whether a valid location fix has been received
    var hasValidLocation: Bool {
        return isAvailable && accuracy > 0
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        checkAvailability()
    }

    private func checkAvailability() {
        // Move system check to background thread to avoid main thread warning
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let servicesEnabled = CLLocationManager.locationServicesEnabled()

            DispatchQueue.main.async {
                guard let self = self else { return }

                let currentStatus = self.locationManager.authorizationStatus
                self.authorizationStatus = currentStatus

                print("DEBUG: Location services enabled system-wide: \(servicesEnabled)")
                print("DEBUG: Current authorization status: \(currentStatus.rawValue)")
                print("DEBUG: Authorization status description: \(self.authorizationStatusDescription)")

                // Available if system-wide location services are enabled
                self.isAvailable = servicesEnabled

                print("DEBUG: Location manager isAvailable: \(self.isAvailable)")

                // Auto-request permission if services are available but not determined
                if servicesEnabled && currentStatus == .notDetermined {
                    print("DEBUG: Auto-requesting location permission")
                    self.requestLocationPermission()
                } else if servicesEnabled && (currentStatus == .authorizedWhenInUse || currentStatus == .authorizedAlways) {
                    print("DEBUG: Starting location updates - already authorized")
                    self.startLocationUpdates()
                }
            }
        }
    }

    private var authorizationStatusDescription: String {
        switch authorizationStatus {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        @unknown default: return "unknown(\(authorizationStatus.rawValue))"
        }
    }

    private func checkAvailabilityAndStart() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let servicesEnabled = CLLocationManager.locationServicesEnabled()

            DispatchQueue.main.async {
                guard let self = self else { return }

                if servicesEnabled {
                    self.isAvailable = true
                    self.startLocationUpdates()
                } else {
                    self.errorMessage = "Location services not available"
                }
            }
        }
    }

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func startLocationUpdates() {
        // If isAvailable is false, it might be due to race condition - check async with completion
        if !isAvailable {
            checkAvailabilityAndStart()
            return
        }

        // Check authorization status properly
        let currentStatus = locationManager.authorizationStatus

        switch currentStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                locationManager.startUpdatingHeading()
            }
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
        locationManager.stopUpdatingHeading()
    }

    // MARK: - Heading Calibration
    func requestHeadingCalibration() {
        // There's no public API to force-show calibration, but restarting
        // heading updates and allowing calibration prompt helps trigger it
        // when the system deems necessary.
        guard CLLocationManager.headingAvailable() else { return }
        locationManager.stopUpdatingHeading()
        locationManager.startUpdatingHeading()
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
            errorMessage = ""
            startLocationUpdates()
        case .denied, .restricted:
            errorMessage = "Location access denied"
        case .notDetermined:
            // Permission request handled automatically in checkAvailability
            errorMessage = ""
        @unknown default:
            break
        }
    }

    // Heading updates
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Use trueHeading if valid, else magneticHeading
        let headingValue = newHeading.trueHeading > 0 ? newHeading.trueHeading : newHeading.magneticHeading
        heading = headingValue
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        // Allow system to show calibration when needed
        return true
    }
}

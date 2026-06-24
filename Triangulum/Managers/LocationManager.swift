import Foundation
import CoreLocation
import UIKit
import os

// Note: this class is NOT yet `@MainActor`. Annotating it cascades into
// `SatelliteManager`, whose `updatePositions()`/`updateNextPass()` read
// location state from main-actor-isolated callbacks but run SGP4 CPU work
// that must stay off-main. A full migration is tracked as a separate
// concurrency PR (LocationManager + SatelliteManager together). For now,
// `openAppSettings()` is individually `@MainActor` because UIApplication.shared
// must be touched on the main thread — see the method doc below.
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let skipAvailabilityCheck: Bool

    @Published var latitude: Double = 0.0
    @Published var longitude: Double = 0.0
    @Published var altitude: Double = 0.0
    @Published var accuracy: Double = 0.0
    @Published var isAvailable: Bool = false
    @Published var heading: Double = 0.0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var errorMessage: String = ""
    private var lastHorizontalAccuracy: Double = -1

    /// Indicates whether a valid location fix has been received
    var hasValidLocation: Bool {
        let isAuthorized = authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        return isAvailable && lastHorizontalAccuracy >= 0 && isAuthorized
    }

    /// Designated initializer.
    /// - Parameter skipAvailabilityCheck: When `true` the async availability
    ///   check is skipped, which prevents background-thread dispatch and
    ///   CLLocationManager work from running during UI-test launches.
    init(skipAvailabilityCheck: Bool = false) {
        self.skipAvailabilityCheck = skipAvailabilityCheck
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        if !skipAvailabilityCheck {
            checkAvailability()
        }
    }

    private func checkAvailability() {
        // Move system check to background thread to avoid main thread warning
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let servicesEnabled = CLLocationManager.locationServicesEnabled()

            DispatchQueue.main.async {
                guard let self = self else { return }

                let currentStatus = self.locationManager.authorizationStatus
                self.authorizationStatus = currentStatus

                Logger.location.debug("Location services enabled system-wide: \(servicesEnabled)")
                Logger.location.debug("Current authorization status: \(currentStatus.rawValue)")
                Logger.location.debug("Authorization status description: \(self.authorizationStatusDescription)")

                // Available if system-wide location services are enabled
                self.isAvailable = servicesEnabled

                Logger.location.debug("Location manager isAvailable: \(self.isAvailable)")

                // Auto-request permission if services are available but not determined
                if servicesEnabled && currentStatus == .notDetermined {
                    Logger.location.debug("Auto-requesting location permission")
                    self.requestLocationPermission()
                } else if servicesEnabled && (currentStatus == .authorizedWhenInUse || currentStatus == .authorizedAlways) {
                    Logger.location.debug("Starting location updates - already authorized")
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

    /// The system URL that deep-links into this app's Location permission screen.
    var appSettingsURL: URL {
        // openSettingsURLString is documented to never be empty.
        URL(string: UIApplication.openSettingsURLString)!
    }

    /// Opens the app's location settings. Used from the UI when authorization
    /// is `.denied` or `.restricted`, because `requestWhenInUseAuthorization()`
    /// is a system no-op in those states and will not re-prompt the user.
    ///
    /// `@MainActor` is intentional and enforced: `UIApplication.shared.open(_:)`
    /// must run on the main thread. Callers (View button actions) are already
    /// main-actor-isolated. See the class note above re: whole-class annotation.
    @MainActor
    func openAppSettings() {
        UIApplication.shared.open(appSettingsURL)
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
        // Track raw accuracy for validity and clamp for display
        lastHorizontalAccuracy = location.horizontalAccuracy
        accuracy = max(0, location.horizontalAccuracy)
        errorMessage = ""
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "Location error: \(error.localizedDescription)"
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        if !skipAvailabilityCheck {
            checkAvailability()
        }

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            errorMessage = ""
            if !skipAvailabilityCheck {
                startLocationUpdates()
            }
        case .denied, .restricted:
            errorMessage = "Location access denied"
        case .notDetermined:
            // Permission request handled automatically in checkAvailability
            errorMessage = ""
        @unknown default:
            Logger.location.warning("LocationManager: Unhandled CLAuthorizationStatus rawValue \(status.rawValue)")
            errorMessage = "Location permission status unknown. Please check Location settings."
        }
    }

    // Heading updates
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Use trueHeading if valid, else magneticHeading
        let headingValue = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        heading = headingValue
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        // Allow system to show calibration when needed
        return true
    }
}

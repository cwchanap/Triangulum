import Foundation
import CoreMotion
import SwiftData

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
    @Published var historyRecordingError: Error?

    // History manager for trend analysis and graphs
    // Initialized lazily on main actor via configureHistory()
    @MainActor
    private(set) var historyManager: PressureHistoryManager?

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
        checkAvailability()
    }

    /// Configure the history manager with SwiftData context
    @MainActor
    func configureHistory(with modelContext: ModelContext) {
        if historyManager == nil {
            historyManager = PressureHistoryManager()
        }
        historyManager?.configure(with: modelContext)
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

            let currentPressure = data.pressure.doubleValue

            // Validate location availability before calculating sea level pressure
            guard locationManager.hasValidLocation else {
                self.errorMessage = "Waiting for location data for accurate pressure reading"
                self.pressure = currentPressure
                return
            }

            let currentAltitude = self.locationManager.altitude
            let seaLevel = self.calculateSeaLevelPressure(
                currentPressure: currentPressure,
                altitude: currentAltitude
            )

            self.pressure = currentPressure
            self.seaLevelPressure = seaLevel
            self.errorMessage = ""

            // Record to history for trend analysis and graphs
            // historyManager is @MainActor, so we need to hop to main actor context
            Task { @MainActor in
                guard let historyManager = self.historyManager else { return }

                do {
                    try await historyManager.recordReading(
                        pressure: currentPressure,
                        altitude: currentAltitude,
                        seaLevelPressure: seaLevel
                    )
                    // Clear error on successful recording
                    self.historyRecordingError = nil
                } catch {
                    print("⚠️ Failed to record barometer reading: \(error.localizedDescription)")
                    // Surface the error to make it observable
                    self.historyRecordingError = error
                }
            }
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
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
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

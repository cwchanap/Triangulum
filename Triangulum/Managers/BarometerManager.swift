import Foundation
import CoreMotion
import SwiftData
import Combine
import os

class BarometerManager: ObservableObject {
    private let altimeter = CMAltimeter()
    private let motionManager: CMMotionManager
    private let locationManager: LocationManager

    @Published var pressure: Double = 0.0
    @Published var attitude: CMAttitude?
    @Published var seaLevelPressure: Double?
    @Published var isAvailable: Bool = false
    @Published var isAttitudeAvailable: Bool = false
    @Published var errorMessage: String = ""
    @Published var historyRecordingError: Error?

    private var cancellables = Set<AnyCancellable>()

    // History manager for trend analysis and graphs
    // Initialized lazily on main actor via configureHistory()
    @MainActor
    private(set) var historyManager: PressureHistoryManager?

    init(locationManager: LocationManager, motionManager: CMMotionManager = MotionService.shared) {
        self.locationManager = locationManager
        self.motionManager = motionManager
        checkAvailability()
    }

    /// Configure the history manager with SwiftData context
    @MainActor
    func configureHistory(with modelContext: ModelContext) {
        if historyManager == nil {
            historyManager = PressureHistoryManager()
        }
        historyManager?.configure(with: modelContext)
        cancellables.removeAll()
        historyManager?.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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

            guard let data = data else {
                Logger.sensor.warning("BarometerManager: Received nil data without error from altimeter")
                return
            }

            let currentPressure = data.pressure.doubleValue
            self.handlePressureUpdate(currentPressure: currentPressure)
        }

        startAttitudeUpdates()
    }

    func handlePressureUpdate(currentPressure: Double) {
        guard locationManager.hasValidLocation else {
            pressure = currentPressure
            seaLevelPressure = nil
            errorMessage = ""
            return
        }

        let currentAltitude = locationManager.altitude
        let seaLevel = calculateSeaLevelPressure(
            currentPressure: currentPressure,
            altitude: currentAltitude
        )

        pressure = currentPressure
        seaLevelPressure = seaLevel
        errorMessage = ""

        // Record to history for trend analysis and graphs
        // historyManager is @MainActor, so we need to hop to main actor context
        Task { @MainActor in
            guard let historyManager = self.historyManager,
                  let seaLevel = self.seaLevelPressure else {
                // History manager not configured - this is expected during initial setup
                // but should be logged if it persists after configureHistory() is called
                return
            }

            do {
                try await historyManager.recordReading(
                    pressure: currentPressure,
                    altitude: currentAltitude,
                    seaLevelPressure: seaLevel
                )
                // Clear error on successful recording
                self.historyRecordingError = nil
            } catch {
                Logger.sensor.warning("Failed to record barometer reading: \(error.localizedDescription)")
                // Surface the error to make it observable
                self.historyRecordingError = error
            }
        }
    }

    func stopBarometerUpdates() {
        altimeter.stopRelativeAltitudeUpdates()
        motionManager.stopDeviceMotionUpdates()
    }

    private func startAttitudeUpdates() {
        guard isAttitudeAvailable else { return }

        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self else { return }

            if let error = error {
                self.errorMessage = "Motion sensor error: \(error.localizedDescription)"
                return
            }

            guard let motion = motion else {
                Logger.sensor.warning("BarometerManager: Received nil motion data without error")
                return
            }
            self.attitude = motion.attitude
        }
    }

    public func calculateSeaLevelPressure(currentPressure: Double, altitude: Double) -> Double {
        let temperatureK = 288.15
        let gasConstant = 287.053
        let gravity = 9.80665

        // Use signed altitude so below-sea-level locations reduce sea-level pressure
        let exponent = (gravity * altitude) / (gasConstant * temperatureK)
        let pressureRatio = exp(exponent)

        return currentPressure * pressureRatio
    }
}

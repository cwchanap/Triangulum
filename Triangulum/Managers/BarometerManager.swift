import Foundation
import CoreMotion
import SwiftData
import Combine
import os

class BarometerManager: ObservableObject {
    private let altimeter = CMAltimeter()
    private let motionManager: CMMotionManager
    private let locationManager: LocationManager
    private let barometerAvailability: () -> Bool

    private enum AttitudeUpdateRequester: Hashable {
        case barometer
        case explicit
    }

    @Published var pressure: Double = 0.0
    @Published var attitude: CMAttitude?
    @Published var seaLevelPressure: Double?
    @Published var isAvailable: Bool = false
    @Published var isAttitudeAvailable: Bool = false
    @Published var errorMessage: String = ""
    @Published var motionStreamFailed: Bool = false
    @Published var historyRecordingError: Error?

    private var cancellables = Set<AnyCancellable>()
    private var didStartBarometerUpdates = false
    private var didStartDeviceMotion = false
    private var attitudeUpdateRequesters = Set<AttitudeUpdateRequester>()
    private var motionRetryCount = 0
    private static let maxMotionRetries = 5

    // History manager for trend analysis and graphs
    // Initialized lazily on main actor via configureHistory()
    @MainActor
    private(set) var historyManager: PressureHistoryManager?

    init(
        locationManager: LocationManager,
        motionManager: CMMotionManager = MotionService.shared,
        barometerAvailability: @escaping () -> Bool = CMAltimeter.isRelativeAltitudeAvailable
    ) {
        self.locationManager = locationManager
        self.motionManager = motionManager
        self.barometerAvailability = barometerAvailability
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
        isAvailable = barometerAvailability()
        isAttitudeAvailable = motionManager.isDeviceMotionAvailable
    }

    func startBarometerUpdates() {
        guard !didStartBarometerUpdates else { return }
        didStartBarometerUpdates = true

        guard isAvailable else {
            if !isAttitudeAvailable {
                errorMessage = "Barometer not available on this device"
            }
            return
        }

        // Only start attitude updates when the barometer is actually available,
        // so devices without a barometer don't run unnecessary motion sensing.
        // The Level page and explicit callers use startAttitudeUpdates() separately.
        startAttitudeUpdates(for: .barometer)

        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            guard let self = self else { return }

            if let error = error {
                self.errorMessage = "Error reading barometer: \(error.localizedDescription)"
                // Reset latch so a future startBarometerUpdates() call can retry.
                // Stop first to avoid duplicate altimeter callback streams.
                self.altimeter.stopRelativeAltitudeUpdates()
                self.didStartBarometerUpdates = false
                // Remove the .barometer requester so stopBarometerUpdates() can
                // still tear down the motion stream from ContentView.onDisappear.
                self.stopAttitudeUpdates(for: .barometer)
                return
            }

            guard let data = data else {
                Logger.sensor.warning("BarometerManager: Received nil data without error from altimeter")
                return
            }

            let currentPressure = data.pressure.doubleValue
            self.handlePressureUpdate(currentPressure: currentPressure)
        }
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
        guard didStartBarometerUpdates else { return }
        altimeter.stopRelativeAltitudeUpdates()
        didStartBarometerUpdates = false
        stopAttitudeUpdates(for: .barometer)
    }

    public func startAttitudeUpdates() {
        startAttitudeUpdates(for: .explicit)
    }

    private func startAttitudeUpdates(for requester: AttitudeUpdateRequester) {
        guard isAttitudeAvailable else { return }
        attitudeUpdateRequesters.insert(requester)

        startDeviceMotionUpdatesIfNeeded()
    }

    private func startDeviceMotionUpdatesIfNeeded() {
        guard isAttitudeAvailable else { return }
        guard !attitudeUpdateRequesters.isEmpty else { return }
        guard !didStartDeviceMotion else { return } // Already running

        motionManager.deviceMotionUpdateInterval = 0.1
        didStartDeviceMotion = true
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self else { return }

            if let error = error {
                self.errorMessage = "Motion sensor error: \(error.localizedDescription)"
                // Clear stale attitude so the Level page doesn't render frozen orientation
                // data after the motion stream has stopped.
                self.attitude = nil
                // Track that the motion stream has failed so the Level page can distinguish
                // this from an initial-loading state even after errorMessage is cleared by
                // a subsequent pressure update.
                self.motionStreamFailed = true
                // Do NOT set isAttitudeAvailable = false here — transient errors should
                // not permanently disable attitude updates. Hardware capability is determined
                // solely by checkAvailability() so that startAttitudeUpdates() can be retried.
                //
                // Reset the running state so a subsequent startAttitudeUpdates() call can
                // re-initiate device motion updates after a transient failure.
                self.motionManager.stopDeviceMotionUpdates()
                self.didStartDeviceMotion = false
                // Keep attitudeUpdateRequesters intact so that requesters (e.g. .barometer,
                // .explicit) are preserved across transient errors. A subsequent call to
                // startAttitudeUpdates(for:) will detect that motion is not running and
                // restart the stream without needing to re-insert requesters.
                self.motionRetryCount += 1
                if self.motionRetryCount <= Self.maxMotionRetries {
                    let delayMs = min(pow(2.0, Double(self.motionRetryCount - 1)) * 500, 8000)
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(delayMs))) { [weak self] in
                        self?.startDeviceMotionUpdatesIfNeeded()
                    }
                } else {
                    Logger.sensor.warning("BarometerManager: Motion stream failed \(Self.maxMotionRetries) times, giving up auto-retry")
                }
                return
            }

            guard let motion = motion else {
                Logger.sensor.warning("BarometerManager: Received nil motion data without error")
                return
            }
            if self.errorMessage.hasPrefix("Motion sensor error:") {
                self.errorMessage = ""
            }
            self.motionStreamFailed = false
            self.motionRetryCount = 0
            self.attitude = motion.attitude
        }
    }

    public func stopAttitudeUpdates() {
        stopAttitudeUpdates(for: .explicit)
    }

    private func stopAttitudeUpdates(for requester: AttitudeUpdateRequester) {
        guard attitudeUpdateRequesters.remove(requester) != nil else { return }
        guard attitudeUpdateRequesters.isEmpty else { return }
        if errorMessage.hasPrefix("Motion sensor error:") {
            errorMessage = ""
        }
        motionStreamFailed = false
        motionRetryCount = 0
        guard didStartDeviceMotion else {
            attitude = nil
            return
        }
        motionManager.stopDeviceMotionUpdates()
        didStartDeviceMotion = false
        attitude = nil
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

import Foundation
import CoreLocation
import os

@MainActor
class WeatherManager: ObservableObject {
    private let baseURL = "https://api.openweathermap.org/data/2.5/weather"
    var locationManager: LocationManager
    /// The repeating timer that drives availability checks and weather refreshes.
    /// Internal (not private) so unit tests can assert that exactly one timer is
    /// scheduled at any given time — preventing the duplicate-timer regression
    /// where stopFrequentPolling() and startMonitoring() each schedule their own.
    var weatherCheckTimer: Timer?
    /// Tracks whether monitoring is active. Set false by stopMonitoring() to prevent
    /// in-flight fetch completions from re-enabling the timer after an explicit stop.
    /// Internal (not private) so unit tests can verify the flag via @testable import.
    var isMonitoringEnabled: Bool = false

    @Published var currentWeather: Weather?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    @Published var isAvailable: Bool = false
    @Published var isInitializing: Bool = true

    /// Designated initializer.
    /// - Parameters:
    ///   - locationManager: The shared `LocationManager` instance.
    ///   - skipMonitoring: When `true` the polling timer and initial fetch
    ///     task are not created, preventing background work in UI-test runs.
    init(locationManager: LocationManager, skipMonitoring: Bool = false) {
        self.locationManager = locationManager

        // Start with loading state
        isInitializing = true

        if !skipMonitoring {
            // Check availability and start monitoring
            isMonitoringEnabled = true
            setupLocationObserver()
        }
    }

    deinit {
        // stopMonitoring() is the preferred cleanup path and should be called from
        // onDisappear. As a defensive fallback, dispatch invalidation back to the
        // main run loop — the same thread the Timer was scheduled on — so a missed
        // stopMonitoring() call never leaks a firing Timer.
        let timer = weatherCheckTimer
        DispatchQueue.main.async {
            timer?.invalidate()
        }
    }

    private func setupLocationObserver() {
        // Check after a brief delay
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.checkAndFetchWeather()
        }

        // Poll every 3 seconds until the first successful weather fetch.
        // On success, stopFrequentPolling() invalidates this timer and replaces it
        // with a 15-minute (900 s) repeating timer to prevent battery drain.
        weatherCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndFetchWeather()
            }
        }
    }

    func stopMonitoring() {
        isMonitoringEnabled = false
        weatherCheckTimer?.invalidate()
        weatherCheckTimer = nil
    }

    private func stopFrequentPolling() {
        weatherCheckTimer?.invalidate()
        weatherCheckTimer = nil
        guard isMonitoringEnabled else {
            Logger.weather.debug("Monitoring stopped — skipping 15-minute timer setup")
            return
        }
        Logger.weather.debug("Stopped frequent polling, switching to 15-minute refresh")
        weatherCheckTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndFetchWeather()
            }
        }
    }

    private func checkAndFetchWeather() {
        let hasAPIKey = Config.hasValidAPIKey
        let locationAvailable = locationManager.isAvailable
        let coordinate = CLLocationCoordinate2D(latitude: locationManager.latitude, longitude: locationManager.longitude)
        // Require both latitude and longitude to be non-zero
        let hasLocationData = CLLocationCoordinate2DIsValid(coordinate) && (coordinate.latitude != 0 && coordinate.longitude != 0)

        Logger.weather.debug("Check - API: \(hasAPIKey), Location: \(locationAvailable), Coords: \(hasLocationData)")

        if !hasAPIKey {
            isInitializing = false
            isAvailable = false
            errorMessage = "API key required. Set in Preferences."
            return
        }

        if !locationAvailable {
            isInitializing = false
            isAvailable = false
            errorMessage = "Location services required"
            return
        }

        if !hasLocationData {
            // Still waiting for location
            isInitializing = true
            isAvailable = false
            errorMessage = "Getting location..."
            return
        }

        // All conditions met
        isAvailable = true
        isInitializing = false
        errorMessage = ""

        // Fetch weather if we don't have any data yet.
        if currentWeather == nil && !isLoading {
            Logger.weather.debug("Auto-fetching weather data")
            Task {
                await fetchWeather()
            }
        } else if currentWeather != nil {
            // We already have weather data. This branch is reached either from the
            // 3-second availability-polling loop (setupLocationObserver fallback in
            // startMonitoring()) or from the 15-minute repeating timer.
            // In both cases we should:
            //   1. Refresh weather so it never goes stale on the 15-minute cadence.
            //   2. Ensure we are on the 15-minute schedule (not the 3-second loop).
            // fetchWeather() calls stopFrequentPolling() on success, but we also
            // call it here so the 3s → 15m transition happens immediately even
            // while a fetch is already in flight.
            if !isLoading && isMonitoringEnabled {
                Logger.weather.debug("Periodic refresh: re-fetching weather data on schedule")
                Task {
                    await fetchWeather()
                }
            }
            stopFrequentPolling()
        }
    }

    func fetchWeather() async {
        Logger.weather.debug("fetchWeather called")

        guard !isLoading else {
            Logger.weather.debug("fetchWeather skipped — already in progress")
            return
        }

        guard Config.hasValidAPIKey else {
            errorMessage = "API key required"
            return
        }

        let coordinate = CLLocationCoordinate2D(latitude: locationManager.latitude, longitude: locationManager.longitude)
        // Require both latitude and longitude to be non-zero
        guard CLLocationCoordinate2DIsValid(coordinate) && (coordinate.latitude != 0 && coordinate.longitude != 0) else {
            errorMessage = "No location data available"
            return
        }

        isLoading = true
        errorMessage = ""

        let lat = locationManager.latitude
        let lon = locationManager.longitude
        let apiKey = Config.openWeatherAPIKey

        let urlString = "\(baseURL)?lat=\(lat)&lon=\(lon)&appid=\(apiKey)"
        Logger.weather.debug("Fetching weather for lat=\(lat), lon=\(lon)")

        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid API URL"
            isLoading = false
            Logger.weather.error("Failed to create URL")
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            isLoading = false

            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.weather.error("Unexpected non-HTTP response")
                errorMessage = "Unexpected server response"
                return
            }

            Logger.weather.debug("HTTP Status Code: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                Logger.weather.error("Authorization error: HTTP \(httpResponse.statusCode, privacy: .public) — pausing polls until key is updated")
                errorMessage = "API Error: HTTP \(httpResponse.statusCode) – check your API key"
                // Stop the timer to avoid hammering the API with a bad key, but keep
                // isMonitoringEnabled = true.  That way a subsequent manual refresh
                // (refreshWeather/refreshAvailability) can call fetchWeather(), succeed
                // once the key is corrected, and have stopFrequentPolling() re-arm the
                // 15-minute timer without needing a full lifecycle restart.
                weatherCheckTimer?.invalidate()
                weatherCheckTimer = nil
                return
            }

            if httpResponse.statusCode != 200 {
                let responseString = String(data: data, encoding: .utf8) ?? "(no body)"
                Logger.weather.error("Error response (HTTP \(httpResponse.statusCode)): \(responseString)")
                errorMessage = "API Error: HTTP \(httpResponse.statusCode)"
                return
            }

            Logger.weather.debug("Received data of size: \(data.count) bytes")

            let weatherResponse = try JSONDecoder().decode(WeatherResponse.self, from: data)
            currentWeather = Weather(from: weatherResponse)
            errorMessage = ""
            Logger.weather.info("Weather data parsed successfully")
            stopFrequentPolling()
        } catch let decodingError as DecodingError {
            isLoading = false
            errorMessage = "Failed to parse weather data"
            Logger.weather.error("Weather parsing error: \(decodingError)")
        } catch {
            isLoading = false
            let errorMsg = "Network error: \(error.localizedDescription)"
            errorMessage = errorMsg
            Logger.weather.error("\(errorMsg)")
        }
    }

    func refreshWeather() {
        Logger.weather.debug("Manual refresh requested")
        guard !isLoading else {
            Logger.weather.debug("refreshWeather skipped — fetch already in progress")
            return
        }
        Task {
            await fetchWeather()
        }
    }

    /// Restart monitoring after stopMonitoring() has been called.
    /// Safe to call even if monitoring is already active — won't duplicate timers.
    func startMonitoring() {
        guard weatherCheckTimer == nil else { return }
        isMonitoringEnabled = true
        if currentWeather != nil {
            // Weather already fetched — revalidate immediately to catch any setting
            // changes (API key removal/update, location permission revocation) that
            // occurred while monitoring was stopped, then resume the 15-minute schedule.
            Logger.weather.debug("startMonitoring: existing weather data found, revalidating before starting 15-minute timer")
            checkAndFetchWeather()
            // checkAndFetchWeather() is synchronous and updates isAvailable inline.
            // Only schedule the 15-minute timer when availability is confirmed;
            // if something changed while monitoring was stopped (e.g. API key
            // removed, location permission revoked) fall back to the 3-second
            // polling loop so the UI recovers without manual intervention.
            if isAvailable {
                // checkAndFetchWeather() above may have already scheduled a 15-minute
                // timer via stopFrequentPolling() (the `else if currentWeather != nil`
                // branch). Only schedule one here when stopFrequentPolling() did NOT
                // run (e.g. availability check failed mid-way). Overwriting a non-nil
                // weatherCheckTimer without invalidating it would orphan the existing
                // timer and allow duplicate firings across stop/start cycles.
                if weatherCheckTimer == nil {
                    weatherCheckTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
                        Task { @MainActor in
                            self?.checkAndFetchWeather()
                        }
                    }
                }
            } else {
                setupLocationObserver()
            }
        } else {
            setupLocationObserver()
        }
    }

    /// Call this when API key is updated to recheck availability
    func refreshAvailability() {
        // Re-enable monitoring if it was stopped, so that successful fetches
        // can restart the 15-minute timer
        isMonitoringEnabled = true
        checkAndFetchWeather()
        // If we have valid conditions but no timer, start the 15-minute timer
        // (handles case where fetchWeather wasn't called because we already have data)
        if isAvailable && weatherCheckTimer == nil {
            Logger.weather.debug("Starting 15-minute timer from refreshAvailability")
            weatherCheckTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.checkAndFetchWeather()
                }
            }
        }
    }
}

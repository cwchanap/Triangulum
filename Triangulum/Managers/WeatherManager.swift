import Foundation
import CoreLocation
import os

@MainActor
class WeatherManager: ObservableObject {
    private let baseURL = "https://api.openweathermap.org/data/2.5/weather"
    var locationManager: LocationManager
    private var weatherCheckTimer: Timer?
    /// Tracks whether monitoring is active. Set false by stopMonitoring() to prevent
    /// in-flight fetch completions from re-enabling the timer after an explicit stop.
    private var isMonitoringEnabled: Bool = false

    @Published var currentWeather: Weather?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    @Published var isAvailable: Bool = false
    @Published var isInitializing: Bool = true

    init(locationManager: LocationManager) {
        self.locationManager = locationManager

        // Start with loading state
        isInitializing = true

        // Check availability and start monitoring
        isMonitoringEnabled = true
        setupLocationObserver()
    }

    /// Timer is also invalidated here as a safety net.
    /// Callers can alternatively call stopMonitoring() (e.g., in onDisappear)
    /// to explicitly stop the timer, especially useful in tests/previews.
    deinit {
        weatherCheckTimer?.invalidate()
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

        // Fetch weather if we don't have any data yet
        if currentWeather == nil && !isLoading {
            Logger.weather.debug("Auto-fetching weather data")
            Task {
                await fetchWeather()
            }
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
                Logger.weather.error("Authorization error: HTTP \(httpResponse.statusCode)")
                errorMessage = "API Error: HTTP \(httpResponse.statusCode) – check your API key"
                stopFrequentPolling()
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
        setupLocationObserver()
    }

    /// Call this when API key is updated to recheck availability
    func refreshAvailability() {
        checkAndFetchWeather()
    }
}

import Foundation
import CoreLocation
import os

class WeatherManager: ObservableObject {
    private let baseURL = "https://api.openweathermap.org/data/2.5/weather"
    var locationManager: LocationManager
    private var weatherCheckTimer: Timer?

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
        setupLocationObserver()
    }

    deinit {
        stopMonitoring()
    }

    private func setupLocationObserver() {
        // Check immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkAndFetchWeather()
        }

        // Then check periodically
        weatherCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkAndFetchWeather()
        }
    }

    func stopMonitoring() {
        weatherCheckTimer?.invalidate()
        weatherCheckTimer = nil
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
            fetchWeather()
        }
    }

    func fetchWeather() {
        Logger.weather.debug("fetchWeather called")

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

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    let errorMsg = "Network error: \(error.localizedDescription)"
                    self?.errorMessage = errorMsg
                    Logger.weather.error("\(errorMsg)")
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    Logger.weather.debug("HTTP Status Code: \(httpResponse.statusCode)")
                    if httpResponse.statusCode != 200 {
                        if let data = data, let responseString = String(data: data, encoding: .utf8) {
                            Logger.weather.error("Error response: \(responseString)")
                            self?.errorMessage = "API Error: HTTP \(httpResponse.statusCode)"
                        }
                        return
                    }
                }

                guard let data = data else {
                    self?.errorMessage = "No data received"
                    Logger.weather.error("No data received")
                    return
                }

                Logger.weather.debug("Received data of size: \(data.count) bytes")

                do {
                    let weatherResponse = try JSONDecoder().decode(WeatherResponse.self, from: data)
                    self?.currentWeather = Weather(from: weatherResponse)
                    self?.errorMessage = ""
                    Logger.weather.info("Weather data parsed successfully")
                } catch {
                    self?.errorMessage = "Failed to parse weather data"
                    Logger.weather.error("Weather parsing error: \(error)")
                    if let responseString = String(data: data, encoding: .utf8) {
                        Logger.weather.error("Response data: \(responseString)")
                    }
                }
            }
        }.resume()
    }

    func refreshWeather() {
        Logger.weather.debug("Manual refresh requested")
        fetchWeather()
    }

    /// Call this when API key is updated to recheck availability
    func refreshAvailability() {
        checkAndFetchWeather()
    }
}

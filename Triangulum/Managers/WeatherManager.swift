import Foundation
import CoreLocation

class WeatherManager: ObservableObject {
    private let baseURL = "https://api.openweathermap.org/data/2.5/weather"
    var locationManager: LocationManager
    
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
    
    private func setupLocationObserver() {
        // Check immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.checkAndFetchWeather()
        }
        
        // Then check periodically
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            self.checkAndFetchWeather()
        }
    }
    
    private func checkAndFetchWeather() {
        let hasAPIKey = Config.hasValidAPIKey
        let locationAvailable = locationManager.isAvailable
        let hasLocationData = locationManager.latitude != 0.0 && locationManager.longitude != 0.0
        
        print("DEBUG: Check - API: \(hasAPIKey), Location: \(locationAvailable), Coords: \(hasLocationData)")
        
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
            print("DEBUG: Auto-fetching weather data")
            fetchWeather()
        }
    }
    
    
    func fetchWeather() {
        print("DEBUG: fetchWeather called")
        
        guard Config.hasValidAPIKey else {
            errorMessage = "API key required"
            return
        }
        
        guard locationManager.latitude != 0.0 && locationManager.longitude != 0.0 else {
            errorMessage = "No location data available"
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        let lat = locationManager.latitude
        let lon = locationManager.longitude
        let apiKey = Config.openWeatherAPIKey
        
        let urlString = "\(baseURL)?lat=\(lat)&lon=\(lon)&appid=\(apiKey)"
        print("DEBUG: API URL: \(baseURL)?lat=\(lat)&lon=\(lon)&appid=\(String(apiKey.prefix(8)))...")
        
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid API URL"
            isLoading = false
            print("DEBUG: Failed to create URL")
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    let errorMsg = "Network error: \(error.localizedDescription)"
                    self?.errorMessage = errorMsg
                    print("DEBUG: \(errorMsg)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("DEBUG: HTTP Status Code: \(httpResponse.statusCode)")
                    if httpResponse.statusCode != 200 {
                        if let data = data, let responseString = String(data: data, encoding: .utf8) {
                            print("DEBUG: Error response: \(responseString)")
                            self?.errorMessage = "API Error: HTTP \(httpResponse.statusCode)"
                        }
                        return
                    }
                }
                
                guard let data = data else {
                    self?.errorMessage = "No data received"
                    print("DEBUG: No data received")
                    return
                }
                
                print("DEBUG: Received data of size: \(data.count) bytes")
                
                do {
                    let weatherResponse = try JSONDecoder().decode(WeatherResponse.self, from: data)
                    self?.currentWeather = Weather(from: weatherResponse)
                    self?.errorMessage = ""
                    print("DEBUG: Weather data parsed successfully")
                } catch {
                    self?.errorMessage = "Failed to parse weather data"
                    print("DEBUG: Weather parsing error: \(error)")
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("DEBUG: Response data: \(responseString)")
                    }
                }
            }
        }.resume()
    }
    
    func refreshWeather() {
        print("DEBUG: Manual refresh requested")
        fetchWeather()
    }
    
    /// Call this when API key is updated to recheck availability
    func refreshAvailability() {
        checkAndFetchWeather()
    }
}
import Foundation

struct WeatherResponse: Codable {
    let weather: [WeatherCondition]
    let main: WeatherMain
    let wind: WeatherWind?
    let visibility: Int?
    let name: String

    struct WeatherCondition: Codable {

        let id: Int
        let main: String
        let description: String
        let icon: String
    }

    struct WeatherMain: Codable {
        let temp: Double
        let feelsLike: Double
        let tempMin: Double
        let tempMax: Double
        let pressure: Int
        let humidity: Int

        enum CodingKeys: String, CodingKey {
            case temp
            case feelsLike = "feels_like"
            case tempMin = "temp_min"
            case tempMax = "temp_max"
            case pressure
            case humidity
        }
    }

    struct WeatherWind: Codable {
        let speed: Double
        let deg: Int?
    }
}

struct Weather {
    let temperature: Double
    let feelsLike: Double
    let tempMin: Double
    let tempMax: Double
    let humidity: Int
    let pressure: Int
    let windSpeed: Double?
    let windDirection: Int?
    let visibility: Int?
    let condition: String
    let description: String
    let icon: String
    let locationName: String
    let timestamp: Date

    init(from response: WeatherResponse) {
        self.temperature = response.main.temp
        self.feelsLike = response.main.feelsLike
        self.tempMin = response.main.tempMin
        self.tempMax = response.main.tempMax
        self.humidity = response.main.humidity
        self.pressure = response.main.pressure
        self.windSpeed = response.wind?.speed
        self.windDirection = response.wind?.deg
        self.visibility = response.visibility
        self.condition = response.weather.first?.main ?? "Unknown"
        self.description = response.weather.first?.description ?? "No description"
        self.icon = response.weather.first?.icon ?? "01d"
        self.locationName = response.name
        self.timestamp = Date()
    }

    var temperatureCelsius: Double {
        return temperature - 273.15
    }

    var temperatureFahrenheit: Double {
        return (temperature - 273.15) * 9/5 + 32
    }

    var systemIconName: String {
        switch icon.prefix(2) {
        case "01": return "sun.max.fill"
        case "02": return "cloud.sun.fill"
        case "03": return "cloud.fill"
        case "04": return "cloud.fill"
        case "09": return "cloud.drizzle.fill"
        case "10": return "cloud.rain.fill"
        case "11": return "cloud.bolt.fill"
        case "13": return "cloud.snow.fill"
        case "50": return "cloud.fog.fill"
        default: return "questionmark.circle.fill"
        }
    }
}

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
    private static let kelvinToCelsius = 273.15

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
        return temperature - Self.kelvinToCelsius
    }

    var feelsLikeCelsius: Double {
        return feelsLike - Self.kelvinToCelsius
    }

    var tempMinCelsius: Double {
        return tempMin - Self.kelvinToCelsius
    }

    var tempMaxCelsius: Double {
        return tempMax - Self.kelvinToCelsius
    }

    var temperatureFahrenheit: Double {
        return (temperature - Self.kelvinToCelsius) * 9/5 + 32
    }

    var systemIconName: String {
        switch icon {
        case "01d": return "sun.max.fill"
        case "01n": return "moon.fill"
        case "02d": return "cloud.sun.fill"
        case "02n": return "cloud.moon.fill"
        case "03d", "03n": return "cloud.fill"
        case "04d", "04n": return "cloud.fill"
        case "09d", "09n": return "cloud.drizzle.fill"
        case "10d": return "cloud.sun.rain.fill"
        case "10n": return "cloud.moon.rain.fill"
        case "11d", "11n": return "cloud.bolt.fill"
        case "13d", "13n": return "cloud.snow.fill"
        case "50d", "50n": return "cloud.fog.fill"
        default: return "questionmark.circle.fill"
        }
    }
}

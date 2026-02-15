import SwiftUI
import os

struct WeatherView: View {
    @ObservedObject var weatherManager: WeatherManager
    @State private var showingWeatherSearch = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "cloud.sun.fill")
                    .font(.title)
                    .foregroundColor(.prussianAccent)
                Text("Weather")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.prussianBlueDark)
                Spacer()

                Button {
                    showingWeatherSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundColor(.prussianAccent)
                }

                Button {
                    Logger.weather.debug("Manual refresh button pressed")
                    weatherManager.refreshWeather()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                        .foregroundColor(.prussianAccent)
                }
                .disabled(weatherManager.isLoading)
            }

            if weatherManager.isInitializing {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.prussianAccent)
                    Text("Initializing weather service...")
                        .foregroundColor(.prussianBlueLight)
                        .font(.caption)
                }
            } else if !weatherManager.isAvailable {
                VStack(spacing: 8) {
                    Text("Weather service unavailable")
                        .foregroundColor(.prussianError)
                        .font(.caption)
                    Text(weatherManager.errorMessage)
                        .foregroundColor(.prussianBlueLight)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
            } else if weatherManager.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.prussianAccent)
                    Text("Loading weather data...")
                        .foregroundColor(.prussianBlueLight)
                        .font(.caption)
                }
            } else if !weatherManager.errorMessage.isEmpty {
                VStack(spacing: 8) {
                    Text(weatherManager.errorMessage)
                        .foregroundColor(.prussianError)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    if weatherManager.errorMessage.contains("API key") {
                        Text("Get a free key from openweathermap.org")
                            .foregroundColor(.prussianBlueLight)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    }
                }
            } else if weatherManager.isAvailable && weatherManager.currentWeather == nil {
                VStack(spacing: 8) {
                    Text("No weather data")
                        .foregroundColor(.prussianBlueLight)
                        .font(.caption)
                    Button("Fetch Weather") {
                        Task {
                            await weatherManager.fetchWeather()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.prussianAccent)
                }
            } else if let weather = weatherManager.currentWeather {
                VStack(spacing: 12) {
                    // Main weather display
                    HStack(spacing: 16) {
                        VStack {
                            Image(systemName: weather.systemIconName)
                                .font(.largeTitle)
                                .foregroundColor(.prussianAccent)
                            Text(weather.condition)
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(weather.temperatureCelsius, specifier: "%.1f")°C")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.prussianBlueDark)
                            Text("Feels like \(weather.feelsLike - 273.15, specifier: "%.1f")°C")
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                            Text(weather.description.capitalized)
                                .font(.caption)
                                .foregroundColor(.prussianBlueLight)
                        }

                        Spacer()
                    }

                    // Weather details
                    VStack(spacing: 8) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Humidity")
                                    .font(.caption)
                                    .foregroundColor(.prussianBlueLight)
                                Text("\(weather.humidity)%")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(.prussianBlueDark)
                            }

                            Spacer()

                            VStack(alignment: .trailing) {
                                Text("Pressure")
                                    .font(.caption)
                                    .foregroundColor(.prussianBlueLight)
                                Text("\(weather.pressure) hPa")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(.prussianBlueDark)
                            }
                        }

                        if let windSpeed = weather.windSpeed {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Wind Speed")
                                        .font(.caption)
                                        .foregroundColor(.prussianBlueLight)
                                    Text("\(windSpeed, specifier: "%.1f") m/s")
                                        .font(.title3)
                                        .fontWeight(.medium)
                                        .foregroundColor(.prussianBlueDark)
                                }

                                Spacer()

                                if let visibility = weather.visibility {
                                    VStack(alignment: .trailing) {
                                        Text("Visibility")
                                            .font(.caption)
                                            .foregroundColor(.prussianBlueLight)
                                        Text("\(visibility / 1000) km")
                                            .font(.title3)
                                            .fontWeight(.medium)
                                            .foregroundColor(.prussianBlueDark)
                                    }
                                }
                            }
                        }

                        HStack {
                            VStack(alignment: .leading) {
                                Text("Min")
                                    .font(.caption)
                                    .foregroundColor(.prussianBlueLight)
                                Text("\(weather.tempMin - 273.15, specifier: "%.1f")°C")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(.prussianBlueDark)
                            }

                            Spacer()

                            VStack(alignment: .trailing) {
                                Text("Max")
                                    .font(.caption)
                                    .foregroundColor(.prussianBlueLight)
                                Text("\(weather.tempMax - 273.15, specifier: "%.1f")°C")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(.prussianBlueDark)
                            }
                        }
                    }

                    // Location and timestamp
                    VStack(spacing: 2) {
                        Text(weather.locationName)
                            .font(.caption)
                            .foregroundColor(.prussianBlueLight)
                        Text("Updated: \(weather.timestamp.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundColor(.prussianBlueLight)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Text("No weather data")
                        .foregroundColor(.prussianBlueLight)
                        .font(.caption)
                    Button("Fetch Weather") {
                        Task {
                            await weatherManager.fetchWeather()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.prussianAccent)
                }
            }
        }
        .widgetCard()
        .sheet(isPresented: $showingWeatherSearch) {
            WeatherSearchView()
        }
        .onAppear {
            if weatherManager.currentWeather == nil && weatherManager.isAvailable {
                Task {
                    await weatherManager.fetchWeather()
                }
            }
        }
    }
}

#Preview {
    let locationManager = LocationManager()
    let weatherManager = WeatherManager(locationManager: locationManager)

    return WeatherView(weatherManager: weatherManager)
        .onAppear {
            // Mock weather data for preview
            let mockResponse = WeatherResponse(
                weather: [
                    WeatherResponse.WeatherCondition(
                        id: 800,
                        main: "Clear",
                        description: "clear sky",
                        icon: "01d"
                    )
                ],
                main: WeatherResponse.WeatherMain(
                    temp: 295.15,
                    feelsLike: 297.0,
                    tempMin: 293.0,
                    tempMax: 298.0,
                    pressure: 1013,
                    humidity: 65
                ),
                wind: WeatherResponse.WeatherWind(speed: 3.5, deg: 180),
                visibility: 10000,
                name: "San Francisco"
            )
            weatherManager.currentWeather = Weather(from: mockResponse)
        }
        .padding()
}

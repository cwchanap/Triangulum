import SwiftUI
import os

struct WeatherView: View {
    @ObservedObject var weatherManager: WeatherManager
    @State private var showingWeatherSearch = false

    var body: some View {
        VStack(spacing: 16) {
            InstrumentHeader(icon: "cloud.sun.fill", title: "Weather", tint: .celGold) {
                HStack(spacing: 14) {
                    Button {
                        showingWeatherSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.celCyan)
                    }

                    Button {
                        Logger.weather.debug("Manual refresh button pressed")
                        weatherManager.refreshWeather()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.celCyan)
                    }
                    .disabled(weatherManager.isLoading)
                }
            }

            if weatherManager.isInitializing {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.celCyan)
                    Text("Initializing weather service...")
                        .foregroundColor(.celTextDim)
                        .font(.caption)
                }
            } else if !weatherManager.isAvailable {
                VStack(spacing: 8) {
                    Text("Weather service unavailable")
                        .foregroundColor(.celRed)
                        .font(.caption)
                    Text(weatherManager.errorMessage)
                        .foregroundColor(.celTextDim)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
            } else if weatherManager.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.celCyan)
                    Text("Loading weather data...")
                        .foregroundColor(.celTextDim)
                        .font(.caption)
                }
            } else if !weatherManager.errorMessage.isEmpty {
                VStack(spacing: 8) {
                    Text(weatherManager.errorMessage)
                        .foregroundColor(.celRed)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    if weatherManager.errorMessage.contains("API key") {
                        Text("Get a free key from openweathermap.org")
                            .foregroundColor(.celTextDim)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    }
                }
            } else if weatherManager.isAvailable && weatherManager.currentWeather == nil {
                VStack(spacing: 8) {
                    Text("No weather data")
                        .foregroundColor(.celTextDim)
                        .font(.caption)
                    Button("Fetch Weather") {
                        Task {
                            await weatherManager.fetchWeather()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.celCyan)
                }
            } else if let weather = weatherManager.currentWeather {
                VStack(spacing: 12) {
                    // Main weather display
                    HStack(spacing: 16) {
                        VStack {
                            Image(systemName: weather.systemIconName)
                                .font(.largeTitle)
                                .foregroundColor(.celCyan)
                            Text(weather.condition)
                                .font(.caption)
                                .foregroundColor(.celTextDim)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(weather.temperatureCelsius, specifier: "%.1f")°C")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.celText)
                            Text("Feels like \(weather.feelsLikeCelsius, specifier: "%.1f")°C")
                                .font(.caption)
                                .foregroundColor(.celTextDim)
                            Text(weather.description.capitalized)
                                .font(.caption)
                                .foregroundColor(.celTextDim)
                        }

                        Spacer()
                    }

                    // Weather details
                    VStack(spacing: 8) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Humidity")
                                    .font(.caption)
                                    .foregroundColor(.celTextDim)
                                Text("\(weather.humidity)%")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(.celText)
                            }

                            Spacer()

                            VStack(alignment: .trailing) {
                                Text("Pressure")
                                    .font(.caption)
                                    .foregroundColor(.celTextDim)
                                Text("\(weather.pressure) hPa")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(.celText)
                            }
                        }

                        if let windSpeed = weather.windSpeed {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Wind Speed")
                                        .font(.caption)
                                        .foregroundColor(.celTextDim)
                                    Text("\(windSpeed, specifier: "%.1f") m/s")
                                        .font(.title3)
                                        .fontWeight(.medium)
                                        .foregroundColor(.celText)
                                }

                                Spacer()

                                if let visibility = weather.visibility {
                                    VStack(alignment: .trailing) {
                                        Text("Visibility")
                                            .font(.caption)
                                            .foregroundColor(.celTextDim)
                                        Text("\(visibility / 1000) km")
                                            .font(.title3)
                                            .fontWeight(.medium)
                                            .foregroundColor(.celText)
                                    }
                                }
                            }
                        }

                        HStack {
                            VStack(alignment: .leading) {
                                Text("Min")
                                    .font(.caption)
                                    .foregroundColor(.celTextDim)
                                Text("\(weather.tempMinCelsius, specifier: "%.1f")°C")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(.celText)
                            }

                            Spacer()

                            VStack(alignment: .trailing) {
                                Text("Max")
                                    .font(.caption)
                                    .foregroundColor(.celTextDim)
                                Text("\(weather.tempMaxCelsius, specifier: "%.1f")°C")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(.celText)
                            }
                        }
                    }

                    // Location and timestamp
                    VStack(spacing: 2) {
                        Text(weather.locationName)
                            .font(.caption)
                            .foregroundColor(.celTextDim)
                        Text("Updated: \(weather.timestamp.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundColor(.celTextDim)
                    }
                }
            }
        }
        .widgetCard()
        .sheet(isPresented: $showingWeatherSearch) {
            WeatherSearchView()
        }
        .onAppear {
            if weatherManager.currentWeather == nil && weatherManager.isAvailable && !weatherManager.isLoading {
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

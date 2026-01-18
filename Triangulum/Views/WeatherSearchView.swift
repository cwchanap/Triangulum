//
//  WeatherSearchView.swift
//  Triangulum
//
//  Created by Rovo Dev on 10/8/2025.
//

import SwiftUI
import CoreLocation

struct WeatherSearchView: View {
    @State private var searchText = ""
    @State private var searchResults: [Weather] = []
    @State private var isSearching = false
    @State private var errorMessage = ""
    @State private var searchHistory: [SearchedCity] = []

    private let weatherManager = WeatherSearchManager()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchBarSection
                contentSection
            }
            .navigationTitle("Weather Search")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.prussianBlue, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            loadSearchHistory()
        }
    }

    private var searchBarSection: some View {
        VStack(spacing: 12) {
            searchBarContent

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .padding()
        .background(Color.white)
        .shadow(color: .prussianBlue.opacity(0.1), radius: 2, x: 0, y: 2)
    }

    private var searchBarContent: some View {
        HStack(spacing: 12) {
            searchTextField
            searchButton
        }
    }

    private var searchTextField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.prussianBlueLight)

            TextField("Search city (e.g., London, Paris, Tokyo)", text: $searchText)
                .textInputAutocapitalization(.words)
                .onSubmit {
                    searchWeather()
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    errorMessage = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.prussianBlueLight)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.prussianSoft.opacity(0.3))
        .cornerRadius(10)
    }

    private var searchButton: some View {
        Button(action: searchWeather) {
            if isSearching {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.white)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
            }
        }
        .foregroundColor(.white)
        .frame(width: 40, height: 40)
        .background(isSearching ? Color.prussianBlueLight : Color.prussianAccent)
        .cornerRadius(8)
        .disabled(isSearching || searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var contentSection: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Search Results
                if !searchResults.isEmpty {
                    Section {
                        ForEach(searchResults, id: \.locationName) { weather in
                            WeatherSearchResultCard(weather: weather) {
                                addToHistory(weather)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Search Results")
                                .font(.headline)
                                .foregroundColor(.prussianBlueDark)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top)
                    }
                }

                // Search History
                if !searchHistory.isEmpty {
                    Section {
                        ForEach(searchHistory, id: \.id) { city in
                            WeatherHistoryCard(city: city) {
                                searchWeatherForCity(city.name)
                            } onDelete: {
                                removeFromHistory(city)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Recent Searches")
                                .font(.headline)
                                .foregroundColor(.prussianBlueDark)
                            Spacer()
                            Button("Clear All") {
                                clearHistory()
                            }
                            .font(.caption)
                            .foregroundColor(.prussianAccent)
                        }
                        .padding(.horizontal)
                        .padding(.top)
                    }
                }

                // Empty State
                if searchResults.isEmpty && searchHistory.isEmpty && !isSearching {
                    VStack(spacing: 16) {
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.prussianBlueLight)

                        Text("Search Weather Worldwide")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.prussianBlueDark)

                        Text("Enter any city name to get current weather conditions from around the world")
                            .font(.body)
                            .foregroundColor(.prussianBlueLight)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 80)
                }
            }
        }
        .background(Color.prussianSoft.ignoresSafeArea())
    }

    // MARK: - Search Functions

    private func searchWeather() {
        let city = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else { return }

        searchWeatherForCity(city)
    }

    private func searchWeatherForCity(_ city: String) {
        isSearching = true
        errorMessage = ""

        Task {
            do {
                let weather = try await weatherManager.fetchWeather(for: city)
                await MainActor.run {
                    searchResults = [weather]
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Could not find weather for '\(city)'. Please check the city name and try again."
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }

    // MARK: - History Management

    private func addToHistory(_ weather: Weather) {
        let city = SearchedCity(name: weather.locationName, country: "")

        // Remove if already exists to avoid duplicates
        searchHistory.removeAll { $0.name.lowercased() == city.name.lowercased() }

        // Add to beginning
        searchHistory.insert(city, at: 0)

        // Keep only last 10 searches
        if searchHistory.count > 10 {
            searchHistory = Array(searchHistory.prefix(10))
        }

        saveSearchHistory()
    }

    private func removeFromHistory(_ city: SearchedCity) {
        searchHistory.removeAll { $0.id == city.id }
        saveSearchHistory()
    }

    private func clearHistory() {
        searchHistory.removeAll()
        saveSearchHistory()
    }

    private func loadSearchHistory() {
        if let data = UserDefaults.standard.data(forKey: "weatherSearchHistory"),
           let decoded = try? JSONDecoder().decode([SearchedCity].self, from: data) {
            searchHistory = decoded
        }
    }

    private func saveSearchHistory() {
        if let encoded = try? JSONEncoder().encode(searchHistory) {
            UserDefaults.standard.set(encoded, forKey: "weatherSearchHistory")
        }
    }
}

// MARK: - Supporting Views

struct WeatherSearchResultCard: View {
    let weather: Weather
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(weather.locationName)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.prussianBlueDark)
                }

                Spacer()

                Button(action: onSave) {
                    Image(systemName: "bookmark")
                        .font(.title3)
                        .foregroundColor(.prussianAccent)
                }
            }

            HStack(spacing: 20) {
                // Temperature
                VStack(alignment: .leading, spacing: 4) {
                    Text("Temperature")
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                    Text(String(format: "%.1f°C", weather.temperatureCelsius))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.prussianBlueDark)
                }

                Spacer()

                // Conditions
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Conditions")
                        .font(.caption)
                        .foregroundColor(.prussianBlueLight)
                    Text(weather.description.capitalized)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.prussianBlueDark)
                        .multilineTextAlignment(.trailing)
                }
            }

            // Additional Info
            HStack(spacing: 16) {
                WeatherInfoItem(title: "Feels Like", value: String(format: "%.1f°C", weather.feelsLike - 273.15))
                WeatherInfoItem(title: "Humidity", value: "\(weather.humidity)%")
                WeatherInfoItem(title: "Pressure", value: "\(weather.pressure) hPa")
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .prussianBlue.opacity(0.1), radius: 4, x: 0, y: 2)
        .padding(.horizontal)
    }
}

struct WeatherHistoryCard: View {
    let city: SearchedCity
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(city.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.prussianBlueDark)

                if !city.country.isEmpty {
                    Text(city.country)
                        .font(.caption2)
                        .foregroundColor(.prussianBlueLight)
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.prussianBlueLight)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.white)
        .cornerRadius(8)
        .shadow(color: .prussianBlue.opacity(0.05), radius: 2, x: 0, y: 1)
        .padding(.horizontal)
        .onTapGesture {
            onTap()
        }
    }
}

struct WeatherInfoItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.prussianBlueLight)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.prussianBlueDark)
        }
    }
}

// MARK: - Data Models

struct SearchedCity: Codable, Identifiable {
    // swiftlint:disable:next identifier_name
    let id = UUID()
    let name: String
    let country: String
    let timestamp = Date()
}

// MARK: - Weather Search Manager

class WeatherSearchManager {
    private let baseURL = "https://api.openweathermap.org/data/2.5/weather"

    func fetchWeather(for city: String) async throws -> Weather {
        guard Config.hasValidAPIKey else {
            throw WeatherSearchError.noAPIKey
        }

        let apiKey = Config.openWeatherAPIKey
        let encodedCity = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city
        let urlString = "\(baseURL)?q=\(encodedCity)&appid=\(apiKey)"

        guard let url = URL(string: urlString) else {
            throw WeatherSearchError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeatherSearchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw WeatherSearchError.cityNotFound
        }

        let weatherResponse = try JSONDecoder().decode(WeatherResponse.self, from: data)
        return Weather(from: weatherResponse)
    }
}

enum WeatherSearchError: Error, LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case cityNotFound

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "API key required. Please set your OpenWeatherMap API key in settings."
        case .invalidURL:
            return "Invalid search URL."
        case .invalidResponse:
            return "Invalid response from weather service."
        case .cityNotFound:
            return "City not found. Please check the spelling and try again."
        }
    }
}

#Preview {
    WeatherSearchView()
}

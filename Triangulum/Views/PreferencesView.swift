//
//  PreferencesView.swift
//  Triangulum
//
//  Created by Chan Wai Chan on 10/8/2025.
//

import SwiftUI

struct PreferencesView: View {
    @AppStorage("showBarometerWidget") private var showBarometerWidget = true
    @AppStorage("showLocationWidget") private var showLocationWidget = true
    @AppStorage("showWeatherWidget") private var showWeatherWidget = true
    @AppStorage("showAccelerometerWidget") private var showAccelerometerWidget = true
    @AppStorage("showGyroscopeWidget") private var showGyroscopeWidget = true
    @AppStorage("showMagnetometerWidget") private var showMagnetometerWidget = true
    @AppStorage("showMapWidget") private var showMapWidget = true
    @AppStorage("mapProvider") private var mapProvider = "apple" // "apple" or "osm"
    @StateObject private var locationManager = LocationManager()

    @State private var apiKeyInput = ""
    @State private var showingAPIKeyAlert = false
    @State private var showingViewAPIKeyAlert = false
    @State private var apiKeyStatus = "Not Set"

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Sensor Widgets")) {
                    Toggle("Barometer", isOn: $showBarometerWidget)
                        .toggleStyle(SwitchToggleStyle(tint: .prussianBlue))

                    Toggle("Location", isOn: $showLocationWidget)
                        .toggleStyle(SwitchToggleStyle(tint: .prussianBlue))

                    Toggle("Weather", isOn: $showWeatherWidget)
                        .toggleStyle(SwitchToggleStyle(tint: .prussianBlue))

                    Toggle("Accelerometer", isOn: $showAccelerometerWidget)
                        .toggleStyle(SwitchToggleStyle(tint: .prussianBlue))

                    Toggle("Gyroscope", isOn: $showGyroscopeWidget)
                        .toggleStyle(SwitchToggleStyle(tint: .prussianBlue))

                    Toggle("Magnetometer", isOn: $showMagnetometerWidget)
                        .toggleStyle(SwitchToggleStyle(tint: .prussianBlue))

                    Toggle("Map", isOn: $showMapWidget)
                        .toggleStyle(SwitchToggleStyle(tint: .prussianBlue))
                }
                .foregroundColor(.primary)

                Section(header: Text("Map")) {
                    Picker("Map Provider", selection: $mapProvider) {
                        Text("Apple Maps").tag("apple")
                        Text("OpenStreetMap").tag("osm")
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    if mapProvider == "osm" {
                        NavigationLink(destination: MapCacheView(locationManager: locationManager)) {
                            HStack {
                                Image(systemName: "externaldrive")
                                    .font(.caption)
                                    .foregroundColor(.prussianBlueLight)
                                Text("Cache Management")
                                    .font(.caption)
                                Spacer()
                            }
                        }
                        .foregroundColor(.prussianBlueLight)
                    }
                }

                Section(header: Text("Weather Configuration")) {
                    HStack {
                        Text("API Key Status:")
                            .font(.caption)
                            .foregroundColor(.prussianBlueLight)
                        Spacer()
                        Text(apiKeyStatus)
                            .font(.caption)
                            .foregroundColor(Config.hasValidAPIKey ? .green : .red)
                    }

                    Button {
                        showingAPIKeyAlert = true
                        apiKeyInput = "" // Clear input field
                    } label: {
                        HStack {
                            Image(systemName: "key")
                                .font(.caption)
                                .foregroundColor(.prussianAccent)
                            Text(Config.hasValidAPIKey ? "Update API Key" : "Set API Key")
                                .font(.caption)
                                .foregroundColor(.prussianAccent)
                        }
                    }

                    if Config.hasValidAPIKey {
                        Button {
                            showingViewAPIKeyAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "eye")
                                    .font(.caption)
                                    .foregroundColor(.prussianBlueLight)
                                Text("View API Key")
                                    .font(.caption)
                                    .foregroundColor(.prussianBlueLight)
                            }
                        }
                    }

                    if Config.hasValidAPIKey {
                        Button {
                            if Config.deleteAPIKey() {
                                updateAPIKeyStatus()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                Text("Remove API Key")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    Text("Get your free API key from openweathermap.org")
                        .font(.caption2)
                        .foregroundColor(.prussianBlueLight)
                        .multilineTextAlignment(.leading)
                }
            }
            .navigationTitle("Preferences")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.prussianBlue, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            updateAPIKeyStatus()
        }
        .alert("Enter OpenWeatherMap API Key", isPresented: $showingAPIKeyAlert) {
            TextField("API Key", text: $apiKeyInput)
            Button("Save") {
                if Config.storeAPIKey(apiKeyInput) {
                    updateAPIKeyStatus()
                    apiKeyInput = "" // Clear the input
                }
            }
            Button("Cancel", role: .cancel) {
                apiKeyInput = ""
            }
        } message: {
            Text("Enter your API key from openweathermap.org. It will be stored securely in the Keychain.")
        }
        .alert("Your OpenWeatherMap API Key", isPresented: $showingViewAPIKeyAlert) {
            Button("Copy to Clipboard") {
                let apiKey = Config.openWeatherAPIKey
                if !apiKey.isEmpty {
                    UIPasteboard.general.string = apiKey
                }
            }
            Button("Close", role: .cancel) { }
        } message: {
            Text(Config.openWeatherAPIKey.isEmpty ? "No API key found" : Config.openWeatherAPIKey)
        }
    }

    private func updateAPIKeyStatus() {
        apiKeyStatus = Config.hasValidAPIKey ? "✓ Set" : "Not Set"
    }
}

#Preview {
    PreferencesView()
}

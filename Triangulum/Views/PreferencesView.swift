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
    @AppStorage("showSatelliteWidget") private var showSatelliteWidget = true
    @AppStorage("showAccelerometerWidget") private var showAccelerometerWidget = true
    @AppStorage("showGyroscopeWidget") private var showGyroscopeWidget = true
    @AppStorage("showMagnetometerWidget") private var showMagnetometerWidget = true
    @AppStorage("showMapWidget") private var showMapWidget = true
    @AppStorage("mapProvider") private var mapProvider = "apple" // "apple" or "osm"
    @ObservedObject var locationManager: LocationManager

    @State private var apiKeyInput = ""
    @State private var showingAPIKeyAlert = false
    @State private var showingViewAPIKeyAlert = false
    @State private var apiKeyStatus = "Not Set"

    private let rowBackground = Color.celSurfaceTop.opacity(0.55)

    var body: some View {
        List {
                Section {
                    widgetToggle("Barometer", "barometer", isOn: $showBarometerWidget)
                    widgetToggle("Location", "location.fill", isOn: $showLocationWidget)
                    widgetToggle("Weather", "cloud.sun.fill", isOn: $showWeatherWidget)
                    widgetToggle("Satellite Tracker", "antenna.radiowaves.left.and.right", isOn: $showSatelliteWidget)
                    widgetToggle("Accelerometer", "move.3d", isOn: $showAccelerometerWidget)
                    widgetToggle("Gyroscope", "rotate.3d", isOn: $showGyroscopeWidget)
                    widgetToggle("Magnetometer", "location.north.line.fill", isOn: $showMagnetometerWidget)
                    widgetToggle("Map", "map.fill", isOn: $showMapWidget)
                } header: {
                    Text("Sensor Array").celEyebrow(.celCyan)
                }
                .listRowBackground(rowBackground)

                Section {
                    Picker("Map Provider", selection: $mapProvider) {
                        Text("Apple Maps").tag("apple")
                        Text("OpenStreetMap").tag("osm")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .foregroundStyle(Color.celText)

                    if mapProvider == "osm" {
                        NavigationLink(destination: MapCacheView(locationManager: locationManager)) {
                            Label {
                                Text("Cache Management").foregroundStyle(Color.celText)
                            } icon: {
                                Image(systemName: "externaldrive").foregroundStyle(Color.celCyan)
                            }
                        }
                    }
                } header: {
                    Text("Map Provider").celEyebrow(.celCyan)
                }
                .listRowBackground(rowBackground)

                Section {
                    HStack {
                        Text("API Key").foregroundStyle(Color.celTextDim)
                        Spacer()
                        StatusPill(Config.hasValidAPIKey ? "Active" : "Not Set",
                                   status: Config.hasValidAPIKey ? .nominal : .alert)
                    }

                    configButton(Config.hasValidAPIKey ? "Update API Key" : "Set API Key",
                                 icon: "key.fill", tint: .celCyan) {
                        apiKeyInput = ""
                        showingAPIKeyAlert = true
                    }

                    if Config.hasValidAPIKey {
                        configButton("View API Key", icon: "eye.fill", tint: .celTextDim) {
                            showingViewAPIKeyAlert = true
                        }
                        configButton("Remove API Key", icon: "trash.fill", tint: .celRed) {
                            if Config.deleteAPIKey() { updateAPIKeyStatus() }
                        }
                    }

                    Text("Get a free key from openweathermap.org")
                        .font(.celTiny)
                        .foregroundStyle(Color.celTextFaint)
                } header: {
                    Text("Weather Service").celEyebrow(.celCyan)
                }
                .listRowBackground(rowBackground)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .celestialBackground(showConstellation: false)
            .tint(.celCyan)
            .navigationTitle("Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.celBackgroundTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("CONFIGURATION")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .tracking(2.5)
                        .foregroundStyle(Color.celText)
                }
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
            Text(maskedAPIKey)
        }
    }

    private func widgetToggle(_ title: String, _ icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label {
                Text(title).foregroundStyle(Color.celText)
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.celCyan)
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: .celCyan))
    }

    private func configButton(_ title: String, icon: String, tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(title).foregroundStyle(tint)
            } icon: {
                Image(systemName: icon).foregroundStyle(tint)
            }
            .font(.system(size: 14))
        }
    }

    private var maskedAPIKey: String {
        let key = Config.openWeatherAPIKey
        if key.isEmpty {
            return "No API key found"
        }
        if key.count <= 8 {
            return "****"
        }
        let prefix = String(key.prefix(4))
        let suffix = String(key.suffix(4))
        return "\(prefix)...\(suffix)"
    }

    private func updateAPIKeyStatus() {
        apiKeyStatus = Config.hasValidAPIKey ? "✓ Set" : "Not Set"
    }
}

#Preview {
    PreferencesView(locationManager: LocationManager())
}

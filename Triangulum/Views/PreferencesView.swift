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
    @AppStorage("showAccelerometerWidget") private var showAccelerometerWidget = true
    @AppStorage("showGyroscopeWidget") private var showGyroscopeWidget = true
    @AppStorage("showMagnetometerWidget") private var showMagnetometerWidget = true
    @AppStorage("showMapWidget") private var showMapWidget = true
    @AppStorage("mapProvider") private var mapProvider = "apple" // "apple" or "osm"
    @StateObject private var locationManager = LocationManager()
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Sensor Widgets")) {
                    Toggle("Barometer", isOn: $showBarometerWidget)
                        .toggleStyle(SwitchToggleStyle(tint: .prussianBlue))
                    
                    Toggle("Location", isOn: $showLocationWidget)
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
            }
            .navigationTitle("Preferences")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.prussianBlue, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

#Preview {
    PreferencesView()
}

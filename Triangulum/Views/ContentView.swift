//
//  ContentView.swift
//  Triangulum
//
//  Created by Chan Wai Chan on 5/8/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @Query private var sensorReadings: [SensorReading]
    @StateObject private var barometerManager = BarometerManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var snapshotManager = SnapshotManager()
    @State private var isRecording = false
    @State private var showSnapshotDialog = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 20) {
                BarometerView(barometerManager: barometerManager)
                
                LocationView(locationManager: locationManager)
                
                Divider()
                    .background(Color.prussianBlueLight)
                
                VStack(alignment: .leading) {
                    HStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Button(action: takeSnapshot) {
                                Text("📸 Snapshot")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.prussianBlue)
                                    .cornerRadius(20)
                            }
                            
                            NavigationLink(destination: FootprintView(snapshotManager: snapshotManager)) {
                                Text("👣 Footprints")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.prussianBlueLight)
                                    .cornerRadius(20)
                            }
                            
                        }
                    }
                    
                    List {
                        ForEach(sensorReadings.prefix(10)) { reading in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(reading.sensorType.displayName)
                                        .font(.caption)
                                        .foregroundColor(.prussianBlueLight)
                                    Spacer()
                                    Text(reading.timestamp, format: .dateTime.hour().minute().second())
                                        .font(.caption)
                                        .foregroundColor(.prussianBlueLight)
                                }
                                Text("\(reading.value, specifier: "%.2f") \(reading.unit)")
                                    .font(.body)
                                    .foregroundColor(.prussianBlueDark)
                                
                                if let lat = reading.latitude, let lon = reading.longitude {
                                    Text("📍 \(lat, specifier: "%.4f")°, \(lon, specifier: "%.4f")°")
                                        .font(.caption2)
                                        .foregroundColor(.prussianBlueLight)
                                }
                                
                                if let additionalData = reading.additionalData {
                                    Text(additionalData)
                                        .font(.caption2)
                                        .foregroundColor(.prussianBlueLight)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: deleteReadings)
                        
                        ForEach(items) { item in
                            NavigationLink {
                                Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                            } label: {
                                Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                            }
                        }
                        .onDelete(perform: deleteItems)
                    }
                }
            }
            .padding()
            .background(Color.prussianSoft.ignoresSafeArea())
            .navigationTitle("Sensor Monitor")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.prussianBlue, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        } detail: {
            Color.prussianSoft.ignoresSafeArea()
        }
        .onAppear {
            barometerManager.startBarometerUpdates()
            locationManager.startLocationUpdates()
        }
        .onDisappear {
            barometerManager.stopBarometerUpdates()
            locationManager.stopLocationUpdates()
        }
        .alert("Snapshot Taken", isPresented: $showSnapshotDialog) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Sensor snapshot has been saved to your footprints.")
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
    
    private func deleteReadings(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(sensorReadings[index])
            }
        }
    }
    
    private func takeSnapshot() {
        let snapshot = SensorSnapshot(
            barometerManager: barometerManager,
            locationManager: locationManager
        )
        snapshotManager.addSnapshot(snapshot)
        showSnapshotDialog = true
    }
    
    private func toggleRecording() {
        isRecording.toggle()
        
        if isRecording {
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                if !self.isRecording {
                    timer.invalidate()
                    return
                }
                
                let barometerReading = SensorReading(
                    sensorType: .barometer,
                    value: self.barometerManager.pressure,
                    unit: "kPa",
                    latitude: self.locationManager.latitude,
                    longitude: self.locationManager.longitude,
                    altitude: self.locationManager.altitude
                )
                self.modelContext.insert(barometerReading)
                
                if self.locationManager.isAvailable && (self.locationManager.authorizationStatus == .authorizedWhenInUse || self.locationManager.authorizationStatus == .authorizedAlways) {
                    let gpsReading = SensorReading(
                        sensorType: .gps,
                        value: self.locationManager.accuracy,
                        unit: "m",
                        additionalData: "Lat: \(self.locationManager.latitude), Lon: \(self.locationManager.longitude)",
                        latitude: self.locationManager.latitude,
                        longitude: self.locationManager.longitude,
                        altitude: self.locationManager.altitude
                    )
                    self.modelContext.insert(gpsReading)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
